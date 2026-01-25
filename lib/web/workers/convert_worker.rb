# frozen_string_literal: true

#
# 変換専用ワーカー
# ダウンロード/更新ワーカーとは別に変換タスクを並列処理する
#

require "singleton"
require "lib/web/workers/task"
require "lib/mixin/all"

module Narou
  class ConvertWorker
    include Singleton
    include Mixin::OutputError

    attr_reader :size

    # タスク履歴の最大保持数
    MAX_TASK_HISTORY = 100

    def self.run
      instance.start
    end

    def initialize
      @queue = Queue.new
      @size = 0
      @mutex = Mutex.new
      @worker_thread = nil
      @cancel_signal = false
      @thread_of_block_executing = nil

      # タスク管理用
      @tasks = {}                    # task_id => Task
      @current_task = nil            # 現在実行中のTask
      @task_history = []             # 完了したタスクの履歴
    end

    def running?
      !@worker_thread.nil?
    end

    def start
      return if running?
      @worker_thread = Thread.new do
        loop do
          q = @queue.pop
          task = q[:task]

          if canceled?
            @queue.clear
            @cancel_signal = false
            # キューに残っているタスクをすべてキャンセル
            @mutex.synchronize do
              @tasks.each_value do |t|
                t.cancel! if t.queued?
              end
            end
          else
            # タスクが既にキャンセルされているかチェック
            if task && task.status == :canceled
              @mutex.synchronize do
                # 既にキャンセル済みのタスクはスキップ
                @current_task = nil
              end
              next
            end

            # タスクを実行中状態にする
            @mutex.synchronize do
              @current_task = task
            end
            task.start! if task

            # ブロックを実行
            @thread_of_block_executing = Thread.new do
              q[:block].call
            end
            @thread_of_block_executing.join
            @thread_of_block_executing = nil

            # タスクを完了状態にする
            task.complete! if task
            @mutex.synchronize do
              move_to_history(task) if task
              @current_task = nil
            end
          end
        rescue Interrupt
          # タスクをキャンセル状態にする
          task&.cancel!("中断されました")
          @mutex.synchronize do
            move_to_history(task) if task
            @current_task = nil
          end
        rescue SystemExit
          # 正常終了
        rescue Exception => e
          # ConvertWorkerスレッド内での例外は表示するだけしてスレッドは生かしたままにする
          output_error($stdout, e)
          # タスクを失敗状態にする
          task&.fail!(e.message, e)
          @mutex.synchronize do
            move_to_history(task) if task
            @current_task = nil
          end
        ensure
          if q && q[:counting]
            countdown
          end
          notification_task_updated if task
        end
      end
    end

    def self.cancel
      instance.cancel
    end

    def cancel
      @mutex.synchronize do
        if @size > 0
          @cancel_signal = true
          @size = 0
          @thread_of_block_executing&.raise(Interrupt)
          # 現在実行中のタスクをキャンセル
          @current_task&.cancel!("ユーザーによりキャンセルされました")
        end
      end
      Thread.pass
    end

    def self.canceled?
      instance.canceled?
    end

    def canceled?
      @cancel_signal
    end

    def self.stop
      instance.stop
    end

    def stop
      @worker_thread&.kill
      @worker_thread = nil
    end

    #
    # タスクを追加
    #
    def self.push_task(task, &)
      instance.push_task_impl(task, &)
    end

    def push_task_impl(task, &block)
      raise ArgumentError, "Task must be a Narou::Task" unless task.is_a?(Narou::Task)

      @mutex.synchronize do
        @tasks[task.id] = task
      end

      countup
      @queue.push(block: block, counting: true, task: task)

      notification_task_updated
      task.id
    end

    def notification_queue
      push_server = Narou::AppServer.push_server
      return unless push_server

      # ConvertWorkerのキューサイズを別途通知
      push_server.send_all("notification.convert_queue" => @size)
    end

    #
    # タスク更新通知
    #
    def notification_task_updated
      push_server = Narou::AppServer.push_server
      return unless push_server

      push_server.send_all("notification.task.updated" => get_combined_tasks_summary)
    end

    #
    # WebWorkerとConvertWorkerの統合されたタスクサマリーを取得
    #
    def get_combined_tasks_summary
      convert_summary = get_tasks_summary_impl
      web_summary = Narou::WebWorker.get_tasks_summary

      {
        current: web_summary[:current] || convert_summary[:current],
        queued: (web_summary[:queued] || []) + (convert_summary[:queued] || []),
        recent_completed: ((web_summary[:recent_completed] || []) + (convert_summary[:recent_completed] || []))
          .sort_by { |t| t[:completed_at] || t[:created_at] }
          .reverse
          .first(10),
        recent_failed: ((web_summary[:recent_failed] || []) + (convert_summary[:recent_failed] || []))
          .sort_by { |t| t[:failed_at] || t[:created_at] }
          .reverse
          .first(10),
        completed_count: (web_summary[:completed_count] || 0) + (convert_summary[:completed_count] || 0),
        failed_count: (web_summary[:failed_count] || 0) + (convert_summary[:failed_count] || 0),
        convert_current: convert_summary[:current],
        convert_queued: convert_summary[:queued]
      }
    end

    def countup
      @mutex.synchronize do
        @size += 1
        notification_queue
      end
    end

    def countdown
      @mutex.synchronize do
        @size -= 1
        @size = 0 if @size < 0
        notification_queue
      end
    end

    #
    # タスク一覧を取得
    #
    def self.get_tasks(status: nil, limit: nil)
      instance.get_tasks_impl(status: status, limit: limit)
    end

    def get_tasks_impl(status: nil, limit: nil)
      @mutex.synchronize do
        tasks = @tasks.values + @task_history
        tasks = tasks.select { |t| t.status == status.to_sym } if status
        tasks = tasks.sort_by(&:created_at).reverse
        tasks = tasks.first(limit) if limit
        tasks.map(&:to_h)
      end
    end

    #
    # タスクサマリーを取得
    #
    def self.get_tasks_summary
      instance.get_tasks_summary_impl
    end

    #
    # WebWorkerとConvertWorkerの統合されたタスクサマリーを取得（クラスメソッド）
    #
    def self.get_combined_tasks_summary
      instance.get_combined_tasks_summary
    end

    def get_tasks_summary_impl
      @mutex.synchronize do
        completed_tasks = @task_history.select { |t| t.status == :completed }
        failed_tasks = @task_history.select { |t| t.status == :failed }
        {
          current: @current_task&.to_h,
          queued: @tasks.values.select(&:queued?).map(&:to_h),
          recent_completed: completed_tasks.first(10).map(&:to_h),
          recent_failed: failed_tasks.first(10).map(&:to_h),
          completed_count: completed_tasks.size,
          failed_count: failed_tasks.size
        }
      end
    end

    #
    # 特定のタスクを取得
    #
    def self.get_task(task_id)
      instance.get_task_impl(task_id)
    end

    def get_task_impl(task_id)
      @mutex.synchronize do
        task = @tasks[task_id] || @task_history.find { |t| t.id == task_id }
        task&.to_h
      end
    end

    #
    # 特定のタスクをキャンセル
    #
    def self.cancel_task(task_id)
      instance.cancel_task_impl(task_id)
    end

    def cancel_task_impl(task_id)
      result = nil
      should_notify = false

      @mutex.synchronize do
        task = @tasks[task_id]
        return { success: false, message: "Task not found" } unless task

        if task.queued?
          task.cancel!("ユーザーによりキャンセルされました")
          move_to_history(task)
          should_notify = true
          result = { success: true, message: "Task canceled" }
        elsif task.running? && task == @current_task
          task.cancel!("ユーザーによりキャンセルされました")
          @thread_of_block_executing&.raise(Interrupt)
          should_notify = true
          result = { success: true, message: "Task cancellation requested" }
        else
          result = { success: false, message: "Task cannot be canceled in current state" }
        end
      end

      notification_task_updated if should_notify
      result
    end

    private

    def move_to_history(task)
      @tasks.delete(task.id)
      @task_history.unshift(task)
      @task_history = @task_history.first(MAX_TASK_HISTORY) if @task_history.size > MAX_TASK_HISTORY
    end
  end
end
