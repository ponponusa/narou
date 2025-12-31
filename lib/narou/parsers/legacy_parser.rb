# frozen_string_literal: true

require "lib/narou/parsers/base_parser"

module Narou
  module Parsers
    #
    # Legacy Parser - 既存の正規表現ベースのパーサーをラップ
    #
    # webnovel/*.yaml の正規表現パターンを使用してHTMLを解析します。
    # 後方互換性を保つために、既存の SiteSetting.multi_match() を利用します。
    #
    class LegacyParser < BaseParser
      def initialize(site_setting, user_config = {}, logger: nil)
        super(site_setting, user_config, logger: logger)
      end

      #
      # 目次ページから章リストを抽出
      #
      # @param [String] html - 目次ページのHTML
      # @return [Array<Hash>] 章情報の配列
      #
      def parse_toc(html)
        match_data = @site_setting.multi_match(html, "subtitles")
        unless match_data
          raise ParserError.new(
            "目次の抽出に失敗しました",
            selector: "subtitles pattern",
            url: @site_setting["toc_url"]
          )
        end

        # multi_match の結果を返す（既存の形式を維持）
        @site_setting["subtitles"]
      end

      #
      # 章ページから本文・前書き・後書きを抽出
      #
      # @param [String] html - 章ページのHTML
      # @param [Hash] subtitle_info - 章情報
      # @return [Hash] 抽出結果 { "body" => String, "introduction" => String, "postscript" => String }
      #
      def parse_section(html, subtitle_info = {})
        @site_setting.multi_match(html, "body_pattern", "introduction_pattern", "postscript_pattern")

        result = {
          "data_type" => @site_setting["data_type"] || "html",
          "body" => @site_setting["body_pattern"].to_s,
          "introduction" => @site_setting["introduction_pattern"].to_s,
          "postscript" => @site_setting["postscript_pattern"].to_s
        }

        # body が空の場合はエラー
        if result["body"].empty?
          raise AllSelectorsFailedError.new(
            "body_pattern",
            [{ "selector" => "body_pattern", "priority" => 0 }]
          )
        end

        result
      end

      #
      # 小説情報ページからメタデータを抽出
      #
      # @param [String] html - 小説情報ページのHTML
      # @param [Array<String>] fields - 取得したいフィールド名のリスト
      # @return [Hash] 抽出結果
      #
      def parse_novel_info(html, fields = %w(title author story))
        @site_setting.multi_match(html, *fields)

        result = {}
        fields.each do |field|
          result[field] = @site_setting[field].to_s
        end

        # title が必須
        if result["title"].to_s.empty?
          raise ParserError, "小説情報の抽出に失敗しました（タイトルが見つかりません）"
        end

        result
      end

      #
      # Legacy パーサーでは構造変更検出は行わない
      #
      def detect_structure_change?(_html)
        false
      end

      #
      # Legacy パーサーでバージョン情報を記録
      #
      def update_successful_selector(_selector_key, _selector)
        # Legacyパーサーではセレクタではなくバージョン情報を記録
        # BaseParserのrecord_selector_historyが呼ばれるが、
        # Legacyの場合は実際にはバージョン番号をセクションファイルに記録する方が重要
        # ここでは何もしない（バージョン記録はSectionDownloaderで行う）
      end
    end
  end
end
