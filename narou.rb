#! /usr/bin/env ruby
# frozen_string_literal: true

#
# Narou.rb ― 小説家になろうダウンロード＆整形スクリプト
#
# Copyright 2013 whiteleaf. All rights reserved.
#

begin
  # narouコマンド前に下記のように環境変数を定義すればbootsnapは無効にする
  # > set NAROU_NO_BOOTSNAP=1
  unless ENV["NAROU_NO_BOOTSNAP"] == "1"
    # 念のためWindows系のプラットフォームではないことを確認しておく
    is_windows = Gem.win_platform? rescue (/mswin|mingw|cygwin|bccwin|wince|emx/ =~ RUBY_PLATFORM)
    unless is_windows
      require "bootsnap"
      Bootsnap.setup(
        cache_dir: 'tmp/bootsnap-cache',
        development_mode: false,
        load_path_cache: true,
        compile_cache_iseq: true,
        compile_cache_yaml: true
      )
    end
  end
rescue Exception => e
  warn "[narou.rb] Bootsnap disabled (#{e.class}: #{e.message})" if ENV["NAROU_BOOTSNAP_DEBUG"] == "1"
end
$bootsnap_enable = defined?(Bootsnap)

require_relative "lib/extension"
require_relative "lib/extensions/monkey_patches"
require_relative "lib/backtracer"

script_dir = File.expand_path(File.dirname(__FILE__))
$debug = File.exist?(File.join(script_dir, "debug"))

Encoding.default_external = Encoding::UTF_8
Narou::Backtracer.argv = ARGV

if ARGV.delete("--time")
  now = Time.now
  at_exit do
    puts "実行時間 #{Time.now - now}秒"
  end
end

require_relative "lib/inventory"

$development = Narou.commit_version.!
if $development
  begin
    require "pry"
    require "awesome_print"
  rescue LoadError
  end
end

global = Inventory.load("global_setting", :global)
$display_backtrace = ARGV.delete("--backtrace")
$display_backtrace ||= $debug
$disable_color = ARGV.delete("--no-color")
$disable_color ||= global["no-color"]
$color_parser ||= global["color-parser"] || "system"

require_relative "lib/narou_logger"
require_relative "lib/version"
require_relative "lib/commandline"

exit Narou::Backtracer.capture {
  CommandLine.run!(ARGV.map(&:dup))
}
