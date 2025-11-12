# frozen_string_literal: true

#
# Copyright 2025 narou-mod contributors. All rights reserved.
#

require_relative "stop"
require_relative "web"
require_relative "output_helper"

module Command
  class Restart < CommandBase
    def self.oneline_help
      "WEBサーバーを再起動します"
    end

    def initialize
      super("[options]")
      @opt.separator <<~HELP
        ・WEBサーバーを再起動します
        ・注意: フォアグラウンド実行のため、restart コマンドは使用できません
        ・サーバーを停止して再度起動する場合は、Ctrl+C で停止後に 'narou-mod web --boot' を実行してください

        Examples:
          # サーバーを停止
          # Ctrl+C または narou-mod stop
          
          # サーバーを起動
          narou-mod web --boot

        Options:
      HELP
      @opt.on("-f", "--force", "（非推奨）強制再起動") {
        @options["force"] = true
      }
    end

    def execute(argv)
      super
      
      Command::OutputHelper.setup_logger(nil)
      
      # フォアグラウンド実行では restart は使えない旨を通知
      Command::OutputHelper.warning("フォアグラウンド実行モードでは restart コマンドは使用できません")
      Command::OutputHelper.info("サーバーを停止して再起動する場合:")
      Command::OutputHelper.info("  1. Ctrl+C でサーバーを停止")
      Command::OutputHelper.info("  2. narou-mod web --boot で再起動")
      
      exit 1
    end
  end
end
