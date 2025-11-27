# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "singleton"
require "forwardable"
require "lib/mixin/all"

module Narou
  class Worker
    include Singleton
    include Mixin::OutputError

    attr_accessor :queue, :mutex, :size, :worker_thread, :cancel_signal, :thread_of_block_executing,
                  :push_server

    class << self
      extend Forwardable

      def_delegators :instance, :push_server=, :join, :cancel, :canceled?, :stop, :push, :size

      def run
        instance.start
      end
    end

    def initialize
      self.queue = Queue.new
      self.mutex = Mutex.new
      self.size = 0
      self.worker_thread = nil
      self.cancel_signal = false
      self.thread_of_block_executing = nil
    end

    def running?
      worker_thread.present?
    end

    def start
      return if running?
      self.worker_thread = Thread.new do
        loop do
          q = queue.pop
          self.cancel_signal = false
          self.thread_of_block_executing = Thread.new do
            q[:block].call
          end
          thread_of_block_executing.join
          self.thread_of_block_executing = nil
        rescue SystemExit
          break  # 正常終了
        rescue Interrupt
          thread_of_block_executing&.raise(Interrupt)
          self.thread_of_block_executing = nil
          break  # 割り込み時は終了
        rescue Exception => e
          output_error($stdout2, e)
        ensure
          countdown
        end
      ensure
        # スレッド終了時のクリーンアップ
        thread_of_block_executing&.kill
        self.thread_of_block_executing = nil
      end
    end

    def join
      until size.zero?
        unless thread_of_block_executing
          Thread.pass
          next
        end
        thread_of_block_executing&.join
      end
    rescue Interrupt
      thread_of_block_executing&.raise(Interrupt)
      self.thread_of_block_executing = nil
      sleep 0.1
    end

    def cancel
      mutex.synchronize do
        if size > 0
          self.cancel_signal = true
          self.size = 0
          thread_of_block_executing&.raise(Interrupt)
          self.thread_of_block_executing = nil
          queue.clear
        end
      end
      Thread.pass
    end

    def canceled?
      cancel_signal
    end

    def stop
      cancel
      # killは非推奨、安全な終了処理を実装
      if worker_thread&.alive?
        begin
          # ワーカースレッドに終了要求
          worker_thread.raise(Interrupt)
          # 最大2秒待機
          unless worker_thread.join(2)
            # 応答しない場合のみkill
            worker_thread.kill
          end
        rescue
          worker_thread&.kill
        end
      end
      self.worker_thread = nil
    end

    def push(&block)
      countup
      queue.push(block: block)
    end

    def notification_queue
      push_server&.send_all("notification.queue" => [Narou::WebWorker.instance.size, size])
    end

    def countup
      mutex.synchronize do
        self.size += 1
        notification_queue
      end
    end

    def countdown
      mutex.synchronize do
        self.size -= 1
        self.size = 0 if size < 0
        notification_queue
      end
    end
  end
end

if Narou.concurrency_enabled?
  Thread.abort_on_exception = true
  Narou::Worker.run

  at_exit do
    next if Narou.web?
    # ここまでたどり着いた時点でダウンロードとかは終わってるので変換ログを普通に表示する
    $stdout2.silent = false if $stdout2&.respond_to?(:silent=)
    Narou::Worker.join
    Narou::Worker.stop
    Command::Convert.display_sending_error_list if defined?(Command::Convert)
  end
end
