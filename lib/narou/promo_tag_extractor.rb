# frozen_string_literal: true

module Narou
  module PromoTagExtractor
    module_function

    BRACKETS = [
      ['\\(', '\\)'], ['\\[', '\\]'], ['【', '】'], ['（', '）'], ['〔', '〕'],
      ['〈', '〉'], ['《', '》'], ['＜', '＞'], ['『', '』'], ['「', '」'],
      ['｟', '｠'], ['〖', '〗']
    ].freeze

    PROMO_KEYWORDS = [
      '書籍化', '文庫化', '単行本化', 'コミカライズ', '漫画化', 'アニメ化', '映画化',
      'ドラマ化', 'ドラマＣＤ化', 'ドラマCD化', 'ドラマＣＤ', 'ドラマCD', 'ボイスドラマ化', 'ゲーム化',
      'ノベライズ', 'ボイスコミック', 'オーディオブック',
      '連載中', '連載開始', '新連載', '配信中', '公開中', '更新中', '完結', '完結済',
      '好評発売中', '発売中', '発売', '重版', '出荷中', '予約受付中',
      '最新話', '公開', '第\\d+巻', '第\\d+話', '配信',
      '受賞', '受賞作', '書籍版発売中', 'コミックス発売中',
      '書籍版', 'コミックス版', '電書版', 'kindle版',
      'コミックス\\s*第\\d+巻'
    ].freeze

    SEP = /\s*[|｜／\/・\-—–―~〜:：;；]+?\s*/x.freeze
    TOKEN_SEPARATOR = /\s*[|｜／\/・･\-—–―~〜:：;；＋+＠@＆&]+?\s*/x.freeze
    TRAILING_DECORATIONS = /[！!？?。．､，,、…‥☆★♪♪※‼⁉︎〜～ー─—―・\s]+\z/.freeze
    WHITESPACE_PATTERN = /[\s\u3000]+/.freeze

    PROMO_REGEXES = PROMO_KEYWORDS.map { |pattern| Regexp.new(pattern) }.freeze
    BRACKET_REGEXES = BRACKETS.map do |opening, closing|
      Regexp.new("#{opening}(.*?)#{closing}")
    end.freeze
    SEP_CAPTURE = Regexp.new("(#{SEP.source})", SEP.options).freeze

    Result = Struct.new(:title, :author, :promo_tags, :title_tags, :author_tags, keyword_init: true)

    def extract(title:, author: nil)
      sanitized_title, title_tags = cleanse(title)
      sanitized_author, author_tags = cleanse(author)
      promo_tags = uniq_preserve_order(title_tags + author_tags)
      Result.new(
        title: sanitized_title,
        author: sanitized_author,
        promo_tags: promo_tags,
        title_tags: title_tags,
        author_tags: author_tags
      )
    end

    def normalize_entry!(entry)
      return false unless entry.is_a?(Hash)

      result = extract(title: entry["title"], author: entry["author"])
      updated = false

      if result.title != entry["title"]
        entry["title"] = result.title
        updated = true
      end

      if result.author != entry["author"]
        entry["author"] = result.author
        updated = true
      end

      promo_tags = result.promo_tags.dup
      if promo_tags.empty? && entry["promo_tags"].is_a?(Array)
        promo_tags = entry["promo_tags"]
      end

      if !entry["promo_tags"].is_a?(Array) || entry["promo_tags"] != promo_tags
        entry["promo_tags"] = promo_tags
        updated = true
      end

      existing_title_tags = entry["promo_tags_title"] if entry["promo_tags_title"].is_a?(Array)
      existing_author_tags = entry["promo_tags_author"] if entry["promo_tags_author"].is_a?(Array)

      title_tags = (result.title_tags || []).dup
      title_tags = existing_title_tags.dup if title_tags.empty? && existing_title_tags
      author_tags = (result.author_tags || []).dup
      author_tags = existing_author_tags.dup if author_tags.empty? && existing_author_tags

      if entry["promo_tags_title"] != title_tags
        entry["promo_tags_title"] = title_tags
        updated = true
      end

      if entry["promo_tags_author"] != author_tags
        entry["promo_tags_author"] = author_tags
        updated = true
      end

      updated
    end

    def cleanse(value)
      original = (value || "").to_s
      text = original.dup
      return [normalize_spacing(original), []] if text.strip.empty?

      tags = []

      text, bracket_tags = strip_bracket_promos(text)
      tags.concat(bracket_tags)

      text, at_tags = strip_at_promos(text)
      tags.concat(at_tags)

      text, separated_tags = strip_separator_promos(text)
      tags.concat(separated_tags)

      normalized = normalize_spacing(text)
      normalized = normalize_spacing(original) if normalized.empty?
      [normalized, uniq_preserve_order(tags)]
    end

    def normalize_spacing(text)
      text.to_s.gsub(WHITESPACE_PATTERN, " ").strip
    end

    def strip_bracket_promos(text)
      tags = []
      stripped = text.dup

      BRACKET_REGEXES.each do |pattern|
        loop do
          replaced = false
          stripped = stripped.gsub(pattern) do |match|
            inner = Regexp.last_match(1)
            segment_tags = extract_segment_tags(inner)
            if segment_tags.empty? || !promotional_content?(inner)
              match
            else
              tags.concat(segment_tags)
              replaced = true
              ""
            end
          end
          break unless replaced
        end
      end

      [stripped, tags]
    end

    def strip_at_promos(text)
      tags = []
      stripped = text.dup

      loop do
        matched = stripped.match(/(.+?)[＠@]\s*(.+)\z/)
        break unless matched

        head = matched[1]
        tail = matched[2]
        segment_tags = extract_segment_tags(tail)
        break if segment_tags.empty?

        tags.concat(segment_tags)
        stripped = head.rstrip
      end

      [stripped, tags]
    end

    def strip_separator_promos(text)
      tags = []
      keep_parts = []
      last_kept = false

      segments = split_with_separators(text)
      segments.each do |segment|
        content = segment[:segment]
        next if content.nil? || content.empty?

        segment_tags = extract_segment_tags(content)
        if segment_tags.empty?
          if segment[:separator] && last_kept
            keep_parts << segment[:separator]
          end
          keep_parts << content
          last_kept = true
        else
          tags.concat(segment_tags)
          last_kept = false
        end
      end

      [keep_parts.join, tags]
    end

    def split_with_separators(text)
      return [] if text.nil? || text.empty?

      parts = text.split(SEP_CAPTURE)
      segments = []
      separator_buffer = nil

      parts.each do |part|
        next if part.nil? || part.empty?

        if part.match?(SEP)
          separator_buffer = part
        else
          segments << { separator: separator_buffer, segment: part }
          separator_buffer = nil
        end
      end

      segments
    end

    def extract_segment_tags(segment)
      trimmed = normalize_spacing(segment)
      return [] if trimmed.empty?

      tokens = split_tokens(trimmed)

      if tokens.size > 1 && tokens.all? { |token| promotional_token?(token) }
        return tokens.map { |token| normalize_spacing(token) }
      end

      if tokens.size == 1 && promotional_token?(tokens.first)
        return [normalize_spacing(tokens.first)]
      end

      return [trimmed] if promotional_token?(trimmed)

      []
    end

    def split_tokens(text)
      text.split(TOKEN_SEPARATOR).map { |token| token.strip }.reject(&:empty?)
    end

    def promotional_token?(text)
      normalized = normalize_for_match(text)
      return false if normalized.empty?

      PROMO_REGEXES.any? { |regex| regex.match?(normalized) }
    end

    def promotional_content?(text)
      normalized = normalize_for_match(text)
      return false if normalized.empty?

      PROMO_REGEXES.any? { |regex| regex.match?(normalized) }
    end

    def normalize_for_match(text)
      normalize_spacing(text).gsub(TRAILING_DECORATIONS, "")
    end

    def uniq_preserve_order(list)
      seen = {}
      list.each_with_object([]) do |item, result|
        next if item.nil? || item.empty?
        next if seen[item]

        seen[item] = true
        result << item
      end
    end
  end
end
