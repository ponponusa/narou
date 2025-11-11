# frozen_string_literal: true

#
# Copyright 2025 narou-mod contributors. All rights reserved.
#

module Command
  class Process < CommandBase
    def self.oneline_help
      "WEBサーバープロセスを管理します"
    end

    def initialize
      super("[options]")
      @opt.separator <<~HELP
        ・WEBサーバープロセスの状態確認や停止を行います

        Examples:
          narou-mod process --status   # 実行中のプロセス状態確認
          narou-mod process --pid      # PID表示
          narou-mod process --stop     # プロセス停止

        Options:
      HELP
      @opt.on("--status", "プロセスの状態を表示") {
        @options["status"] = true
      }
      @opt.on("--pid", "PIDを表示") {
        @options["pid"] = true
      }
      @opt.on("--stop", "プロセスを停止") {
        @options["stop"] = true
      }
    end

    def execute(argv)
      super
      
      pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-web.pid")
      
      if @options["stop"]
        stop_process(pid_file)
      elsif @options["pid"]
        show_pid(pid_file)
      else # デフォルトは status
        show_status(pid_file)
      end
    end

    private

    def stop_process(pid_file)
      unless File.exist?(pid_file)
        puts "WEBサーバーは起動していません"
        return
      end

      pid = File.read(pid_file).to_i
      begin
        ::Process.kill("TERM", pid)
        puts "WEBサーバーを停止しました (PID: #{pid})"
        File.delete(pid_file) if File.exist?(pid_file)
      rescue Errno::ESRCH
        puts "PID #{pid} のプロセスが見つかりません"
        File.delete(pid_file) if File.exist?(pid_file)
      rescue Errno::EPERM
        puts "PID #{pid} のプロセスを停止する権限がありません"
      end
    end

    def show_pid(pid_file)
      if File.exist?(pid_file)
        puts File.read(pid_file).strip
      else
        puts "WEBサーバーは起動していません"
        exit 1
      end
    end

    def show_status(pid_file)
      backend_pid_file = pid_file
      frontend_pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-frontend.pid")
      
      backend_running = false
      frontend_running = false
      backend_pid = nil
      frontend_pid = nil
      
      # バックエンドの状態確認
      if File.exist?(backend_pid_file)
        backend_pid = File.read(backend_pid_file).to_i
        if process_running?(backend_pid)
          backend_running = true
        else
          File.delete(backend_pid_file)
        end
      end
      
      # フロントエンドの状態確認
      if File.exist?(frontend_pid_file)
        frontend_pid = File.read(frontend_pid_file).to_i
        if process_running?(frontend_pid)
          frontend_running = true
        else
          File.delete(frontend_pid_file)
        end
      end
      
      # 状態を表示
      if backend_running
        puts "バックエンドサーバー: 実行中 (PID: #{backend_pid})"
        
        # ポート情報を表示
        setting = Inventory.load("server_setting", :global)
        if setting["server-port"]
          puts "  ポート: #{setting["server-port"]}"
          puts "  URL: http://localhost:#{setting["server-port"]}/"
        end
      else
        puts "バックエンドサーバー: 停止中"
      end
      
      if frontend_running
        puts "フロントエンドサーバー: 実行中 (PID: #{frontend_pid})"
        puts "  URL: http://localhost:4321/"
      else
        puts "フロントエンドサーバー: 停止中"
      end
      
      if !backend_running && !frontend_running
        puts ""
        puts "両サーバーが停止しています"
      end
    end

    def process_running?(pid)
      ::Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end
  end
end
