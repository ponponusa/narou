# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/output/progressbar"

#
# コンソール用のプログレスバーはWEB UIでは使えないため置き換える
# プログレスバーの出力を完全に無効化
#
class ProgressBar
  def self.push_server=(server)
    @@push_server = server
  end

  alias :original_initialize :initialize

  def initialize(*, **opt)
    # 親クラスのinitializeを呼ぶ（@ioを設定するため）
    original_initialize(*, **opt)
    # プログレスバーイベントは送信しない（無効化）
    # @@push_server.send_all("progressbar.init" => { target_console: io.target_console })
  end

  def output(num)
    # プログレスバーの出力を完全に無効化
    # フロントエンド側での表示問題があるため、出力しない
  end

  def clear
    # プログレスバーのクリア処理を無効化
  end
end

