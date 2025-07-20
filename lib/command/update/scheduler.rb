require "time"
require "thread"
require_relative "../../inventory"

module Command
  class Update
    class Scheduler
      def initialize
        @thread = nil
        @running = false
        @mutex = Mutex.new
      end

      def start
        return if running?
        
        @mutex.synchronize do
          return if @running
          
          inventory = Inventory.load("local_setting", :local)
          enabled = inventory["update.auto-schedule.enable"]
          schedule_string = inventory["update.auto-schedule"]
          
          return unless enabled && schedule_string && !schedule_string.empty?
          
          @running = true
          @thread = Thread.new do
            begin
              run_scheduler(schedule_string)
            rescue => e
              puts "自動アップデートスケジューラーでエラーが発生しました: #{e.message}"
            ensure
              @running = false
            end
          end
        end
      end

      def stop
        @mutex.synchronize do
          if @thread && @running
            @running = false
            @thread.kill
            @thread = nil
          end
        end
      end

      def running?
        @running
      end

      private

      def run_scheduler(schedule_string)
        while @running
          times = parse_schedule_times(schedule_string)
          next_run_time = calculate_next_run_time(times)
          
          if next_run_time
            sleep_until(next_run_time)
            if @running
              execute_auto_update
            end
          else
            sleep(3600) # 1時間待機して再チェック
          end
        end
      end

      def parse_schedule_times(schedule_string)
        return [] if schedule_string.nil? || schedule_string.empty?
        
        schedule_string.split(",").map(&:strip).filter_map do |time_str|
          next if time_str.empty?
          
          if time_str =~ /\A(\d{4})\z/
            hour = $1[0, 2].to_i
            minute = $1[2, 2].to_i
            
            if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
              { hour: hour, minute: minute }
            end
          end
        end
      end

      def calculate_next_run_time(times)
        return nil if times.empty?
        
        now = Time.now
        today = Date.today
        
        # 今日の時間をチェック
        times.each do |time|
          run_time = Time.new(today.year, today.month, today.day, time[:hour], time[:minute], 0)
          return run_time if run_time > now
        end
        
        # 今日の時間がすべて過ぎている場合、明日の最初の時間を返す
        tomorrow = today + 1
        first_time = times.min_by { |t| [t[:hour], t[:minute]] }
        Time.new(tomorrow.year, tomorrow.month, tomorrow.day, first_time[:hour], first_time[:minute], 0)
      end

      def sleep_until(target_time)
        while @running
          now = Time.now
          if now >= target_time
            break
          end
          
          sleep_time = [target_time - now, 60].min # 最大60秒間隔でチェック
          sleep(sleep_time)
        end
      end

      def execute_auto_update
        puts "自動アップデートを実行中... (#{Time.now.strftime('%Y/%m/%d %H:%M:%S')})"
        
        begin
          # WebWorkerを使用して非同期実行
          if defined?(Narou::WebWorker)
            Narou::WebWorker.push do
              puts "自動アップデート処理を開始します"
              begin
                # 同一プロセス内でupdateコマンドを実行して詳細ログを表示
                require_relative "../update"
                
                update_command = Command::Update.new
                
                # exitを回避するため、execute内でのexitをrescueする
                begin
                  update_command.execute([])
                  puts "自動アップデートが正常に完了しました"
                rescue SystemExit => e
                  case e.status
                  when 0
                    puts "自動アップデートが正常に完了しました"
                  when 1..9
                    puts "自動アップデートが完了しました（#{e.status}件の小説でエラーがありました）"
                  else
                    puts "自動アップデートで重大なエラーが発生しました（終了コード: #{e.status}）"
                  end
                end
              rescue => e
                puts "自動アップデート処理中にエラーが発生しました: #{e.message}"
                puts "バックトレース: #{e.backtrace.first(3).join(', ')}"
              end
            end
            puts "自動アップデートをキューに追加しました"
          else
            # フォールバック：別プロセスで実行
            pid = Process.spawn("narou", "update")
            Process.detach(pid)
            puts "自動アップデートを開始しました（プロセスID: #{pid}）"
          end
        rescue => e
          puts "自動アップデート中にエラーが発生しました: #{e.message}"
        end
      end

      class << self
        def instance
          @instance ||= new
        end

        def start
          instance.start
        end

        def stop
          instance.stop
        end

        def running?
          instance.running?
        end
      end
    end
  end
end