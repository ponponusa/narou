# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

#
# Legacy API v1 - システム関連エンドポイント
# 
# 既存のWebUIとの互換性を維持するためのLegacy API実装
#

module Narou
  module ApiV1
    # システム情報・キュー管理関連 API v1 エンドポイント
    module System
      def self.register(app)
        app.class_eval do
          # キャンセル処理
          post "/api/cancel" do
            Narou::WebWorker.cancel
            Narou::Worker.cancel if Narou.concurrency_enabled?
          end

          # キューサイズ取得
          get "/api/get_queue_size" do
            res = [
              Narou::WebWorker.instance.size, Narou::Worker.size
            ]
            json res
          end

          # 履歴取得
          get "/api/history" do
            case params["stream"]
            when "stdout2"
              $stdout2.string
            else
              $stdout.string
            end
          end

          # 履歴クリア
          post "/api/clear_history" do
            Narou::PushServer.instance.clear_history
            $stdout.string.clear
            $stdout2.string.clear if Narou.concurrency_enabled?
          end

          # バージョン情報（現在）
          get "/api/version/current.json" do
            json({ version: Narou::VERSION })
          end

          # バージョン情報（最新）
          get "/api/version/latest.json" do
            json({ version: Narou.latest_version })
          end

          # ソート状態取得
          get "/api/sort_state" do
            server_setting = Inventory.load("server_setting", :global)
            current_sort = server_setting["current_sort"]
            
            if current_sort
              json({
                column: current_sort["column"],
                dir: current_sort["dir"]
              })
            else
              # デフォルトソート: 最新話掲載日 降順
              json({
                column: "general_lastup",
                dir: "down"
              })
            end
          end
        end
      end
    end
  end
end
