# frozen_string_literal: true

#
# Copyright ...
#

require "termcolorlight"

module Narou
  module Input
    module_function

    # ---- helper --------------------------------------------------------------
    def _env_non_interactive?
      ENV["NAROU_NONINTERACTIVE"] == "1"
    end

    def _tty?
      $stdin.respond_to?(:tty?) ? $stdin.tty? : false
    end

    def _print(str)
      $stdout.print(str)
    end

    def _puts(str = "")
      $stdout.puts(str)
    end

    def _gets
      $stdin.gets
    end
    # -------------------------------------------------------------------------

    #
    # yes/no 確認
    #
    # message        : 表示文
    # default        : 空入力(Enter)時の返値
    # nontty_default : 入力不能(EOF等)や非TTY時の返値
    #
    def confirm(message, default = false, nontty_default = true)
      # Web UI実行時は非対話モード
      if defined?(Narou) && Narou.respond_to?(:web?) && Narou.web?
        return nontty_default
      end
      # 非対話フラグが設定されている場合は即座に nontty_default を返す
      if _env_non_interactive?
        return nontty_default
      end
      # 非TTY（pipe等）は旧挙動どおり nontty_default を返す
      unless _tty?
        return nontty_default
      end

      prompt = "#{message} (y/n)?: "
      _print(prompt)

      # getch を優先（RSpec が stub してくる）
      if $stdin.respond_to?(:getch)
        ch = $stdin.getch
        return nontty_default if ch.nil?
        ch = ch.to_s
        _puts(ch)
        case ch.downcase
        when "y" then true
        when "n" then false
        when "\r", "\n" then default
        else
          loop do
            _print(prompt)
            ch = $stdin.getch
            return nontty_default if ch.nil?
            ch = ch.to_s
            _puts(ch)
            case ch.downcase
            when "y" then return true
            when "n" then return false
            when "\r", "\n" then return default
            end
          end
        end
      else
        # 行読みフォールバック
        line = _gets
        return nontty_default if line.nil?
        input = line.strip
        return default if input.empty?
        case input.downcase
        when "y", "yes" then true
        when "n", "no"  then false
        else
          loop do
            _print(prompt)
            line = _gets
            return nontty_default if line.nil?
            input = line.strip
            return default if input.empty?
            case input.downcase
            when "y", "yes" then return true
            when "n", "no"  then return false
            end
          end
        end
      end
    end

    #
    # 選択肢から 1 つ選ぶ
    #
    # choices: { "key" => "説明", ..., default: "key" }
    #
    def choose(title, message, choices)
      default_key = choices[:default] || choices.keys.find { |k| k != :default }

      # 非対話フラグが設定されている場合は default を返す
      if _env_non_interactive?
        return default_key
      end
      # 非TTY（pipe/EOF）なら default を返す
      unless _tty?
        return default_key
      end

      _puts(title)
      _puts(message)
      choices.each do |name, help|
        next if name == :default
        _puts "<bold>#{name}</bold>: #{help}".termcolor
      end

      loop do
        _print("> ")
        line = _gets
        return default_key if line.nil?
        input = line.strip.downcase
        keys = choices.keys.reject { |k| k == :default }
        if keys.include?(input)
          return input
        end
        _puts "選択肢の中にありません。もう一度入力して下さい"
      end
    end

    #
    # Enter 待ち（TTY のときだけ）
    #
    def pause(message = "続行するには Enter を押してください…")
      return if _env_non_interactive?
      return unless _tty?
      _puts(message)
      _gets
    end
  end
end
