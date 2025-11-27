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

# 共通起動ロジックを実行
require "lib/loading/bootstrap"
Narou::Bootstrap.run(script_dir, ARGV)

