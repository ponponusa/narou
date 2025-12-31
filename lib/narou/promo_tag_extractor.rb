# frozen_string_literal: true

require "lib/core/inventory"
require "lib/novel/novelsetting"

module Narou
  module PromoTagExtractor
    module_function

    BRACKETS = [
      ['\\(', '\\)'], ['\\[', '\\]'], ["【", "】"], ["（", "）"], ["〔", "〕"],
      ["〈", "〉"], ["《", "》"], ["＜", "＞"], ["『", "』"], ["「", "」"],
      ["｟", "｠"], ["〖", "〗"]
    ].freeze

    DEFAULT_PROMO_KEYWORDS = [
      "書籍化", "文庫化", "単行本化", "コミカライズ", "漫画化", "アニメ化", "映画化",
      "ドラマ化", "ドラマＣＤ化", "ドラマCD化", "ドラマＣＤ", "ドラマCD", "ボイスドラマ化", "ゲーム化",
      "ノベライズ", "ボイスコミック", "オーディオブック",
      "連載中", "連載開始", "新連載", "連載版", "配信中", "公開中", "更新中", "完結", "完結済",
      "好評発売中", "発売中", "発売", "重版", "出荷中", "予約受付中",
      "最新話", "公開", '第\\d+巻', '第\\d+話',
      "受賞", "受賞作", "書籍版発売中", "コミックス発売中",
      "書籍版", "コミックス版", "電書版", "kindle版",
      'コミックス\\s*第\\d+巻', 'コミック\\s*第?\\d+巻', '第?\\d+巻\\s*発売'
    ].freeze

    DEFAULT_PROMO_REGEXES = DEFAULT_PROMO_KEYWORDS.map { |pattern| Regexp.new(pattern) }.freeze

    SEP = %r{\s*[|｜／/・\-—–―~〜:：;；]+?\s*}x.freeze
    TOKEN_SEPARATOR = %r{\s*[|｜／/・･\-—–―~〜:：;；＋+＠@＆&]+?\s*}x.freeze
    TRAILING_DECORATIONS = /[！!？?。．､，,、…‥☆★♪※‼⁉︎〜～ー─—―・\s]+\z/.freeze
    WHITESPACE_PATTERN = /[\s\u3000]+/.freeze

    BRACKET_REGEXES = BRACKETS.map do |opening, closing|
      # ReDoS攻撃を防ぐため、改行以外の文字に限定し、文字数制限を追加
      Regexp.new("#{opening}([^\n]{1,200}?)#{closing}")
    end.freeze
    SEP_CAPTURE = Regexp.new("(#{SEP.source})", SEP.options).freeze

    DEFAULT_ENABLED = false

    Result = Struct.new(:title, :author, :promo_tags, :title_tags, :author_tags, keyword_init: true)
    Config = Struct.new(:enabled, :keywords, :regexes, keyword_init: true)

    def extract(title:, author: nil, config: nil)
      resolved_config = build_config(config)
      unless resolved_config.enabled
        return Result.new(
          title: normalize_spacing(title),
          author: normalize_spacing(author),
          promo_tags: [],
          title_tags: [],
          author_tags: []
        )
      end

      promo_regexes = resolved_config.regexes
      sanitized_title, title_tags = cleanse(title, promo_regexes: promo_regexes)
      sanitized_author, author_tags = cleanse(author, promo_regexes: promo_regexes)
      promo_tags = uniq_preserve_order(title_tags + author_tags)
      Result.new(
        title: sanitized_title,
        author: sanitized_author,
        promo_tags: promo_tags,
        title_tags: title_tags,
        author_tags: author_tags
      )
    end

    def normalize_entry!(entry, config: nil, novel_id: nil)
      return false unless entry.is_a?(Hash)

      resolved_config = config || resolve_config(novel_id: novel_id || entry["id"])

      base_title = entry["title_raw_latest"]
      base_title = entry.fetch("title_original", nil) if base_title.nil?
      base_title ||= entry["title"]

      original_author = entry.fetch("author_original", nil) || entry["author"]

      entry["title_original"] = base_title if base_title
      entry["author_original"] = original_author if original_author

      result = extract(title: base_title, author: original_author, config: resolved_config)
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
      title_tags = result.title_tags.dup
      author_tags = result.author_tags.dup

      unless entry["promo_tags"] == promo_tags
        entry["promo_tags"] = promo_tags
        updated = true
      end

      unless entry["promo_tags_title"] == title_tags
        entry["promo_tags_title"] = title_tags
        updated = true
      end

      unless entry["promo_tags_author"] == author_tags
        entry["promo_tags_author"] = author_tags
        updated = true
      end

      updated
    end

    def resolve_config(novel_id: nil)
      global_settings = Inventory.load("local_setting")
      force_settings = NovelSetting.load_force_settings
      default_settings = NovelSetting.load_default_settings

      keywords = DEFAULT_PROMO_KEYWORDS.dup
      keywords.concat(coerce_keywords(global_settings["promo-tag.keywords"]))
      keywords.concat(coerce_keywords(default_settings["promo_tag_additional_keywords"]))
      keywords.concat(coerce_keywords(force_settings["promo_tag_additional_keywords"]))

      enable = determine_enable_from_settings(
        global_settings: global_settings,
        force_settings: force_settings,
        default_settings: default_settings
      )

      novel_setting = load_novel_setting(novel_id)
      if novel_setting
        keywords.concat(coerce_keywords(novel_setting["promo_tag_additional_keywords"]))
        enable = determine_enable_with_novel(
          novel_setting: novel_setting,
          current_enable: enable,
          global_settings: global_settings,
          force_settings: force_settings
        )
      end

      keywords = uniq_preserve_order(keywords)
      Config.new(
        enabled: enable,
        keywords: keywords,
        regexes: compiled_regexes_for(keywords)
      )
    end

    def load_novel_setting(novel_id)
      return nil unless novel_id
      NovelSetting.create(novel_id, false, false)
    rescue StandardError
      nil
    end

    def determine_enable_from_settings(global_settings:, force_settings:, default_settings:)
      if force_settings.include?("enable_promo_tag_filter")
        force_settings["enable_promo_tag_filter"]
      elsif global_settings.include?("promo-tag.enable")
        global_settings["promo-tag.enable"]
      elsif default_settings.include?("enable_promo_tag_filter")
        default_settings["enable_promo_tag_filter"]
      else
        DEFAULT_ENABLED
      end
    end

    def determine_enable_with_novel(novel_setting:, current_enable:, global_settings:, force_settings:)
      return current_enable if force_settings.include?("enable_promo_tag_filter")

      if novel_setting_override?(novel_setting)
        novel_setting["enable_promo_tag_filter"]
      elsif !global_settings.include?("promo-tag.enable")
        novel_setting["enable_promo_tag_filter"]
      else
        current_enable
      end
    end

    def novel_setting_override?(novel_setting)
      ini = novel_setting_ini_section(novel_setting)
      ini.is_a?(Hash) ? ini.key?("enable_promo_tag_filter") : ini.include?("enable_promo_tag_filter")
    end

    def novel_setting_ini_section(novel_setting)
      novel_setting.load_setting_ini["global"]
    rescue StandardError
      {}
    end

    def build_config(config)
      case config
      when Config
        keywords = (config.keywords || DEFAULT_PROMO_KEYWORDS).dup
        regexes = config.regexes || compiled_regexes_for(keywords)
        enabled = config.enabled.nil? ? DEFAULT_ENABLED : config.enabled
        Config.new(enabled: enabled, keywords: keywords, regexes: regexes)
      when Hash
        base_keywords = config[:keywords] ? coerce_keywords(config[:keywords]) : DEFAULT_PROMO_KEYWORDS.dup
        additions = coerce_keywords(config[:additional_keywords])
        keywords = uniq_preserve_order(base_keywords + additions)
        enabled = config.key?(:enabled) ? config[:enabled] : DEFAULT_ENABLED
        Config.new(enabled: enabled, keywords: keywords, regexes: compiled_regexes_for(keywords))
      else
        Config.new(
          enabled: DEFAULT_ENABLED,
          keywords: DEFAULT_PROMO_KEYWORDS.dup,
          regexes: DEFAULT_PROMO_REGEXES
        )
      end
    end

    def compiled_regexes_for(keywords)
      @compiled_regex_cache ||= {}
      cache_key = keywords.join("\u0000")
      @compiled_regex_cache[cache_key] ||= compile_regexes(keywords)
    end

    def compile_regexes(keywords)
      keywords.map do |pattern|
        Regexp.new(pattern)
      rescue RegexpError
        Regexp.new(Regexp.escape(pattern))
      end
    end

    def coerce_keywords(value)
      case value
      when nil
        []
      when Array
        value.flat_map { |item| parse_keywords(item) }
      else
        parse_keywords(value)
      end
    end

    def parse_keywords(raw)
      raw.to_s.split(/[\n,]+/).map { |keyword| normalize_spacing(keyword) }.reject(&:empty?)
    end

    def cleanse(value, promo_regexes: DEFAULT_PROMO_REGEXES)
      original = (value || "").to_s
      text = original.dup
      return [normalize_spacing(original), []] if text.strip.empty?

      tags = []

      text, bracket_tags = strip_bracket_promos(text, promo_regexes: promo_regexes)
      tags.concat(bracket_tags)

      text, at_tags = strip_at_promos(text, promo_regexes: promo_regexes)
      tags.concat(at_tags)

      text, separated_tags = strip_separator_promos(text, promo_regexes: promo_regexes)
      tags.concat(separated_tags)

      normalized = normalize_spacing(text)
      # タイトル全文がプロモタグになることはないので、空になった場合は誤認識として
      # オリジナルのタイトルをそのまま返す（プロモタグなし扱い）
      if normalized.empty?
        return [normalize_spacing(original), []]
      end

      [normalized, uniq_preserve_order(tags)]
    end

    def normalize_spacing(text)
      text.to_s.gsub(WHITESPACE_PATTERN, " ").strip
    end

    def strip_bracket_promos(text, promo_regexes: DEFAULT_PROMO_REGEXES)
      tags = []
      stripped = text.dup

      BRACKET_REGEXES.each do |pattern|
        loop do
          replaced = false
          stripped = stripped.gsub(pattern) do |match|
            inner = Regexp.last_match(1)
            segment_tags = extract_segment_tags(inner, promo_regexes: promo_regexes)
            if segment_tags.empty? || !promotional_content?(inner, promo_regexes: promo_regexes)
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

    def strip_at_promos(text, promo_regexes: DEFAULT_PROMO_REGEXES)
      tags = []
      stripped = text.dup

      loop do
        at_index = stripped.rindex(/[＠@]/)
        break unless at_index

        head = stripped[0...at_index]
        tail = stripped[(at_index + 1)..-1]
        tail = tail&.lstrip
        break unless tail && !tail.empty?

        segment_tags = extract_segment_tags(tail, promo_regexes: promo_regexes)
        break if segment_tags.empty?

        tags.concat(segment_tags)
        stripped = head.rstrip
      end

      [stripped, tags]
    end

    def strip_separator_promos(text, promo_regexes: DEFAULT_PROMO_REGEXES)
      tags = []
      keep_parts = []
      last_kept = false

      segments = split_with_separators(text)
      segments.each do |segment|
        content = segment[:segment]
        next if content.nil? || content.empty?

        segment_tags = extract_segment_tags(content, promo_regexes: promo_regexes)
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

    def extract_segment_tags(segment, promo_regexes: DEFAULT_PROMO_REGEXES)
      trimmed = normalize_spacing(segment)
      return [] if trimmed.empty?

      tokens = split_tokens(trimmed)

      if tokens.size > 1 && tokens.all? { |token| promotional_token?(token, promo_regexes: promo_regexes) }
        return tokens.map { |token| normalize_spacing(token) }
      end

      if tokens.size == 1 && promotional_token?(tokens.first, promo_regexes: promo_regexes)
        return [normalize_spacing(tokens.first)]
      end

      # セグメント全体がプロモーショナルな場合のみタグとして返す
      if promotional_content?(trimmed, promo_regexes: promo_regexes)
        return [trimmed]
      end

      []
    end

    def split_tokens(text)
      text.split(TOKEN_SEPARATOR).map(&:strip).reject(&:empty?)
    end

    def promotional_token?(text, promo_regexes: DEFAULT_PROMO_REGEXES)
      normalized = normalize_for_match(text)
      return false if normalized.empty?

      promo_regexes.any? { |regex| regex.match?(normalized) }
    end

    def promotional_content?(text, promo_regexes: DEFAULT_PROMO_REGEXES)
      normalized = normalize_for_match(text)
      return false if normalized.empty?

      promo_regexes.any? { |regex| regex.match?(normalized) }
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
