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
      data.gsub(/[ 　\t]+$/m, "")
    end
  end
end
