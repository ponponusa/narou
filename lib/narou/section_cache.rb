# frozen_string_literal: true

#
# Copyright 2026 ponponusa. All rights reserved.
#

require 'digest'
require 'yaml'
require 'fileutils'
require 'set'
require_relative 'section_cache/cache_entry'
require_relative 'section_cache/chunk_archiver'
require_relative 'section_cache/settings_fingerprint'
require_relative 'section_cache/file_lock'
require 'core/version'

module Narou
  # セクションキャッシュを管理するクラス
  #
  # 変換済みセクションをキャッシュし、ソースの変更がない場合に
  # 再利用することで変換処理を高速化する
  class SectionCache
    META_FILENAME = 'meta.yaml'
    LOCK_FILENAME = '.lock'
    CACHE_VERSION = 2

    attr_reader :hit_count, :miss_count

    # SectionCache を初期化する
    #
    # @param setting [NovelSetting] novel setting object
    def initialize(setting:)
      @setting = setting
      @settings_hash = SettingsFingerprint.compute(setting)
      # 衝突リスク軽減のため16文字に拡張（2^64通り）
      @settings_hash_prefix = @settings_hash.sub('sha256:', '')[0, 16]

      # 設定ハッシュごとにディレクトリを分離（設定変更時の共存）
      @chapters_base_dir = File.join(setting.archive_path, 'chapters')
      @chapters_dir = File.join(@chapters_base_dir, @settings_hash_prefix)

      lock_timeout = (ENV['NAROU_CACHE_LOCK_TIMEOUT'] || '30').to_i
      @archiver = ChunkArchiver.new(base_path: @chapters_dir)
      @lock = FileLock.new(File.join(@chapters_base_dir, LOCK_FILENAME), timeout: lock_timeout)
      @memory_cache = {}
      @dirty_chunks = Set.new
      @hit_count = 0
      @miss_count = 0

      # toc.yaml からインデックス正規化マッピングを構築
      # （カクヨムのような巨大IDを連番に変換するため）
      @index_to_position = build_index_mapping

      # キャッシュの整合性チェックと自動修復
      validate_and_repair_cache

      # 古いキャッシュのクリーンアップ（オプション、ロック保護付き）
      cleanup_old_caches if ENV['NAROU_CACHE_CLEANUP_OLD'] == 'true'
    end

    # chapters ディレクトリのパスを返す
    #
    # @return [String]
    def chapters_dir
      @chapters_dir
    end

    # chapters ベースディレクトリのパスを返す
    #
    # @return [String]
    def chapters_base_dir
      @chapters_base_dir
    end

    # キャッシュの整合性をチェックし、必要に応じて修復する
    #
    # - ディレクトリ名（16文字）とメタのフルハッシュが一致しない場合は現在のキャッシュをクリア
    # - converter_version が変更された場合は全設定ハッシュ配下を削除（ロック付き）
    #
    # @return [void]
    def validate_and_repair_cache
      meta = load_meta
      return unless meta # メタがなければ新規キャッシュ

      # フルハッシュの検証（ディレクトリ名の衝突対策）
      if meta['settings_hash'] != @settings_hash
        warn 'キャッシュのハッシュ不一致を検出、クリアします' if ENV['NAROU_DEBUG']
        clear
        return
      end

      # converter_version の検証（変更時は全設定ハッシュ配下を削除）
      if meta['converter_version'] != Narou::VERSION
        if ENV['NAROU_DEBUG']
          warn "コンバータバージョン変更を検出 (#{meta['converter_version']} -> #{Narou::VERSION})、全キャッシュをクリアします"
        end
        clear_all_settings_caches
        nil
      end
    end

    # 全設定ハッシュ配下のキャッシュを削除する（ロック保護付き）
    #
    # converter_version 変更時に呼び出される。
    # ベースディレクトリ配下の全キャッシュを削除する。
    #
    # @return [void]
    def clear_all_settings_caches
      return unless Dir.exist?(@chapters_base_dir)

      with_lock do
        Dir.glob(File.join(@chapters_base_dir, '*')).each do |entry|
          next unless File.directory?(entry)
          next if File.basename(entry) == LOCK_FILENAME.sub(/^\./, '')

          FileUtils.rm_rf(entry)
        end
      end

      # メモリキャッシュもクリア
      @memory_cache.clear
      @dirty_chunks.clear
    end

    # 古いキャッシュディレクトリを削除する（ロック保護付き）
    #
    # 並行実行中のプロセスがキャッシュを使用している可能性があるため、
    # ベースディレクトリのロックを取得してから削除する
    #
    # @return [void]
    def cleanup_old_caches
      return unless Dir.exist?(@chapters_base_dir)

      with_lock do
        Dir.glob(File.join(@chapters_base_dir, '*')).each do |entry|
          next unless File.directory?(entry)
          next if File.basename(entry) == @settings_hash_prefix
          next if File.basename(entry) == LOCK_FILENAME.sub(/^\./, '')

          # 最終更新から一定時間経過したもののみ削除（安全策）
          mtime = begin
            File.mtime(entry)
          rescue StandardError
            Time.now
          end
          FileUtils.rm_rf(entry) if Time.now - mtime > 3600 # 1時間以上前
        end
      end
    end

    # セクション全体のハッシュを計算する
    #
    # @param section [Hash] original section data
    # @return [String] hash with 'sha256:' prefix
    def compute_source_hash(section)
      # chapter, subtitle, element（data_type を含む）をハッシュ対象にする
      # data_type の変化（html/pre_html/text）で変換結果が変わるため含める
      target = {
        'chapter' => section['chapter'],
        'subtitle' => section['subtitle'],
        'element' => section['element']
      }
      content = YAML.dump(target)
      "sha256:#{Digest::SHA256.hexdigest(content)}"
    end

    # キャッシュからエントリを取得する
    #
    # @param index [Integer, String] section index
    # @param original_section [Hash] original section data
    # @return [Hash, nil] { section:, use_dakuten_font: } or nil if cache miss
    def get(index:, original_section:)
      return nil unless valid_settings?

      normalized = normalize_index(index)
      return nil if normalized < 1 # 不正なindexはキャッシュ無効扱い

      current_hash = compute_source_hash(original_section)
      chunk_range = @archiver.chunk_range_for(normalized)

      # メモリキャッシュを確認
      unless @memory_cache.key?(chunk_range)
        @memory_cache[chunk_range] = @archiver.extract(chunk_range: chunk_range)
      end

      entry = @memory_cache[chunk_range][normalized]
      if entry&.valid?(current_hash: current_hash)
        @hit_count += 1
        return {
          section: deep_dup(entry.converted_section),
          use_dakuten_font: entry.use_dakuten_font
        }
      end

      @miss_count += 1
      nil
    end

    # キャッシュにエントリを保存する
    #
    # @param index [Integer, String] section index
    # @param original_section [Hash] original section data
    # @param converted_section [Hash] converted section data
    # @param use_dakuten_font [Boolean] whether dakuten font markers were detected
    # @return [void]
    def store(index:, original_section:, converted_section:, use_dakuten_font: false)
      normalized = normalize_index(index)
      return if normalized < 1 # 不正なindexは保存しない

      source_hash = compute_source_hash(original_section)
      chunk_range = @archiver.chunk_range_for(normalized)

      entry = CacheEntry.new(
        source_hash: source_hash,
        converted_section: converted_section,
        use_dakuten_font: use_dakuten_font
      )

      @memory_cache[chunk_range] ||= @archiver.extract(chunk_range: chunk_range)
      @memory_cache[chunk_range][normalized] = entry
      @dirty_chunks.add(chunk_range)
    end

    # 設定が有効かどうかを確認する
    #
    # 初期化時に validate_and_repair_cache で整合性チェック済みのため、
    # ここではメタの存在とバージョンのみを確認する
    #
    # @return [Boolean]
    def valid_settings?
      meta = load_meta
      return false unless meta

      # 初期化時に settings_hash と converter_version は検証済み
      # ここでは CACHE_VERSION（データ形式バージョン）のみ確認
      meta['version'] == CACHE_VERSION
    end

    # メタデータを保存する
    #
    # @return [void]
    def save_meta
      FileUtils.mkdir_p(@chapters_dir)
      meta = {
        'version' => CACHE_VERSION,
        'settings_hash' => @settings_hash,
        'converter_version' => Narou::VERSION,
        'created_at' => Time.now.iso8601
      }
      File.write(meta_path, YAML.dump(meta))
    end

    # メモリ上の変更をディスクに書き込む
    #
    # @return [void]
    def flush
      return if @dirty_chunks.empty?

      save_meta unless File.exist?(meta_path)

      @dirty_chunks.each do |chunk_range|
        entries = @memory_cache[chunk_range]
        next if entries.nil? || entries.empty?

        @archiver.archive(chunk_range: chunk_range, entries: entries)
      end
      @dirty_chunks.clear
    end

    # 全てのキャッシュをクリアする
    #
    # @return [void]
    def clear
      @memory_cache.clear
      @dirty_chunks.clear
      @archiver.clear_all
      FileUtils.rm_f(meta_path)
    end

    # プロセス間ロックを取得して処理を実行する
    #
    # @param exclusive [Boolean] true for exclusive lock
    # @yield block to execute with lock
    # @return block result
    def with_lock(exclusive: true, &block)
      @lock.with_lock(exclusive: exclusive, &block)
    end

    # 統計情報を返す
    #
    # @return [Hash]
    def statistics
      {
        hit_count: @hit_count,
        miss_count: @miss_count,
        hit_rate: @hit_count + @miss_count > 0 ?
          (@hit_count.to_f / (@hit_count + @miss_count) * 100).round(1) : 0,
        dirty_chunks: @dirty_chunks.size,
        memory_chunks: @memory_cache.size
      }
    end

    # 並列プロセスからの更新をマージしてフラッシュする
    #
    # ロック取得後に最新のチャンクを再読込し、他プロセスの更新を
    # 上書きせずにマージして書き込む
    #
    # @param pending_stores [Array<Hash>] 保存待ちのエントリ
    #   各要素は { index:, original:, converted:, use_dakuten_font: } の形式
    # @return [void]
    def merge_and_flush(pending_stores)
      return if pending_stores.empty?

      with_lock do
        # ロック取得後に最新のチャンクを再読込
        affected_chunks = pending_stores.map do |item|
          @archiver.chunk_range_for(normalize_index(item[:index]))
        end.uniq

        affected_chunks.each do |chunk_range|
          # 最新のディスク状態を読み込み（他プロセスの更新を取得）
          @memory_cache[chunk_range] = @archiver.extract(chunk_range: chunk_range)
        end

        # 自分の変更をマージ
        pending_stores.each do |item|
          store(
            index: item[:index],
            original_section: item[:original],
            converted_section: item[:converted],
            use_dakuten_font: item[:use_dakuten_font] || false
          )
        end

        # フラッシュ
        flush
      end
    end

    private

    # toc.yaml からインデックス正規化マッピングを構築する
    #
    # カクヨムのような巨大なエピソードID（例: '4852201425154905928'）を
    # 連番（1, 2, 3...）に正規化するためのマッピングを作成する
    #
    # @return [Hash<String, Integer>] 元のindex => 連番位置 のマッピング
    def build_index_mapping
      toc_path = File.join(@setting.archive_path, 'toc.yaml')
      return {} unless File.exist?(toc_path)

      toc = YAML.safe_load_file(toc_path, permitted_classes: [Time])
      subtitles = toc['subtitles'] || []

      mapping = {}
      subtitles.each_with_index do |subtitle, i|
        original_index = subtitle['index']
        next unless original_index

        mapping[original_index.to_s] = i + 1 # 1-based position
      end
      mapping
    rescue StandardError
      {}
    end

    # インデックスを正規化する
    #
    # toc.yaml に基づくマッピングが存在する場合は連番に変換する
    # マッピングがない場合は元の値を整数として返す
    #
    # @param index [Integer, String] section index
    # @return [Integer] normalized index
    def normalize_index(index)
      str_index = index.to_s
      @index_to_position[str_index] || str_index.to_i
    end

    def meta_path
      File.join(@chapters_dir, META_FILENAME)
    end

    def load_meta
      return nil unless File.exist?(meta_path)

      YAML.safe_load_file(meta_path, permitted_classes: [Time])
    rescue StandardError
      nil
    end

    # ディープコピーを作成する
    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      when String
        obj.dup
      else
        obj
      end
    end
  end
end
