# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

#
# Widget & Partial 関連ルート
#
module Narou
  module WidgetRoutes
    # ブックマークレットモード設定
    BOOKMARKLET_MODE = %w(download insert_button).freeze

    # ウィジェット許可ホスト設定（SiteSetting.settingsからドメイン一覧を取得）
    ALLOW_HOSTS = SiteSetting.settings.values.each_with_object([]) { |setting, memo|
      domains = setting["domain"] || setting["domains"]
      if domains
        memo.concat(Array(domains))
      end
    }.freeze

    def self.registered(app)
      #
      # Partials - HTML部分テンプレート
      #

      # CSV一括ダウンロードフォーム部分
      app.get "/partial/csv_import" do
        @display_csv_import_button = !Narou.get_preset_dir.glob("*.csv").empty?
        haml :_csv_import, layout: false
      end

      # ダウンロードフォーム部分
      app.get "/partial/download_form" do
        haml :_download_form, layout: false
      end

      #
      # Widget - ブックマークレットとウィジェットページ
      #

      # ブックマークレットスクリプト配信
      app.get "/js/widget.js" do
        mode = params["mode"]
        unless BOOKMARKLET_MODE.include?(mode)
          halt 400, "Invalid mode parameter"
        end

        @mode = mode
        content_type "text/javascript"
        erb :widget_js, layout: false
      end

      # ウィジェット用 X-Frame-Options 設定（許可ホストからの埋め込みを許可）
      app.before "/widget/*" do
        # allow_from を使用している場合、ALLOW_HOSTS にドメインが設定されていれば許可
        response["X-Frame-Options"] = if ALLOW_HOSTS.any?
                                        # X-Frame-Options は複数のホスト指定に対応していないため
                                        # 実際には最初のホストのみ許可する
                                        "ALLOW-FROM #{ALLOW_HOSTS.first}"
                                      else
                                        "SAMEORIGIN"
                                      end
      end

      # ウィジェット: ダウンロード
      app.get "/widget/download" do
        @display_csv_import_button = !Narou.get_preset_dir.glob("*.csv").empty?
        haml :widget_download, layout: :widget_layout
      end

      # ウィジェット: ドラッグ&ドロップ
      app.get "/widget/drag_and_drop" do
        haml :widget_drag_and_drop, layout: :widget_layout
      end

      # ウィジェット: メモ帳
      app.get "/widget/notepad" do
        haml :widget_notepad, layout: :widget_layout
      end
    end
  end
end
