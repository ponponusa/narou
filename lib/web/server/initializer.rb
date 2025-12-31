# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

#
# サーバー初期化処理を担当するモジュール
#
# 起動時の初期化、メッセージ表示、デバイス監視、データベース準備、認証設定など
#
module ServerInitializer
  #
  # サーバー初期化
  #
  def initialize
    super
    puts_hello_messages
    start_device_ejectable_event
    fill_general_all_no_in_database
    setup_server_authentication
  end

  #
  # 起動メッセージを表示
  #
  def puts_hello_messages
    # バージョン情報は履歴に保存しない（STDERRに出力）
    # Web UI モードでは $stdout 経由で出力（StreamingLogger が制御）
    if Narou.web?
      $stdout.puts "<white>Narou.rb MOD version #{Narou::VERSION}</white>".termcolor
    else
      STDERR.puts "<white>Narou.rb MOD version #{Narou::VERSION}</white>".termcolor
    end
  end

  #
  # デバイス取り外し可能状態の監視を開始
  #
  def start_device_ejectable_event
    return unless Device.support_eject?
    Thread.new do
      loop do
        if defined?(@@push_server) && @@push_server && @@push_server.connections.count > 0
          device = Narou.get_device
          @@push_server.send_all(:"device.ejectable" => device && device.ejectable?)
        end

        sleep 2
      end
    end
  end

  #
  # 目次から小説の総話数を取得
  #
  def general_all_no_by_toc(id)
    toc = Downloader.new(id).load_toc_file
    return nil unless toc
    toc["subtitles"].size
  rescue Downloader::InvalidTarget
    nil
  end

  #
  # 話数の設定されていない小説の話数を取得して埋める
  #
  def fill_general_all_no_in_database
    modified = false
    Database.instance.each do |id, data|
      next if data["general_all_no"]
      data["general_all_no"] = general_all_no_by_toc(id)
      modified = true
    end
    Database.instance.save_database if modified
  end

  #
  # サーバーの認証の設定
  #
  # Digest認証がRackの機能からオミットされたので、Basic認証に変更
  #
  def setup_server_authentication
    auth = Inventory.load("global_setting", :global).group("server-basic-auth")
    user = auth.user
    passwd = auth.password # ハッシュは使わない

    return unless auth.enable && user && passwd

    self.class.class_exec do
      use Rack::Auth::Basic, "narou.rb MOD" do |username, password|
        username == user && password == passwd
      end
    end
  end
end
