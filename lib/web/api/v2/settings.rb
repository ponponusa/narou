# frozen_string_literal: true

#
# Copyright 2025 ponponusa. All rights reserved.
#

require "lib/web/api/v2/base"

module Narou
  module ApiV2
    # 設定関連 API v2 エンドポイント
    module Settings
      def self.register(app)
        app.class_eval do
          include Narou::ApiV2::Base

          # GET /api/v2/settings
          # 設定一覧取得
          get '/api/v2/settings' do
            set_cors_headers
            
            begin
              require "cli/command/setting"
              require "core/inventory"
              
              settings = {
                local: Inventory.load("local_setting", :local),
                global: Inventory.load("global_setting", :global)
              }
              
              # 設定変数のメタ情報も含める
              setting_variables = Command::Setting.get_setting_variables
              
              # 設定値とメタ情報を統合
              result = {
                local: {},
                global: {},
                variables: setting_variables
              }
              
              [:local, :global].each do |scope|
                settings[scope].each do |name, value|
                  result[scope][name] = {
                    value: value,
                    type: setting_variables[scope][name]&.[](:type),
                    help: setting_variables[scope][name]&.[](:help)
                  }
                end
              end
              
              json success_response(result)
            rescue StandardError => e
              status 500
              json error_response('SETTINGS_GET_ERROR', e.message)
            end
          end

          # GET /api/v2/settings/variables
          # 設定可能な変数の定義一覧を取得
          get '/api/v2/settings/variables' do
            set_cors_headers
            
            begin
              require "cli/command/setting"
              
              setting_variables = Command::Setting.get_setting_variables
              tab_names = Command::Setting.get_setting_tab_names
              tab_info = Command::Setting.get_setting_tab_info
              
              json success_response({
                variables: setting_variables,
                tab_names: tab_names,
                tab_info: tab_info
              })
            rescue StandardError => e
              status 500
              json error_response('VARIABLES_GET_ERROR', e.message)
            end
          end

          # PUT /api/v2/settings
          # 設定更新
          put '/api/v2/settings' do
            set_cors_headers
            
            body = parse_json_body
            settings = body['settings']
            
            unless settings && settings.is_a?(Hash) && !settings.empty?
              status 400
              return json error_response('INVALID_PARAMS', 'Settings object is required')
            end
            
            begin
              require "cli/command/setting"
              require "core/inventory"
              require "narou_logger"
              
              # 設定コマンドのインスタンスを作成
              setting_cmd = Command::Setting.new
              error_list = {}
              
              # エラーハンドリング
              setting_cmd.on(:error) do |msg, name|
                error_list[name] = msg if name
              end
              
              # 設定値を引数形式に変換
              built_arguments = []
              settings.each do |name, value|
                if value.nil? || value == ""
                  # 空文字は設定削除
                  built_arguments << "#{name}="
                else
                  # 値を文字列化
                  argument_value = case value
                                   when Array
                                     value.join(",")
                                   when TrueClass, FalseClass
                                     value.to_s
                                   else
                                     value.to_s
                                   end
                  built_arguments << "#{name}=#{argument_value}"
                end
              end
              
              # 設定を実行
              setting_cmd.execute!(built_arguments, io: Narou::NullIO.new)
              Inventory.clear
              
              # 自動アップデート設定が変更された場合、スケジューラーを再起動
              if built_arguments.any? { |arg| arg.start_with?("update.auto-schedule") }
                require "web/api/command/update/scheduler"
                Command::Update::Scheduler.stop
                Command::Update::Scheduler.start
              end
              
              if error_list.empty?
                json success_response(
                  { updated_count: settings.size },
                  message: 'Settings updated successfully'
                )
              else
                status 400
                json error_response(
                  'SETTINGS_UPDATE_ERROR',
                  "#{error_list.size} settings had errors",
                  details: error_list
                )
              end
            rescue StandardError => e
              status 500
              json error_response('SETTINGS_UPDATE_ERROR', e.message)
            end
          end

          # PATCH /api/v2/settings
          # 設定部分更新（PUTと同じ動作）
          patch '/api/v2/settings' do
            set_cors_headers
            
            body = parse_json_body
            settings = body['settings']
            
            unless settings && settings.is_a?(Hash) && !settings.empty?
              status 400
              return json error_response('INVALID_PARAMS', 'Settings object is required')
            end
            
            begin
              require "cli/command/setting"
              require "core/inventory"
              require "narou_logger"
              
              setting_cmd = Command::Setting.new
              error_list = {}
              
              setting_cmd.on(:error) do |msg, name|
                error_list[name] = msg if name
              end
              
              built_arguments = []
              settings.each do |name, value|
                if value.nil? || value == ""
                  built_arguments << "#{name}="
                else
                  argument_value = case value
                                   when Array
                                     value.join(",")
                                   when TrueClass, FalseClass
                                     value.to_s
                                   else
                                     value.to_s
                                   end
                  built_arguments << "#{name}=#{argument_value}"
                end
              end
              
              setting_cmd.execute!(built_arguments, io: Narou::NullIO.new)
              Inventory.clear
              
              if built_arguments.any? { |arg| arg.start_with?("update.auto-schedule") }
                require "web/api/command/update/scheduler"
                Command::Update::Scheduler.stop
                Command::Update::Scheduler.start
              end
              
              if error_list.empty?
                json success_response(
                  { updated_count: settings.size },
                  message: 'Settings updated successfully'
                )
              else
                status 400
                json error_response(
                  'SETTINGS_UPDATE_ERROR',
                  "#{error_list.size} settings had errors",
                  details: error_list
                )
              end
            rescue StandardError => e
              status 500
              json error_response('SETTINGS_UPDATE_ERROR', e.message)
            end
          end

          # GET /api/v2/settings/parser
          # パーサー設定を取得
          get '/api/v2/settings/parser' do
            set_cors_headers
            
            begin
              require "narou/parsers/config_manager"
              
              # グローバル設定を読み込み
              global_config = Narou::Parsers::ConfigManager.load_global_config
              
              # サポートしているドメイン一覧
              domains = []
              
              # preset/parsers/ からドメイン一覧を取得
              preset_dir = Narou.script_dir.join("preset", "parsers")
              if preset_dir.exist?
                Dir.glob(preset_dir.join("*.yaml")).each do |path|
                  domain = File.basename(path, ".yaml")
                  domains << domain unless domain.start_with?("_")
                end
              end
              
              # .narou/parsers/ からカスタム設定を取得
              user_parser_dir = Narou.root_dir.join(".narou", "parsers")
              user_configs = {}
              if user_parser_dir.exist?
                Dir.glob(user_parser_dir.join("*.yaml")).each do |path|
                  domain = File.basename(path, ".yaml")
                  next if domain.start_with?("_")
                  begin
                    user_configs[domain] = YAML.load_file(path)
                  rescue => e
                    # エラーは無視して続行
                  end
                end
              end
              
              result = {
                global_config: global_config,
                domains: domains.sort,
                user_configs: user_configs
              }
              
              json success_response(result)
            rescue StandardError => e
              status 500
              json error_response('PARSER_CONFIG_GET_ERROR', e.message)
            end
          end

          # POST /api/v2/settings/parser
          # パーサー設定を更新
          post '/api/v2/settings/parser' do
            set_cors_headers
            
            body = parse_json_body
            
            begin
              require "narou/parsers/config_manager"
              
              updated = []
              
              # グローバル設定の更新
              if body['default_engine']
                global_config = Narou::Parsers::ConfigManager.load_global_config
                global_config['default_engine'] = body['default_engine']
                Narou::Parsers::ConfigManager.save_global_config(global_config)
                updated << 'default_engine'
              end
              
              # 小説ごとのエンジン設定
              if body['novel_engines'] && body['novel_engines'].is_a?(Hash)
                body['novel_engines'].each do |novel_id, engine|
                  Narou::Parsers::ConfigManager.set_engine_for_novel(novel_id, engine)
                  updated << "novel_#{novel_id}"
                end
              end
              
              # ドメイン別設定の更新
              if body['domain_config'] && body['domain_config'].is_a?(Hash)
                domain = body['domain_config']['domain']
                config = body['domain_config']['config']
                engine = body['domain_config']['engine'] || 'nokogiri'
                
                if domain && config
                  Narou::Parsers::ConfigManager.save_parser_config(domain, config, engine)
                  updated << "domain_#{domain}"
                end
              end
              
              json success_response(
                { updated: updated },
                message: 'Parser settings updated successfully'
              )
            rescue StandardError => e
              status 500
              json error_response('PARSER_CONFIG_UPDATE_ERROR', e.message)
            end
          end
        end
      end
    end
  end
end
