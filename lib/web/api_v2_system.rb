# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require_relative 'api_v2'

module Narou
  module ApiV2
    # システム情報関連 API v2 エンドポイント
    module System
      def self.register(app)
        app.class_eval do
          include Narou::ApiV2::Base

          # GET /api/v2/system/version
          # バージョン情報取得
          get '/api/v2/system/version' do
            set_cors_headers
            
            begin
              version_data = {
                narou: Narou::VERSION,
                ruby: RUBY_VERSION,
                latest: Narou.latest_version
              }
              
              json success_response(version_data)
            rescue StandardError => e
              status 500
              json error_response('VERSION_ERROR', e.message)
            end
          end

          # GET /api/v2/system/queue
          # キュー情報取得
          get '/api/v2/system/queue' do
            set_cors_headers
            
            begin
              web_worker_size = Narou::WebWorker.instance.size
              worker_size = Narou::Worker.size
              total_size = web_worker_size + worker_size
              
              queue_data = {
                total: total_size,
                web_worker: web_worker_size,
                worker: worker_size,
                running: total_size > 0
              }
              
              json success_response(queue_data)
            rescue StandardError => e
              status 500
              json error_response('QUEUE_ERROR', e.message)
            end
          end

          # GET /api/v2/system/status
          # システムステータス取得（キュー＋PushServer情報）
          get '/api/v2/system/status' do
            set_cors_headers
            
            begin
              web_worker_size = Narou::WebWorker.instance.size
              worker_size = Narou::Worker.size
              total_size = web_worker_size + worker_size
              
              # PushServer の状態を確認
              push_server_running = false
              push_server_port = nil
              if defined?(@@push_server) && @@push_server
                push_server_running = @@push_server.running?
                push_server_port = @@push_server.port if push_server_running
              end
              
              status_data = {
                queue: {
                  total: total_size,
                  web_worker: web_worker_size,
                  worker: worker_size,
                  running: total_size > 0
                },
                push_server: {
                  running: push_server_running,
                  port: push_server_port
                },
                version: {
                  narou: Narou::VERSION,
                  ruby: RUBY_VERSION
                }
              }
              
              json success_response(status_data)
            rescue StandardError => e
              status 500
              json error_response('STATUS_ERROR', e.message)
            end
          end
        end
      end
    end
  end
end
