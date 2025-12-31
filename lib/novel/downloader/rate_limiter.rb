# frozen_string_literal: true

require "singleton"

class Downloader
  #
  # ダウンロードレート制限を管理するクラス
  #
  # クラス変数の代わりに Singleton パターンを使用して
  # グローバルな状態を管理します。
  #
  class RateLimiter
    include Singleton

    DEFAULT_INTERVAL_WAIT = 0.7   # download.interval のデフォルト値(秒)
    STEPS_WAIT_TIME = 5           # 数話ごとにかかるwaitの秒数

    def initialize
      @wait_counter = 0
      @last_download_time = Time.now - 20
      @interval_sleep_time = nil
      @max_steps_wait_time = nil
      @mutex = Mutex.new
    end

    #
    # レート制限設定を初期化
    #
    def configure
      @mutex.synchronize do
        return if @configured

        interval = Inventory.load("local_setting")["download.interval"] || DEFAULT_INTERVAL_WAIT
        @interval_sleep_time = [interval, 0].max
        @max_steps_wait_time = [STEPS_WAIT_TIME, @interval_sleep_time].max
        @configured = true
      end
    end

    #
    # ダウンロード前の待機処理
    #
    # @param download_wait_steps [Integer] 何話ごとに長い待機を入れるか
    #
    def wait_for_download(download_wait_steps)
      configure unless @configured

      @mutex.synchronize do
        # 最後のダウンロードから一定時間経過していたらカウンターをリセット
        if Time.now - @last_download_time > @max_steps_wait_time
          @wait_counter = 0
        end

        # 指定されたステップごとに長い待機を入れる
        if download_wait_steps > 0 &&
           @wait_counter % download_wait_steps == 0 &&
           @wait_counter >= download_wait_steps
          # MEMO:
          # 小説家になろうは連続DL規制があるため、ウェイトを入れる必要がある。
          # 10話ごとに規制が入るため、10話ごとにウェイトを挟む。
          # 1話ごとに1秒待機を10回繰り返そうと、11回目に規制が入るため、ウェイトは必ず必要。
          sleep(@max_steps_wait_time)
        else
          sleep(@interval_sleep_time) if @wait_counter > 0
        end

        @wait_counter += 1
        @last_download_time = Time.now
      end
    end

    #
    # カウンターをリセット（テスト用）
    #
    def reset!
      @mutex.synchronize do
        @wait_counter = 0
        @last_download_time = Time.now - 20
        @configured = false
      end
    end
  end
end
