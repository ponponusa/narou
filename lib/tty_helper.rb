# frozen_string_literal: true

# 
# Copyright 2025 ponponUSA. All rights reserved.
#

module TTYHelper
  def self.non_interactive?
    ENV["NAROU_NONINTERACTIVE"] == "1"
  end

  # Y/N 確認（非対話時は default で即返す）
  def self.ask_yes_no(message, default: true, in_io: $stdin, out_io: $stdout)
    return default if non_interactive?
    out_io.print("#{message} [y/N]: ")
    ans = in_io.gets&.strip&.downcase
    return default if ans.nil? || ans.empty?
    %w[y yes].include?(ans)
  end

  # 「Enterで続行」待ち（非対話時はスキップ）
  def self.pause(message = "続行するには Enter を押してください…", in_io: $stdin, out_io: $stdout)
    return if non_interactive?
    out_io.puts(message)
    in_io.gets
  end
end
