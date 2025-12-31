# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require "securerandom"
require "time"

module Narou
  #
  # タスクキュー管理用のタスククラス
  #
  class Task
    attr_reader :id, :type, :novel_id, :novel_title, :novel_author, :status, :message,
                :created_at, :started_at, :completed_at, :error, :retry_count, :max_retries,
                :progress, :total_steps, :current_step

    # タスクタイプ
    TYPES = %i(download convert update remove).freeze

    # タスク状態
    STATUS_QUEUED = :queued       # キュー待ち
    STATUS_RUNNING = :running     # 実行中
    STATUS_COMPLETED = :completed # 完了
    STATUS_FAILED = :failed       # 失敗
    STATUS_CANCELED = :canceled   # キャンセル
    STATUSES = [STATUS_QUEUED, STATUS_RUNNING, STATUS_COMPLETED, STATUS_FAILED, STATUS_CANCELED].freeze

    def initialize(type:, novel_id: nil, novel_title: nil, novel_author: nil, max_retries: 0)
      unless TYPES.include?(type.to_sym)
        raise ArgumentError, "Invalid task type: #{type}. Must be one of #{TYPES.join(', ')}"
      end

      @id = SecureRandom.uuid
      @type = type.to_sym
      @novel_id = novel_id
      @novel_title = novel_title
      @novel_author = novel_author
      @status = STATUS_QUEUED
      @message = nil
      @created_at = Time.now
      @started_at = nil
      @completed_at = nil
      @error = nil
      @retry_count = 0
      @max_retries = max_retries
      @progress = 0.0          # 0.0 ~ 100.0
      @total_steps = nil       # 全ステップ数
      @current_step = 0        # 現在のステップ
      @mutex = Mutex.new
    end

    #
    # タスクを実行中状態にする
    #
    def start!
      @mutex.synchronize do
        raise "Task already started" if @started_at
        @status = STATUS_RUNNING
        @started_at = Time.now
        @message = "実行中..."
      end
    end

    #
    # タスクを完了状態にする
    #
    def complete!(message = "完了")
      @mutex.synchronize do
        @status = STATUS_COMPLETED
        @completed_at = Time.now
        @message = message
        @error = nil
      end
    end

    #
    # タスクを失敗状態にする
    #
    def fail!(error_message, exception = nil)
      @mutex.synchronize do
        @status = STATUS_FAILED
        @completed_at = Time.now
        @message = error_message
        @error = {
          message: error_message,
          class: exception&.class&.name,
          backtrace: exception&.backtrace&.first(5)
        }
      end
    end

    #
    # タスクをキャンセル状態にする
    #
    def cancel!(message = "キャンセルされました")
      @mutex.synchronize do
        @status = STATUS_CANCELED
        @completed_at = Time.now
        @message = message
      end
    end

    #
    # メッセージを更新
    #
    def update_message(message)
      @mutex.synchronize do
        @message = message
      end
    end

    #
    # 進捗状況を更新（パーセンテージ）
    #
    def update_progress(percentage, message = nil)
      @mutex.synchronize do
        @progress = [[percentage.to_f, 0.0].max, 100.0].min
        @message = message if message
      end
    end

    #
    # 全ステップ数を設定
    #
    def set_total_steps(total)
      @mutex.synchronize do
        @total_steps = total
        @current_step = 0
        @progress = 0.0
      end
    end

    #
    # 現在のステップを進める
    #
    def advance_step(message = nil)
      @mutex.synchronize do
        @current_step += 1
        if @total_steps && @total_steps > 0
          @progress = (@current_step.to_f / @total_steps * 100).round(2)
        end
        @message = message if message
      end
    end

    #
    # 再試行可能か判定
    #
    def retryable?
      @status == STATUS_FAILED && @retry_count < @max_retries
    end

    #
    # 再試行
    #
    def retry!
      @mutex.synchronize do
        raise "Task is not retryable" unless retryable?
        @retry_count += 1
        @status = STATUS_QUEUED
        @message = "再試行中 (#{@retry_count}/#{@max_retries})"
        @error = nil
        @started_at = nil
        @completed_at = nil
      end
    end

    #
    # タスクが終了しているか
    #
    def finished?
      [STATUS_COMPLETED, STATUS_FAILED, STATUS_CANCELED].include?(@status)
    end

    #
    # タスクが実行中か
    #
    def running?
      @status == STATUS_RUNNING
    end

    #
    # タスクがキュー待ちか
    #
    def queued?
      @status == STATUS_QUEUED
    end

    #
    # 経過時間を取得（秒）
    #
    def elapsed_time
      return 0 unless @started_at
      end_time = @completed_at || Time.now
      end_time - @started_at
    end

    #
    # タスク情報をHashに変換
    #
    def to_h
      @mutex.synchronize do
        {
          id: @id,
          type: @type.to_s,
          novel_id: @novel_id,
          novel_title: @novel_title,
          novel_author: @novel_author,
          status: @status.to_s,
          message: @message,
          created_at: @created_at.iso8601,
          started_at: @started_at&.iso8601,
          completed_at: @completed_at&.iso8601,
          elapsed_time: elapsed_time.round(2),
          error: @error,
          retry_count: @retry_count,
          max_retries: @max_retries,
          progress: @progress,
          total_steps: @total_steps,
          current_step: @current_step
        }
      end
    end

    #
    # タスク情報をJSON形式で取得
    #
    def to_json(*_args)
      require "json"
      to_h.to_json
    end
  end
end
