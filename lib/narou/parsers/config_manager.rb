# frozen_string_literal: true

#
# パーサー設定の読み込み・保存を管理するクラス
#

require "yaml"
require "fileutils"
require "narou/parsers/parser_error"

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
            YAML.load_file(path)
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

          # ユーザー設定が存在すればそれを使用、なければデフォルト設定を直接使用
          if user_config
            user_config
          elsif default_config
            default_config
          else
            raise ConfigLoadError, "設定ファイルが見つかりません: #{domain} (engine: #{engine})"
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
          File.exist?(path) ? YAML.load_file(path) : nil
        rescue => e
          warn "[ConfigManager] ユーザー設定読み込みエラー: #{path} - #{e.message}"
          nil
        end

        def load_default_config(domain, engine)
          path = default_config_path(domain, engine)
          File.exist?(path) ? YAML.load_file(path) : nil
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
