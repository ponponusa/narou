# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "yaml"
require "parallel"
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
      # 並列処理の閾値（環境変数で制御可能、デフォルト: 10エピソード）
      parallel_threshold = (ENV['NAROU_PARALLEL_THRESHOLD'] || 10).to_i
      
      # 並列処理が有効な場合（デフォルト有効、環境変数で無効化可能）
      parallel_enabled = ENV['NAROU_PARALLEL_CONVERT'] != 'false' && subtitles.size >= parallel_threshold
      
      if parallel_enabled
        # プロセスベースの並列化を使用（GILの影響を回避）
        # ただし、WindowsではParallelのプロセスベースが動作しないため、スレッドベースを使用
        # 環境変数で明示的に指定された場合はそれを優先
        if ENV['NAROU_PARALLEL_USE_PROCESSES']
          use_processes = ENV['NAROU_PARALLEL_USE_PROCESSES'] == 'true'
        else
          # デフォルト: Windows以外ではプロセスベース
          use_processes = !Helper.os_windows?
        end
        
        stream_io.puts "Using #{use_processes ? 'process' : 'thread'}-based parallel processing (#{subtitles.size} episodes, threshold: #{parallel_threshold})" if ENV['NAROU_DEBUG']
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
    # subtitle info から変換処理をする（チャンクベース並列版）
    #
    def subtitles_to_sections_parallel_chunked(subtitles, html, section_save_dir, site_setting, parallel_count)
      # チャンクサイズの計算（環境変数で上書き可能）
      chunk_size = if ENV['NAROU_CHUNK_SIZE']
        ENV['NAROU_CHUNK_SIZE'].to_i
      else
        # デフォルト: 1000エピソード/チャンク（ベンチマークで最適値を確認）
        # プロセス起動オーバーヘッドと並列効率のバランスが最も良い
        1000
      end
      
      stream_io.puts "Parallel processes: #{parallel_count} (chunk-based, chunk_size=#{chunk_size})" if ENV['NAROU_DEBUG']
      
      # サブタイトルをチャンクに分割
      subtitle_chunks = subtitles.each_slice(chunk_size).to_a
      stream_io.puts "Split into #{subtitle_chunks.size} chunks" if ENV['NAROU_DEBUG']
      
      # 各チャンクを並列処理
      converter_class = load_converter(@setting.archive_path)
      
      chunk_results = Parallel.map_with_index(subtitle_chunks, in_processes: parallel_count) do |chunk, chunk_idx|
        # プロセスごとにConverterを作成
        chunk_converter = converter_class.new(@setting, @inspector, @illustration)
        chunk_html = HTML.new
        chunk_html.strip_decoration_tag = @setting.enable_strip_decoration_tag
        if site_setting
          chunk_html.set_illust_setting(
            current_url: site_setting["illust_current_url"],
            grep_pattern: site_setting["illust_grep_pattern"]
          )
        end
        
        # チャンク内のエピソードを処理
        chunk_sections = []
        chunk.each_with_index do |subinfo, idx_in_chunk|
          global_index = chunk_idx * chunk_size + idx_in_chunk
          
          # 進捗表示（10件ごと）
          trigger(:"convert_main.loop", global_index) if (global_index % 10).zero?
          
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

          # チャンク固有のConverterで変換
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
