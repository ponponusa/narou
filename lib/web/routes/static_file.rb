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
        # 開発環境のパス
        dev_index_path = File.join(__dir__, "../../frontend/dist/index.html")
        
        # gem環境のパス
        gem_index_path = File.expand_path("../../frontend/dist/index.html", File.dirname(__FILE__))
        
        index_path = if File.exist?(dev_index_path)
                       dev_index_path
                     elsif File.exist?(gem_index_path)
                       gem_index_path
                     else
                       nil
                     end
        
        if index_path && File.exist?(index_path)
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
        # 開発環境とgem環境の両方に対応
        asset_filename = params['splat'].first
        
        # 開発環境のパス
        dev_asset_path = File.join(__dir__, "../../frontend/dist/_astro", asset_filename)
        
        # gem環境のパス
        gem_asset_path = File.expand_path("../../frontend/dist/_astro/#{asset_filename}", File.dirname(__FILE__))
        
        asset_path = if File.exist?(dev_asset_path)
                       dev_asset_path
                     elsif File.exist?(gem_asset_path)
                       gem_asset_path
                     else
                       nil
                     end
        
        if asset_path && File.exist?(asset_path)
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
        # 開発環境のパス
        dev_favicon_path = File.join(__dir__, "../../frontend/dist/favicon.svg")
        
        # gem環境のパス
        gem_favicon_path = File.expand_path("../../frontend/dist/favicon.svg", File.dirname(__FILE__))
        
        favicon_path = if File.exist?(dev_favicon_path)
                         dev_favicon_path
                       elsif File.exist?(gem_favicon_path)
                         gem_favicon_path
                       else
                         nil
                       end
        
        if favicon_path && File.exist?(favicon_path)
          send_file favicon_path
        else
          halt 404
        end
      else
        halt 404
      end
    end
  end
end
