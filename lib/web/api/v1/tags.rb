# frozen_string_literal: true

module Narou
  module ApiV1
    module Tags
      def self.register(app)
        app.class_eval do
          # タグ一覧（HTML形式）
          get "/api/tag_list" do
            result =
              +'<div><span class="tag tag-reset label label-default" data-tag="">タグ検索を解除</span></div>' \
              '<div class="text-muted" style="font-size:10px">Altキーを押しながらで除外検索</div>'
            tagname_list = Command::Tag.get_tag_list.keys
            tagname_list.sort.each do |tagname|
              result << "<div>#{decorate_tags([tagname])} " \
                        "<span class='select-color-button' data-target-tag='#{h tagname}'>" \
                        "<span class='#{Command::Tag.get_color(tagname)}'>a</span></span></div>"
            end
            result
          end

          # タグ一覧（JSON形式）
          get "/api/tag_list.json" do
            headers "Access-Control-Allow-Origin" => "*"
            tag_list = Narou::TagManager.get_tag_list
            result = tag_list.map do |tagname, count|
              {
                name: tagname,
                count: count,
                color: Narou::TagManager.get_color(tagname)
              }
            end
            json(result.sort_by { |tag| tag[:name] })
          end

          # タグ情報取得（JSON形式）
          post "/api/taginfo.json" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids
            ids.map!(&:to_i)

            # tag情報取得時点でのソート状態が渡された場合はそれを使用
            if params["sort_state"] && params["timestamp"]
              debug_puts "[DEBUG] TagInfo with fixed sort state (timestamp: #{params["timestamp"]})"
              # 固定化された状態でデータを取得
              sorted_ids = sort_ids_with_fixed_state(ids.map(&:to_s), params["sort_state"]).map(&:to_i)
            else
              debug_puts "[DEBUG] TagInfo with current state"
              sorted_ids = ids
            end

            database = Database.instance
            tag_info = {}

            # まず全体のタグ一覧を取得（すべてのタグを選択肢として表示するため）
            all_tags = Command::Tag.get_tag_list
            all_tags.each do |tag, total_count|
              tag_info[tag] = {
                count: 0,
                total_count: total_count,
                tag: tag,
                html: decorate_tags([tag]),
                exclusion_html: params["with_exclusion"] ? decorate_exclusion_tags([tag]) : ""
              }
            end

            # 選択されたIDの小説での各タグの出現回数を計算
            sorted_ids.each do |id|
              data = database[id]
              next unless data

              tags = data["tags"] || []
              tags.each do |tag|
                if tag_info[tag]
                  tag_info[tag][:count] += 1
                end
              end
            end

            debug_puts "[DEBUG] TagInfo processing #{sorted_ids.length} novels for #{tag_info.keys.length} tags (#{all_tags.keys.length} total tags available)"
            json Hash[tag_info.sort_by { |k, v| k }].values
          end

          # タグ編集
          post "/api/edit_tag" do
            request.body.rewind
            raw_body = request.body.read.to_s

            unless request.media_type == "application/json"
              debug_puts "[ERROR] Unsupported Content-Type for tag edit: #{request.media_type.inspect}"
              halt 415, json({
                success: false,
                error: "Unsupported Media Type",
                message: "このエンドポイントは application/json のみ受け付けます"
              })
            end

            if raw_body.empty?
              debug_puts "[ERROR] Empty request body for tag edit"
              halt 400, json({ success: false, error: "Empty request body" })
            end

            begin
              request_payload = JSON.parse(raw_body)
            rescue JSON::ParserError => e
              debug_puts "[ERROR] Failed to parse JSON payload: #{e.message}"
              halt 400, json({ success: false, error: "Invalid JSON payload" })
            end

            unless request_payload.is_a?(Hash)
              debug_puts "[ERROR] Tag edit payload must be a JSON object: #{request_payload.class.name}"
              halt 400, json({ success: false, error: "JSON object required" })
            end

            ids = select_valid_novel_ids(request_payload["ids"])
            bad_request!("小説が選択されていません") unless ids

            # tag編集実行時点でのソート状態が渡された場合はそれを使用
            if request_payload["sort_state"] && request_payload["timestamp"]
              debug_puts "[DEBUG] Tag edit with fixed sort state (timestamp: #{request_payload["timestamp"]})"
              sorted_ids = sort_ids_with_fixed_state(ids, request_payload["sort_state"])
            else
              debug_puts "[DEBUG] Tag edit with current sort state"
              sorted_ids = ids
            end

            debug_puts "[DEBUG] Tag edit processing #{sorted_ids.length} novels: #{sorted_ids.inspect}"
            debug_puts "[DEBUG] Received payload: #{request_payload.inspect}"
            debug_puts "[DEBUG] Received states param: #{request_payload["states"].inspect}"
            debug_puts "[DEBUG] Received states class: #{request_payload["states"]&.class&.name || 'nil'}"

            # states パラメータの存在チェック
            if request_payload["states"].nil? || request_payload["states"].empty?
              debug_puts "[ERROR] States parameter is nil or empty"
              return { success: false, error: "No tag states provided" }.to_json
            end

            # TagManager を使ってタグ編集を実行
            begin
              result = Narou::TagManager.edit_tags(request_payload["states"], sorted_ids.map(&:to_i))

              if result[:success]
                debug_puts "タグ編集完了 (追加: #{result[:added].join(', ')}, 削除: #{result[:deleted].join(', ')})"

                # キャッシュをクリアしてからイベント送信
                NovelListProcessor.clear_all_cache
                debug_puts "全キャッシュクリア後にリロードイベントを送信"

                # テーブルリロードとタグキャンバス更新を順次実行
                Narou::AppServer.push_server.send_all(:"table.reload")
                Narou::AppServer.push_server.send_all(:"tag.updateCanvas")

                { success: true }.to_json
              else
                debug_puts "[ERROR] Tag edit failed: #{result[:error]}"
                { success: false, error: result[:error] }.to_json
              end
            rescue => e
              debug_puts "[ERROR] Failed to edit tags: #{e.message}"
              debug_puts "[ERROR] States param details: #{request_payload["states"].inspect}"
              { success: false, error: e.message }.to_json
            end
          end

          # タグ色変更
          post "/api/change_tag_color" do
            tag = params["tag"] or bad_request!("タグが指定されていません")
            color = params["color"] or bad_request!("カラーが指定されていません")
            tag_colors = Inventory.load("tag_colors")
            tag_colors[tag] = color
            tag_colors.save

            # キャッシュを確実にクリアしてからイベント送信
            NovelListProcessor.clear_all_cache
            puts "タグ色変更完了: 全キャッシュクリア後にリロードイベントを送信"

            # テーブルリロードとタグキャンバス更新を順次実行
            Narou::AppServer.push_server.send_all(:"table.reload")
            Narou::AppServer.push_server.send_all(:"tag.updateCanvas")
          end
        end
      end
    end
  end
end
