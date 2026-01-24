# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

#
# 静的ファイル配信ルーティングを担当するモジュール
#
# ルートページ、CSS、Astroアセット、faviconなどの配信ロジックを集約
#
module StaticFileRoutes
  # フロントエンドのdistディレクトリのパスを返す
  # gem環境と開発環境の両方に対応
  # Narou.script_dir は gem のインストールディレクトリを指す
  def self.frontend_dist_dir
    @frontend_dist_dir ||= File.join(Narou.script_dir, "frontend", "dist")
  end

  def self.registered(app)
    #
    # ルートページ配信
    #
    app.get "/" do
      if self.class.legacy_mode?
        # Legacy Haml UI
        setting = Inventory.load("server_setting", :global)
        @is_first_access = !setting["already-accessed"]
        if @is_first_access
          setting["already-accessed"] = true
          setting.save
        end
        haml :index, layout: true
      else
        # New Astro UI
        index_path = File.join(StaticFileRoutes.frontend_dist_dir, "index.html")

        if File.exist?(index_path)
          # HTMLは常に最新を確認（ハッシュ付きアセットへの参照を更新するため）
          headers "Cache-Control" => "no-cache, must-revalidate"
          send_file index_path
        else
          halt 500, "Frontend not built. Run 'cd frontend && npm run build' first."
        end
      end
    end

    #
    # スタイルシート配信
    #
    app.get "/style.css" do
      if self.class.legacy_mode?
        scss :style
      else
        # Astro UI では使用しない
        halt 404
      end
    end

    #
    # Astro ビルド済みアセット配信
    #
    app.get "/_astro/*" do
      unless self.class.legacy_mode?
        asset_filename = params["splat"].first
        asset_path = File.join(StaticFileRoutes.frontend_dist_dir, "_astro", asset_filename)

        if File.exist?(asset_path)
          # ハッシュ付きアセットは長期キャッシュ可能（1年間）
          headers "Cache-Control" => "public, max-age=31536000, immutable"
          send_file asset_path
        else
          halt 404
        end
      else
        halt 404
      end
    end

    #
    # Favicon配信
    #
    app.get "/favicon.svg" do
      unless self.class.legacy_mode?
        favicon_path = File.join(StaticFileRoutes.frontend_dist_dir, "favicon.svg")

        if File.exist?(favicon_path)
          send_file favicon_path
        else
          halt 404
        end
      else
        halt 404
      end
    end

    #
    # ロゴアイコン配信
    #
    app.get "/logo_icon.svg" do
      unless self.class.legacy_mode?
        logo_path = File.join(StaticFileRoutes.frontend_dist_dir, "logo_icon.svg")

        if File.exist?(logo_path)
          send_file logo_path
        else
          halt 404
        end
      else
        halt 404
      end
    end

    #
    # バックエンド設定JSON配信（PushServerポート番号など）
    # 現在のサーバー設定から動的に生成
    #
    app.get "/backend-port.json" do
      unless self.class.legacy_mode?
        headers "Cache-Control" => "no-store, must-revalidate"
        content_type :json

        # 現在のサーバー設定から動的に生成
        push_server = Narou::AppServer.push_server
        port_info = {
          backend_port: settings.port,
          push_server_port: push_server&.port || settings.port + 1,
          updated_at: Time.now.iso8601
        }
        port_info.to_json
      else
        halt 404
      end
    end

    #
    # Astro サブページ配信（help, settings, tasks など）
    #
    %w[help settings settings-debug tasks].each do |page|
      app.get "/#{page}" do
        unless self.class.legacy_mode?
          page_path = File.join(StaticFileRoutes.frontend_dist_dir, page, "index.html")

          if File.exist?(page_path)
            # HTMLは常に最新を確認（ハッシュ付きアセットへの参照を更新するため）
            headers "Cache-Control" => "no-cache, must-revalidate"
            send_file page_path
          else
            halt 404
          end
        else
          halt 404
        end
      end
    end
  end
end
