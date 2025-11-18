# frozen_string_literal: true

require "sinatra/base"
require_relative "base"
require_relative "../../web_worker"
require_relative "../../task"

module Narou
  module ApiV2
    # タスク管理 API v2 エンドポイント
    module Tasks
      def self.register(app)
        app.class_eval do
          # GET /api/v2/tasks
          # タスク一覧取得
          get '/api/v2/tasks' do
            set_cors_headers
            
            status_filter = params['status']
            limit = params['limit']&.to_i
            
            begin
              tasks = Narou::WebWorker.get_tasks(
                status: status_filter,
                limit: limit
              )
              
              json success_response(
                { tasks: tasks, count: tasks.length }
              )
            rescue StandardError => e
              status 500
              json error_response('TASKS_ERROR', e.message)
            end
          end

          # GET /api/v2/tasks/summary
          # タスクサマリー取得
          get '/api/v2/tasks/summary' do
            set_cors_headers
            
            begin
              summary = Narou::WebWorker.get_tasks_summary
              
              json success_response(summary)
            rescue StandardError => e
              status 500
              json error_response('TASKS_SUMMARY_ERROR', e.message)
            end
          end

          # GET /api/v2/tasks/:id
          # 特定のタスク取得
          get '/api/v2/tasks/:id' do
            set_cors_headers
            
            task_id = params['id']
            
            begin
              task = Narou::WebWorker.get_task(task_id)
              
              unless task
                status 404
                return json error_response('TASK_NOT_FOUND', "Task #{task_id} not found")
              end
              
              json success_response(task)
            rescue StandardError => e
              status 500
              json error_response('TASK_ERROR', e.message)
            end
          end

          # OPTIONS /api/v2/tasks (CORS preflight)
          options '/api/v2/tasks' do
            set_cors_headers
            status 204
          end

          # OPTIONS /api/v2/tasks/summary (CORS preflight)
          options '/api/v2/tasks/summary' do
            set_cors_headers
            status 204
          end

          # OPTIONS /api/v2/tasks/:id (CORS preflight)
          options '/api/v2/tasks/:id' do
            set_cors_headers
            status 204
          end

          # POST /api/v2/tasks/:id/cancel
          # タスクをキャンセル
          post '/api/v2/tasks/:id/cancel' do
            set_cors_headers
            
            task_id = params['id']
            
            begin
              result = Narou::WebWorker.cancel_task(task_id)
              
              if result[:success]
                json success_response({ message: result[:message] })
              else
                status 400
                json error_response('TASK_CANCEL_ERROR', result[:message])
              end
            rescue StandardError => e
              status 500
              json error_response('TASK_CANCEL_ERROR', e.message)
            end
          end

          # POST /api/v2/tasks/:id/pause
          # タスクを一時停止
          post '/api/v2/tasks/:id/pause' do
            set_cors_headers
            
            task_id = params['id']
            
            begin
              result = Narou::WebWorker.pause_task(task_id)
              
              if result[:success]
                json success_response({ message: result[:message] })
              else
                status 400
                json error_response('TASK_PAUSE_ERROR', result[:message])
              end
            rescue StandardError => e
              status 500
              json error_response('TASK_PAUSE_ERROR', e.message)
            end
          end

          # POST /api/v2/tasks/:id/resume
          # タスクを再開
          post '/api/v2/tasks/:id/resume' do
            set_cors_headers
            
            task_id = params['id']
            
            begin
              result = Narou::WebWorker.resume_task(task_id)
              
              if result[:success]
                json success_response({ message: result[:message] })
              else
                status 400
                json error_response('TASK_RESUME_ERROR', result[:message])
              end
            rescue StandardError => e
              status 500
              json error_response('TASK_RESUME_ERROR', e.message)
            end
          end

          # OPTIONS /api/v2/tasks/:id/cancel (CORS preflight)
          options '/api/v2/tasks/:id/cancel' do
            set_cors_headers
            status 204
          end

          # OPTIONS /api/v2/tasks/:id/pause (CORS preflight)
          options '/api/v2/tasks/:id/pause' do
            set_cors_headers
            status 204
          end

          # OPTIONS /api/v2/tasks/:id/resume (CORS preflight)
          options '/api/v2/tasks/:id/resume' do
            set_cors_headers
            status 204
          end
        end
      end
    end
  end
end
