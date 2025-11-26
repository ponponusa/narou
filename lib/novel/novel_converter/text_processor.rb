# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "yaml"
require "etc"
require "lib/novel/downloader"
require "lib/novel/sitesetting"
require "lib/conversion/html"
require "lib/conversion/template"

class NovelConverter
  #
  # テキスト整形・変換処理
  #
  module TextProcessor
    #
    # YAMLファイルから小説セクションをロード
    #
    def load_novel_section(subtitle_info, section_save_dir)
      file_subtitle = subtitle_info["file_subtitle"] || subtitle_info["subtitle"] # 互換性維持のため
      path = section_save_dir.join("#{subtitle_info["index"]} #{file_subtitle}.yaml")
      begin
        YAML.unsafe_load_file(path)
      rescue SystemCallError => e
        # bootsnap on Windows can raise Errno::E01 errors, fallback to standard YAML
        raise if e.is_a?(Errno::ENOENT)
        YAML.unsafe_load(File.read(path))
      end
    rescue Errno::ENOENT
      stream_io.puts
      stream_io.error(<<~MSG.termcolor)
        <yellow>"#{path.basename}"</yellow> を見つけることが出来ませんでした。
        対象の小説を一度 Update を実行することで、ファイルをダウンロード出来ます。
      MSG
      exit Narou::EXIT_ERROR_CODE
    end

    #
    # 複数のYAMLファイルを一括で読み込み（Ractor版）
    #
    def load_novel_sections_batch(subtitle_infos, section_save_dir)
      # Ractorで並列読み込み
      results = Array.new(subtitle_infos.size)
      
      # CPU数に応じたRactor数（I/O処理なので多めに）
      ractor_count = [Etc.nprocessors * 4, 16].min
      
      # サブタイトルをチャンクに分割
      chunk_size = (subtitle_infos.size.to_f / ractor_count).ceil
      chunks = subtitle_infos.each_slice(chunk_size).to_a
      
      # Ractorを起動
      ractors = chunks.map.with_index do |chunk, chunk_idx|
        # Ractorに渡すデータはshareable（Ractor-safeなオブジェクト）である必要がある
        chunk_data = chunk.map(&:dup).freeze
        section_save_dir_str = section_save_dir.to_s.freeze
        
        Ractor.new(chunk_data, section_save_dir_str, chunk_idx) do |ch_data, dir_str, ch_idx|
          require "yaml"
          require "pathname"
          
          dir = Pathname.new(dir_str)
          ch_data.map do |subtitle_info|
            file_subtitle = subtitle_info["file_subtitle"] || subtitle_info["subtitle"]
            path = dir.join("#{subtitle_info["index"]} #{file_subtitle}.yaml")
            
            begin
              YAML.unsafe_load_file(path)
            rescue SystemCallError => e
              raise if e.is_a?(Errno::ENOENT)
              YAML.unsafe_load(File.read(path))
            end
          end
        end
      end
      
      # 結果を収集
      ractors.each_with_index do |ractor, chunk_idx|
        chunk_size_actual = chunks[chunk_idx].size
        base_idx = chunk_idx * chunk_size
        
        chunk_results = ractor.take
        chunk_results.each_with_index do |section, offset|
          results[base_idx + offset] = section
        end
      end
      
      results
    end

    # is_hotentry を有効にすると、テンプレートで作成するテキストファイルに
    # あらすじ、作品タイトル、本の読み終わり表示が付与されなくなる
    def create_novel_text_by_template(sections, toc, is_hotentry = false, index = nil)
      cover_chuki = create_cover_chuki
      device = Narou.get_device
      setting = @setting

      toc["title"]  = setting.novel_title  unless setting.novel_title.empty?
      toc["author"] = setting.novel_author unless setting.novel_author.empty?

      processing_title = toc["title"]
      processing_title += "_#{index}" if index
      processed_title = decorate_title(processing_title)
      template_name = (device&.ibunko? ? NOVEL_TEXT_TEMPLATE_NAME_FOR_IBUNKO : NOVEL_TEXT_TEMPLATE_NAME)

      # テンプレートをキャッシュする
      # コンパイル済みERB（またはProc）をキャッシュして binding だけ都度差し込む
      @__template_cache ||= {}
      compiled = @__template_cache[template_name]
      unless compiled
        compiled = Template.compile(template_name, 1.1)
        @__template_cache[template_name] = compiled
      end

      Template.render(compiled, binding)
    end

    #
    # テキストファイル変換時の実質的なメイン処理
    #
    def convert_main_for_text(text)
      result = @converter.convert(text, "textfile")
      unless @setting.enable_enchant_midashi
        @inspector.info "テキストファイルの処理を実行しましたが、改行直後の見出し付与は有効になっていません。" \
                        "setting.ini の enable_enchant_midashi を true にすることをお薦めします。"
      end
      splited = result.split("\n", 3)
      # 表紙の挿絵注記を3行目に挟み込む
      converted_text = [splited[0], splited[1], create_cover_chuki, splited[2]].join("\n")

      @use_dakuten_font = @converter.use_dakuten_font

      [converted_text]
    end

    #
    # 管理小説変換時の実質的なメイン処理
    #
    # 引数 subtitles にデータを渡した場合はそれを直接使う
    # is_hotentry を有効にすると出力されるテキストファイルにあらすじや作品タイトル等が含まれなくなる
    # また、 is_hotentry を有効にすると分割も行われなくなる
    #
    def convert_main_for_novel(subtitles = nil, is_hotentry = false)
      toc = Downloader.get_toc_data(@setting.archive_path)
      subtitles ||= cut_subtitles(toc["subtitles"])
      if is_hotentry == false && @setting.slice_size > 0 && subtitles.length > @setting.slice_size
        stream_io.puts "#{@setting.slice_size}話ごとに分割して変換します"
        array_of_subtitles = subtitles.each_slice(@setting.slice_size).to_a
      else
        array_of_subtitles = [subtitles]
      end
      toc["story"] = @converter.convert(toc["story"], "story")
      site_setting = SiteSetting.find(toc["toc_url"])
      html = HTML.new
      html.strip_decoration_tag = @setting.enable_strip_decoration_tag
      html.set_illust_setting(
        current_url: site_setting["illust_current_url"],
        grep_pattern: site_setting["illust_grep_pattern"]
      )
      array_of_converted_text = []
      array_of_subtitles.each_with_index do |sliced_subtitles, index|
        @converter.subtitles = sliced_subtitles
        html.clear
        sections = subtitles_to_sections(sliced_subtitles, html)
        array_of_converted_text.push(
          create_novel_text_by_template(
            sections, toc, is_hotentry,
            array_of_subtitles.length == 1 ? nil : index + 1
          )
        )
      end

      if is_hotentry
        array_of_converted_text[0]
      else
        array_of_converted_text
      end
    end

    def cut_subtitles(subtitles)
      case cut_size = @setting.cut_old_subtitles
      when 0
        result = subtitles
      when 1...subtitles.size
        stream_io.puts "#{cut_size}話分カットして変換します"
        result = subtitles[cut_size..-1]
      else
        stream_io.puts "最新話のみ変換します"
        result = [subtitles[-1]]
      end
      result
    end

    #
    # subtitle info から変換処理をする
    #
    def subtitles_to_sections(subtitles, html)
      # 並列処理が有効な場合（環境変数で制御）
      if ENV['NAROU_PARALLEL_CONVERT'] == 'true' && subtitles.size > 100
        # プロセスベースの並列化を使用（GILの影響を回避）
        use_processes = ENV['NAROU_PARALLEL_USE_PROCESSES'] == 'true'
        stream_io.puts "Using #{use_processes ? 'process' : 'thread'}-based parallel processing (#{subtitles.size} episodes)" if ENV['NAROU_DEBUG']
        return subtitles_to_sections_parallel(subtitles, html, use_processes: use_processes)
      end

      stream_io.puts "Using sequential processing (#{subtitles.size} episodes)" if ENV['NAROU_DEBUG']
      # 従来のシーケンシャル処理
      subtitles_to_sections_sequential(subtitles, html)
    end

    #
    # subtitle info から変換処理をする（並列版）
    #
    def subtitles_to_sections_parallel(subtitles, html, use_processes: false)
      section_save_dir = Downloader.get_novel_section_save_dir(@setting.archive_path)
      site_setting = SiteSetting.find(@setting.toc_url) if @setting.respond_to?(:toc_url)
      
      trigger(:"convert_main.init", subtitles)

      # 並列処理用のConverterプールを作成
      # スレッド数は環境変数で制御可能（デフォルト: CPUコア数）
      parallel_count = (ENV['NAROU_PARALLEL_THREADS'] || Parallel.processor_count).to_i
      
      # チャンクベース処理が有効か判定（デフォルト: 有効）
      use_chunked = ENV['NAROU_PARALLEL_CHUNKED'] != 'false'
      
      if use_chunked && use_processes
        # チャンクベース処理（プロセス起動オーバーヘッドを削減）
        return subtitles_to_sections_parallel_chunked(
          subtitles, html, section_save_dir, site_setting, parallel_count
        )
      end
      
      # 従来のエピソード単位並列処理
      stream_io.puts "Parallel #{use_processes ? 'processes' : 'threads'}: #{parallel_count} (episode-based)" if ENV['NAROU_DEBUG']
      
      # 各スレッド/プロセス用のConverterをThread-localストレージで管理
      converter_class = load_converter(@setting.archive_path)
      thread_converters = {}
      converter_mutex = Mutex.new unless use_processes
      
      parallel_options = use_processes ? { in_processes: parallel_count } : { in_threads: parallel_count }
      
      sections = Parallel.map_with_index(subtitles, parallel_options) do |subinfo, i|
        # スレッド/プロセス固有のConverterを取得または作成
        if use_processes
          # プロセスベースの場合は毎回新規作成（プロセス間で共有不可）
          thread_converter = converter_class.new(@setting, @inspector, @illustration)
        else
          # スレッドベースの場合はThread-localで管理
          thread_id = Thread.current.object_id
          thread_converter = thread_converters[thread_id]
          unless thread_converter
            thread_converter = converter_mutex.synchronize do
              unless thread_converters[thread_id]
                stream_io.puts "Creating converter for thread #{thread_id}" if ENV['NAROU_DEBUG']
                thread_converters[thread_id] = converter_class.new(@setting, @inspector, @illustration)
              end
              thread_converters[thread_id]
            end
          end
        end
        
        # 進捗表示（10件ごと）
        trigger(:"convert_main.loop", i) if (i % 10).zero?
        
        # 各スレッドで独立したHTMLオブジェクトを使用
        thread_html = HTML.new
        thread_html.strip_decoration_tag = @setting.enable_strip_decoration_tag
        if site_setting
          thread_html.set_illust_setting(
            current_url: site_setting["illust_current_url"],
            grep_pattern: site_setting["illust_grep_pattern"]
          )
        end

        # セクションをロード
        original_section = load_novel_section(subinfo, section_save_dir)
        
        # 独立したコピーを作成
        section = original_section.dup
        section["element"] = original_section["element"].dup

        # data_type 判定
        element = section["element"]
        data_type = element.delete("data_type") || "text"

        # HTML→青空変換
        preprocessed_element_texts = {}
        element.each do |text_type, elm_text|
          if data_type != "text"
            thread_html.string = elm_text
            elm_text = thread_html.to_aozora(pre_html: data_type == "pre_html")
          end
          preprocessed_element_texts[text_type] = elm_text
        end

        # バッチ入力を作成
        batch_inputs = {}
        if section["chapter"] && !section["chapter"].empty?
          batch_inputs[:chapter] = [section["chapter"], "chapter"]
        end
        batch_inputs[:subtitle] = [section["subtitle"], "subtitle"]
        preprocessed_element_texts.each do |text_type, body_text|
          batch_inputs[[:element, text_type]] = [body_text, text_type]
        end

        # スレッド固有のConverterで変換
        thread_converter.current_index = i
        thread_converter.data_type = data_type
        converted = thread_converter.convert_multi(batch_inputs)
        
        if batch_inputs[:chapter]
          section["chapter"] = converted[:chapter]
        end
        section["subtitle"] = converted[:subtitle]
        element.each_key do |text_type|
          section["element"][text_type] = converted[[:element, text_type]]
        end

        section
      end

      @use_dakuten_font = @converter.use_dakuten_font
      sections
    ensure
      trigger(:"convert_main.finish")
    end

    #
    # subtitle info から変換処理をする（Ractorベース並列版）
    #
    def subtitles_to_sections_parallel_chunked(subtitles, html, section_save_dir, site_setting, parallel_count)
      # チャンクサイズの計算（環境変数で上書き可能）
      chunk_size = if ENV['NAROU_CHUNK_SIZE']
        ENV['NAROU_CHUNK_SIZE'].to_i
      else
        # デフォルト: 1000エピソード/チャンク
        1000
      end
      
      stream_io.puts "Ractor workers: #{parallel_count} (chunk-based, chunk_size=#{chunk_size})" if ENV['NAROU_DEBUG']
      
      # サブタイトルをチャンクに分割
      subtitle_chunks = subtitles.each_slice(chunk_size).to_a
      stream_io.puts "Split into #{subtitle_chunks.size} chunks" if ENV['NAROU_DEBUG']
      
      # Ractorで処理するための準備
      converter_class = load_converter(@setting.archive_path)
      converter_path = converter_class.name.split('::').join('/')
      converter_file = "lib/novel/#{converter_path.downcase}.rb"
      
      # Ractor-safeなデータ構造を準備
      setting_data = @setting.to_hash.freeze
      section_save_dir_str = section_save_dir.to_s.freeze
      site_setting_data = site_setting ? site_setting.to_hash.freeze : nil
      
      # Ractorワーカーを起動
      ractors = subtitle_chunks.map.with_index do |chunk, chunk_idx|
        # Ractor-safeなデータのみ渡す
        chunk_data = chunk.map { |s| s.dup.freeze }.freeze
        
        Ractor.new(chunk_data, chunk_idx, chunk_size, setting_data, section_save_dir_str, 
                   site_setting_data, converter_file) do |ch_data, ch_idx, ch_size, 
                                                            settings, dir_str, site_set, conv_file|
          require "yaml"
          require "pathname"
          require_relative conv_file
          require "lib/conversion/html"
          require "lib/novel/novel_setting"
          require "lib/novel/novel_inspector"
          require "lib/novel/novel_illustration"
          
          # 各Ractor内でConverter/HTML/設定を作成
          dir = Pathname.new(dir_str)
          novel_setting = NovelSetting.new
          settings.each { |k, v| novel_setting[k] = v }
          
          inspector = NovelInspector.new(nil)
          illustration = NovelIllustration.new
          chunk_converter = Object.const_get(conv_file.split('/').last.split('.').first.split('_').map(&:capitalize).join)
                                  .new(novel_setting, inspector, illustration)
          
          chunk_html = HTML.new
          chunk_html.strip_decoration_tag = novel_setting.enable_strip_decoration_tag
          if site_set
            chunk_html.set_illust_setting(
              current_url: site_set["illust_current_url"],
              grep_pattern: site_set["illust_grep_pattern"]
            )
          end
          
          # チャンク内の全セクションを読み込み
          loaded_sections = ch_data.map do |subtitle_info|
            file_subtitle = subtitle_info["file_subtitle"] || subtitle_info["subtitle"]
            path = dir.join("#{subtitle_info["index"]} #{file_subtitle}.yaml")
            begin
              YAML.unsafe_load_file(path)
            rescue SystemCallError => e
              raise if e.is_a?(Errno::ENOENT)
              YAML.unsafe_load(File.read(path))
            end
          end
          
          # チャンク内の各エピソードを処理
          chunk_sections = []
          ch_data.each_with_index do |subinfo, idx_in_chunk|
            original_section = loaded_sections[idx_in_chunk]
            
            # 独立したコピーを作成
            section = original_section.dup
            section["element"] = original_section["element"].dup

            # data_type 判定
            element = section["element"]
            data_type = element.delete("data_type") || "text"

            # HTML→青空変換
            preprocessed_element_texts = {}
            element.each do |text_type, elm_text|
              if data_type != "text"
                chunk_html.string = elm_text
                elm_text = chunk_html.to_aozora(pre_html: data_type == "pre_html")
              end
              preprocessed_element_texts[text_type] = elm_text
            end

            # バッチ入力を作成
            batch_inputs = {}
            if section["chapter"] && !section["chapter"].empty?
              batch_inputs[:chapter] = [section["chapter"], "chapter"]
            end
            batch_inputs[:subtitle] = [section["subtitle"], "subtitle"]
            preprocessed_element_texts.each do |text_type, body_text|
              batch_inputs[[:element, text_type]] = [body_text, text_type]
            end

            # 変換実行
            global_index = ch_idx * ch_size + idx_in_chunk
            chunk_converter.current_index = global_index
            chunk_converter.data_type = data_type
            converted = chunk_converter.convert_multi(batch_inputs)
            
            if batch_inputs[:chapter]
              section["chapter"] = converted[:chapter]
            end
            section["subtitle"] = converted[:subtitle]
            element.each_key do |text_type|
              section["element"][text_type] = converted[[:element, text_type]]
            end

            chunk_sections << section
          end
          
          chunk_sections
        end
      end
      
      # 結果を収集（進捗表示込み）
      chunk_results = []
      ractors.each_with_index do |ractor, idx|
        result = ractor.take
        chunk_results << result
        
        # 進捗表示（チャンクごと）
        processed_count = (idx + 1) * chunk_size
        trigger(:"convert_main.loop", [processed_count, subtitles.size].min) if ENV['NAROU_DEBUG']
      end
      
      # チャンクの結果を統合
      sections = chunk_results.flatten
      
      @use_dakuten_font = @converter.use_dakuten_font
      sections
    ensure
      trigger(:"convert_main.finish")
    end

    #
    # subtitle info から変換処理をする（従来のシーケンシャル版）
    #
    def subtitles_to_sections_sequential(subtitles, html)
      # 章データをキャッシュ
      @__section_cache ||= {}

      sections = []
      section_save_dir = Downloader.get_novel_section_save_dir(@setting.archive_path)

      trigger(:"convert_main.init", subtitles)

      subtitles.each_with_index do |subinfo, i|
        trigger(:"convert_main.loop", i)
        @converter.current_index = i

        # YAMLロードをキャッシュ
        key = subinfo["index"]
        original_section = @__section_cache[key]
        unless original_section
          original_section = load_novel_section(subinfo, section_save_dir)
          @__section_cache[key] = original_section
        end

        # キャッシュを壊さないようディープ寄りにdup
        # （chapter/subtitle/elementなど後で書き換えるので）
        section = original_section.dup
        section["element"] = original_section["element"].dup

        # data_type 判定
        element = section["element"]
        data_type = element.delete("data_type") || "text"
        @converter.data_type = data_type

        # HTML→青空変換が必要なやつを先にプレーンテキスト化
        preprocessed_element_texts = {}
        element.each do |text_type, elm_text|
          if data_type != "text"
            html.string = elm_text
            elm_text = html.to_aozora(pre_html: data_type == "pre_html")
          end
          preprocessed_element_texts[text_type] = elm_text
        end

        # まとめてコンバータに渡すためのバッチ入力を作る
        batch_inputs = {}

        # chapter
        if section["chapter"] && !section["chapter"].empty?
          batch_inputs[:chapter] = [section["chapter"], "chapter"]
        end

        # subtitle
        @inspector.subtitle = section["subtitle"]
        batch_inputs[:subtitle] = [section["subtitle"], "subtitle"]

        # element 各種
        preprocessed_element_texts.each do |text_type, body_text|
          batch_inputs[[:element, text_type]] = [body_text, text_type]
        end

        # 一括変換
        converted = @converter.convert_multi(batch_inputs)
        if batch_inputs[:chapter]
          section["chapter"] = converted[:chapter]
        end

        section["subtitle"] = converted[:subtitle]

        element.each_key do |text_type|
          section["element"][text_type] = converted[[:element, text_type]]
        end

        sections << section
      end

      @use_dakuten_font = @converter.use_dakuten_font
      sections
    ensure
      trigger(:"convert_main.finish")
    end

    #
    # テキストデータ先頭二行からタイトルと著者名を取得
    #
    def get_title_and_author_by_text(text)
      title, author = text.split("\n", 3)
      { "title" => title, "author" => author }
    end
  end
end
