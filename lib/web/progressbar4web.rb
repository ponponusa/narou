# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require_relative "../progressbar"

#
# コンソール用のプログレスバーはWEB UIでは使えないため置き換える
# プログレスバーの出力を完全に無効化
#
class ProgressBar
  def self.push_server=(server)
    @@push_server = server
  end

  # すべてのメソッドを無効化して何もしないようにする
  def initialize(*args, **opt)
    # 何もしない
  end

  def output(num)
    # 何もしない
  end

  def clear
    # 何もしない
  end
  
  def calc_ratio(num)
    0.0
  end
  
  def silent?
    true
  end
end

