# frozen_string_literal: true

#
# Copyright 2025 narou-mod contributors. All rights reserved.
#

module Command
  class Stop < CommandBase
    def self.oneline_help
      "WEBサーバーを停止します"
    end

    def initialize
      super("[options]")
      @opt.separator <<~HELP
        ・WEBサーバーを停止します

        Examples:
          narou-mod stop          # サーバーを停止
          narou-mod stop --force  # 強制停止（SIGKILL）

        Options:
      HELP
      @opt.on("-f", "--force", "強制停止（SIGKILL）") {
        @options["force"] = true
      }
    end

    def execute(argv)
      super
      
      backend_stopped = stop_backend
      frontend_stopped = stop_frontend
      
      if !backend_stopped && !frontend_stopped
        puts "サーバーは起動していません"
      end
    end

    private

    def stop_backend
      pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-web.pid")
      
      unless File.exist?(pid_file)
        return false
      end

      pid = File.read(pid_file).to_i
      signal = @options["force"] ? "KILL" : "TERM"
      
      begin
        ::Process.kill(signal, pid)
        signal_name = @options["force"] ? "強制停止" : "停止"
        puts "バックエンドサーバーを#{signal_name}しました (PID: #{pid})"
        File.delete(pid_file) if File.exist?(pid_file)
        true
      rescue Errno::ESRCH
        puts "PID #{pid} のプロセスが見つかりません"
        File.delete(pid_file) if File.exist?(pid_file)
        false
      rescue Errno::EPERM
        puts "PID #{pid} のプロセスを停止する権限がありません"
        exit 1
      end
    end

    def stop_frontend
      pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-frontend.pid")
      
      unless File.exist?(pid_file)
        return false
      end

      pid = File.read(pid_file).to_i
      signal = @options["force"] ? "KILL" : "TERM"
      
      begin
        ::Process.kill(signal, pid)
        signal_name = @options["force"] ? "強制停止" : "停止"
        puts "フロントエンドサーバーを#{signal_name}しました (PID: #{pid})"
        File.delete(pid_file) if File.exist?(pid_file)
        true
      rescue Errno::ESRCH
        puts "PID #{pid} のプロセスが見つかりません"
        File.delete(pid_file) if File.exist?(pid_file)
        false
      rescue Errno::EPERM
        puts "PID #{pid} のプロセスを停止する権限がありません"
        exit 1
      end
    end
  end
end
