# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

#
# Legacy API v1 - ユーティリティエンドポイント
#
# ノートパッド、バックアップ、デバイス操作等の補助機能
#

module Narou
  module ApiV1
    # ユーティリティ関連 API v1 エンドポイント
    module Utilities
      def self.register(app)
        app.class_eval do
          # ノートパッド読み込み
          get "/api/notepad/read" do
            content_type "text/plain"
            if File.exist?(notepad_text_path)
              File.read(notepad_text_path)
            else
              ""
            end
          end

          # ノートパッド保存
          post "/api/notepad/save" do
            File.write(notepad_text_path, params["text"])
            Narou::AppServer.push_server.send_all("notepad.change" => {
              text: params["text"], object_id: params["object_id"]
            })
            ""
          end

          # デバイス取り外し
          post "/api/eject" do
            do_eject = proc do
              device = Narou.get_device
              device&.eject do
                puts "<bold><green>端末を取り外しました</green></bold>".termcolor
              end
            end
            if params["enqueue"] == "true"
              Narou::WebWorker.push do
                Narou.concurrency_call(&do_eject)
              end
            else
              do_eject.call
            end
            ""
          end

          # Diff情報
          post "/api/diff" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids
            number = params["number"] || "1"
            disabled_log_io = $stdout.dup_with_disabled_logging
            Narou::WebWorker.push do
              # diff コマンドは１度に一つのIDしか受け取らないので一つずつ表示する
              ids.each do |id|
                # セキュリティ的にWEB UIでは独自の差分表示のみ使う
                CommandLine.run!("diff", "--no-tool", id, "--number", number)
                Helper.print_horizontal_rule(disabled_log_io)
              end
            end
          end

          # Diff一覧
          get "/api/diff_list" do
            target = params["target"] or return ""
            id = Downloader.get_id_by_target(target) or return ""
            @list = Command::Diff.new.get_diff_list(id)
            haml :_diff_list, layout: false
          end

          # Diff履歴クリア
          post "/api/diff_clean" do
            target = params["target"] or bad_request!("target が指定されていません")
            id = Downloader.get_id_by_target(target) or bad_request!("対象の小説が見つかりません")
            Narou::WebWorker.push do
              CommandLine.run!("diff", "--clean", id)
            end
          end

          # フォルダを開く
          post "/api/folder" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids
            CommandLine.run!("folder", ids)
          end

          # バックアップ
          post "/api/backup" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids
            Narou::WebWorker.push do
              CommandLine.run!("backup", ids)
            end
          end

          # Inspect
          post "/api/inspect" do
            ids = select_valid_novel_ids(params["ids"])
            bad_request!("小説が選択されていません") unless ids
            Narou::WebWorker.push do
              CommandLine.run!("inspect", ids)
            end
          end

          # CSV ダウンロード
          get "/api/csv/download" do
            content_type "application/csv"
            attachment "novels.csv"

            csv_command = Command::Csv.new
            result = csv_command.generate
            puts "CSVファイルをエクスポートしました (#{result.bytesize} bytes)"
            result
          rescue StandardError => e
            puts "[ERROR] CSVエクスポートに失敗しました: #{e.message}"
            status 500
            content_type "text/plain"
            "CSVエクスポートエラー: #{e.message}"
          end

          # CSV インポート
          post "/api/csv/import" do
            raw_files = params["files"]
            bad_request!("CSVファイルが指定されていません") if raw_files.nil?
            files = raw_files.is_a?(Array) ? raw_files.compact : [raw_files].compact
            bad_request!("CSVファイルが指定されていません") if files.empty?
            csv = Command::Csv.new
            imported_count = 0
            files.each do |file|
              csv.import(file[:tempfile])
              imported_count += 1
            end
            bad_request!("CSVファイルが指定されていません") if imported_count.zero?
            puts "CSVファイルをインポートしました (#{imported_count}件)"
            ""
          rescue StandardError => e
            puts "[ERROR] CSVインポートに失敗しました: #{e.message}"
            status 500
            "CSVインポートエラー: #{e.message}"
          end

          # ダウンロード登録すると同時にグレーのボタン画像を返す
          get "/api/download4ssl" do
            target = params["target"] or error("need a parameter: `target'")
            opt_mail = "--mail" if query_to_boolean(params["mail"])
            Narou::WebWorker.push do
              CommandLine.run!("download", target, opt_mail)
              Narou::AppServer.push_server.send_all(:"table.reload")
            end
            redirect "/resources/images/dl_button1.gif"
          end

          # ダウンロード済みかどうかで表示が変わる画像
          get "/api/downloadable.gif" do
            target = params["target"]
            # 0: 未ダウンロード, 1: ダウンロード済み, 2: ダウンロード出来ない
            number =
              if target
                Downloader.get_id_by_target(target) ? 1 : 0
              else
                2
              end
            redirect "/resources/images/dl_button#{number}.gif"
          end

          # URL検証用正規表現リスト
          get "/api/validate_url_regexp_list" do
            json SiteSetting.settings.values.map { |setting|
              Array(setting["url"]).map do |url|
                "(#{url.gsub(/\?<.+?>/, "?:").gsub("\\", "\\\\")})"
              end
            }.flatten
          end
        end
      end
    end
  end
end
