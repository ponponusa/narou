# frozen_string_literal: true

#
# Copyright 2026 ponponusa. All rights reserved.
#

module Narou
  class SectionCache
    # キャッシュエントリのデータクラス
    #
    # 変換済みセクションとソースのハッシュ値を保持する
    class CacheEntry
      attr_reader :source_hash, :converted_section, :use_dakuten_font

      # CacheEntry を初期化する
      #
      # @param source_hash [String] SHA256 hash of original section
      # @param converted_section [Hash] converted section data
      # @param use_dakuten_font [Boolean] whether dakuten font markers were detected
      def initialize(source_hash:, converted_section:, use_dakuten_font: false)
        @source_hash = source_hash
        @converted_section = converted_section
        @use_dakuten_font = use_dakuten_font
      end

      # キャッシュが有効かどうかを判定する
      #
      # @param current_hash [String] current source hash
      # @return [Boolean]
      def valid?(current_hash:)
        @source_hash == current_hash
      end

      # Hash 形式に変換する
      #
      # @return [Hash]
      def to_h
        {
          'source_hash' => @source_hash,
          'converted_section' => @converted_section,
          'use_dakuten_font' => @use_dakuten_font
        }
      end

      # Hash から CacheEntry を生成する
      #
      # @param hash [Hash]
      # @return [CacheEntry]
      def self.from_h(hash)
        new(
          source_hash: hash['source_hash'],
          converted_section: hash['converted_section'],
          use_dakuten_font: hash['use_dakuten_font'] || false
        )
      end
    end
  end
end
