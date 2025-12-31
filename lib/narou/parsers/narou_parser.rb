# frozen_string_literal: true

#
# 小説家になろう専用パーサー
#

require "lib/narou/parsers/base_parser"

module Narou
  module Parsers
    class NarouParser < BaseParser
      # 目次ページを解析
      def parse_toc(html)
        doc = Nokogiri::HTML(html, nil, @config["encoding"] || "UTF-8")

        {
          "subtitles" => extract_subtitles(doc),
          "title" => extract_title(doc),
          "author" => extract_author(doc),
          "story" => extract_story(doc)
        }
      rescue AllSelectorsFailedError => e
        @logger.error "目次ページの解析に失敗: #{e.message}"
        raise ParserError, "目次ページの解析に失敗しました"
      end

      # 本文ページを解析
      def parse_section(html, subtitle_info = {})
        doc = Nokogiri::HTML(html, nil, @config["encoding"] || "UTF-8")

        {
          "body" => extract_body(doc),
          "introduction" => extract_introduction(doc),
          "postscript" => extract_postscript(doc),
          "data_type" => "html"
        }
      rescue AllSelectorsFailedError => e
        # サイト構造変更の可能性をチェック
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
          "title" => extract_novel_info_item(doc, "title_selector"),
          "author" => extract_novel_info_item(doc, "author_selector"),
          "story" => extract_novel_info_item(doc, "story_selector"),
          "novel_type" => extract_novel_info_item(doc, "novel_type_selector"),
          "general_all_no" => extract_novel_info_item(doc, "general_all_no_selector")
        }
      rescue => e
        @logger.error "小説情報ページの解析に失敗: #{e.message}"
        raise ParserError, "小説情報ページの解析に失敗しました"
      end

      private

      def extract_subtitles(doc)
        # 目次リストを取得
        toc_selector = @config["toc_selectors"]&.first
        unless toc_selector
          raise ConfigLoadError, "toc_selectors が設定されていません"
        end

        items = extract_with_fallback(doc, "toc_selectors", extract_type: "list")

        items.map.with_index do |item, idx|
          {
            "index" => extract_index_from_href(item["href"]),
            "href" => item["href"],
            "subtitle" => item["subtitle"],
            "subdate" => item["subdate"],
            "chapter" => item["chapter"] || "",
            "subchapter" => ""
          }
        end
      end

      def extract_index_from_href(href)
        # /n1234ab/123/ から 123 を抽出
        return nil unless href
        href.match(%r{/(\d+)/?$})&.captures&.first
      end

      def extract_title(doc)
        novel_info_selectors = @config["novel_info_selectors"]
        return nil unless novel_info_selectors.is_a?(Hash)

        selector = novel_info_selectors["title"]
        return nil unless selector

        result = doc.css(selector).first
        result&.text&.strip
      end

      def extract_author(doc)
        novel_info_selectors = @config["novel_info_selectors"]
        return nil unless novel_info_selectors.is_a?(Hash)

        selector = novel_info_selectors["author"]
        return nil unless selector

        result = doc.css(selector).first
        result&.text&.strip
      end

      def extract_story(doc)
        novel_info_selectors = @config["novel_info_selectors"]
        return nil unless novel_info_selectors.is_a?(Hash)

        selector = novel_info_selectors["story"]
        return nil unless selector

        result = doc.css(selector).first
        result&.inner_html&.strip
      end

      def extract_body(doc)
        extract_with_fallback(doc, "body_selectors", extract_type: "inner_html")
      rescue AllSelectorsFailedError
        # body が見つからない場合は空文字列を返す
        @logger.warn "本文が見つかりませんでした"
        ""
      end

      def extract_introduction(doc)
        extract_with_fallback(doc, "introduction_selectors", extract_type: "inner_html")
      rescue AllSelectorsFailedError
        # introduction はオプショナル
        ""
      end

      def extract_postscript(doc)
        extract_with_fallback(doc, "postscript_selectors", extract_type: "inner_html")
      rescue AllSelectorsFailedError
        # postscript はオプショナル
        ""
      end

      def extract_novel_info_item(doc, selector_key)
        novel_info_selectors = @config["novel_info_selectors"]
        return nil unless novel_info_selectors.is_a?(Hash)

        selector = novel_info_selectors[selector_key.sub(/_selector$/, "")]
        return nil unless selector

        result = doc.css(selector).first
        result&.text&.strip
      end
    end
  end
end
