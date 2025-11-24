#! /usr/bin/env ruby
# frozen_string_literal: true

#
# Narou.rb MOD ― 小説家になろうダウンロード＆整形スクリプト
#
# Copyright 2013 whiteleaf. All rights reserved.
#

# プロジェクトルートをロードパスに追加
script_dir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift(script_dir)

require "lib/loading/extension"
require "lib/extensions/monkey_patches"
require "lib/utilities/backtracer"

$debug = File.exist?("debug")

Encoding.default_external = Encoding::UTF_8
Narou::Backtracer.argv = ARGV

if ARGV.delete("--time")
  now = Time.now
  at_exit do
    puts "実行時間 #{Time.now - now}秒"
  end
end

require "core/inventory"

$development = Narou.commit_version.!
# NOTE:
# 開発用の pry / awesome_print は console コマンド内でのみ遅延ロードします。
# ここ（narou.rb）で require しないことで通常起動を軽くします。

global = Inventory.load("global_setting", :global)
$display_backtrace = ARGV.delete("--backtrace")
$display_backtrace ||= $debug
$disable_color = ARGV.delete("--no-color")
$disable_color ||= global["no-color"]
$color_parser ||= global["color-parser"] || "system"

require "output/narou_logger"
require "core/version"
require "cli/commandline"

exit Narou::Backtracer.capture {
  CommandLine.run!(ARGV.map(&:dup))
}
