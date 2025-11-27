# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/core/narou"
require "lib/cli/command"
require "lib/utilities/helper"
require "lib/core/inventory"

module CommandLine
  module_function

  def run(*argv, catch_exit: false, io: $stdout)
    argv.flatten!
    argv_for_windows(argv)
    cmd_name = take_command_name(argv)
    proc_default_arguments(argv, cmd_name)
    if argv.delete("--multiple")
      multiple_argument_extract(argv)
    end
    unless STDIN.tty?
      # 端末からの生入力だとブロックするので、パイプ/リダイレクト時のみ読む
      # nohup環境などでSTDINが閉じられている場合はスキップ
      if !$stdin.tty? && !$stdin.closed?
        begin
          argv += ($stdin.read || "").split
        rescue Errno::EBADF
          # STDINが利用不可の場合は無視
        end
      end
    end

    command_class = Command.load_command(cmd_name)
    unless command_class
      error "不明なコマンドです。narou-mod help を確認してください"
      exit Narou::EXIT_ERROR_CODE
    end

    if catch_exit
      command_class.execute!(argv, io: io)
    else
      cmd = command_class.new
      cmd.stream_io = io
      cmd.execute(argv)
    end
  ensure
    Command.load_command("convert")
    Command::Convert.display_sending_error_list if defined?(Command::Convert)
  end

  def run!(*argv, io: $stdout)
    run(*argv, catch_exit: true, io: io)
  end

  def load_default_arguments(cmd)
    default_arguments_list = Inventory.load("local_setting")
    (default_arguments_list["default_args.#{cmd}"] || "").split
  end

  def argv_for_windows(argv)
    return unless Helper.os_windows?
    argv.map! { |arg| arg.is_a?(Integer) ? arg : arg&.encode(Encoding::UTF_8) }
  end

  def take_command_name(argv)
    argv.unshift("help") if argv.empty?
    name = argv.shift.downcase
    name = Command::Shortcuts[name] || name
    name = case name
           when "-v", "--version" then "version"
           when "-h", "--help"    then "help"
           else name
           end

    unless Narou.already_init?
      name = "help" unless %w(help version init).include?(name)
    end

    unless Command.names.include?(name)
      error "不明なコマンドです。narou-mod help を確認してください"
      exit Narou::EXIT_ERROR_CODE
    end
    name
  end

  def proc_default_arguments(argv, name)
    if argv.empty? && STDIN.tty?
      argv.concat(load_default_arguments(name))
    end
  end

  def multiple_argument_extract(argv)
    delimiter = Inventory.load("local_setting")["multiple-delimiter"] || ","
    argv.map! { |arg| arg.split(delimiter) }.flatten!
  end
end
