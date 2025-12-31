# frozen_string_literal: true

#
# ConverterBase utility methods
#

class ConverterBase
  module Utilities
    #
    # 全角版 String#rstrip!
    #
    def zenkaku_rstrip(line)
      line.gsub!(/[　\s]+\z/, "")
    end

    #
    # すべての行の行末空白を削除
    #
    def rstrip_all_lines(data)
      # 各行ごとに処理することで、正規表現DoSを回避しつつ全行の末尾空白を削除
      data.lines.map { |line| line.sub(/[ 　\t]+\z/, "") }.join
    end
  end
end
