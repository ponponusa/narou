# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

#
# Legacy API v1 - 設定関連エンドポイント
#
# 小説設定の一括適用や更新設定等
#

module Narou
  module ApiV1
    # 設定関連 API v1 エンドポイント
    module Settings
      def self.register(app)
        app.class_eval do
          # 一般最新話更新
          post "/api/update_general_lastup" do
            option = params["option"]
            option = nil if option == "all"
            is_update_modified = params["is_update_modified"] == "true"
            Narou::WebWorker.push do
              CommandLine.run!(["update", "--gl", option].compact)
              NovelListProcessor.clear_all_cache # 全キャッシュ無効化
              Narou::AppServer.push_server.send_all(:"table.reload")
              Narou::AppServer.push_server.send_all(:"tag.updateCanvas")
              if is_update_modified
                puts "<yellow>#{Narou::MODIFIED_TAG} タグの付いた小説を更新します</yellow>".termcolor
                CommandLine.run!("update", "tag:#{Narou::MODIFIED_TAG}")
                NovelListProcessor.clear_all_cache # 全キャッシュ無効化
                Narou::AppServer.push_server.send_all(:"table.reload")
                Narou::AppServer.push_server.send_all(:"tag.updateCanvas")
              end
            end
          end

          # 設定の焼き付け
          post "/api/setting_burn" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids
            Narou::WebWorker.push do
              CommandLine.run!("setting", "--burn", ids)
            end
          end
        end
      end
    end
  end
end
