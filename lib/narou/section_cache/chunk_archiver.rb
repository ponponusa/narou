# frozen_string_literal: true

#
# Copyright 2026 ponponusa. All rights reserved.
#

require 'yaml'
require 'fileutils'
require 'zlib'
require_relative 'cache_entry'

# zstd-ruby はオプショナル（Windows対応）
begin
  require 'zstd-ruby'
  ZSTD_AVAILABLE = true
rescue LoadError
  ZSTD_AVAILABLE = false
end

module Narou
  class SectionCache
    # チャンクを圧縮でアーカイブ化するクラス
    #
    # 200話単位でチャンクを作成し、zstd（優先）またはgzip（フォールバック）で圧縮する
    class ChunkArchiver
      # チャンクサイズ（0以下や非数値は200にフォールバック）
      CHUNK_SIZE = begin
        val = (ENV['NAROU_CACHE_CHUNK_SIZE'] || '200').to_i
        val > 0 ? val : 200
      end
      ARCHIVE_VERSION = 1

      # ChunkArchiver を初期化する
      #
      # @param base_path [String] base directory path for archives
      def initialize(base_path:)
        @base_path = base_path
        @use_zstd = ZSTD_AVAILABLE
        FileUtils.mkdir_p(@base_path)
      end

      # インデックスからチャンク範囲を計算する
      #
      # @param index [Integer, String] section index
      # @return [Array<Integer>] [start_index, end_index]
      def chunk_range_for(index)
        index = index.to_i
        chunk_num = ((index - 1) / CHUNK_SIZE)
        start_idx = chunk_num * CHUNK_SIZE + 1
        end_idx = start_idx + CHUNK_SIZE - 1
        [start_idx, end_idx]
      end

      # チャンクのファイル名を生成する
      #
      # @param start_idx [Integer] start index
      # @param end_idx [Integer] end index
      # @return [String] filename
      def chunk_filename(start_idx, end_idx)
        ext = @use_zstd ? 'zst' : 'gz'
        format('chunk_%04d-%04d.%s', start_idx, end_idx, ext)
      end

      # エントリをアーカイブに保存する
      #
      # @param chunk_range [Array<Integer>] [start_index, end_index]
      # @param entries [Hash<Integer, CacheEntry>] entries to archive
      # @return [void]
      def archive(chunk_range:, entries:)
        data = {
          'version' => ARCHIVE_VERSION,
          'chunk_range' => chunk_range,
          'created_at' => Time.now.iso8601,
          'entries' => entries.transform_values(&:to_h)
        }

        yaml_content = YAML.dump(data)
        compressed = compress(yaml_content)

        filename = chunk_filename(chunk_range[0], chunk_range[1])
        atomic_write(File.join(@base_path, filename), compressed)
      end

      # アーカイブからエントリを展開する
      #
      # @param chunk_range [Array<Integer>] [start_index, end_index]
      # @return [Hash<Integer, CacheEntry>]
      def extract(chunk_range:)
        filepath = find_archive_file(chunk_range)
        return {} unless filepath && File.exist?(filepath)

        compressed = File.binread(filepath)
        yaml_content = decompress(compressed, filepath)
        data = YAML.safe_load(yaml_content, permitted_classes: [Time])

        data['entries'].transform_keys(&:to_i).transform_values do |hash|
          CacheEntry.from_h(hash)
        end
      rescue StandardError => e
        warn "キャッシュ展開エラー: #{e.message}"
        {}
      end

      # 単一のエントリを更新する
      #
      # @param index [Integer, String] section index
      # @param entry [CacheEntry] entry to update
      # @return [void]
      def update_entry(index:, entry:)
        index = index.to_i
        return if index < 1 # 不正なindexは無視

        chunk_range = chunk_range_for(index)
        existing = extract(chunk_range: chunk_range)
        existing[index] = entry
        archive(chunk_range: chunk_range, entries: existing)
      end

      # 単一のエントリを削除する
      #
      # @param index [Integer, String] section index
      # @return [void]
      def delete_entry(index:)
        index = index.to_i
        return if index < 1 # 不正なindexは無視

        chunk_range = chunk_range_for(index)
        existing = extract(chunk_range: chunk_range)
        existing.delete(index)

        if existing.empty?
          filepath = find_archive_file(chunk_range)
          FileUtils.rm_f(filepath) if filepath
        else
          archive(chunk_range: chunk_range, entries: existing)
        end
      end

      # 全てのアーカイブを削除する
      #
      # @return [void]
      def clear_all
        Dir.glob(File.join(@base_path, 'chunk_*.*')).each do |file|
          FileUtils.rm_f(file)
        end
      end

      private

      # アーカイブファイルのパスを探す（zst/gz両対応）
      def find_archive_file(chunk_range)
        base = format('chunk_%04d-%04d', chunk_range[0], chunk_range[1])
        # zstd が利用可能な場合のみ .zst を探索対象にする
        extensions = @use_zstd ? %w[zst gz] : %w[gz]
        extensions.each do |ext|
          path = File.join(@base_path, "#{base}.#{ext}")
          return path if File.exist?(path)
        end
        nil
      end

      # データを圧縮する
      def compress(data)
        if @use_zstd
          Zstd.compress(data, 3)
        else
          Zlib::Deflate.deflate(data, Zlib::BEST_COMPRESSION)
        end
      end

      # データを展開する
      def decompress(data, filepath)
        if filepath.end_with?('.zst')
          Zstd.decompress(data)
        else
          Zlib::Inflate.inflate(data)
        end
      end

      # アトミック書き込み（一時ファイル経由）
      def atomic_write(filepath, data)
        temp_path = "#{filepath}.tmp.#{Process.pid}"
        begin
          File.binwrite(temp_path, data)
          File.rename(temp_path, filepath)
        rescue StandardError
          FileUtils.rm_f(temp_path)
          raise
        end
      end
    end
  end
end
