# frozen_string_literal: true

#
# Narou.rb MOD 起動ブートストラップ
#
# narou.rb と bin/narou-mod の共通起動ロジックを提供する
#

module Narou
  module Bootstrap
    class << self
      # メインの起動処理
      # @param script_dir [String] スクリプトのディレクトリパス
      # @param argv [Array<String>] コマンドライン引数
      def run(script_dir, argv = ARGV)
        setup_environment(script_dir, argv)
        setup_global_options(argv)
        execute_command(argv)
      end

      private

      # 環境のセットアップ
      def setup_environment(script_dir, argv)
        require "lib/loading/extension"
        require "lib/extensions/monkey_patches"
        require "lib/utilities/backtracer"

        $debug = File.exist?(File.join(script_dir, "debug"))

        Encoding.default_external = Encoding::UTF_8
        Narou::Backtracer.argv = argv

        setup_time_tracking(argv)

        require "lib/core/inventory"

        $development = Narou.commit_version.!
      end

      # --time オプションの処理
      def setup_time_tracking(argv)
        if argv.delete("--time")
          now = Time.now
          at_exit do
            puts "実行時間 #{Time.now - now}秒"
          end
        end
      end

      # グローバルオプションのセットアップ
      def setup_global_options(argv)
        global = Inventory.load("global_setting", :global)
        $display_backtrace = argv.delete("--backtrace")
        $display_backtrace ||= $debug
        $disable_color = argv.delete("--no-color")
        $disable_color ||= global["no-color"]
        $color_parser ||= global["color-parser"] || "system"

        require "lib/output/narou_logger"
        require "lib/core/version"
        require "lib/cli/commandline"
      end

      # コマンド実行
      def execute_command(argv)
        exit Narou::Backtracer.capture {
          CommandLine.run!(argv.map(&:dup))
        }
      end
    end
  end
end
