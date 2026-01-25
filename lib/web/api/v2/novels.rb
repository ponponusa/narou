# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require "cgi"
require "lib/web/api/v2/base"

module Narou
  module ApiV2
    # 小説関連 API v2 エンドポイント
    module Novels
      def self.register(app)
        app.class_eval do
          include Narou::ApiV2::Base

          # GET /api/v2/novels
          # 小説一覧取得（全データ、gzip圧縮で送信）
          # YAMLベースのため、サーバー側で部分的なページネーションは非効率
          # クライアント側で全データを保持してSvelte 5 Runesで処理する設計
          get "/api/v2/novels" do
            set_cors_headers

            begin
              # データベースの準備チェック
              unless database_ready?
                status 503
                headers "Retry-After" => "2" # 2秒後に再試行を推奨
                return json error_response("SERVICE_UNAVAILABLE", "データベースを準備中です。しばらくお待ちください。")
              end

              # パラメータなしで全データを取得
              # Rack::Deflaterが自動的にgzip圧縮してくれる
              result = process_novel_list_request({})

              # レスポンス変換: raw_tags を tags にマッピング
              novels = result[:data].map do |novel|
                novel_data = novel.dup
                novel_data[:tags] = novel_data[:raw_tags] || []
                novel_data.delete(:raw_tags) # raw_tags は削除
                novel_data
              end

              json success_response({
                novels: novels,
                total: result[:recordsTotal]
              })
            rescue StandardError => e
              status 500
              json error_response("INTERNAL_ERROR", e.message)
            end
          end

          # GET /api/v2/novels/:id
          # 小説詳細取得
          get "/api/v2/novels/:id" do
            set_cors_headers

            id = params["id"].to_i
            database = Database.instance
            data = database[id]

            if data
              # タグ情報を配列に変換
              tags = data["tags"] || []
              novel_data = data.dup
              novel_data["tags"] = tags

              # サイトトップURLを生成（toc_urlから）
              toc_url = data["toc_url"]
              if toc_url
                begin
                  uri = URI.parse(toc_url)
                  novel_data["site_top_url"] = "#{uri.scheme}://#{uri.host}/"
                rescue URI::InvalidURIError
                  # URL解析に失敗した場合はnil
                end
              end

              # プロモタグ除去前の元のタイトルと著者を含める
              novel_data["title_original"] = data["title_original"] if data["title_original"]
              novel_data["author_original"] = data["author_original"] if data["author_original"]

              # 状態を動的に生成
              novel_data["status"] = generate_novel_status(id, data)

              # ダウンロード日時と変換日時をファイルシステムから取得
              novel_dir = Downloader.get_novel_data_dir_by_target(id)
              if novel_dir && Dir.exist?(novel_dir)
                # toc.yaml の最終更新日時 = ダウンロード日時
                toc_file = File.join(novel_dir, "toc.yaml")
                if File.exist?(toc_file)
                  novel_data["download_date"] = File.mtime(toc_file)
                end

                # EPUB ファイルの最終更新日時 = 変換日時
                device = Narou.get_device
                ext = device ? device.ebook_file_ext : ".epub"
                epub_paths = Narou.get_ebook_file_paths(id, ext)
                if !epub_paths.empty? && File.exist?(epub_paths[0])
                  novel_data["convert_date"] = File.mtime(epub_paths[0])
                end
              end

              json success_response(novel_data)
            else
              status 404
              json error_response("NOT_FOUND", "Novel ID #{id} not found")
            end
          end

          # POST /api/v2/novels/download
          # 小説ダウンロード
          post "/api/v2/novels/download" do
            set_cors_headers

            body = parse_json_body
            targets = body["targets"]
            force = body["force"] || false
            convert_after_download = body["convert_after_download"] || false
            tags = body["tags"] # タグ（配列または文字列）

            # タグを配列に変換
            tags_array = case tags
                         when Array
                           tags.map(&:to_s).reject(&:empty?)
                         when String
                           tags.split(/[,、\s]+/).map(&:strip).reject(&:empty?)
                         else
                           []
                         end

            if targets.nil? || targets.empty?
              status 400
              return json error_response("INVALID_PARAMS", "targets parameter is required")
            end

            begin
              task_ids = targets.map do |target|
                # target が小説IDの場合、タイトルと作者を取得
                novel_id = nil
                novel_title = nil
                novel_author = nil

                if target.is_a?(Integer) || target.to_s.match?(/^\d+$/)
                  data = Database.instance[target.to_i]
                  if data
                    novel_id = data["id"]
                    novel_title = data["title"]
                    novel_author = data["author"]
                  end
                end

                # タスクを作成
                task = Narou::Task.new(
                  type: :download,
                  novel_id: novel_id,
                  novel_title: novel_title || target,
                  novel_author: novel_author,
                  max_retries: 0
                )

                # タスクをキューに追加
                Narou::WebWorker.push_task(task) do
                  if force
                    CommandLine.run!("download", "--force", target)
                  else
                    CommandLine.run!("download", target)
                  end
                  NovelListProcessor.clear_all_cache
                  @@push_server.send_all(:'table.reload') if defined?(@@push_server)

                  # ダウンロード完了後にタグを付与
                  if tags_array.any?
                    # 新規ダウンロードの場合、targetから小説データを検索
                    downloaded_data = Downloader.get_data_by_target(target)
                    if downloaded_data
                      downloaded_id = downloaded_data["id"]
                      # タグコマンドを実行
                      CommandLine.run!("tag", "--add", tags_array.join(" "), downloaded_id.to_s)
                      NovelListProcessor.clear_all_cache
                    end
                  end

                  # ダウンロード完了後に変換を実行
                  if convert_after_download && novel_id
                    # 変換タスクを作成
                    convert_task = Narou::Task.new(
                      type: :convert,
                      novel_id: novel_id,
                      novel_title: novel_title,
                      novel_author: novel_author,
                      max_retries: 0
                    )

                    # 変換タスクを変換専用ワーカーに追加（並列処理）
                    require "lib/web/workers/convert_worker"
                    Narou::ConvertWorker.push_task(convert_task) do
                      CommandLine.run!("convert", "--no-open", novel_id.to_s)
                      NovelListProcessor.clear_all_cache
                    end
                  end
                rescue StandardError => e
                  # エラー時はログに記録してタスクを失敗状態にする
                  raise e
                end

                task.id
              end

              json success_response(
                {
                  targets: targets,
                  force: force,
                  convert_after_download: convert_after_download,
                  task_ids: task_ids
                },
                message: "Download started"
              )
            rescue StandardError => e
              status 500
              json error_response("DOWNLOAD_ERROR", e.message)
            end
          end

          # POST /api/v2/novels/convert
          # 小説変換
          post "/api/v2/novels/convert" do
            set_cors_headers

            body = parse_json_body
            ids = validate_ids(body["ids"])

            unless ids
              status 400
              return json error_response("INVALID_PARAMS", "Valid novel IDs are required")
            end

            begin
              # 存在しない小説IDをチェック
              not_found_ids = []
              task_ids = []

              ids.each do |id|
                data = Database.instance[id.to_i]

                unless data
                  not_found_ids << id
                  next
                end

                # タスクを作成
                task = Narou::Task.new(
                  type: :convert,
                  novel_id: data["id"],
                  novel_title: data["title"],
                  novel_author: data["author"],
                  max_retries: 0
                )

                # タスクを変換専用ワーカーに追加
                require "lib/web/workers/convert_worker"
                Narou::ConvertWorker.push_task(task) do
                  CommandLine.run!("convert", "--no-open", id)
                  NovelListProcessor.clear_all_cache
                end

                task_ids << task.id
              end

              # エラーがある場合はwarning付きで返す
              if not_found_ids.any?
                json success_response(
                  {
                    ids: ids - not_found_ids,
                    not_found: not_found_ids,
                    count: task_ids.length,
                    task_ids: task_ids
                  },
                  message: "Convert started (#{not_found_ids.length} novels not found)"
                )
              else
                json success_response(
                  { ids: ids, count: task_ids.length, task_ids: task_ids },
                  message: "Convert started"
                )
              end
            rescue StandardError => e
              status 500
              json error_response("CONVERT_ERROR", e.message)
            end
          end

          # POST /api/v2/novels/update
          # 小説更新チェック（既存小説の新着確認）
          # @param ids [Array<Integer>] 更新対象の小説ID配列
          # @param force_redownload [Boolean] 全話強制再ダウンロード（default: false）
          # @param include_frozen [Boolean] 凍結小説も対象にする（default: false）
          # @param convert_after_update [Boolean] 更新後に変換を実行（default: true）
          # @param skip_unchanged [Boolean] 更新なしの小説の変換をスキップ（default: true）
          post "/api/v2/novels/update" do
            set_cors_headers

            body = parse_json_body
            ids = body["ids"]
            force_redownload = body["force_redownload"] || false
            include_frozen = body["include_frozen"] || false
            # convert_after_update のデフォルトは true（指定がなければ変換も実行）
            convert_after_update = body.fetch("convert_after_update", true)
            # skip_unchanged のデフォルトは true（更新なしの小説は変換をスキップ）
            skip_unchanged = body.fetch("skip_unchanged", true)

            if ids.nil? || ids.empty?
              status 400
              return json error_response("INVALID_PARAMS", "ids parameter is required")
            end

            begin
              task_ids = []
              skipped_ids = []

              ids.each do |id|
                # 小説IDから情報を取得
                data = Database.instance[id.to_i]

                unless data
                  skipped_ids << id
                  next
                end

                novel_id = data["id"]
                novel_title = data["title"]
                novel_author = data["author"]

                # タスクを作成
                task = Narou::Task.new(
                  type: :update,
                  novel_id: novel_id,
                  novel_title: novel_title,
                  novel_author: novel_author,
                  max_retries: 0
                )

                # 凍結状態を確認（force_redownload + include_frozen の場合に一時解除が必要）
                is_frozen = Narou.novel_frozen?(novel_id)
                need_temp_unfreeze = force_redownload && include_frozen && is_frozen

                # 更新前の情報を記録（変換スキップ判定用）
                old_new_arrivals_date = data["new_arrivals_date"]
                old_last_update = data["last_update"]

                # タスクをキューに追加
                Narou::WebWorker.push_task(task) do
                  if force_redownload
                    # 全話強制再ダウンロード（download --force 相当）
                    # 凍結小説の場合は一時的に解除してダウンロード後に再凍結
                    if need_temp_unfreeze
                      frozen_list = Inventory.load("freeze")
                      frozen_list.delete(novel_id)
                      frozen_list.save
                    end
                    begin
                      # 常に --no-convert で実行（変換は別ワーカーで実行）
                      args = ["--force", "--no-convert", novel_id.to_s]
                      CommandLine.run!("download", *args)
                    ensure
                      # 元々凍結されていた場合は再凍結
                      if need_temp_unfreeze
                        frozen_list = Inventory.load("freeze")
                        frozen_list[novel_id] = true
                        frozen_list.save
                      end
                    end
                  else
                    # 新着のみ確認（update コマンド）
                    # 常に --no-convert で実行（変換は別ワーカーで実行）
                    args = ["--no-convert"]
                    args << "--force" if include_frozen # 凍結小説も対象
                    args << novel_id.to_s
                    CommandLine.run!("update", *args)
                  end
                  NovelListProcessor.clear_all_cache
                  @@push_server.send_all(:'table.reload') if defined?(@@push_server)

                  # 更新完了後に変換タスクをConvertWorkerに追加
                  if convert_after_update
                    # 更新有無を判定（skip_unchanged が true の場合）
                    should_convert = true
                    if skip_unchanged && !force_redownload
                      # データベースを再読み込みして更新状態を確認
                      updated_data = Database.instance[novel_id]
                      new_new_arrivals_date = updated_data&.dig("new_arrivals_date")
                      new_last_update = updated_data&.dig("last_update")

                      # new_arrivals_date と last_update の両方が変化していなければ更新なしと判定
                      # （タイトル・著者名の変更時は last_update のみ変化する）
                      if new_new_arrivals_date == old_new_arrivals_date && new_last_update == old_last_update
                        should_convert = false
                        # ログ出力（更新なしでスキップ）
                        puts "#{novel_title} は更新がないため変換をスキップしました"
                      end
                    end

                    if should_convert
                      convert_task = Narou::Task.new(
                        type: :convert,
                        novel_id: novel_id,
                        novel_title: novel_title,
                        novel_author: novel_author,
                        max_retries: 0
                      )

                      require "lib/web/workers/convert_worker"
                      Narou::ConvertWorker.push_task(convert_task) do
                        CommandLine.run!("convert", "--no-open", novel_id.to_s)
                        NovelListProcessor.clear_all_cache
                      end
                    end
                  end
                end

                task_ids << task.id
              end

              response_data = {
                ids: ids.map(&:to_i) - skipped_ids.map(&:to_i),
                force_redownload: force_redownload,
                include_frozen: include_frozen,
                convert_after_update: convert_after_update,
                skip_unchanged: skip_unchanged,
                task_ids: task_ids
              }

              if skipped_ids.any?
                response_data[:skipped_ids] = skipped_ids
                json success_response(
                  response_data,
                  message: "Update started (#{skipped_ids.length} novels not found)"
                )
              else
                json success_response(response_data, message: "Update started")
              end
            rescue StandardError => e
              status 500
              json error_response("UPDATE_ERROR", e.message)
            end
          end

          # POST /api/v2/novels/remove
          # 小説削除
          post "/api/v2/novels/remove" do
            set_cors_headers

            body = parse_json_body
            ids = validate_ids(body["ids"])
            with_file = body["with_file"] || false

            unless ids
              status 400
              return json error_response("INVALID_PARAMS", "Valid novel IDs are required")
            end

            begin
              args = with_file ? ["--with-file", "--yes", *ids] : ["--yes", *ids]
              Narou::WebWorker.push do
                CommandLine.run!("remove", *args)
                NovelListProcessor.clear_all_cache
                @@push_server.send_all(:'table.reload') if defined?(@@push_server)
              end

              json success_response(
                { ids: ids, count: ids.length, with_file: with_file },
                message: "Remove started"
              )
            rescue StandardError => e
              status 500
              json error_response("REMOVE_ERROR", e.message)
            end
          end

          # POST /api/v2/novels/freeze
          # 凍結/凍結解除
          # Parameters:
          #   - ids: 小説IDの配列
          #   - freeze: true(凍結) または false(凍結解除)、省略時はトグル
          post "/api/v2/novels/freeze" do
            set_cors_headers

            body = parse_json_body
            ids = validate_ids(body["ids"])

            unless ids
              status 400
              return json error_response("INVALID_PARAMS", "Valid novel IDs are required")
            end

            begin
              freeze_param = body["freeze"]

              Narou::WebWorker.push do
                if freeze_param == true
                  # 明示的に凍結
                  CommandLine.run!("freeze", "--on", ids)
                elsif freeze_param == false
                  # 明示的に凍結解除
                  CommandLine.run!("freeze", "--off", ids)
                else
                  # パラメータなしの場合はトグル
                  CommandLine.run!("freeze", ids)
                end
                NovelListProcessor.clear_all_cache
              end

              action = if freeze_param == true
                         "frozen"
                       else
                         (freeze_param == false ? "unfrozen" : "toggled")
                       end
              json success_response(
                { ids: ids, count: ids.length },
                message: "Novels #{action}"
              )
            rescue StandardError => e
              status 500
              json error_response("FREEZE_ERROR", e.message)
            end
          end

          # GET /api/v2/novels/:id/epub
          # EPUB ファイルダウンロード
          get "/api/v2/novels/:id/epub" do
            set_cors_headers

            id = params["id"].to_i
            database = Database.instance
            data = database[id]

            unless data
              status 404
              return json error_response("NOT_FOUND", "Novel ID #{id} not found")
            end

            # デバイスに応じた拡張子を取得
            device = Narou.get_device
            ext = device ? device.ebook_file_ext : ".epub"
            paths = Narou.get_ebook_file_paths(id, ext)

            if !paths.empty? && File.exist?(paths[0])
              # ファイル名を "[著者名] タイトル.拡張子" の形式にする
              author = data["author"] || "Unknown"
              title = data["title"] || "Untitled"
              filename = "[#{author}] #{title}#{ext}"

              # UTF-8ファイル名をRFC 5987形式でエンコード
              encoded_filename = CGI.escape(filename).gsub("+", "%20")

              # Content-Dispositionヘッダーを設定（RFC 5987形式）
              # send_file の filename オプションは使わず、手動でヘッダーを設定
              content_type "application/epub+zip"
              headers["Content-Disposition"] = "attachment; filename*=UTF-8''#{encoded_filename}"

              send_file(paths[0])
            else
              status 404
              json error_response("EPUB_NOT_FOUND", "EPUB file not found. Please convert the novel first.")
            end
          end

          # GET /api/v2/novels/:id/story
          # 小説のあらすじ取得
          get "/api/v2/novels/:id/story" do
            set_cors_headers

            begin
              unless database_ready?
                status 503
                headers "Retry-After" => "2"
                return json error_response("SERVICE_UNAVAILABLE", "データベースを準備中です。しばらくお待ちください。")
              end

              target_id = params[:id]
              if target_id.nil? || target_id.to_s.empty?
                status 400
                return json error_response("INVALID_REQUEST", "小説IDが指定されていません")
              end

              toc = Downloader.get_toc_by_target(target_id)
              unless toc
                status 404
                return json error_response("NOT_FOUND", "対象の小説が見つかりません")
              end

              story = toc["story"] || ""
              html = HTML.new
              json success_response({
                title: toc["title"],
                story: html.ln_to_br(story.strip)
              })
            rescue StandardError => e
              status 500
              json error_response("INTERNAL_ERROR", e.message)
            end
          end
        end
      end
    end
  end
end
