# frozen_string_literal: true

require "sinatra/base"
require "lib/web/api/v2/base"
require "lib/web/workers/web_worker"
require "lib/web/workers/convert_worker"
require "lib/web/workers/task"

module Narou
  module ApiV2
    # タスク管理 API v2 エンドポイント
    module Tasks
      def self.register(app)
        app.class_eval do
          # GET /api/v2/tasks
          # タスク一覧取得（全データ、gzip圧縮で送信）
          # クライアント側で全データを保持してSvelte 5 Runesで処理する設計
          get "/api/v2/tasks" do
            set_cors_headers

            begin
              # 全タスクを取得（WebWorkerとConvertWorkerの両方から）
              # Rack::Deflaterが自動的にgzip圧縮してくれる
              web_tasks = Narou::WebWorker.get_tasks
              convert_tasks = Narou::ConvertWorker.get_tasks

              # 両方のタスクを結合してタイムスタンプでソート
              tasks = (web_tasks + convert_tasks).sort_by { |t| t[:created_at] || Time.now.to_s }.reverse

              json success_response(
                { tasks: tasks, count: tasks.length }
              )
            rescue StandardError => e
              status 500
              json error_response("TASKS_ERROR", e.message)
            end
          end

          # GET /api/v2/tasks/summary
          # タスクサマリー取得
          get "/api/v2/tasks/summary" do
            set_cors_headers

            begin
              # WebWorkerとConvertWorkerの統合されたサマリーを取得
              web_summary = Narou::WebWorker.get_tasks_summary
              convert_summary = Narou::ConvertWorker.get_tasks_summary

              # 統合されたサマリーを作成
              summary = {
                current: web_summary[:current],
                queued: web_summary[:queued] || [],
                recent_completed: ((web_summary[:recent_completed] || []) + (convert_summary[:recent_completed] || []))
                        .sort_by { |t| t[:completed_at] || t[:created_at] || "" }
                        .reverse
                        .first(10),
                recent_failed: ((web_summary[:recent_failed] || []) + (convert_summary[:recent_failed] || []))
                        .sort_by { |t| t[:failed_at] || t[:created_at] || "" }
                        .reverse
                        .first(10),
                completed_count: (web_summary[:completed_count] || 0) + (convert_summary[:completed_count] || 0),
                failed_count: (web_summary[:failed_count] || 0) + (convert_summary[:failed_count] || 0),
                convert_current: convert_summary[:current],
                convert_queued: convert_summary[:queued] || []
              }

              json success_response(summary)
            rescue StandardError => e
              status 500
              json error_response("TASKS_SUMMARY_ERROR", e.message)
            end
          end

          # GET /api/v2/tasks/:id
          # 特定のタスク取得
          get "/api/v2/tasks/:id" do
            set_cors_headers

            task_id = params["id"]

            begin
              # WebWorkerとConvertWorkerの両方から検索
              task = Narou::WebWorker.get_task(task_id)
              task ||= Narou::ConvertWorker.get_task(task_id)

              unless task
                status 404
                return json error_response("TASK_NOT_FOUND", "Task #{task_id} not found")
              end

              json success_response(task)
            rescue StandardError => e
              status 500
              json error_response("TASK_ERROR", e.message)
            end
          end

          # OPTIONS /api/v2/tasks (CORS preflight)
          options "/api/v2/tasks" do
            set_cors_headers
            status 204
          end

          # OPTIONS /api/v2/tasks/summary (CORS preflight)
          options "/api/v2/tasks/summary" do
            set_cors_headers
            status 204
          end

          # OPTIONS /api/v2/tasks/:id (CORS preflight)
          options "/api/v2/tasks/:id" do
            set_cors_headers
            status 204
          end

          # POST /api/v2/tasks/:id/cancel
          # タスクをキャンセル
          post "/api/v2/tasks/:id/cancel" do
            set_cors_headers

            task_id = params["id"]

            begin
              # WebWorkerとConvertWorkerの両方から検索してキャンセル
              result = Narou::WebWorker.cancel_task(task_id)
              result = Narou::ConvertWorker.cancel_task(task_id) unless result[:success]

              if result[:success]
                json success_response({ message: result[:message] })
              else
                status 400
                json error_response("TASK_CANCEL_ERROR", result[:message])
              end
            rescue StandardError => e
              status 500
              json error_response("TASK_CANCEL_ERROR", e.message)
            end
          end

          # OPTIONS /api/v2/tasks/:id/cancel (CORS preflight)
          options "/api/v2/tasks/:id/cancel" do
            set_cors_headers
            status 204
          end

          # POST /api/v2/cancel
          # 全タスクキャンセル
          post "/api/v2/cancel" do
            set_cors_headers

            begin
              Narou::WebWorker.cancel
              Narou::ConvertWorker.cancel
              Worker.cancel
              json success_response({ message: "All tasks canceled" })
            rescue StandardError => e
              status 500
              json error_response("CANCEL_ERROR", e.message)
            end
          end

          # POST /api/v2/cancel/all
          # 全タスクキャンセル（/api/v2/cancel と同じ）
          post "/api/v2/cancel/all" do
            set_cors_headers

            begin
              Narou::WebWorker.cancel
              Narou::ConvertWorker.cancel
              Worker.cancel
              json success_response({ message: "All tasks canceled" })
            rescue StandardError => e
              status 500
              json error_response("CANCEL_ERROR", e.message)
            end
          end

          # OPTIONS /api/v2/cancel (CORS preflight)
          options "/api/v2/cancel" do
            set_cors_headers
            status 204
          end

          # OPTIONS /api/v2/cancel/all (CORS preflight)
          options "/api/v2/cancel/all" do
            set_cors_headers
            status 204
          end
        end
      end
    end
  end
end
