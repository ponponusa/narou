# frozen_string_literal: true

#
# Copyright 2026 ponponusa. All rights reserved.
#

require 'fileutils'

module Narou
  class SectionCache
    # プロセス間ファイルロック
    #
    # 並列プロセスからのキャッシュアクセスを安全に行うためのロック機構
    class FileLock
      class TimeoutError < StandardError; end

      # FileLock を初期化する
      #
      # @param lock_file [String] lock file path
      # @param timeout [Float] timeout in seconds (default: 30)
      def initialize(lock_file, timeout: 30)
        @lock_file = lock_file
        @timeout = timeout
        FileUtils.mkdir_p(File.dirname(@lock_file))
      end

      # ロックを取得してブロックを実行する
      #
      # @param exclusive [Boolean] true for exclusive lock, false for shared lock
      # @yield block to execute with lock
      # @return block result
      def with_lock(exclusive: true)
        mode = exclusive ? File::LOCK_EX : File::LOCK_SH
        start_time = Time.now

        File.open(@lock_file, File::RDWR | File::CREAT) do |f|
          loop do
            if f.flock(mode | File::LOCK_NB)
              begin
                return yield
              ensure
                f.flock(File::LOCK_UN)
              end
            end

            if Time.now - start_time > @timeout
              raise TimeoutError, "ロック取得がタイムアウトしました: #{@lock_file}"
            end

            sleep 0.01
          end
        end
      end
    end
  end
end
