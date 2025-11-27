#! /usr/bin/env ruby
# frozen_string_literal: true

#
# Narou.rb MOD ― 小説家になろうダウンロード＆整形スクリプト
#
# Copyright 2013 whiteleaf. All rights reserved.
#

# プロジェクトルートをロードパスの先頭に追加
script_dir = File.expand_path(__dir__)

# 開発環境（narou.rb が存在する場所から実行）では、インストール済みの gem と
# 競合しないよう対策を行う
# 1. gem のパスを $LOAD_PATH から除外
# 2. 既にロード済みの gem ファイルを $LOADED_FEATURES から除外
# 3. RubyGems の gem 自動解決をリセット
$LOAD_PATH.reject! { |path| path.include?("narou-mod") && path.include?("gems") }
$LOADED_FEATURES.reject! { |path| path.include?("narou-mod") && path.include?("gems") }
$LOAD_PATH.unshift(script_dir) unless $LOAD_PATH.include?(script_dir)

# RubyGems が narou-mod gem を自動解決しないようにする
if defined?(Gem)
  Gem.loaded_specs.delete("narou-mod")
end

require "lib/loading/extension"
require "lib/extensions/monkey_patches"
require "lib/utilities/backtracer"

$debug = File.exist?(File.join(script_dir, "debug"))

Encoding.default_external = Encoding::UTF_8
Narou::Backtracer.argv = ARGV

if ARGV.delete("--time")
  now = Time.now
  at_exit do
    puts "実行時間 #{Time.now - now}秒"
  end
end

require "lib/core/inventory"

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

require "lib/output/narou_logger"
require "lib/core/version"
require "lib/cli/commandline"

exit Narou::Backtracer.capture {
  CommandLine.run!(ARGV.map(&:dup))
}
