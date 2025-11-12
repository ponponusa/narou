# frozen_string_literal: true

#
# Copyright 2025 narou-mod contributors. All rights reserved.
#

require_relative "output_helper"

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
      
      Command::OutputHelper.setup_logger(nil)
      
      backend_stopped = stop_backend
      frontend_stopped = stop_frontend
      
      if !backend_stopped && !frontend_stopped
        Command::OutputHelper.warning("サーバーは起動していません")
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
        Command::OutputHelper.success("バックエンドサーバーを#{signal_name}しました (PID: #{pid})")
        File.delete(pid_file) if File.exist?(pid_file)
        true
      rescue Errno::ESRCH
        Command::OutputHelper.warning("PID #{pid} のプロセスが見つかりません")
        File.delete(pid_file) if File.exist?(pid_file)
        false
      rescue Errno::EPERM
        Command::OutputHelper.error("PID #{pid} のプロセスを停止する権限がありません")
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
        # プロセスグループ全体に停止シグナルを送信
        # npmの子プロセス（astro devなど）も含めて停止
        ::Process.kill("-#{signal}", pid)
        signal_name = @options["force"] ? "強制停止" : "停止"
        Command::OutputHelper.success("フロントエンドサーバーを#{signal_name}しました (PID: #{pid})")
        File.delete(pid_file) if File.exist?(pid_file)
        true
      rescue Errno::ESRCH
        Command::OutputHelper.warning("PID #{pid} のプロセスが見つかりません")
        File.delete(pid_file) if File.exist?(pid_file)
        false
      rescue Errno::EPERM
        Command::OutputHelper.error("PID #{pid} のプロセスを停止する権限がありません")
        exit 1
      end
    end
  end
end
