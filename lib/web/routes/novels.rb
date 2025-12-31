# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "cgi"

#
# 小説管理ルーティングを担当するモジュール
#
# 小説個別設定、ダウンロード、作者コメント表示などのルーティングを集約
#
module NovelsRoutes
  # Downloaderを遅延ロード（autoload）
  autoload :Downloader, "novel/downloader"

  def self.registered(app)
    #
    # 小説個別ルートフィルター
    #
    app.before "/novels/:id/*" do
      @id = params[:id]
      not_found unless @id =~ /^\d+$/
      @data = Downloader.get_data_by_target(@id)
      not_found unless @data
    end

    #
    # 小説設定ページフィルター
    #
    app.before "/novels/:id/setting" do
      @novel_title = @data["title"]
      @title = "小説の変換設定 - #{h @novel_title}"
      @setting_variables = []
      @error_list = {}
      @novel_setting = NovelSetting.new(@id, true, true) # 空っぽの設定を作成
      @novel_setting.settings = @novel_setting.load_setting_ini["global"]
      @original_settings = NovelSetting.get_original_settings
      @force_settings = NovelSetting.load_force_settings
      @default_settings = NovelSetting.load_default_settings
      @replace_pattern = @novel_setting.load_replace_pattern
    end

    #
    # 小説設定保存
    #
    app.post "/novels/:id/setting" do
      # 変換設定保存
      @original_settings.each do |info|
        name = info[:name]
        type = info[:type]
        param_data = params[name]
        value = nil
        begin
          if type == :boolean
            if param_data
              value = convert_on_off_to_boolean(param_data)
            else
              value = false
            end
          elsif param_data.is_a?(Array)
            value = param_data.join(",")
          else
            if param_data.strip != ""
              value = Helper.string_cast_to_type(param_data, type)
            end
          end
          @novel_setting[name] = value
        rescue Helper::InvalidVariableType => e
          @error_list[name] = e.message
        end
      end
      @novel_setting.save_settings

      # 置換設定保存
      params_replace_pattern = params["replace_pattern"]
      @novel_setting.replace_pattern.clear
      if params_replace_pattern.is_a?(Array)
        params_replace_pattern.each do |pattern|
          left = pattern["left"].strip
          right = pattern["right"].strip
          next if left == ""
          @novel_setting.replace_pattern << [left, right]
        end
      end
      @novel_setting.save_replace_pattern

      if @error_list.empty?
        session[:alert] = [ "保存が完了しました", "success" ]
      else
        session[:alert] = [ "#{@error_list.size}個の設定にエラーがありました", "danger" ]
      end

      haml :"novels/setting"
    end

    #
    # 小説設定ページ表示
    #
    app.get "/novels/:id/setting" do
      haml :"novels/setting"
    end

    #
    # 小説ファイルダウンロード
    #
    app.get "/novels/:id/download" do
      device = Narou.get_device
      ext = device ? device.ebook_file_ext : ".epub"
      paths = Narou.get_ebook_file_paths(@id, ext)
      if !paths.empty? && File.exist?(paths[0])
        # ファイル名を "[著者名] タイトル.拡張子" の形式にする
        author = @data["author"] || "Unknown"
        title = @data["title"] || "Untitled"
        filename = "[#{author}] #{title}#{ext}"

        # UTF-8ファイル名をRFC 5987形式でエンコード
        encoded_filename = CGI.escape(filename).gsub("+", "%20")

        content_type "application/octet-stream"
        headers["Content-Disposition"] = "attachment; filename*=UTF-8''#{encoded_filename}"

        send_file(paths[0])
      else
        not_found
      end
    end

    #
    # 作者コメント一覧表示
    #
    app.get "/novels/:id/author_comments" do
      downloader = Downloader.new(@id)
      toc = downloader.load_toc_file
      @comments = []
      introductions_count = 0
      postscripts_count = 0
      toc["subtitles"].each do |sub|
        section_path = downloader.section_file_path(sub)
        begin
          element = YAML.unsafe_load_file(section_path)["element"]
        rescue SystemCallError
          # bootsnap on Windows can raise Errno::E01 errors, fallback to standard YAML
          element = YAML.unsafe_load(File.read(section_path))["element"]
        end
        data_type = element["data_type"] || "text"
        introduction = element["introduction"] || ""
        postscript = element["postscript"] || ""
        if data_type == "html"
          html = HTML.new
          html.strip_decoration_tag = true
          html.string = introduction
          introduction = html.to_aozora
          html.string = postscript
          postscript = html.to_aozora
        end
        @comments.push(
          sub: sub,
          introduction: introduction,
          postscript: postscript
        )
        introductions_count += 1 unless introduction.empty?
        postscripts_count += 1 unless postscript.empty?
      rescue Errno::ENOENT
      end
      total = toc["subtitles"].count.to_f
      @introductions_ratio = (introductions_count / total * 100).round(2)
      @postscripts_ratio = (postscripts_count / total * 100).round(2)
      haml :"novels/author_comments"
    end

    #
    # メモ帳ページ
    #
    app.get "/notepad" do
      @title = "メモ帳"
      haml :notepad
    end

    #
    # 個別メニュー編集ページ
    #
    app.get "/edit_menu" do
      @title = "個別メニューの編集"
      haml :edit_menu
    end
  end
end
