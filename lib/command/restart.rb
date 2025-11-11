# frozen_string_literal: true

#
# Copyright 2025 narou-mod contributors. All rights reserved.
#

require_relative "stop"
require_relative "web"

module Command
  class Restart < CommandBase
    def self.oneline_help
      "WEBサーバーを再起動します"
    end

    def initialize
      super("[options]")
      @opt.separator <<~HELP
        ・WEBサーバーを再起動します

        Examples:
          narou-mod restart          # サーバーを再起動
          narou-mod restart --force  # 強制再起動

        Options:
      HELP
      @opt.on("-f", "--force", "強制再起動") {
        @options["force"] = true
      }
    end

    def execute(argv)
      super
      
      pid_file = File.join(Narou.root_dir, "tmp", "pids", "narou-web.pid")
      
      # 停止処理
      if File.exist?(pid_file)
        puts "WEBサーバーを停止しています..."
        stop_cmd = Stop.new
        stop_argv = @options["force"] ? ["--force"] : []
        stop_cmd.execute(stop_argv)
        
        sleep 2  # サーバーが完全に停止するまで待つ
      else
        puts "WEBサーバーは起動していません。起動します..."
      end
      
      # 起動処理
      puts "WEBサーバーを起動しています..."
      web_cmd = Web.new
      web_cmd.execute(["--boot", "--daemon", "--no-browser"])
      
      puts "WEBサーバーの再起動が完了しました"
    end
  end
end
