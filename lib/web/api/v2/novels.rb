# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require_relative 'base'

module Narou
  module ApiV2
    # 小説関連 API v2 エンドポイント
    module Novels
      def self.register(app)
        app.class_eval do
          include Narou::ApiV2::Base

          # GET /api/v2/novels
          # 小説一覧取得
          get '/api/v2/novels' do
            set_cors_headers
            
            begin
              # データベースの準備チェック
              unless database_ready?
                status 503
                headers 'Retry-After' => '2' # 2秒後に再試行を推奨
                return json error_response('SERVICE_UNAVAILABLE', 'データベースを準備中です。しばらくお待ちください。')
              end
              
              # パラメータ取得
              page = (params['page'] || 1).to_i
              per_page = (params['per_page'] || 50).to_i
              
              # データ取得（既存のprocess_novel_list_requestを利用）
              result = process_novel_list_request(params)
              
              # レスポンス変換: raw_tags を tags にマッピング
              novels = result[:data].map do |novel|
                novel_data = novel.dup
                novel_data[:tags] = novel_data[:raw_tags] || []
                novel_data.delete(:raw_tags) # raw_tags は削除
                novel_data
              end
              
              json success_response({
                novels: novels,
                pagination: {
                  total: result[:recordsTotal],
                  filtered: result[:recordsFiltered],
                  page: page,
                  per_page: per_page
                }
              })
            rescue StandardError => e
              status 500
              json error_response('INTERNAL_ERROR', e.message)
            end
          end

          # GET /api/v2/novels/:id
          # 小説詳細取得
          get '/api/v2/novels/:id' do
            set_cors_headers
            
            id = params['id'].to_i
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
            
            json success_response(novel_data)
            else
              status 404
              json error_response('NOT_FOUND', "Novel ID #{id} not found")
            end
          end

          # POST /api/v2/novels/download
          # 小説ダウンロード
          post '/api/v2/novels/download' do
            set_cors_headers
            
            body = parse_json_body
            targets = body['targets']
            force = body['force'] || false
            convert_after_download = body['convert_after_download'] || false
            
            if targets.nil? || targets.empty?
              status 400
              return json error_response('INVALID_PARAMS', 'targets parameter is required')
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
                  begin
                    if force
                      CommandLine.run!('download', '--force', target)
                    else
                      CommandLine.run!('download', target)
                    end
                    Narou::AppServer.clear_all_cache
                    @@push_server.send_all(:'table.reload') if defined?(@@push_server)
                    
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
                      
                      # 変換タスクをキューに追加
                      Narou::WebWorker.push_task(convert_task) do
                        CommandLine.run!('convert', '--no-open', novel_id.to_s)
                        Narou::AppServer.clear_all_cache
                      end
                    end
                  rescue => e
                    # エラー時はログに記録してタスクを失敗状態にする
                    raise e
                  end
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
                message: 'Download started'
              )
            rescue StandardError => e
              status 500
              json error_response('DOWNLOAD_ERROR', e.message)
            end
          end

          # POST /api/v2/novels/convert
          # 小説変換
          post '/api/v2/novels/convert' do
            set_cors_headers
            
            body = parse_json_body
            ids = validate_ids(body['ids'])
            
            unless ids
              status 400
              return json error_response('INVALID_PARAMS', 'Valid novel IDs are required')
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
                
                # タスクをキューに追加
                Narou::WebWorker.push_task(task) do
                  CommandLine.run!('convert', '--no-open', id)
                  Narou::AppServer.clear_all_cache
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
                  message: 'Convert started'
                )
              end
            rescue StandardError => e
              status 500
              json error_response('CONVERT_ERROR', e.message)
            end
          end

          # POST /api/v2/novels/remove
          # 小説削除
          post '/api/v2/novels/remove' do
            set_cors_headers
            
            body = parse_json_body
            ids = validate_ids(body['ids'])
            with_file = body['with_file'] || false
            
            unless ids
              status 400
              return json error_response('INVALID_PARAMS', 'Valid novel IDs are required')
            end
            
            begin
              args = with_file ? ['--with-file', '--yes', *ids] : ['--yes', *ids]
              Narou::WebWorker.push do
                CommandLine.run!('remove', *args)
                Narou::AppServer.clear_all_cache
                @@push_server.send_all(:'table.reload') if defined?(@@push_server)
              end
              
              json success_response(
                { ids: ids, count: ids.length, with_file: with_file },
                message: 'Remove started'
              )
            rescue StandardError => e
              status 500
              json error_response('REMOVE_ERROR', e.message)
            end
          end

          # POST /api/v2/novels/freeze
          # 凍結/凍結解除
          # Parameters:
          #   - ids: 小説IDの配列
          #   - freeze: true(凍結) または false(凍結解除)、省略時はトグル
          post '/api/v2/novels/freeze' do
            set_cors_headers

            body = parse_json_body
            ids = validate_ids(body['ids'])

            unless ids
              status 400
              return json error_response('INVALID_PARAMS', 'Valid novel IDs are required')
            end

            begin
              freeze_param = body['freeze']
              
              Narou::WebWorker.push do
                if freeze_param == true
                  # 明示的に凍結
                  CommandLine.run!('freeze', '--on', ids)
                elsif freeze_param == false
                  # 明示的に凍結解除
                  CommandLine.run!('freeze', '--off', ids)
                else
                  # パラメータなしの場合はトグル
                  CommandLine.run!('freeze', ids)
                end
                Narou::AppServer.clear_all_cache
              end

              action = freeze_param == true ? 'frozen' : (freeze_param == false ? 'unfrozen' : 'toggled')
              json success_response(
                { ids: ids, count: ids.length },
                message: "Novels #{action}"
              )
            rescue StandardError => e
              status 500
              json error_response('FREEZE_ERROR', e.message)
            end
          end

          # GET /api/v2/novels/:id/epub
          # EPUB ファイルダウンロード
          get '/api/v2/novels/:id/epub' do
            set_cors_headers

            id = params['id'].to_i
            database = Database.instance
            data = database[id]

            unless data
              status 404
              return json error_response('NOT_FOUND', "Novel ID #{id} not found")
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
              encoded_filename = CGI.escape(filename).gsub('+', '%20')
              
              # Content-Dispositionヘッダーを明示的に設定
              content_type "application/epub+zip"
              headers "Content-Disposition" => "attachment; filename*=UTF-8''#{encoded_filename}"
              send_file(paths[0])
            else
              status 404
              json error_response('EPUB_NOT_FOUND', 'EPUB file not found. Please convert the novel first.')
            end
          end
        end
      end
    end
  end
end
