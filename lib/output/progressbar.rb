# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

class ProgressBar
  class OverRangeError < StandardError; end

  attr_reader :io

  def initialize(max, interval = 1, width = 50, char = "*", io: $stdout)
    @max = max == 0 ? 1.0 : max.to_f
    @interval = interval
    @width = width
    @char = char
    @counter = 0
    @io = io
  end

  def output(num)
    # プログレスバーの出力を無効化
    # フロントエンド側での表示問題があるため、バックエンド側で出力を抑制
    nil

    # 以下は無効化されたコード
    # return if silent?
    # if num > @max
    #   raise OverRangeError, "`#{num}` over `#{@max}(max)`"
    # end
    # @counter += 1
    # return unless @counter % @interval == 0
    # ratio = calc_ratio(num)
    # now = (@width * ratio).round
    # rest = @width - now
    # io.stream.print format("[%s%s] %d%%\r", @char * now, " " * rest, (ratio * 100).round)
  end

  def clear
    # プログレスバーのクリア処理を無効化
    nil

    # 以下は無効化されたコード
    # return if silent?
    # io.stream.print "\e[2K\r" # 行削除して行頭へ移動
  end

  def calc_ratio(num)
    num / @max
  end

  def silent?
    ENV["NAROU_ENV"] == "test" || !io.tty? || io.silent?
  end
end
