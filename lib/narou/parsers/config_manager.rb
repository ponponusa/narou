# frozen_string_literal: true

#
# パーサー設定の読み込み・保存を管理するクラス
#

require "yaml"
require "fileutils"
require "lib/narou/parsers/parser_error"

module Narou
  module Parsers
    class ConfigManager
      GLOBAL_CONFIG_PATH = ".narou/parser_config.yaml"
      NOKOGIRI_USER_DIR = ".narou/parsers"
      LEGACY_USER_DIR = ".narou/legacy_parsers"
      NOKOGIRI_DEFAULT_DIR = "preset/parsers"
      LEGACY_DEFAULT_DIR = "webnovel"

      class << self
        # グローバル設定を読み込み
        def load_global_config
          path = File.join(Narou.root_dir, GLOBAL_CONFIG_PATH)
          if File.exist?(path)
            YAML.load_file(path, aliases: true)
          else
            # デフォルト設定
            default_config = {
              "default_engine" => "nokogiri",
              "novels" => {}
            }
            save_global_config(default_config)
            default_config
          end
        end

        # グローバル設定を保存
        def save_global_config(config)
          path = File.join(Narou.root_dir, GLOBAL_CONFIG_PATH)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, YAML.dump(config))
        end

        # 指定小説・サイトのパーサー設定を読み込み
        def load_parser_config(domain, engine)
          user_config = load_user_config(domain, engine)
          default_config = load_default_config(domain, engine)

          unless default_config
            raise ConfigLoadError, "デフォルト設定ファイルが見つかりません: #{domain} (engine: #{engine})"
          end

          # ユーザー設定が存在する場合はデフォルト設定とマージ
          if user_config
            merged = default_config.dup
            user_config.each do |key, value|
              merged[key] = value unless value.nil?
            end
            merged
          else
            default_config
          end
        end

        # ユーザー設定を保存
        def save_parser_config(domain, config, engine = "nokogiri")
          user_path = user_config_path(domain, engine)
          FileUtils.mkdir_p(File.dirname(user_path))
          File.write(user_path, YAML.dump(config))
        end

        # 小説ごとのエンジン設定を取得
        def get_engine_for_novel(novel_id)
          global_config = load_global_config
          global_config.dig("novels", novel_id, "engine") ||
            global_config["default_engine"] ||
            "nokogiri"
        end

        # 小説ごとのエンジン設定を保存
        def set_engine_for_novel(novel_id, engine)
          global_config = load_global_config
          global_config["novels"] ||= {}
          global_config["novels"][novel_id] ||= {}
          global_config["novels"][novel_id]["engine"] = engine
          save_global_config(global_config)
        end

        # 成功したセレクタを記録
        def update_successful_selector(domain, selector_key, selector, engine = "nokogiri")
          # ユーザー設定が存在する場合のみ記録を保存
          user_config = load_user_config(domain, engine)
          return unless user_config

          user_config["last_successful_selectors"] ||= {}
          user_config["last_successful_selectors"][selector_key] = {
            "selector" => selector,
            "date" => Time.now.strftime("%Y-%m-%d %H:%M:%S")
          }
          save_parser_config(domain, user_config, engine)
        end

        # セレクタ履歴を記録（Nokogiri用）
        def record_selector_history(domain, selector_key, selector, engine = "nokogiri")
          user_config = load_user_config(domain, engine) || {}
          user_config["selector_history"] ||= {}
          user_config["selector_history"][selector_key] ||= []

          # 既存のエントリを探す
          history_entry = user_config["selector_history"][selector_key].find { |h| h["selector"] == selector }

          if history_entry
            # 既存エントリを更新
            history_entry["last_success"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
            history_entry["success_count"] = (history_entry["success_count"] || 0) + 1
          else
            # 新規エントリを追加
            new_entry = {
              "selector" => selector,
              "first_success" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
              "last_success" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
              "success_count" => 1
            }

            # セレクタ変更を検出（現在のlast_successful_selectorsと異なる場合）
            last_successful = user_config.dig("last_successful_selectors", selector_key, "selector")
            if last_successful && last_successful != selector
              new_entry["detected_change"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
              new_entry["replaced_selector"] = last_successful

              # 変更ログに記録
              record_selector_change(domain, selector_key, last_successful, selector, engine)
            end

            user_config["selector_history"][selector_key] << new_entry
          end

          # 後方互換のため last_successful_selectors も更新
          user_config["last_successful_selectors"] ||= {}
          user_config["last_successful_selectors"][selector_key] = {
            "selector" => selector,
            "date" => Time.now.strftime("%Y-%m-%d %H:%M:%S")
          }

          save_parser_config(domain, user_config, engine)
        rescue => e
          warn "[ConfigManager] セレクタ履歴の記録に失敗: #{e.message}"
        end

        # セレクタ変更を変更ログに記録
        def record_selector_change(domain, selector_key, old_selector, new_selector, engine)
          change_log_path = File.join(Narou.root_dir, ".narou/parsers/change_log.yaml")
          change_log = File.exist?(change_log_path) ? YAML.load_file(change_log_path, aliases: true) : {}

          change_log[domain] ||= []
          change_log[domain] << {
            "timestamp" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
            "selector_key" => selector_key,
            "old_selector" => old_selector,
            "new_selector" => new_selector,
            "detection_type" => "auto",
            "engine" => engine
          }

          FileUtils.mkdir_p(File.dirname(change_log_path))
          File.write(change_log_path, YAML.dump(change_log))
        rescue => e
          warn "[ConfigManager] 変更ログの記録に失敗: #{e.message}"
        end

        # セレクタ履歴を取得
        def get_selector_history(domain, engine = "nokogiri")
          user_config = load_user_config(domain, engine)
          return {} unless user_config

          user_config["selector_history"] || {}
        end

        # 変更ログを取得
        def get_change_log(domain = nil)
          change_log_path = File.join(Narou.root_dir, ".narou/parsers/change_log.yaml")
          return {} unless File.exist?(change_log_path)

          change_log = YAML.load_file(change_log_path, aliases: true)
          domain ? change_log[domain] || [] : change_log
        rescue => e
          warn "[ConfigManager] 変更ログの読み込みに失敗: #{e.message}"
          {}
        end

        # アーカイブされたレガシーパーサーを取得
        def load_archived_legacy_parser(domain, version)
          archive_path = File.join(Narou.script_dir, "preset/parsers/legacy_archive/#{domain}/v#{version}.yaml")
          return nil unless File.exist?(archive_path)

          YAML.load_file(archive_path, aliases: true)
        rescue => e
          warn "[ConfigManager] アーカイブの読み込みに失敗: #{domain} v#{version} - #{e.message}"
          nil
        end

        # レガシーパーサーのバージョン履歴を取得
        def get_legacy_version_history(domain)
          archive_dir = File.join(Narou.script_dir, "preset/parsers/legacy_archive/#{domain}")
          return [] unless Dir.exist?(archive_dir)

          versions = []
          Dir.glob(File.join(archive_dir, "v*.yaml")).each do |path|
            version = File.basename(path, ".yaml").sub(/^v/, "")
            versions << version
          end

          versions.sort
        rescue => e
          warn "[ConfigManager] バージョン履歴の取得に失敗: #{domain} - #{e.message}"
          []
        end

        # 全てのサイト設定を取得（Web UI 用）
        def list_all_parser_configs(engine)
          configs = {}
          dir = engine == "nokogiri" ? NOKOGIRI_DEFAULT_DIR : LEGACY_DEFAULT_DIR

          Dir.glob(File.join(Narou.script_dir, dir, "*.yaml")) do |path|
            domain = File.basename(path, ".yaml")
            configs[domain] = load_parser_config(domain, engine)
          end

          configs
        end

        private

        def load_user_config(domain, engine)
          path = user_config_path(domain, engine)
          File.exist?(path) ? YAML.load_file(path, aliases: true) : nil
        rescue => e
          warn "[ConfigManager] ユーザー設定読み込みエラー: #{path} - #{e.message}"
          nil
        end

        def load_default_config(domain, engine)
          path = default_config_path(domain, engine)
          # レガシーエンジンの場合はaliasesを許可（webnovel/*.yamlはエイリアスを使用）
          File.exist?(path) ? YAML.load_file(path, aliases: true) : nil
        rescue => e
          warn "[ConfigManager] デフォルト設定読み込みエラー: #{path} - #{e.message}"
          nil
        end

        def copy_default_to_user(domain, engine, default_config)
          user_path = user_config_path(domain, engine)
          FileUtils.mkdir_p(File.dirname(user_path))
          File.write(user_path, YAML.dump(default_config))
        end

        def user_config_path(domain, engine)
          dir = engine == "nokogiri" ? NOKOGIRI_USER_DIR : LEGACY_USER_DIR
          File.join(Narou.root_dir, dir, "#{domain}.yaml")
        end

        def default_config_path(domain, engine)
          dir = engine == "nokogiri" ? NOKOGIRI_DEFAULT_DIR : LEGACY_DEFAULT_DIR
          File.join(Narou.script_dir, dir, "#{domain}.yaml")
        end
      end
    end
  end
end
