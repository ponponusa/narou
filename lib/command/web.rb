# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require_relative "web_legacy"

module Command
  class Web < CommandBase
    def self.oneline_help
      "WEBアプリケーション用サーバを起動します"
    end

    def initialize
      super("[options...]")
      @opt.separator <<~HELP
        ・WEBアプリケーション用サーバを起動します
        ・小説の管理及び設定をブラウザで行うことができます
        ・--port を指定しない場合、ポートは初回起動時にランダムで設定します
          (以降同じ設定を引き継ぎます)
        ・デフォルトでバックグラウンドで起動します (--no-daemon で前面実行)
        ・サーバの停止は 'narou-mod stop' または 'narou-mod process --stop'

        Examples:
          narou-mod web                    # バックグラウンドで起動
          narou-mod web --no-daemon        # フォアグラウンドで起動（Ctrl+Cで停止）
          narou-mod web -p 4567            # ポート4567で起動
          narou-mod web --open-browser     # ブラウザを自動で開く

        Options:
      HELP
      @opt.on("-p", "--port PORT", Integer, "起動するポートを指定") { |port|
        @options["port"] = port
      }
      @opt.on("-n", "--no-browser", "起動時にブラウザは開かない") {
        @options["no-browser"] = true
      }
      @opt.on("-o", "--open-browser", "起動時にブラウザを開く") {
        @options["open-browser"] = true
      }
      @opt.on("-d", "--daemon", "バックグラウンドで起動（デフォルト）") {
        @options["daemon"] = true
      }
      @opt.on("--no-daemon", "フォアグラウンドで起動") {
        @options["daemon"] = false
      }
      @opt.on("-l", "--legacy", "旧 Haml UI を使用する (デフォルトは新 Astro UI)") {
        @options["legacy"] = true
      }
    end

    def execute(argv)
      # --legacy オプションが指定された場合は WebLegacy に委譲
      if argv.include?("--legacy") || argv.include?("-l")
        return WebLegacy.new.execute(argv)
      end

      # --boot オプションの処理
      if argv.delete("--boot")
        @rebooted = !!argv.delete("--reboot")
        super
        # デーモンモードのデフォルト設定（明示的に指定されていない場合のみ）
        @options["daemon"] = true unless @options.key?("daemon")
        boot
      else
        super
        puts "サーバを起動するには --boot オプションを指定してください"
        puts "Example: narou-mod web --boot"
      end
    end

    private

    def host
      @options["host"] || "127.0.0.1"
    end

    def boot
      require_relative "../narou"
      require_relative "../web/appserver"
      
      # 既にサーバーが起動しているかチェック
      pid_file = pid_file_path
      if File.exist?(pid_file)
        existing_pid = File.read(pid_file).to_i
        if process_running?(existing_pid)
          puts "WEBサーバーはすでに起動しています (PID: #{existing_pid})"
          puts "停止するには 'narou-mod stop' を実行してください"
          exit 0
        else
          # 古いPIDファイルを削除
          File.delete(pid_file)
        end
      end
      
      # デーモンモードフラグ
      daemon_mode = @options.fetch("daemon", true)
      
      if daemon_mode
        puts "WEBサーバーをバックグラウンドで起動しています..."
        puts "ログ: tmp/logs/narou-web.log"
        daemonize
        # daemonize内で親プロセスはexit、子プロセスだけがここに到達する
      end

      # サーバーを起動（子プロセスまたはフォアグラウンドモード）
      start_server
    end

    def start_server
      port = @options["port"] || 5678
      
      # PushServerの初期化（Legacy互換）
      Narou::AppServer.push_server = Narou::PushServer.instance
      
      if @options["open-browser"]
        frontend_url = "http://#{host}:4321/"
        Helper.open_browser(frontend_url)
      end
      
      Narou::AppServer.set(:bind, host)
      Narou::AppServer.set(:port, port)
      Narou::AppServer.run!
    end

    def daemonize
      # デーモン化
      pid = fork
      
      if pid
        # 親プロセス
        puts "WEBサーバーをバックグラウンドで起動しました (PID: #{pid})"
        $stdout.flush
        $stderr.flush
        exit 0
      else
        # 子プロセス
        # 出力をフラッシュしてから新しいセッションを作成
        $stdout.flush
        $stderr.flush
        
        # 新しいセッションを作成
        ::Process.setsid
        
        # ログファイルにリダイレクト
        log_file = File.join(Narou.root_dir, "tmp", "logs", "narou-web.log")
        log_dir = File.dirname(log_file)
        FileUtils.mkdir_p(log_dir) unless File.exist?(log_dir)
        
        # STDINをクローズ
        STDIN.reopen("/dev/null")
        
        # STDOUT と STDERR をログファイルにリダイレクト
        STDOUT.reopen(log_file, "a")
        STDOUT.sync = true
        STDERR.reopen(STDOUT)
        STDERR.sync = true
        
        puts "=========================================="
        puts "WEBサーバーが起動しました"
        puts "PID: #{::Process.pid}"
        puts "Time: #{Time.now}"
        puts "=========================================="
        
        # PIDファイルに書き込み
        write_pid_file
        
        # 処理を継続（このメソッドから戻る）
      end
    end

    def pid_file_path
      File.join(Narou.root_dir, "tmp", "pids", "narou-web.pid")
    end

    def write_pid_file
      pid_file = pid_file_path
      pid_dir = File.dirname(pid_file)
      FileUtils.mkdir_p(pid_dir) unless File.exist?(pid_dir)
      File.write(pid_file, ::Process.pid.to_s)
    end

    def delete_pid_file
      File.delete(pid_file_path) if File.exist?(pid_file_path)
    end

    def process_running?(pid)
      ::Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end
  end
end
