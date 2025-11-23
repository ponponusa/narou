# frozen_string_literal: true

#
# パーサーを選択するためのファクトリクラス
#

require_relative "config_manager"
require_relative "parser_error"

module Narou
  module Parsers
    class ParserSelector
      class << self
        # サイトと設定に基づいて適切なパーサーを選択
        def select(site_setting, novel_id: nil, logger: nil)
          domain = site_setting["domain"]
          raise ParserError, "domain が設定されていません" unless domain

          # パーサーエンジンを決定
          engine = determine_engine(novel_id)
          
          # ユーザー設定を読み込み
          user_config = ConfigManager.load_parser_config(domain, engine)
          
          # エンジンに応じてパーサーを生成
          create_parser(domain, engine, site_setting, user_config, logger)
        end

        # 小説IDまたはグローバル設定からエンジンを決定
        def determine_engine(novel_id)
          if novel_id
            ConfigManager.get_engine_for_novel(novel_id)
          else
            global_config = ConfigManager.load_global_config
            global_config["default_engine"] || "nokogiri"
          end
        end

        # エンジンとドメインに応じて適切なパーサーを生成
        def create_parser(domain, engine, site_setting, user_config, logger)
          if engine == "legacy"
            require_relative "legacy_parser"
            LegacyParser.new(site_setting, user_config, logger: logger)
          else
            # Nokogiri パーサー
            parser_class = get_parser_class(domain)
            parser_class.new(site_setting, user_config, logger: logger)
          end
        end

        # ドメインに応じた専用パーサークラスを取得
        def get_parser_class(domain)
          case domain
          when "ncode.syosetu.com", "novel18.syosetu.com"
            require_relative "narou_parser"
            NarouParser
          when "kakuyomu.jp"
            require_relative "kakuyomu_parser"
            KakuyomuParser
          when "syosetu.org"
            require_relative "narou_parser"
            NarouParser  # syosetu.org も同じ構造
          else
            # デフォルトは汎用 Nokogiri パーサー
            require_relative "nokogiri_parser"
            NokogiriParser
          end
        end
      end
    end
  end
end
