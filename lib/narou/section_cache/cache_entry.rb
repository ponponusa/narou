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
      attr_reader :source_hash, :converted_section

      # CacheEntry を初期化する
      #
      # @param source_hash [String] SHA256 hash of original section
      # @param converted_section [Hash] converted section data
      def initialize(source_hash:, converted_section:)
        @source_hash = source_hash
        @converted_section = converted_section
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
          'converted_section' => @converted_section
        }
      end

      # Hash から CacheEntry を生成する
      #
      # @param hash [Hash]
      # @return [CacheEntry]
      def self.from_h(hash)
        new(
          source_hash: hash['source_hash'],
          converted_section: hash['converted_section']
        )
      end
    end
  end
end
