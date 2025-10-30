# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require_relative "commandbase"

# command/*.rb を全て読み込む
Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), "command", "*.rb"))).sort.each do |path|
  require path
end

module Command
  #
  # コマンド一覧（ヘルプ表示順）
  #
  COMMAND_LIST = {
    "download" => defined?(Download) ? Download : nil,
    "update"   => defined?(Update) ? Update : nil,
    "list"     => defined?(List) ? List : nil,
    "convert"  => defined?(Convert) ? Convert : nil,
    "diff"     => defined?(Diff) ? Diff : nil,
    "setting"  => defined?(Setting) ? Setting : nil,
    "alias"    => defined?(Alias) ? Alias : nil,
    "inspect"  => defined?(Inspect) ? Inspect : nil,
    "send"     => defined?(Send) ? Send : nil,
    "folder"   => defined?(Folder) ? Folder : nil,
    "browser"  => defined?(Browser) ? Browser : nil,
    "remove"   => defined?(Remove) ? Remove : nil,
    "freeze"   => defined?(Freeze) ? Freeze : nil,
    "tag"      => defined?(Tag) ? Tag : nil,
    "web"      => defined?(Web) ? Web : nil,
    "mail"     => defined?(Mail) ? Mail : nil,
    "backup"   => defined?(Backup) ? Backup : nil,
    "csv"      => defined?(Csv) ? Csv : nil,
    "clean"    => defined?(Clean) ? Clean : nil,
    "log"      => defined?(Log) ? Log : nil,
    "trace"    => defined?(Trace) ? Trace : nil,
    "help"     => defined?(Help) ? Help : nil,
    "version"  => defined?(Version) ? Version : nil,
    "init"     => defined?(Init) ? Init : nil
  }.compact.freeze

  #
  # API互換用：古い呼び出しをサポート
  #
  def self.get_list
    COMMAND_LIST
  end

  # commandline.rb が呼ぶ用
  def self.names
    COMMAND_LIST.keys
  end

  # commandline.rb が呼ぶ用
  def self.load_command(name)
    key = name.to_s.downcase
    COMMAND_LIST[key]
  end

  def self.exists?(name)
    COMMAND_LIST.key?(name)
  end

  # ショートカット定義（上から順に優先度が高い）
  Shortcuts = Hash[*get_list.keys.reverse.flat_map { |s|
    [s[0], s, s[0..1], s]
  }].freeze
end
