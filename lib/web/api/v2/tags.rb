# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require "lib/web/api/v2/base"

module Narou
  module ApiV2
    # タグ関連 API v2 エンドポイント
    module Tags
      def self.register(app)
        app.class_eval do
          include Narou::ApiV2::Base

          # GET /api/v2/tags
          # タグ一覧取得
          get "/api/v2/tags" do
            set_cors_headers

            begin
              require "lib/narou/tag_manager"
              tag_list = Narou::TagManager.get_tag_list

              tags = tag_list.map do |tagname, count|
                {
                  name: tagname,
                  count: count,
                  color: Narou::TagManager.get_color(tagname)
                }
              end

              json success_response({ tags: tags.sort_by { |tag| tag[:name] } })
            rescue StandardError => e
              status 500
              json error_response("TAG_LIST_ERROR", e.message)
            end
          end

          # GET /api/v2/tags/index
          # タグインデックス取得（タグ名 → 小説IDリストのマップ）
          # フロントエンドでの高速フィルタリング用
          # キャッシュを使用して高速化
          get "/api/v2/tags/index" do
            set_cors_headers

            begin
              # クラス変数でキャッシュを保持
              @@tag_index_cache ||= { data: nil, generated_at: nil }

              # キャッシュが存在し、データベースの更新時刻より新しい場合はキャッシュを返す
              database = Database.instance
              db_mtime = database.cache_modified_time.to_i # Time を Integer に変換

              if @@tag_index_cache[:data] && @@tag_index_cache[:generated_at] &&
                 @@tag_index_cache[:generated_at] >= db_mtime
                # キャッシュヒット
                json success_response(@@tag_index_cache[:data])
              else
                # キャッシュミス - 新規生成
                tag_index = {}

                # 全小説をスキャンしてタグインデックスを構築
                database.each do |id, novel_data|
                  tags = novel_data["tags"]
                  next unless tags && tags.is_a?(Array)

                  # IDを明示的に整数に変換
                  novel_id = id.to_i

                  tags.each do |tag|
                    tag_index[tag] ||= []
                    tag_index[tag] << novel_id
                  end
                end

                # 各タグのID配列をソート（オプション、検索性能にはあまり影響しない）
                tag_index.each_value(&:sort!)

                generated_at = Time.now.to_i
                response_data = {
                  tag_index: tag_index,
                  total_tags: tag_index.size,
                  generated_at: generated_at
                }

                # キャッシュを更新
                @@tag_index_cache = { data: response_data, generated_at: generated_at }

                json success_response(response_data)
              end
            rescue StandardError => e
              status 500
              json error_response("TAG_INDEX_ERROR", e.message)
            end
          end

          # POST /api/v2/tags/info
          # タグ詳細情報取得（選択された小説のタグ状態）
          post "/api/v2/tags/info" do
            set_cors_headers

            body = parse_json_body
            ids = validate_ids(body["ids"])

            unless ids
              status 400
              return json error_response("INVALID_PARAMS", "Valid novel IDs are required")
            end

            begin
              require "lib/narou/tag_manager"
              tag_info = Narou::TagManager.get_tag_info(ids)

              json success_response({ tag_info: tag_info })
            rescue StandardError => e
              status 500
              json error_response("TAG_INFO_ERROR", e.message)
            end
          end

          # POST /api/v2/tags/edit
          # タグ一括編集
          post "/api/v2/tags/edit" do
            set_cors_headers

            body = parse_json_body
            ids = validate_ids(body["ids"])
            states = body["states"]

            unless ids
              status 400
              return json error_response("INVALID_PARAMS", "Valid novel IDs are required")
            end

            unless states && states.is_a?(Hash) && !states.empty?
              status 400
              return json error_response("INVALID_PARAMS", "Tag states are required")
            end

            begin
              require "lib/narou/tag_manager"
              result = Narou::TagManager.edit_tags(states, ids)

              if result[:success]
                # キャッシュをクリア
                NovelListProcessor.clear_all_cache
                @@tag_index_cache = { data: nil, generated_at: nil }

                # PushServerでイベント送信
                if defined?(@@push_server) && @@push_server
                  @@push_server.send_all(:'table.reload')
                  @@push_server.send_all(:'tag.updateCanvas')
                end

                json success_response(
                  {
                    added: result[:added],
                    deleted: result[:deleted],
                    novel_count: result[:novel_count]
                  },
                  message: "Tags edited successfully"
                )
              else
                status 500
                json error_response("TAG_EDIT_ERROR", result[:error])
              end
            rescue StandardError => e
              status 500
              json error_response("TAG_EDIT_ERROR", e.message)
            end
          end

          # POST /api/v2/tags/add
          # タグ追加
          post "/api/v2/tags/add" do
            set_cors_headers

            body = parse_json_body
            ids = validate_ids(body["ids"])
            tags = body["tags"]

            unless ids
              status 400
              return json error_response("INVALID_PARAMS", "Valid novel IDs are required")
            end

            unless tags && tags.is_a?(Array) && !tags.empty?
              status 400
              return json error_response("INVALID_PARAMS", "Tags array is required")
            end

            begin
              require "lib/narou/tag_manager"
              result = Narou::TagManager.add_tags(tags, ids)

              if result[:success]
                # キャッシュをクリア
                NovelListProcessor.clear_all_cache
                @@tag_index_cache = { data: nil, generated_at: nil }

                # PushServerでイベント送信
                if defined?(@@push_server) && @@push_server
                  @@push_server.send_all(:'table.reload')
                  @@push_server.send_all(:'tag.updateCanvas')
                end

                json success_response(
                  { tags: tags, novel_count: result[:added_count] },
                  message: "Tags added successfully"
                )
              else
                status 500
                json error_response("TAG_ADD_ERROR", result[:error])
              end
            rescue StandardError => e
              status 500
              json error_response("TAG_ADD_ERROR", e.message)
            end
          end

          # POST /api/v2/tags/delete
          # タグ削除
          post "/api/v2/tags/delete" do
            set_cors_headers

            body = parse_json_body
            ids = validate_ids(body["ids"])
            tags = body["tags"]

            unless ids
              status 400
              return json error_response("INVALID_PARAMS", "Valid novel IDs are required")
            end

            unless tags && tags.is_a?(Array) && !tags.empty?
              status 400
              return json error_response("INVALID_PARAMS", "Tags array is required")
            end

            begin
              require "lib/narou/tag_manager"
              result = Narou::TagManager.delete_tags(tags, ids)

              if result[:success]
                # キャッシュをクリア
                NovelListProcessor.clear_all_cache
                @@tag_index_cache = { data: nil, generated_at: nil }

                # PushServerでイベント送信
                if defined?(@@push_server) && @@push_server
                  @@push_server.send_all(:'table.reload')
                  @@push_server.send_all(:'tag.updateCanvas')
                end

                json success_response(
                  { tags: tags, novel_count: result[:deleted_count] },
                  message: "Tags deleted successfully"
                )
              else
                status 500
                json error_response("TAG_DELETE_ERROR", result[:error])
              end
            rescue StandardError => e
              status 500
              json error_response("TAG_DELETE_ERROR", e.message)
            end
          end

          # POST /api/v2/tags/color
          # タグの色を設定
          post "/api/v2/tags/color" do
            set_cors_headers

            body = parse_json_body
            colors = body["colors"]

            unless colors && colors.is_a?(Hash) && !colors.empty?
              status 400
              return json error_response("INVALID_PARAMS", "Colors hash is required")
            end

            begin
              require "lib/narou/tag_manager"
              Narou::TagManager.set_colors(colors)

              # PushServerでイベント送信
              if defined?(@@push_server) && @@push_server
                @@push_server.send_all(:'tag.updateCanvas')
              end

              json success_response(
                { colors: colors },
                message: "Tag colors updated successfully"
              )
            rescue StandardError => e
              status 500
              json error_response("TAG_COLOR_ERROR", e.message)
            end
          end
        end
      end
    end
  end
end
