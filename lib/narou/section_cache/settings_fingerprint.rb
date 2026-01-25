# frozen_string_literal: true

#
# Copyright 2026 ponponusa. All rights reserved.
#

require 'digest'
require 'yaml'

module Narou
  class SectionCache
    # 設定値のフィンガープリント（ハッシュ）を計算するクラス
    #
    # キャッシュに影響する設定値を抽出し、それらのハッシュを計算する。
    # 設定が変更された場合にキャッシュを無効化するために使用する。
    module SettingsFingerprint
      # キャッシュに影響する設定名のリスト
      CACHE_AFFECTING_SETTINGS = %w[
        enable_yokogaki
        enable_convert_num_to_kanji
        enable_kanji_num_with_units
        kanji_num_with_units_lower_digit_zero
        enable_alphabet_force_zenkaku
        disable_alphabet_word_to_zenkaku
        enable_half_indent_bracket
        enable_auto_indent
        enable_force_indent
        enable_auto_join_in_brackets
        enable_auto_join_line
        enable_ruby
        enable_illust
        enable_transform_fraction
        enable_transform_date
        date_format
        enable_convert_horizontal_ellipsis
        enable_convert_page_break
        to_page_break_threshold
        enable_dakuten_font
        enable_ruby_youon_to_big
        enable_pack_blank_line
        enable_kana_ni_to_kanji_ni
        enable_insert_word_separator
        enable_insert_char_separator
        enable_strip_decoration_tag
        enable_prolonged_sound_mark_to_dash
        enable_erase_introduction
        enable_erase_postscript
        author_comment_style
      ].freeze

      class << self
        # 設定値からハッシュを計算する
        #
        # @param setting [NovelSetting] novel setting object
        # @return [String] hash with 'sha256:' prefix
        def compute(setting)
          values = extract_values(setting)
          content = YAML.dump(values)
          "sha256:#{Digest::SHA256.hexdigest(content)}"
        end

        # キャッシュに影響する設定名のリストを返す
        #
        # @return [Array<String>]
        def cache_affecting_settings
          CACHE_AFFECTING_SETTINGS
        end

        private

        # 設定から関連する値を抽出する
        #
        # @param setting [NovelSetting]
        # @return [Hash]
        def extract_values(setting)
          result = {}
          CACHE_AFFECTING_SETTINGS.each do |name|
            result[name] = setting.settings[name] if setting.settings.key?(name)
          end
          # replace.txt パターンも含める
          result['replace_pattern'] = setting.replace_pattern if setting.respond_to?(:replace_pattern)
          result
        end
      end
    end
  end
end
