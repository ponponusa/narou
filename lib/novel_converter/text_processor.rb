# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "yaml"
require_relative "../downloader"
require_relative "../sitesetting"
require_relative "../html"
require_relative "../template"

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
