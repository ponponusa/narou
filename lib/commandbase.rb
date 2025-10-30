# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "optparse"
require "termcolorlight"

# help をログに記録しないために STDOUT に直接出力する
OptionParser::Officious["help"] = proc do |parser|
  OptionParser::Switch::NoArgument.new do |_arg|
    STDOUT.puts parser.help
    exit
  end
end

module Command
  class CommandBase
    attr_accessor :stream_io

    # postfixies は改行で区切ることで2パターン以上記述できる
    def initialize(postfixies = " ")
      self.stream_io = $stdout
      @opt = OptionParser.new(nil, 20)
      command_name = self.class.to_s[/::(.+)$/, 1].downcase
      banner = postfixies.split("\n").map.with_index { |postfix, i|
        (i.zero? ? "Usage: " : "   or: ") + "narou #{command_name} #{postfix}"
      }.join("\n")
      @opt.banner = "<bold><green>#{TermColorLight.escape(banner)}</green></bold>".termcolor
      @options = {}

      # ヘルプを見やすく色付け
      def @opt.help
        msg = super
        # 見出し部分
        msg.gsub!(/((?:Examples|Options|Configuration|[^\s]+? Variable List):)/) do
          "<underline><bold>#{$1}</bold></underline>".termcolor
        end
        # Examples のコメント部分
        msg.gsub!(/(#.+)$/) { "<cyan>#{TermColorLight.escape($1)}</cyan>".termcolor }
        # 文字列部分
        msg.gsub!(/(".+?")/) { "<yellow>#{TermColorLight.escape($1)}</yellow>".termcolor }
        msg
      end
    end

    def display_help!
      STDOUT.puts @opt.help
      exit
    end

    def execute(argv)
      @options.clear
      load_local_settings
      @opt.parse!(argv)
    rescue OptionParser::InvalidOption => e
      error "不明なオプションです(#{e})"
      exit Narou::EXIT_ERROR_CODE
    rescue OptionParser::InvalidArgument => e
      error "オプションの引数が正しくありません(#{e})"
      exit Narou::EXIT_ERROR_CODE
    rescue OptionParser::MissingArgument => e
      error "オプションの引数が指定されていないか正しくありません(#{e})"
      exit Narou::EXIT_ERROR_CODE
    rescue OptionParser::AmbiguousOption => e
      error "曖昧な省略オプションです(#{e})"
      exit Narou::EXIT_ERROR_CODE
    end

    def load_local_settings
      command_prefix = self.class.to_s[/[^:]+$/].downcase
      local_settings = Inventory.load("local_setting")
      local_settings.each do |name, value|
        if name =~ /^#{command_prefix}\.(.+)$/
          @options[$1] = value
        end
      end
    end

    #
    # タグ情報をID情報に展開する
    #
    def tagname_to_ids(array)
      database  = Database.instance
      tag_index = database.tag_indexies
      all_ids   = database.ids

      # 補集合はこの昇順を基準にする
      all_sorted = Array(all_ids).map(&:to_i).sort
      expanded = []

      array.each do |arg|
        str = arg.to_s

        # 数値はID優先（存在すれば）
        if str =~ /\A\d+\z/
          id = str.to_i
          if database[id]
            expanded << id
            next
          end
        end

        case str
        when /\Atag:(.+)\z/
          name = Regexp.last_match(1)
          ids  = Array(tag_index[name])
          expanded.concat(ids.empty? ? [name] : ids)

        when /\A\^tag:(.+)\z/
          name = Regexp.last_match(1)
          ids  = tag_index[name]
          if ids.nil? || ids.empty?
            # 未登録の除外タグは補集合にせず、文字列として返す
            expanded << name
          else
            # 補集合は昇順で安定化
            expanded.concat(all_sorted - ids.map(&:to_i))
          end

        else
          ids = Array(tag_index[str])
          expanded.concat(ids.empty? ? [str] : ids)
        end
      end

      # 入力順ベースで uniq（既存仕様を維持）
      array.replace(expanded.uniq)
    end

    #
    # コマンドを実行するが、アプリケーションは終了させない
    #
    def execute!(*argv, io: $stdout)
      self.stream_io = io
      argv.flatten!
      execute(argv)
    rescue SystemExit => e
      e.status
    else
      0
    end

    def self.execute!(*argv, io: $stdout)
      cmd = new
      cmd.execute!(*argv, io: io)
    end

    def self.oneline_help
      raise "implement #{self}.oneline_help"
    end

    #
    # 指定したメソッドを呼び出す際に、フック関数があればそれ経由で呼ぶ
    #
    def hook_call(target_method, *argv)
      hook = "hook_#{target_method}"
      target_method_proc = (method(target_method) rescue -> {})
      if respond_to?(hook)
        __send__(hook, *argv, &target_method_proc)
      else
        target_method_proc.call(*argv)
      end
    end

    #
    # 設定の強制設定
    #
    def force_change_settings_function(pairs)
      settings = Inventory.load("local_setting")
      modified = false
      pairs.each do |name, value|
        if settings[name].nil? || settings[name] != value
          settings[name] = value
          puts "<bold><cyan>#{name} を #{value} に強制変更しました</cyan></bold>".termcolor
          modified = true
        end
      end
      settings.save if modified
    end

    #
    # コマンド出力のログ保存を抑制する
    #
    def disable_logging
      self.stream_io = stream_io.dup_with_disabled_logging
    end
  end
end
