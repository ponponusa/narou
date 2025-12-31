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
          get "/api/v2/settings" do
            set_cors_headers

            begin
              require "lib/cli/command/setting"
              require "lib/core/inventory"

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
              json error_response("SETTINGS_GET_ERROR", e.message)
            end
          end

          # GET /api/v2/settings/variables
          # 設定可能な変数の定義一覧を取得
          get "/api/v2/settings/variables" do
            set_cors_headers

            begin
              require "lib/cli/command/setting"

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
              json error_response("VARIABLES_GET_ERROR", e.message)
            end
          end

          # PUT /api/v2/settings
          # 設定更新
          put "/api/v2/settings" do
            set_cors_headers

            body = parse_json_body
            settings = body["settings"]

            unless settings && settings.is_a?(Hash) && !settings.empty?
              status 400
              return json error_response("INVALID_PARAMS", "Settings object is required")
            end

            begin
              require "lib/cli/command/setting"
              require "lib/core/inventory"
              require "lib/output/narou_logger"

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
                require "lib/cli/command/update/scheduler"
                Command::Update::Scheduler.stop
                Command::Update::Scheduler.start
              end

              if error_list.empty?
                json success_response(
                  { updated_count: settings.size },
                  message: "Settings updated successfully"
                )
              else
                status 400
                json error_response(
                  "SETTINGS_UPDATE_ERROR",
                  "#{error_list.size} settings had errors",
                  details: error_list
                )
              end
            rescue StandardError => e
              status 500
              json error_response("SETTINGS_UPDATE_ERROR", e.message)
            end
          end

          # PATCH /api/v2/settings
          # 設定部分更新（PUTと同じ動作）
          patch "/api/v2/settings" do
            set_cors_headers

            body = parse_json_body
            settings = body["settings"]

            unless settings && settings.is_a?(Hash) && !settings.empty?
              status 400
              return json error_response("INVALID_PARAMS", "Settings object is required")
            end

            begin
              require "lib/cli/command/setting"
              require "lib/core/inventory"
              require "lib/output/narou_logger"

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
                require "lib/cli/command/update/scheduler"
                Command::Update::Scheduler.stop
                Command::Update::Scheduler.start
              end

              if error_list.empty?
                json success_response(
                  { updated_count: settings.size },
                  message: "Settings updated successfully"
                )
              else
                status 400
                json error_response(
                  "SETTINGS_UPDATE_ERROR",
                  "#{error_list.size} settings had errors",
                  details: error_list
                )
              end
            rescue StandardError => e
              status 500
              json error_response("SETTINGS_UPDATE_ERROR", e.message)
            end
          end

          # GET /api/v2/settings/parser
          # パーサー設定を取得
          get "/api/v2/settings/parser" do
            set_cors_headers

            begin
              require "lib/narou/parsers/config_manager"

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

              # セレクタ履歴を取得（新規）
              selector_histories = {}
              domains.each do |domain|
                history = Narou::Parsers::ConfigManager.get_selector_history(domain, "nokogiri")
                selector_histories[domain] = history if history.any?
              end

              # 変更ログを取得（新規）
              change_log = Narou::Parsers::ConfigManager.get_change_log

              result = {
                global_config: global_config,
                domains: domains.sort,
                user_configs: user_configs,
                selector_histories: selector_histories,
                change_log: change_log
              }

              json success_response(result)
            rescue StandardError => e
              status 500
              json error_response("PARSER_CONFIG_GET_ERROR", e.message)
            end
          end

          # POST /api/v2/settings/parser
          # パーサー設定を更新
          post "/api/v2/settings/parser" do
            set_cors_headers

            body = parse_json_body

            begin
              require "lib/narou/parsers/config_manager"

              updated = []

              # グローバル設定の更新
              if body["default_engine"]
                global_config = Narou::Parsers::ConfigManager.load_global_config
                global_config["default_engine"] = body["default_engine"]
                Narou::Parsers::ConfigManager.save_global_config(global_config)
                updated << "default_engine"
              end

              # 小説ごとのエンジン設定
              if body["novel_engines"] && body["novel_engines"].is_a?(Hash)
                body["novel_engines"].each do |novel_id, engine|
                  Narou::Parsers::ConfigManager.set_engine_for_novel(novel_id, engine)
                  updated << "novel_#{novel_id}"
                end
              end

              # ドメイン別設定の更新
              if body["domain_config"] && body["domain_config"].is_a?(Hash)
                domain = body["domain_config"]["domain"]
                config = body["domain_config"]["config"]
                engine = body["domain_config"]["engine"] || "nokogiri"

                if domain && config
                  Narou::Parsers::ConfigManager.save_parser_config(domain, config, engine)
                  updated << "domain_#{domain}"
                end
              end

              json success_response(
                { updated: updated },
                message: "Parser settings updated successfully"
              )
            rescue StandardError => e
              status 500
              json error_response("PARSER_CONFIG_UPDATE_ERROR", e.message)
            end
          end

          # GET /api/v2/settings/parser/diagnostics/:domain
          # 特定ドメインの診断情報を取得
          get "/api/v2/settings/parser/diagnostics/:domain" do
            set_cors_headers

            domain = params[:domain]
            engine = params[:engine] || "nokogiri"

            begin
              require "lib/narou/parsers/config_manager"
              require "lib/core/database"

              result = {
                domain: domain,
                engine: engine
              }

              if engine == "nokogiri"
                # Nokogiriの場合: セレクタ履歴を取得
                selector_history = Narou::Parsers::ConfigManager.get_selector_history(domain, "nokogiri")
                result[:selector_history] = selector_history

                # セレクタの適用範囲を計算（簡易版）
                selector_coverage = {}
                selector_history.each do |selector_key, history_entries|
                  selector_coverage[selector_key] = history_entries.map do |entry|
                    {
                      selector: entry["selector"],
                      first_success: entry["first_success"],
                      last_success: entry["last_success"],
                      success_count: entry["success_count"],
                      detected_change: entry["detected_change"],
                      replaced_selector: entry["replaced_selector"]
                    }
                  end
                end
                result[:selector_coverage] = selector_coverage
              else
                # Legacyの場合: バージョン履歴を取得
                version_history = Narou::Parsers::ConfigManager.get_legacy_version_history(domain)
                result[:version_history] = version_history

                # 各バージョンのパーサー定義を取得
                version_details = {}
                version_history.each do |version|
                  archived_parser = Narou::Parsers::ConfigManager.load_archived_legacy_parser(domain, version)
                  if archived_parser
                    version_details[version] = {
                      version: archived_parser["version"],
                      name: archived_parser["name"],
                      patterns: {
                        body_pattern: archived_parser["body_pattern"]&.to_s,
                        introduction_pattern: archived_parser["introduction_pattern"]&.to_s,
                        postscript_pattern: archived_parser["postscript_pattern"]&.to_s
                      }
                    }
                  end
                end
                result[:version_details] = version_details
              end

              # このドメインの小説を取得
              novels = []
              Database.instance.each_key do |id|
                novel_data = Database.instance[id]
                if novel_data && novel_data["toc_url"]&.include?(domain)
                  novels << {
                    id: id,
                    title: novel_data["title"],
                    last_update: novel_data["last_update"]&.to_i,
                    parser_engine: Narou::Parsers::ConfigManager.get_engine_for_novel(id)
                  }
                end
              end
              result[:novels] = novels

              # 変更ログを取得
              change_log = Narou::Parsers::ConfigManager.get_change_log(domain)
              result[:change_log] = change_log

              json success_response(result)
            rescue StandardError => e
              status 500
              json error_response("DIAGNOSTICS_ERROR", e.message)
            end
          end

          # GET /api/v2/settings/export
          # 設定ファイルをZIPでエクスポート
          get "/api/v2/settings/export" do
            set_cors_headers

            begin
              require "zip"
              require "stringio"

              local_dir = Narou.local_setting_dir
              global_dir = Narou.global_setting_dir

              unless local_dir&.exist?
                status 400
                return json error_response("NOT_INITIALIZED", "Narou is not initialized")
              end

              # ZIPファイルをメモリ上で作成
              zip_buffer = StringIO.new
              Zip::OutputStream.write_buffer(zip_buffer) do |zos|
                # .narou/ 配下の設定ファイルを追加
                if local_dir&.exist?
                  Dir.glob(local_dir.join("*.yaml")).each do |file|
                    filename = File.basename(file)
                    zos.put_next_entry(".narou/#{filename}")
                    zos.write(File.read(file))
                  end

                  # パーサー設定ディレクトリ
                  parser_dir = local_dir.join("parsers")
                  if parser_dir.exist?
                    Dir.glob(parser_dir.join("*.yaml")).each do |file|
                      filename = File.basename(file)
                      zos.put_next_entry(".narou/parsers/#{filename}")
                      zos.write(File.read(file))
                    end
                  end

                  # replace.txt
                  replace_file = local_dir.join("replace.txt")
                  if replace_file.exist?
                    zos.put_next_entry(".narou/replace.txt")
                    zos.write(File.read(replace_file))
                  end
                end

                # .narousetting/ 配下の設定ファイルを追加
                if global_dir&.exist?
                  Dir.glob(global_dir.join("*.yaml")).each do |file|
                    filename = File.basename(file)
                    zos.put_next_entry(".narousetting/#{filename}")
                    zos.write(File.read(file))
                  end

                  # グローバル置換ファイル
                  global_replace = global_dir.join("replace.txt")
                  if global_replace.exist?
                    zos.put_next_entry(".narousetting/replace.txt")
                    zos.write(File.read(global_replace))
                  end
                end
              end

              zip_buffer.rewind

              content_type "application/zip"
              attachment "narou-settings-#{Time.now.strftime('%Y%m%d-%H%M%S')}.zip"
              zip_buffer.read
            rescue StandardError => e
              status 500
              json error_response("EXPORT_ERROR", e.message)
            end
          end

          # POST /api/v2/settings/import
          # ZIPファイルから設定をインポート
          post "/api/v2/settings/import" do
            set_cors_headers

            begin
              require "zip"

              unless params[:file] && params[:file][:tempfile]
                status 400
                return json error_response("NO_FILE", "No file uploaded")
              end

              local_dir = Narou.local_setting_dir
              global_dir = Narou.global_setting_dir

              unless local_dir&.exist?
                status 400
                return json error_response("NOT_INITIALIZED", "Narou is not initialized")
              end

              imported_files = []
              skipped_files = []

              Zip::File.open(params[:file][:tempfile].path) do |zip_file|
                zip_file.each do |entry|
                  next if entry.directory?

                  # セキュリティチェック: パストラバーサル防止
                  entry_name = entry.name
                  next if entry_name.include?("..") || entry_name.start_with?("/")

                  # 許可するファイルパターンのみ処理
                  if entry_name.start_with?(".narou/")
                    relative_path = entry_name.sub(".narou/", "")
                    target_path = local_dir.join(relative_path)

                    # サブディレクトリが必要な場合は作成
                    FileUtils.mkdir_p(File.dirname(target_path))

                    # yamlまたはtxtファイルのみインポート
                    if relative_path.end_with?(".yaml", ".txt")
                      File.write(target_path, entry.get_input_stream.read)
                      imported_files << entry_name
                    else
                      skipped_files << entry_name
                    end
                  elsif entry_name.start_with?(".narousetting/")
                    relative_path = entry_name.sub(".narousetting/", "")
                    target_path = global_dir.join(relative_path)

                    # サブディレクトリが必要な場合は作成
                    FileUtils.mkdir_p(File.dirname(target_path))

                    # yamlまたはtxtファイルのみインポート
                    if relative_path.end_with?(".yaml", ".txt")
                      File.write(target_path, entry.get_input_stream.read)
                      imported_files << entry_name
                    else
                      skipped_files << entry_name
                    end
                  else
                    skipped_files << entry_name
                  end
                end
              end

              # Inventoryのキャッシュをクリア
              Inventory.clear_cache if Inventory.respond_to?(:clear_cache)

              json success_response(
                {
                  imported_count: imported_files.size,
                  imported_files: imported_files,
                  skipped_count: skipped_files.size,
                  skipped_files: skipped_files
                },
                message: "Settings imported successfully"
              )
            rescue Zip::Error => e
              status 400
              json error_response("INVALID_ZIP", "Invalid ZIP file: #{e.message}")
            rescue StandardError => e
              status 500
              json error_response("IMPORT_ERROR", e.message)
            end
          end
        end
      end
    end
  end
end
