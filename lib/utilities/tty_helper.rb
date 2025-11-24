# frozen_string_literal: true

#
# Copyright 2025 ponponUSA. All rights reserved.
#

module TTYHelper
  def self.non_interactive?(input = $stdin)
    return true if ENV["NAROU_NONINTERACTIVE"] == "1"
    return true if defined?(Narou) && Narou.respond_to?(:web?) && Narou.web?
    io = input || $stdin
    return true unless io.respond_to?(:tty?) && io.tty?
    false
  end

  # Y/N 確認（非対話時は default で即返す）
  def self.ask_yes_no(message, default: true, in_io: $stdin, out_io: $stdout)
    return default if non_interactive?(in_io)
    out_io.print("#{message} [y/N]: ")
    ans = in_io.gets&.strip&.downcase
    return default if ans.nil? || ans.empty?
    %w(y yes).include?(ans)
  end

  # 「Enterで続行」待ち（非対話時はスキップ）
  def self.pause(message = "続行するには Enter を押してください…", in_io: $stdin, out_io: $stdout)
    return if non_interactive?(in_io)
    out_io.puts(message)
    in_io.gets
  end
end
