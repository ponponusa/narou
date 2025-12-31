# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require "lib/web/api/v2/base"

module Narou
  module ApiV2
    # システム情報関連 API v2 エンドポイント
    module System
      def self.register(app)
        app.class_eval do
          include Narou::ApiV2::Base

          # GET /api/v2/system/version
          # バージョン情報取得
          get "/api/v2/system/version" do
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
              json error_response("VERSION_ERROR", e.message)
            end
          end

          # GET /api/v2/system/queue
          # キュー情報取得
          get "/api/v2/system/queue" do
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
              json error_response("QUEUE_ERROR", e.message)
            end
          end

          # GET /api/v2/system/status
          # システムステータス取得（キュー＋PushServer情報）
          get "/api/v2/system/status" do
            set_cors_headers

            begin
              web_worker_size = Narou::WebWorker.instance.size
              worker_size = Narou::Worker.size
              total_size = web_worker_size + worker_size

              # PushServer の状態を確認
              push_server_running = false
              push_server_port = nil
              push_server = self.class.push_server
              if push_server
                push_server_running = push_server.running?
                push_server_port = push_server.port if push_server_running
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
              json error_response("STATUS_ERROR", e.message)
            end
          end

          # POST /api/v2/cancel
          # すべてのタスクをキャンセル
          post "/api/v2/cancel" do
            set_cors_headers

            begin
              Narou::WebWorker.cancel
              Narou::Worker.cancel if defined?(Narou::Worker)

              json success_response(
                { cancelled: true },
                message: "All tasks cancelled"
              )
            rescue StandardError => e
              status 500
              json error_response("CANCEL_ERROR", e.message)
            end
          end

          # POST /api/v2/console/clear
          # コンソール履歴をクリア
          post "/api/v2/console/clear" do
            set_cors_headers

            begin
              push_server = self.class.push_server
              if push_server
                push_server.clear_history
                json success_response(
                  { cleared: true },
                  message: "Console history cleared"
                )
              else
                status 503
                json error_response("PUSH_SERVER_NOT_AVAILABLE", "PushServer is not running")
              end
            rescue StandardError => e
              status 500
              json error_response("CLEAR_ERROR", e.message)
            end
          end

          # POST /api/v2/server/stop
          # サーバー停止
          post "/api/v2/server/stop" do
            set_cors_headers

            begin
              # レスポンスを返してから停止処理を実行
              Thread.new do
                sleep 0.5

                # クリーンアップ処理
                begin
                  Narou::WebWorker.stop if defined?(Narou::WebWorker)
                rescue StandardError => e
                  $stderr.puts "WebWorkerの停止中にエラー: #{e.message}"
                end

                begin
                  push_server = Narou::PushServer.instance
                  push_server.quit if push_server
                rescue StandardError => e
                  $stderr.puts "PushServerの停止中にエラー: #{e.message}"
                end

                # ProcessManagerを使用してフロントエンドを停止
                begin
                  require "lib/narou/process_manager"
                  frontend_manager = Narou::ProcessManager.new("narou-frontend")
                  if frontend_manager.process_running?
                    frontend_manager.stop_process(timeout: 5)
                  end
                rescue StandardError => e
                  $stderr.puts "フロントエンドの停止中にエラー: #{e.message}"
                end

                # 通常の終了コード（0）で終了（外部ループも停止）
                exit 0
              end

              json success_response(
                { stopping: true },
                message: "Server is stopping..."
              )
            rescue StandardError => e
              status 500
              json error_response("STOP_ERROR", e.message)
            end
          end

          # POST /api/v2/server/restart
          # サーバー再起動
          post "/api/v2/server/restart" do
            set_cors_headers

            begin
              # レスポンスを返してから再起動処理を実行
              Thread.new do
                sleep 0.5

                # クリーンアップ処理
                begin
                  Narou::WebWorker.stop if defined?(Narou::WebWorker)
                rescue StandardError => e
                  $stderr.puts "WebWorkerの停止中にエラー: #{e.message}"
                end

                begin
                  push_server = Narou::PushServer.instance
                  push_server.quit if push_server
                rescue StandardError => e
                  $stderr.puts "PushServerの停止中にエラー: #{e.message}"
                end

                # ProcessManagerを使用してフロントエンドを停止
                begin
                  require "lib/narou/process_manager"
                  frontend_manager = Narou::ProcessManager.new("narou-frontend")
                  if frontend_manager.process_running?
                    frontend_manager.stop_process(timeout: 5)
                  end
                rescue StandardError => e
                  $stderr.puts "フロントエンドの停止中にエラー: #{e.message}"
                end

                # EXIT_REQUEST_REBOOTで終了（外部ループが再起動する）
                exit Narou::EXIT_REQUEST_REBOOT
              end

              json success_response(
                { restarting: true },
                message: "Server is restarting..."
              )
            rescue StandardError => e
              status 500
              json error_response("RESTART_ERROR", e.message)
            end
          end
        end
      end
    end
  end
end
