# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

#
# 設定管理ルーティングを担当するモジュール
#
# グローバル設定、小説個別設定の表示・保存ルーティングを集約
#
module SettingsRoutes
  def self.registered(app)
    #
    # 設定ページフィルター
    #
    app.before "/settings" do
      if self.class.legacy_mode?
        @title = "環境設定"
        @setting_variables = Command::Setting.get_setting_variables
        @error_list = {}
        @global_replace_pattern = @replace_pattern = Narou.global_replace_pattern
      end
    end

    #
    # 設定保存
    #
    app.post "/settings" do
      built_arguments = []
      device = params.delete("device")
      [:local, :global].each do |scope|
        @setting_variables[scope].each do |name, info|
          param_data = params[name]
          argument = ""
          if info[:type] == :boolean
            # :boolean 用のフォームデータは on, off, nil で渡される。
            # ただしチェックボックスはチェックした時だけ on が渡されるので、
            # 何もデータが無い＝off を選択したと判断する。
            # 隠しデータの場合は hidden として on, off, nil が必ず送信されるので、
            # それで判断できる。
            if param_data
              argument = convert_on_off_to_boolean(param_data).to_s
            else
              argument = "false"
            end
          elsif param_data.is_a?(Array)
            argument = param_data.join(",")
          else
            argument = param_data
          end
          built_arguments << "#{name}=#{argument}"
        end
      end
      # device の項目だけ関連項目を変更するという挙動をするため、変更を上書き
      # されないように最後にまわす
      built_arguments << "device=#{device}" if device
      unless built_arguments.empty?
        setting = Command::Setting.new
        setting.on(:error) do |msg, name|
          if name
            @error_list[name] = msg
          end
        end
        setting.execute!(built_arguments, io: Narou::NullIO.new)
        Inventory.clear

        # 自動アップデート設定が変更された場合、スケジューラーを再起動
        if built_arguments.any? { |arg| arg.start_with?("update.auto-schedule") }
          require "lib/web/command/update/scheduler"
          Command::Update::Scheduler.stop
          Command::Update::Scheduler.start
        end
      end

      # 置換設定保存
      params_replace_pattern = params["replace_pattern"]
      @global_replace_pattern.clear
      if params_replace_pattern.is_a?(Array)
        params_replace_pattern.each do |pattern|
          left = pattern["left"].strip
          right = pattern["right"].strip
          next if left == ""
          @global_replace_pattern << [left, right]
        end
      end
      Narou.save_global_replace_pattern

      if @error_list.empty?
        session[:alert] = [ "保存が完了しました", "success" ]
      else
        session[:alert] = [ "#{@error_list.size}個の設定にエラーがありました", "danger" ]
      end
      redirect to "/settings"
    end

    #
    # 設定ページ表示
    #
    app.get "/settings" do
      if self.class.legacy_mode?
        haml :settings
      else
        # Astro UI の settings ページ
        # 開発環境のパス
        dev_settings_path = "../frontend/dist/settings/index.html"

        # gem環境のパス
        gem_settings_path = "../frontend/dist/settings/index.html"

        settings_path = if File.exist?(dev_settings_path)
                          dev_settings_path
                        elsif File.exist?(gem_settings_path)
                          gem_settings_path
                        end

        if settings_path && File.exist?(settings_path)
          send_file settings_path
        else
          halt 404, "Settings page not found"
        end
      end
    end
  end
end
