# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require_relative "../tty_helper"

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
        ・サーバ起動後にブラウザを立ち上げます
        ・サーバの停止はコンソールで Ctrl+C を入力します

        Examples:
          narou-mod web   # サーバ起動(ポートはランダム。ポート設定保存)
          narou-mod web -p 4567   # ポート4567で起動(保存はされない)

          # 先に決めておく
          narou-mod s server-port=8000
          narou-mod web   # ポート8000で起動

        Options:
      HELP
      @opt.on("-p", "--port PORT", Integer, "起動するポートを指定") { |port|
        @options["port"] = port
      }
      @opt.on("-n", "--no-browser", "起動時にブラウザは開かない") {
        @options["no-browser"] = true
      }
      @opt.on("-l", "--legacy", "旧 Haml UI を使用する (デフォルトは新 Astro UI)") {
        @options["legacy"] = true
      }
    end

    def confirm_of_first
      setting = Inventory.load("server_setting", :global)
      is_first = !setting["already-server-boot"]
      if is_first
        puts <<~FIRST_BOOT
          初めてサーバを起動します。ファイアウォールのアクセス許可を尋ねられた場合、許可をして下さい。
          また、起動したサーバを止めるにはコンソール上で Ctrl+C を入力するか、ブラウザ上で「設定(歯車マーク)→サーバをシャットダウン」を実行して下さい。
        FIRST_BOOT
        if @options["no-browser"]
          puts "(何かキーを押して下さい)"
        else
          puts "(何かキーを押して下さい。サーバ起動後ブラウザが立ち上がります)"
        end
        # 対話環境でのみキー待ち。非対話（テスト/CI）では即時戻る
        unless TTYHelper.non_interactive?
          $stdin.getch
        end
        setting["already-server-boot"] = true
        setting.save
      end
      is_first
    end

    def create_push_server(params)
      host = params[:host]
      port = params[:port]
      push_server = Narou::PushServer.instance
      accepted_domains = (host == "0.0.0.0" ? "*" : host)
      if accepted_domains != "*"
        global_setting = Inventory.load("global_setting", :global)
        addtional_accepted_domains = global_setting["server-ws-add-accepted-domains"]
        if addtional_accepted_domains
          accepted_domains = [
            accepted_domains,
            addtional_accepted_domains.split(",").map(&:strip)
          ].flatten
        end
      end
      push_server.accepted_domains = accepted_domains
      push_server.port = port + 1
      push_server.host = host
      push_server
    end

    def update_frontend_env(port)
      frontend_dir = File.join(Narou.root_dir, "frontend")
      env_file = File.join(frontend_dir, ".env")
      
      # フロントエンドディレクトリが存在しない場合はスキップ
      return unless File.directory?(frontend_dir)
      
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
    end

    def execute(argv)
      if argv.delete("--boot")
        @rebooted = !!argv.delete("--reboot")
        super
        boot
      else
        argv << "--backtrace" if $display_backtrace
        argv << "--no-color" if $disable_color
        argv << "--boot"
        argv_copy = argv.dup
        kill_threads
        begin
          loop do
            system(RbConfig.ruby, "-x", $0, "web", *argv)
            break unless $?.exitstatus == Narou::EXIT_REQUEST_REBOOT
            argv = argv_copy.dup
            argv.push("--no-browser", "--reboot")
          end
        rescue Interrupt
          # 中断されてコンソールへの入力が可能になってから、WEBrick が終了するまで
          # タイムラグがあって表示がごちゃまぜになるので、終わるのを少し待つ
          sleep 1
        end
      end
    end

    def kill_threads
      return unless worker_available?
      Narou::Worker.stop
    end

    # rubocop:disable Metrics/AbcSize
    def boot
      load_web_dependencies
      confirm_of_first
      
      max_retries = 5
      retry_count = 0
      
      loop do
        begin
          params = Narou::AppServer.create_address(@options["port"])
          
          # フロントエンドの設定ファイルを更新
          update_frontend_env(params[:port])
          
          push_server = create_push_server(params)
          Narou.web = true
          Thread.abort_on_exception = true

          # Legacy モードの設定
          Narou::AppServer.legacy_mode = @options["legacy"] || false

          address = "http://#{params[:host]}:#{params[:port]}/"
          puts address
          puts "サーバを止めるには Ctrl+C を入力"
          if @options["legacy"]
            puts "(Legacy Haml UI モード)"
          else
            puts "(New Astro UI モード)"
          end
          puts

          push_server.run
          open_browser_when_server_boot(address)
          send_rebooted_event_when_connection_recover(push_server)

          $stdout = Narou::StreamingLogger.new(push_server)
          $stdout2 = if Inventory.load["concurrency"]
                       Narou::StreamingLogger.new(push_server, $stdout2, target_console: "stdout2")
                     else
                       $stdout
                     end
          ProgressBar.push_server = push_server
          if worker_available?
            Narou::Worker.push_server = push_server
          end
          Narou::AppServer.push_server = push_server
          Narou::WebWorker.run

          # 自動アップデートスケジューラーを開始
          require_relative "update/scheduler"
          Command::Update::Scheduler.start

          Narou::AppServer.run!

          # 自動アップデートスケジューラーを停止
          Command::Update::Scheduler.stop

          push_server.quit
          Narou::WebWorker.stop
          Narou::Worker.stop if worker_available?
          if Narou::AppServer.request_reboot?
            exit Narou::EXIT_REQUEST_REBOOT
          end
          
          break  # 成功したらループを抜ける
          
        rescue Errno::EADDRINUSE => e
          retry_count += 1
          if retry_count >= max_retries
            Helper.open_browser(address) unless @options["no-browser"]
            $stdout.puts <<~PORT_IN_USE
              #{e}
              ポートが使われています。サーバがすでに立ち上がっているかどうか確認して下さい。
              他のアプリケーションが使っているポートだった場合、ポートを変更して下さい。

              ポートの変更方法
                $ narou-mod s server-port=5678
            PORT_IN_USE
            exit Narou::EXIT_ERROR_CODE
          end
          
          # ポートをインクリメントして再試行
          global_setting = Inventory.load("global_setting", :global)
          current_port = global_setting["server-port"] || 5678
          new_port = current_port + retry_count
          
          $stdout.puts "[WARN] Port #{current_port} is already in use. Trying port #{new_port}..."
          
          # 次回の試行用に一時的にポートを変更（設定ファイルは更新しない）
          @options["port"] = new_port
        end
      end
    end
    # rubocop:enable Metrics/AbcSize

    def open_browser_when_server_boot(address)
      return if @options["no-browser"]
      Thread.new do
        sleep 0.2 until Narou::AppServer.running?
        Helper.open_browser(address)
      end
    end

    def send_rebooted_event_when_connection_recover(push_server)
      return unless @rebooted
      Thread.new do
        timeout = Time.now + 20
        # WebSocketのコネクションが回復するまで待つ
        until push_server.connections.count != 0
          sleep 0.2
          Thread.current.kill if Time.now > timeout
        end
        puts "<yellow>再起動が完了しました。</yellow>".termcolor
        push_server.send_all(:"server.rebooted")
      end
    end

    private

    def worker_available?
      defined?(Narou::Worker)
    end

    def load_web_dependencies
      Command.require_all
      require_relative "../narou_logger"
      require_relative "../downloader"
      require_relative "../sitesetting"
      require_relative "../database"
      require_relative "../html"
      require_relative "../web/all"
    end

  end
end
