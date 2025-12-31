# frozen_string_literal: true

#
# カクヨム専用パーサー（JSON + HTML 対応）
#

require "json"
require "lib/narou/parsers/base_parser"

module Narou
  module Parsers
    class KakuyomuParser < BaseParser
      # 目次ページを解析（JSON データを優先）
      def parse_toc(html)
        doc = Nokogiri::HTML(html, nil, @config["encoding"] || "UTF-8")

        # JSON データ抽出を試みる
        if @config["json_data_source"]
          begin
            json_data = extract_json_data(doc)
            return parse_toc_from_json(json_data) if json_data
          rescue JsonParseError => e
            @logger.warn "JSON解析失敗、HTMLフォールバック: #{e.message}"
          end
        end

        # HTML からのフォールバック
        parse_toc_from_html(doc)
      end

      # 本文ページを解析
      def parse_section(html, subtitle_info = {})
        doc = Nokogiri::HTML(html, nil, @config["encoding"] || "UTF-8")

        {
          "body" => extract_body(doc),
          "introduction" => "", # カクヨムには前書き・後書きがない
          "postscript" => "",
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

        # JSON データから取得を試みる
        if @config["json_data_source"]
          begin
            json_data = extract_json_data(doc)
            return parse_novel_info_from_json(json_data) if json_data
          rescue JsonParseError => e
            @logger.warn "JSON解析失敗、HTMLフォールバック: #{e.message}"
          end
        end

        # HTML からのフォールバック
        parse_novel_info_from_html(doc)
      end

      private

      # JSON データを抽出
      def extract_json_data(doc)
        json_config = @config["json_data_source"]
        selector = json_config["selector"]

        script_tag = doc.css(selector).first
        unless script_tag
          raise JsonParseError, "JSON script tag not found: #{selector}"
        end

        json_text = script_tag.content
        JSON.parse(json_text)
      rescue JSON::ParserError => e
        raise JsonParseError, "JSON parse error: #{e.message}"
      end

      # JSON から目次データを抽出
      def parse_toc_from_json(json_data)
        paths = @config["json_data_source"]["paths"]
        work_id = dig_json_path(json_data, paths["work_id"])

        # パス内の {workId} を実際の値に置換
        toc_path = paths["toc"].gsub("{workId}", work_id.to_s)
        toc_data = dig_json_path(json_data, toc_path)

        {
          "subtitles" => parse_toc_chapters(toc_data, json_data),
          "title" => dig_json_path(json_data, paths["title"].gsub("{workId}", work_id.to_s)),
          "author" => extract_author_from_json(json_data, work_id),
          "story" => dig_json_path(json_data, paths["story"]&.gsub("{workId}", work_id.to_s))
        }
      end

      # JSON パスを辿ってデータを取得
      def dig_json_path(data, path)
        return nil unless path

        keys = path.split(".")
        keys.reduce(data) do |current, key|
          case current
          when Hash
            current[key]
          when Array
            key.to_i < current.size ? current[key.to_i] : nil
          end
        end
      end

      # TOC の章データを解析
      def parse_toc_chapters(toc_data, apollo_state)
        return [] unless toc_data.is_a?(Array)

        subtitles = []
        current_chapter = ""

        toc_data.each do |item_ref|
          ref_key = item_ref.is_a?(Hash) ? item_ref["__ref"] : nil
          next unless ref_key

          item = apollo_state[ref_key]
          next unless item

          case item["__typename"]
          when "Chapter"
            current_chapter = item["title"] if item["level"] == 1
          when "Episode"
            subtitles << {
              "index" => item["id"],
              "href" => "/works/#{item['workId']}/episodes/#{item['id']}",
              "subtitle" => item["title"],
              "subdate" => item["publishedAt"],
              "chapter" => current_chapter,
              "subchapter" => ""
            }
          end
        end

        subtitles
      end

      # 著者情報を JSON から抽出
      def extract_author_from_json(json_data, work_id)
        author_path = @config["json_data_source"]["paths"]["author"]
        return nil unless author_path

        author_ref = dig_json_path(json_data, author_path.gsub("{workId}", work_id.to_s))
        return nil unless author_ref

        author_data = json_data[author_ref]
        author_data ? author_data["activityName"] : nil
      end

      # HTML から目次データを抽出（フォールバック）
      def parse_toc_from_html(doc)
        {
          "subtitles" => [],
          "title" => extract_title_from_html(doc),
          "author" => extract_author_from_html(doc),
          "story" => extract_story_from_html(doc)
        }
      end

      # JSON から小説情報を抽出
      def parse_novel_info_from_json(json_data)
        paths = @config["json_data_source"]["paths"]
        work_id = dig_json_path(json_data, paths["work_id"])

        {
          "title" => dig_json_path(json_data, paths["title"]&.gsub("{workId}", work_id.to_s)),
          "author" => extract_author_from_json(json_data, work_id),
          "story" => dig_json_path(json_data, paths["story"]&.gsub("{workId}", work_id.to_s))
        }
      end

      # HTML から小説情報を抽出（フォールバック）
      def parse_novel_info_from_html(doc)
        {
          "title" => extract_title_from_html(doc),
          "author" => extract_author_from_html(doc),
          "story" => extract_story_from_html(doc)
        }
      end

      def extract_body(doc)
        extract_with_fallback(doc, "body_selectors", extract_type: "inner_html")
      end

      def extract_title_from_html(doc)
        novel_info_selectors = @config["novel_info_selectors"]
        return nil unless novel_info_selectors.is_a?(Hash)

        selector = novel_info_selectors["title"]
        return nil unless selector
        doc.css(selector).first&.text&.strip
      end

      def extract_author_from_html(doc)
        novel_info_selectors = @config["novel_info_selectors"]
        return nil unless novel_info_selectors.is_a?(Hash)

        selector = novel_info_selectors["author"]
        return nil unless selector
        doc.css(selector).first&.text&.strip
      end

      def extract_story_from_html(doc)
        novel_info_selectors = @config["novel_info_selectors"]
        return nil unless novel_info_selectors.is_a?(Hash)

        selector = novel_info_selectors["story"]
        return nil unless selector
        doc.css(selector).first&.inner_html&.strip
      end
    end
  end
end
