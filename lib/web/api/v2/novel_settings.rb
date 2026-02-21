# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require "lib/web/api/v2/base"
require "lib/novel/novelsetting"

module Narou
  module ApiV2
    # 小説個別設定関連 API v2 エンドポイント
    module NovelSettings
      def self.register(app)
        app.class_eval do
          include Narou::ApiV2::Base

          # GET /api/v2/novels/:id/settings
          # 小説個別設定取得
          get "/api/v2/novels/:id/settings" do
            set_cors_headers

            id = params["id"].to_i
            database = Database.instance
            data = database[id]

            unless data
              status 404
              return json error_response("NOT_FOUND", "Novel ID #{id} not found")
            end

            begin
              # 小説設定オブジェクト作成
              novel_setting = NovelSetting.new(id, true, true)
              novel_setting.settings = novel_setting.load_setting_ini["global"]

              # 設定項目の定義情報
              original_settings = NovelSetting.get_original_settings
              force_settings = NovelSetting.load_force_settings
              default_settings = NovelSetting.load_default_settings

              # フロントエンド用に整形
              settings_data = original_settings.map do |info|
                name = info[:name]
                value = novel_setting[name]

                # force設定がある場合はそれを優先
                effective_value = if force_settings.include?(name)
                                    force_settings[name]
                                  else
                                    value
                                  end

                {
                  name: name,
                  type: info[:type],
                  value: effective_value,
                  original_value: value, # 実際のsetting.iniの値
                  default_value: default_settings.include?(name) ? default_settings[name] : info[:value],
                  help: info[:help],
                  is_forced: force_settings.include?(name),
                  select_keys: info[:select_keys],
                  select_summaries: info[:select_summaries]
                }
              end

              # 置換設定も取得
              replace_pattern = novel_setting.load_replace_pattern

              json success_response({
                novel_id: id,
                novel_title: data["title"],
                settings: settings_data,
                replace_pattern: replace_pattern
              })
            rescue StandardError => e
              status 500
              json error_response("INTERNAL_ERROR", e.message)
            end
          end

          # PUT /api/v2/novels/:id/settings
          # 小説個別設定更新
          put "/api/v2/novels/:id/settings" do
            set_cors_headers

            id = params["id"].to_i
            database = Database.instance
            data = database[id]

            unless data
              status 404
              return json error_response("NOT_FOUND", "Novel ID #{id} not found")
            end

            body = parse_json_body
            settings_updates = body["settings"] || {}
            replace_pattern_updates = body["replace_pattern"]

            begin
              # 小説設定オブジェクト作成
              novel_setting = NovelSetting.new(id, true, true)
              novel_setting.settings = novel_setting.load_setting_ini["global"]
              original_settings = NovelSetting.get_original_settings

              # エラーリスト
              error_list = {}

              # 設定値の更新
              original_settings.each do |info|
                name = info[:name]
                type = info[:type]

                # 更新対象のみ処理
                next unless settings_updates.key?(name)

                param_data = settings_updates[name]
                value = nil

                begin
                  if type == :boolean
                    if param_data.nil?
                      value = nil
                    elsif param_data == true || param_data == "on"
                      value = true
                    elsif param_data == false || param_data == "off"
                      value = false
                    else
                      value = false
                    end
                  elsif param_data.is_a?(Array)
                    value = param_data.join(",")
                  elsif param_data.is_a?(String)
                    if param_data.strip != ""
                      value = Helper.string_cast_to_type(param_data, type)
                    else
                      value = nil
                    end
                  elsif param_data.nil?
                    value = nil
                  else
                    value = param_data
                  end

                  novel_setting[name] = value
                rescue Helper::InvalidVariableType => e
                  error_list[name] = e.message
                end
              end

              # エラーがなければ保存
              if error_list.empty?
                novel_setting.save_settings

                # 置換設定の更新
                if replace_pattern_updates
                  novel_setting.replace_pattern.clear
                  replace_pattern_updates.each do |pattern|
                    left = pattern["left"].to_s.strip
                    right = pattern["right"].to_s.strip
                    next if left == ""
                    novel_setting.replace_pattern << [left, right]
                  end
                  novel_setting.save_replace_pattern
                end

                json success_response(
                  { novel_id: id },
                  message: "Settings updated successfully"
                )
              else
                status 400
                json error_response("VALIDATION_ERROR", "#{error_list.size} settings have errors", details: error_list)
              end
            rescue StandardError => e
              status 500
              json error_response("INTERNAL_ERROR", e.message)
            end
          end
        end
      end
    end
  end
end
