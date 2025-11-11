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
            
            if targets.nil? || targets.empty?
              status 400
              return json error_response('INVALID_PARAMS', 'targets parameter is required')
            end
            
            begin
              Narou::WebWorker.push do
                if force
                  CommandLine.run!('download', '--force', targets)
                else
                  CommandLine.run!('download', targets)
                end
                Narou::AppServer.clear_all_cache
                @@push_server.send_all(:'table.reload') if defined?(@@push_server)
              end
              
              json success_response(
                { targets: targets, force: force },
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
              Narou::WebWorker.push do
                CommandLine.run!('convert', '--no-open', ids)
                Narou::AppServer.clear_all_cache
              end
              
              json success_response(
                { ids: ids, count: ids.length },
                message: 'Convert started'
              )
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
          # 凍結トグル
          post '/api/v2/novels/freeze' do
            set_cors_headers
            
            body = parse_json_body
            ids = validate_ids(body['ids'])
            
            unless ids
              status 400
              return json error_response('INVALID_PARAMS', 'Valid novel IDs are required')
            end
            
            begin
              Narou::WebWorker.push do
                CommandLine.run!('freeze', '--on', ids)
                Narou::AppServer.clear_all_cache
              end
              
              json success_response(
                { ids: ids, count: ids.length },
                message: 'Freeze toggled'
              )
            rescue StandardError => e
              status 500
              json error_response('FREEZE_ERROR', e.message)
            end
          end
        end
      end
    end
  end
end
