# frozen_string_literal: true

#
# 汎用 Nokogiri パーサー（サイト別アダプタが存在しない場合のフォールバック）
#

require "lib/narou/parsers/base_parser"

module Narou
  module Parsers
    class NokogiriParser < BaseParser
      # 目次ページを解析
      def parse_toc(html)
        doc = Nokogiri::HTML(html, nil, @config["encoding"] || "UTF-8")

        {
          "subtitles" => extract_subtitles(doc),
          "title" => extract_simple_selector(doc, "novel_info_selectors", "title"),
          "author" => extract_simple_selector(doc, "novel_info_selectors", "author"),
          "story" => extract_simple_selector(doc, "novel_info_selectors", "story", type: "inner_html")
        }
      rescue AllSelectorsFailedError => e
        @logger.error "目次ページの解析に失敗: #{e.message}"
        raise ParserError, "目次ページの解析に失敗しました"
      end

      # 本文ページを解析
      def parse_section(html, subtitle_info = {})
        doc = Nokogiri::HTML(html, nil, @config["encoding"] || "UTF-8")

        {
          "body" => extract_with_fallback(doc, "body_selectors", extract_type: "inner_html"),
          "introduction" => extract_optional(doc, "introduction_selectors"),
          "postscript" => extract_optional(doc, "postscript_selectors"),
          "data_type" => "html"
        }
      rescue AllSelectorsFailedError => e
        if detect_structure_change?(html, "body_selectors")
          last_successful_selectors = @config["last_successful_selectors"]
          last_selector = if last_successful_selectors.is_a?(Hash)
                            body_info = last_successful_selectors["body_selectors"]
                            body_info["selector"] if body_info.is_a?(Hash)
                          end

          raise StructureChangedError.new(
            subtitle_info["href"] || "unknown",
            last_selector
          )
        end

        @logger.error "本文ページの解析に失敗: #{e.message}"
        raise ParserError, "本文ページの解析に失敗しました"
      end

      # 小説情報ページを解析
      def parse_novel_info(html)
        doc = Nokogiri::HTML(html, nil, @config["encoding"] || "UTF-8")

        {
          "title" => extract_simple_selector(doc, "novel_info_selectors", "title"),
          "author" => extract_simple_selector(doc, "novel_info_selectors", "author"),
          "story" => extract_simple_selector(doc, "novel_info_selectors", "story", type: "inner_html")
        }
      rescue => e
        @logger.error "小説情報ページの解析に失敗: #{e.message}"
        raise ParserError, "小説情報ページの解析に失敗しました"
      end

      private

      def extract_subtitles(doc)
        return [] unless @config["toc_selectors"]

        items = extract_with_fallback(doc, "toc_selectors", extract_type: "list")
        items.map { |item| normalize_subtitle_item(item) }
      rescue AllSelectorsFailedError
        @logger.warn "目次リストが見つかりませんでした"
        []
      end

      def normalize_subtitle_item(item)
        {
          "index" => item["index"] || item["href"]&.match(/(\d+)/)&.captures&.first,
          "href" => item["href"],
          "subtitle" => item["subtitle"] || "",
          "subdate" => item["subdate"] || "",
          "chapter" => item["chapter"] || "",
          "subchapter" => item["subchapter"] || ""
        }
      end

      def extract_simple_selector(doc, selector_group, key, type: "text")
        group = @config[selector_group]
        return nil unless group.is_a?(Hash)

        selector = group[key]
        return nil unless selector

        result = doc.css(selector).first
        return nil unless result

        type == "inner_html" ? result.inner_html.strip : result.text.strip
      end

      def extract_optional(doc, selector_key)
        extract_with_fallback(doc, selector_key, extract_type: "inner_html")
      rescue AllSelectorsFailedError
        ""
      end
    end
  end
end
