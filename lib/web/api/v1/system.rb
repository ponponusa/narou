# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

#
# Legacy API v1 - システム関連エンドポイント
#
# 既存のWebUIとの互換性を維持するためのLegacy API実装
#

module Narou
  module ApiV1
    # システム情報・キュー管理関連 API v1 エンドポイント
    module System
      def self.register(app)
        app.class_eval do
          # キャンセル処理
          post "/api/cancel" do
            Narou::WebWorker.cancel
            Narou::Worker.cancel if Narou.concurrency_enabled?
          end

          # キューサイズ取得
          get "/api/get_queue_size" do
            res = [
              Narou::WebWorker.instance.size, Narou::Worker.size
            ]
            json res
          end

          # 履歴取得
          get "/api/history" do
            case params["stream"]
            when "stdout2"
              $stdout2.string
            else
              $stdout.string
            end
          end

          # 履歴クリア
          post "/api/clear_history" do
            Narou::PushServer.instance.clear_history
            $stdout.string.clear
            $stdout2.string.clear if Narou.concurrency_enabled?
          end

          # バージョン情報（現在）
          get "/api/version/current.json" do
            json({ version: Narou::VERSION })
          end

          # バージョン情報（最新）
          get "/api/version/latest.json" do
            json({ version: Narou.latest_version })
          end

          # ソート状態取得
          get "/api/sort_state" do
            server_setting = Inventory.load("server_setting", :global)
            current_sort = server_setting["current_sort"]

            if current_sort
              json({
                column: current_sort["column"],
                dir: current_sort["dir"]
              })
            else
              # デフォルトソート: 最新話掲載日 降順
              json({
                column: "general_lastup",
                dir: "down"
              })
            end
          end

          # サーバーステータス取得
          get "/api/server/status" do
            # フォアグラウンド実行モードでは、このAPIが応答している時点でバックエンドは起動中
            # PIDファイルはフォアグラウンド実行では作成されないため、チェックしない
            backend_running = true # このAPIが応答している = バックエンドは起動中
            backend_pid = ::Process.pid # 現在のプロセスのPID

            # フロントエンドのステータスは引き続きPIDファイルで判定
            frontend_pid_file = File.join(Narou.tmp_dir, "pids", "narou-frontend.pid")
            frontend_running = false
            frontend_pid = nil

            if File.exist?(frontend_pid_file)
              pid = File.read(frontend_pid_file).to_i
              begin
                ::Process.kill(0, pid)
                # プロセスが存在する
                frontend_running = true
                frontend_pid = pid
              rescue Errno::ESRCH
                # プロセスが存在しない -> PIDファイルを削除
                File.delete(frontend_pid_file)
                frontend_running = false
                frontend_pid = nil
              rescue Errno::EPERM
                # 権限がないが、プロセスは存在する
                frontend_running = true
                frontend_pid = pid
              end
            end

            json({
              backend: {
                running: backend_running,
                pid: backend_pid
              },
              frontend: {
                running: frontend_running,
                pid: frontend_pid
              }
            })
          end

          # サーバー再起動
          post "/api/server/restart" do
            # 再起動リクエストを設定してサーバーを停止（legacy版と同じ実装）
            Thread.new do
              sleep 0.5 # レスポンスを返してから停止

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

            json({ success: true, message: "サーバーを再起動しています..." })
          end

          # サーバー停止
          post "/api/server/stop" do
            # Sinatraサーバーを停止（legacy版と同じ実装）
            Thread.new do
              sleep 0.5 # レスポンスを返してから停止

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

            json({ success: true, message: "サーバーを停止しています..." })
          end
        end
      end
    end
  end
end
