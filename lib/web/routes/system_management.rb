# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

#
# システム管理ルーティングを担当するモジュール
#
# シャットダウン、再起動、システム更新などの管理機能ルーティングを集約
#
module SystemManagementRoutes
  def self.registered(app)
    #
    # ヘルプページ
    #
    app.get "/help" do
      @title = "ヘルプ"
      haml :help
    end

    #
    # バージョン情報ページ
    #
    app.get "/about" do
      @narourb_version = settings.version
      @ruby_version = build_ruby_version
      haml :_about, layout: false
    end

    #
    # サーバーシャットダウン
    #
    app.post "/shutdown" do
      self.class.quit!
      "シャットダウンしました。再起動するまで操作は出来ません"
    end

    #
    # サーバー再起動
    #
    app.post "/reboot" do
      self.class.request_reboot
      self.class.quit!
      haml :_rebooting, layout: false
    end

    #
    # システム更新（GitHubから最新版を取得）
    #
    app.post "/update_system" do
      Thread.new do
        result = Narou::SystemUpdater.update_from_github
        @@gem_update_last_log = result.log

        case result.status
        when :success
          @@already_update_system = true
          Narou::AppServer.push_server.send_all("server.update.success" => result.log)
        when :nothing
          Narou::AppServer.push_server.send_all("server.update.nothing" => result.log)
        else
          Narou::AppServer.push_server.send_all("server.update.failure" => result.log)
        end
      rescue Narou::SystemUpdater::Error => e
        log = "更新に失敗しました: #{e.message}"
        @@gem_update_last_log = log
        Narou::AppServer.push_server.send_all("server.update.failure" => log)
      rescue StandardError => e
        log = <<~LOG.strip
          予期しないエラーが発生しました: #{e.class} #{e.message}
          #{Array(e.backtrace).join("\n")}
        LOG
        @@gem_update_last_log = log
        Narou::AppServer.push_server.send_all("server.update.failure" => log)
      end
    end

    #
    # 最新の更新ログを取得
    #
    app.post "/gem_update_last_log" do
      content_type "text/plain"
      @@gem_update_last_log
    end

    #
    # 更新済みかどうかチェック
    #
    app.post "/check_already_update_system" do
      json({ result: @@already_update_system })
    end
  end
end
