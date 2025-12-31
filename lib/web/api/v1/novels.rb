# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

#
# Legacy API v1 - Novels エンドポイント
#
# 小説の一覧取得、ダウンロード、変換、更新、削除などの操作を提供
#

module Narou
  module ApiV1
    module Novels
      def self.register(app)
        app.class_eval do
          # 小説一覧取得（DataTables用） - GET版
          get "/api/list" do
            result = process_novel_list_request(params)
            json result
          rescue StandardError => e
            # エラーが発生した場合のレスポンス
            puts "API List Error: #{e.message}"
            puts e.backtrace.join("\n")

            json({
              draw: params["draw"].to_i || 1,
              data: [],
              recordsTotal: 0,
              recordsFiltered: 0,
              error: "サーバーエラーが発生しました: #{e.message}"
            })
          end

          # 小説一覧取得（DataTables用） - POST版（URIが長くなる問題を回避）
          post "/api/list" do
            result = process_novel_list_request(params)
            json result
          rescue StandardError => e
            # エラーが発生した場合のレスポンス
            puts "API List Error: #{e.message}"
            puts e.backtrace.join("\n")

            json({
              draw: params["draw"].to_i || 1,
              data: [],
              recordsTotal: 0,
              recordsFiltered: 0,
              error: "サーバーエラーが発生しました: #{e.message}"
            })
          end

          # 小説の変換
          post "/api/convert" do
            ids = select_valid_novel_ids(params["ids"]) or halt(400, json({ error: "小説が選択されていません" }))

            # convert実行時点でのソート状態が渡された場合はそれを使用
            if params["sort_state"] && params["timestamp"]
              debug_puts "[DEBUG] Convert with fixed sort state (timestamp: #{params["timestamp"]})"
              sorted_ids = sort_ids_with_fixed_state(ids, params["sort_state"])
            else
              # 従来通りの現在のソート状態に基づく並び替え
              debug_puts "[DEBUG] Convert with current sort state"
              sorted_ids = sort_ids_by_current_sort(ids)
            end

            debug_puts "[DEBUG] Convert processing #{sorted_ids.length} novels: #{sorted_ids.inspect}"
            concurrency_push do
              CommandLine.run!("convert", "--no-open", sorted_ids)
            end

            json({
              success: true,
              message: "変換処理を開始しました",
              count: sorted_ids.length,
              ids: sorted_ids
            })
          rescue StandardError => e
            puts "[ERROR] Convert API error: #{e.class}: #{e.message}"
            puts e.backtrace.first(5).join("\n") if $DEBUG
            status 500
            json({ error: "変換処理でエラーが発生しました: #{e.message}" })
          end

          # 小説のダウンロード
          post "/api/download" do
            headers "Access-Control-Allow-Origin" => "*"
            targets_param = params["targets"]
            bad_request!("ダウンロード対象が指定されていません") if targets_param.nil?

            targets = targets_param.is_a?(Array) ? targets_param : targets_param.to_s.split
            targets = targets.map(&:to_s).reject(&:empty?)
            bad_request!("ダウンロード対象が指定されていません") if targets.empty?

            opt_mail = "--mail" if query_to_boolean(params["mail"])
            Narou::WebWorker.push do
              CommandLine.run!("download", targets, opt_mail)
              NovelListProcessor.clear_all_cache # 全キャッシュ無効化
              Narou::AppServer.push_server.send_all(:"table.reload")
            end
            status 200
          end

          # 小説の強制ダウンロード
          post "/api/download_force" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids
            Narou::WebWorker.push do
              CommandLine.run!("download", "--force", ids)
              NovelListProcessor.clear_all_cache # 全キャッシュ無効化
              Narou::AppServer.push_server.send_all(:"table.reload")
            end
            status 200
          end

          # 小説のメール送信
          post "/api/mail" do
            ids = select_valid_novel_ids(params["ids"]) || []
            Narou::WebWorker.push do
              Narou.concurrency_call do
                CommandLine.run!("mail", ids, io: $stdout2)
              end
            end
            status 200
          end

          # 小説の更新
          post "/api/update" do
            if params["update_all"] == "true"
              # 全件更新の場合 - 処理用完全IDリストを使用
              puts "[DEBUG] All novels update requested" if ENV["NAROU_DEBUG"] == "1"

              # 新しいキャッシュシステムで全IDを取得（現在のフィルター・ソート条件適用済み）
              sorted_ids = get_full_sorted_ids(params)
              puts "[DEBUG] Full sorted IDs for update: #{sorted_ids.length} items" if ENV["NAROU_DEBUG"] == "1"
              puts "[DEBUG] First 10 IDs: #{sorted_ids.first(10).inspect}" if ENV["NAROU_DEBUG"] == "1"

              opt_arguments = []
              if params["force"] == "true"
                opt_arguments << "--force"
              end
              Narou::WebWorker.push do
                puts "<white>全ての小説の更新を開始します（#{sorted_ids.length}件を#{current_sort_display_string}で処理）</white>".termcolor
                cmd = Command::Update.new
                if table_reload_timing == "every"
                  cmd.on(:success) do
                    Narou::AppServer.push_server.send_all(:"table.reload")
                  end
                end
                cmd.execute!(sorted_ids, opt_arguments)
                NovelListProcessor.clear_all_cache # 全キャッシュ無効化
                Narou::AppServer.push_server.send_all(:"table.reload")
              end
            else
              # 選択された小説のみ更新 - 処理用完全IDリストと照合
              selected_ids = select_valid_novel_ids(params["ids"]) || []
              puts "[DEBUG] Selected IDs from WebUI: #{selected_ids.inspect}" if ENV["NAROU_DEBUG"] == "1"

              if selected_ids.empty?
                puts "[DEBUG] No valid IDs selected, skipping update" if ENV["NAROU_DEBUG"] == "1"
                status 200
                return
              end

              # 処理用完全IDリストを取得（現在のフィルター・ソート条件適用済み）
              full_sorted_ids = get_full_sorted_ids(params)
              puts "[DEBUG] Full sorted IDs: #{full_sorted_ids.length} items" if ENV["NAROU_DEBUG"] == "1"

              # 選択されたIDを完全リストの順序で並び替え
              sorted_ids = full_sorted_ids.select { |id| selected_ids.include?(id) }
              puts "[DEBUG] Final sorted IDs for update: #{sorted_ids.inspect}" if ENV["NAROU_DEBUG"] == "1"

              if sorted_ids.empty?
                puts "[DEBUG] No selected IDs found in current filter/sort, skipping update" if ENV["NAROU_DEBUG"] == "1"
                status 200
                return
              end

              opt_arguments = []
              if params["force"] == "true"
                opt_arguments << "--force"
              end
              Narou::WebWorker.push do
                puts "<white>更新を開始します（#{sorted_ids.length}件を#{current_sort_display_string}で処理）</white>".termcolor
                cmd = Command::Update.new
                if table_reload_timing == "every"
                  cmd.on(:success) do
                    Narou::AppServer.push_server.send_all(:"table.reload")
                  end
                end
                cmd.execute!(sorted_ids, opt_arguments)
                NovelListProcessor.clear_all_cache # 全キャッシュ無効化
                Narou::AppServer.push_server.send_all(:"table.reload")
              end
            end
            status 200
          end

          # タグによる更新
          post "/api/update_by_tag" do
            tags = params["tags"] || []
            exclusion_tags = params["exclusion_tags"] || []
            tag_params = tags.map do |tag|
              "tag:#{tag}"
            end
            tag_params += exclusion_tags.map do |tag|
              "^tag:#{tag}"
            end
            bad_request!("タグが指定されていません") if tag_params.empty?
            Narou::WebWorker.push do
              cmd = Command::Update.new
              if table_reload_timing == "every"
                cmd.on(:success) do
                  Narou::AppServer.push_server.send_all(:"table.reload")
                end
              end
              cmd.execute!(tag_params)
              NovelListProcessor.clear_all_cache # 全キャッシュ無効化
              Narou::AppServer.push_server.send_all(:"table.reload")
            end
          end

          # 端末への送信
          post "/api/send" do
            ids = select_valid_novel_ids(params["ids"]) || []
            Narou::WebWorker.push do
              Narou.concurrency_call do
                CommandLine.run!("send", ids, io: $stdout2)
              end
            end
          end

          # ブックマークのバックアップ
          post "/api/backup_bookmark" do
            Narou::WebWorker.push do
              CommandLine.run!("send", "--backup-bookmark")
            end
          end

          # 小説の凍結（トグル）
          post "/api/freeze" do
            ids = select_valid_novel_ids(params["ids"]) or halt(400, json({ error: "小説が選択されていません" }))
            Narou::WebWorker.push do
              CommandLine.run!("freeze", ids)
              NovelListProcessor.clear_all_cache
              Narou::AppServer.push_server.send_all(:"table.reload")
            end
            json({ success: true, message: "凍結状態を切り替えました", count: ids.length })
          rescue StandardError => e
            puts "[ERROR] Freeze API error: #{e.class}: #{e.message}"
            status 500
            json({ error: "凍結処理でエラーが発生しました: #{e.message}" })
          end

          # 小説の凍結（ON）
          post "/api/freeze_on" do
            ids = select_valid_novel_ids(params["ids"]) or halt(400, json({ error: "小説が選択されていません" }))
            Narou::WebWorker.push do
              CommandLine.run!("freeze", "--on", ids)
              NovelListProcessor.clear_all_cache
              Narou::AppServer.push_server.send_all(:"table.reload")
            end
            json({ success: true, message: "凍結しました", count: ids.length })
          rescue StandardError => e
            puts "[ERROR] Freeze On API error: #{e.class}: #{e.message}"
            status 500
            json({ error: "凍結処理でエラーが発生しました: #{e.message}" })
          end

          # 小説の凍結（OFF）
          post "/api/freeze_off" do
            ids = select_valid_novel_ids(params["ids"]) or halt(400, json({ error: "小説が選択されていません" }))
            Narou::WebWorker.push do
              CommandLine.run!("freeze", "--off", ids)
              NovelListProcessor.clear_all_cache
              Narou::AppServer.push_server.send_all(:"table.reload")
            end
            json({ success: true, message: "凍結を解除しました", count: ids.length })
          rescue StandardError => e
            puts "[ERROR] Freeze Off API error: #{e.class}: #{e.message}"
            status 500
            json({ error: "凍結解除処理でエラーが発生しました: #{e.message}" })
          end

          # 小説の削除
          post "/api/remove" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids

            # remove実行時点でのソート状態が渡された場合はそれを使用
            if params["sort_state"] && params["timestamp"]
              debug_puts "[DEBUG] Remove with fixed sort state (timestamp: #{params["timestamp"]})"
              sorted_ids = sort_ids_with_fixed_state(ids, params["sort_state"])
            else
              # 従来通りの現在のソート状態に基づく並び替え
              debug_puts "[DEBUG] Remove with current sort state"
              sorted_ids = sort_ids_by_current_sort(ids)
            end

            opt_arguments = []
            if params["with_file"] == "true"
              opt_arguments << "--with-file"
            end

            debug_puts "[DEBUG] Remove processing #{sorted_ids.length} novels: #{sorted_ids.inspect}"
            begin
              Narou::WebWorker.push do
                CommandLine.run!("remove", "--yes", sorted_ids, opt_arguments)
                Narou::AppServer.push_server.send_all(:"table.reload")
              rescue StandardError => e
                Narou::AppServer.push_server.send_all(:error, { message: "削除に失敗しました: #{e.message}" })
              end
              { success: true }.to_json
            rescue StandardError => e
              status 500
              { error: "削除処理でエラーが発生しました: #{e.message}" }.to_json
            end
          end

          # 小説の削除（ファイル込み）
          post "/api/remove_with_file" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids

            # remove実行時点でのソート状態が渡された場合はそれを使用
            if params["sort_state"] && params["timestamp"]
              debug_puts "[DEBUG] Remove with file with fixed sort state (timestamp: #{params["timestamp"]})"
              sorted_ids = sort_ids_with_fixed_state(ids, params["sort_state"])
            else
              # 従来通りの現在のソート状態に基づく並び替え
              debug_puts "[DEBUG] Remove with file with current sort state"
              sorted_ids = sort_ids_by_current_sort(ids)
            end

            debug_puts "[DEBUG] Remove with file processing #{sorted_ids.length} novels: #{sorted_ids.inspect}"
            begin
              Narou::WebWorker.push do
                CommandLine.run!("remove", "--yes", "--with-file", sorted_ids)
                Narou::AppServer.push_server.send_all(:"table.reload")
              rescue StandardError => e
                Narou::AppServer.push_server.send_all(:error, { message: "削除に失敗しました: #{e.message}" })
              end
              { success: true }.to_json
            rescue StandardError => e
              status 500
              { error: "削除処理でエラーが発生しました: #{e.message}" }.to_json
            end
          end

          # 小説のあらすじ取得
          get "/api/story" do
            target_id = params["id"]
            bad_request!("小説IDが指定されていません") if target_id.nil? || target_id.to_s.empty?
            toc = Downloader.get_toc_by_target(target_id)
            unless toc
              status 404
              return json({ success: false, error: "対象の小説が見つかりません" })
            end
            story = toc["story"] || ""
            html = HTML.new
            json title: toc["title"], story: html.ln_to_br(story.strip)
          end

          # 小説総数取得
          get "/api/novels/count" do
            json({ count: Database.instance.get_object.size })
          end

          # 全小説ID取得（フィルタリング対応）
          get "/api/novels/all_ids" do
            result = get_all_filtered_novel_ids(params)
            json result
          end
        end
      end
    end
  end
end
