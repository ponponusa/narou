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
            backend_running = true  # このAPIが応答している = バックエンドは起動中
            backend_pid = ::Process.pid  # 現在のプロセスのPID
            
            # フロントエンドのステータスは引き続きPIDファイルで判定
            frontend_pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-frontend.pid")
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
            # フォアグラウンド実行モードでは再起動は使用不可
            halt 400, json({
              success: false,
              error: "フォアグラウンド実行モードでは restart コマンドは使用できません。\nサーバーを停止して再起動する場合:\n  1. Ctrl+C でサーバーを停止\n  2. narou-mod web --boot で再起動"
            })
          end

          # サーバー停止
          post "/api/server/stop" do
            # フォアグラウンド実行モードでは、別プロセスでstopコマンドを実行
            pid = fork do
              exec("narou-mod", "stop")
            end
            ::Process.detach(pid)
            
            json({ success: true, message: "サーバーを停止しています...\nCtrl+C で即座に停止することもできます。" })
          end
        end
      end
    end
  end
end
