# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require_relative "web_legacy"
require_relative "output_helper"

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
        ・フォアグラウンドで実行されます（Ctrl+Cで停止）
        ・サーバの停止は Ctrl+C または 'narou-mod stop'

        Examples:
          narou-mod web --boot                    # サーバーを起動
          narou-mod web --boot -p 4567            # ポート4567で起動
          narou-mod web --boot --open-browser     # ブラウザを自動で開く
          narou-mod web --boot --log-file app.log # ログをファイルに出力

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
      @opt.on("--log-file FILE", "ログをファイルに出力（デフォルト: 標準出力）") { |file|
        @options["log-file"] = file
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
        
        # OutputHelperの初期化
        Command::OutputHelper.setup_logger(@options["log-file"])
        
        boot
      else
        super
        $stdout.puts "サーバを起動するには --boot オプションを指定してください"
        $stdout.puts "Example: narou-mod web --boot"
      end
    end

    private

    def host
      @options["host"] || "127.0.0.1"
    end

    # 表示用のホスト名（127.0.0.1をlocalhostに変換）
    def display_host
      host == "127.0.0.1" ? "localhost" : host
    end

    def boot
      # フロントエンド設定を更新（require前に実行）
      port = @options["port"] || 5678
      update_frontend_env(port) if should_start_frontend?
      
      # 起動メッセージを表示（require_relative "../narou" より前に実行）
      # narou.rbをrequireすると$stdoutがNarou::Loggerに置き換わるため
      Command::OutputHelper.render("web_starting", {
        host: display_host,
        port: port,
        frontend_enabled: should_start_frontend?
      })
      
      # Narouモジュールをロード（$stdoutがNarou::Loggerに置き換わる）
      require_relative "../narou"
      require_relative "../web/appserver"
      
      # シグナルハンドラを設定（Ctrl+Cで停止）
      setup_signal_handlers
      
      # フロントエンドを起動
      start_frontend if should_start_frontend?

      # バックエンドサーバーを起動
      start_server
    end

    def setup_signal_handlers
      # Ctrl+C (SIGINT) と SIGTERM のハンドラを設定
      Signal.trap("INT") do
        Command::OutputHelper.info("\n\nサーバーを停止しています...")
        stop_all_servers
        exit 0
      end

      Signal.trap("TERM") do
        Command::OutputHelper.info("SIGTERMを受信しました。サーバーを停止しています...")
        stop_all_servers
        exit 0
      end
    end

    def stop_all_servers
      # フロントエンドサーバーを停止
      stop_frontend if should_start_frontend?
      
      # 必要に応じて追加のクリーンアップ処理
    end

    def stop_frontend
      frontend_pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-frontend.pid")
      
      if File.exist?(frontend_pid_file)
        pid = File.read(frontend_pid_file).to_i
        begin
          Process.kill("TERM", pid)
          File.delete(frontend_pid_file)
        rescue Errno::ESRCH
          # プロセスが既に終了している
          File.delete(frontend_pid_file) if File.exist?(frontend_pid_file)
        end
      end
    end

    def should_start_frontend?
      # テスト環境ではフロントエンドを起動しない
      return false if ENV["NAROU_ENV"] == "test"
      
      # --no-frontendオプションが指定されている場合は起動しない
      return false if @options["no-frontend"]
      
      # 開発環境（frontend/ディレクトリが存在）の場合のみ
      frontend_dir = File.join(Narou.root_dir, "frontend")
      File.directory?(frontend_dir) && File.exist?(File.join(frontend_dir, "package.json"))
    end

    def start_frontend
      frontend_dir = File.join(Narou.root_dir, "frontend")
      frontend_log = File.join(Narou.root_dir, "tmp", "logs", "narou-frontend.log")
      frontend_pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-frontend.pid")
      
      # 既にフロントエンドサーバーが起動しているかチェック
      if File.exist?(frontend_pid_file)
        existing_pid = File.read(frontend_pid_file).to_i
        begin
          ::Process.kill(0, existing_pid)
          Command::OutputHelper.info("フロントエンドサーバーは既に起動しています (PID: #{existing_pid})")
          return
        rescue Errno::ESRCH, Errno::EPERM
          File.delete(frontend_pid_file)
        end
      end
      
      Command::OutputHelper.info("フロントエンドサーバーを起動しています...")
      
      # フロントエンドサーバーをバックグラウンドで起動
      pid = fork do
        # 新しいプロセスグループを作成（stop時に子プロセスも停止できるようにする）
        ::Process.setpgid(0, 0)
        
        Dir.chdir(frontend_dir)
        
        # 標準入力・出力・エラーをリダイレクト
        log_dir = File.dirname(frontend_log)
        FileUtils.mkdir_p(log_dir) unless File.exist?(log_dir)
        
        STDIN.reopen("/dev/null")
        STDOUT.reopen(frontend_log, "a")
        STDERR.reopen(STDOUT)
        STDOUT.sync = true
        STDERR.sync = true
        
        # npm run dev を実行
        exec("npm", "run", "dev")
      end
      
      # PIDファイルに書き込み
      pid_dir = File.dirname(frontend_pid_file)
      FileUtils.mkdir_p(pid_dir) unless File.exist?(pid_dir)
      File.write(frontend_pid_file, pid.to_s)
      
      # プロセスをデタッチ（親プロセスが終了してもフロントエンドは継続）
      Process.detach(pid)
      
      Command::OutputHelper.success("フロントエンドサーバーを起動しました (PID: #{pid})")
      sleep 1  # フロントエンドサーバーの起動を待つ
    end

    def stop_frontend
      frontend_pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-frontend.pid")
      
      return unless File.exist?(frontend_pid_file)
      
      pid = File.read(frontend_pid_file).to_i
      begin
        # プロセスグループごと停止
        ::Process.kill("TERM", -pid)
        sleep 0.5
        
        # 停止を確認
        begin
          ::Process.kill(0, pid)
          # まだ生きている場合は強制終了
          ::Process.kill("KILL", -pid)
        rescue Errno::ESRCH
          # 既に停止済み
        end
        
        File.delete(frontend_pid_file)
        Command::OutputHelper.success("フロントエンドサーバーを停止しました")
      rescue Errno::ESRCH, Errno::EPERM
        File.delete(frontend_pid_file)
      end
    end

    def stop_all_servers
      Command::OutputHelper.info("サーバーを停止しています...")
      stop_frontend if should_start_frontend?
      exit 0
    end

    def setup_signal_handlers
      # Ctrl+C (SIGINT) と kill (SIGTERM) に対応
      Signal.trap("INT") do
        puts "\n"  # 改行を入れて見やすく
        stop_all_servers
      end
      
      Signal.trap("TERM") do
        stop_all_servers
      end
    end

    def start_server
      port = @options["port"] || 5678
      
      # サーバー起動完了メッセージ（$stdoutを置き換える前に表示）
      Command::OutputHelper.render("web_started", {
        host: display_host,
        port: port,
        frontend_enabled: should_start_frontend?
      })
      
      # PushServerの初期化と起動
      push_server = Narou::PushServer.instance
      push_server.port = port + 1
      push_server.host = host
      push_server.accepted_domains = ["*"]
      Narou::AppServer.push_server = push_server
      
      # WorkerとWebWorkerにもpush_serverを設定
      Narou::Worker.push_server = push_server
      
      # PushServerを起動
      push_server.run
      
      # StreamingLoggerを設定（標準出力をPushServerに送信）
      require_relative "../web/streaminglogger"
      $stdout = Narou::StreamingLogger.new(push_server)
      $stdout2 = if Inventory.load["concurrency"]
                   Narou::StreamingLogger.new(push_server, $stdout2, target_console: "stdout2")
                 else
                   $stdout
                 end
      
      # WebWorkerを起動（タスクキュー処理用）
      Narou::WebWorker.run
      
      if @options["open-browser"]
        frontend_url = should_start_frontend? ? "http://#{display_host}:4321/" : "http://#{display_host}:#{port}/"
        Helper.open_browser(frontend_url)
      end
      
      Narou::AppServer.set(:bind, host)
      Narou::AppServer.set(:port, port)
      Narou::AppServer.run!
    end

    def update_frontend_env(port)
      frontend_dir = File.join(Narou.root_dir, "frontend")
      env_file = File.join(frontend_dir, ".env")
      
      ws_port = port + 1
      
      # .envファイルを読み込むか、なければテンプレートを使用
      env_content = if File.exist?(env_file)
                      File.read(env_file)
                    else
                      <<~ENV
                        # バックエンドAPIサーバーのURL
                        # 開発時はViteのプロキシを使用するため空文字列
                        PUBLIC_API_BASE_URL=
                        
                        # PushServer WebSocketポート（HTTPサーバーポート + 1）
                        PUBLIC_PUSH_SERVER_PORT=5679
                        
                        # 開発モード設定
                        PUBLIC_DEV_MODE=true
                      ENV
                    end
      
      # PUBLIC_PUSH_SERVER_PORTを更新
      env_content.gsub!(/^PUBLIC_PUSH_SERVER_PORT=.*$/, "PUBLIC_PUSH_SERVER_PORT=#{ws_port}")
      
      File.write(env_file, env_content)
      
      # astro.config.mjsのプロキシ設定も更新
      config_file = File.join(frontend_dir, "astro.config.mjs")
      if File.exist?(config_file)
        config_content = File.read(config_file)
        config_content.gsub!(/target:\s*['"]http:\/\/localhost:\d+['"]/, "target: 'http://localhost:#{port}'")
        File.write(config_file, config_content)
      end
      
      # ポート情報をJSONファイルとして保存（フロントエンドから読み込み可能にする）
      port_info_file = File.join(frontend_dir, "public", "backend-port.json")
      port_info_dir = File.dirname(port_info_file)
      FileUtils.mkdir_p(port_info_dir) unless File.exist?(port_info_dir)
      
      require 'json'
      port_info = {
        backend_port: port,
        push_server_port: ws_port,
        updated_at: Time.now.iso8601
      }
      File.write(port_info_file, JSON.pretty_generate(port_info))
    end

    private

    def host
      @options["host"] || "127.0.0.1"
    end
  end
end
