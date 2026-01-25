# frozen_string_literal: true

#
# Copyright 2026 ponponusa. All rights reserved.
#

require_relative "../spec_helper"
require "lib/novel/novelconverter"
require "tmpdir"
require "ostruct"

# use_dakuten_font フラグのキャッシュヒット時の集約テスト
#
# このテストは、セクションキャッシュからのキャッシュヒット時に
# use_dakuten_font フラグが正しく集約されることを検証する。
#
# 並列処理はデフォルト無効だが、将来の廃棄に備えた動作保証として残す。
RSpec.describe "NovelConverter::TextProcessor use_dakuten_font aggregation" do
  # テスト用の軽量コンバータークラス
  class FakeConverter
    attr_accessor :use_dakuten_font, :current_index, :data_type, :output_text_dir

    def initialize(*)
      @use_dakuten_font = false
    end

    def convert_multi(batch_inputs)
      # 濁点フォントマーカー '゛' が含まれていたらフラグを立てる
      if batch_inputs.values.any? { |(text, _)| text.to_s.include?("゛") }
        @use_dakuten_font = true
      end
      batch_inputs.transform_values { |(text, _)| text }
    end

    def cleanup; end
  end

  # テスト用のキャッシュクラス
  class FakeCache
    attr_reader :stored_entries

    def initialize(results)
      @results = results
      @stored_entries = []
    end

    def get(index:, original_section:)
      @results[index]
    end

    def store(index:, original_section:, converted_section:, use_dakuten_font: false)
      @stored_entries << {
        index: index,
        original_section: original_section,
        converted_section: converted_section,
        use_dakuten_font: use_dakuten_font
      }
    end

    def merge_and_flush(pending_stores)
      pending_stores.each do |item|
        store(
          index: item[:index],
          original_section: item[:original],
          converted_section: item[:converted],
          use_dakuten_font: item[:use_dakuten_font]
        )
      end
    end

    def flush; end

    def statistics
      { hit_count: 0, miss_count: 0, hit_rate: 0 }
    end
  end

  # テスト用のNovelConverterサブクラス
  class TestNovelConverter < NovelConverter
    attr_writer :test_cache, :test_sections
    attr_accessor :use_dakuten_font

    def load_converter(_archive_path)
      FakeConverter
    end

    def initialize_section_cache
      @test_cache
    end

    def initialize_section_cache_for_parallel(_setting)
      @test_cache
    end

    def load_novel_section(subinfo, _dir)
      @test_sections[subinfo["index"]]
    end

    # トリガーを無効化
    def trigger(*); end
  end

  let(:temp_dir) { Dir.mktmpdir }
  let(:setting) do
    # NovelSettingの最小限のモック（OpenStructを使用）
    OpenStruct.new(
      id: "n1234",
      archive_path: temp_dir,
      novel_author: "",
      author: "test_author",
      novel_title: "",
      title: "test_title",
      output_filename: "",
      enable_inspect: false,
      enable_strip_decoration_tag: false,
      enable_illust: false,
      enable_transform_date: false,
      enable_transform_fraction: false,
      enable_ruby: false,
      enable_convert_horizontal_ellipsis: false,
      enable_auto_indent: false,
      enable_dakuten_font: true, # 濁点フォント機能を有効化（テスト対象）
      replace_pattern: []
    )
  end

  let(:subtitles) { [{ "index" => 1, "subtitle" => "第1話" }] }
  let(:original_section) do
    { "subtitle" => "第1話", "element" => { "body" => "本文" }, "chapter" => "" }
  end
  let(:cached_section) do
    { "subtitle" => "第1話（変換済み）", "element" => { "body" => "変換済み本文" }, "chapter" => "" }
  end

  before do
    allow(Downloader).to receive(:get_novel_section_save_dir).and_return(Pathname.new(temp_dir))
    allow(SiteSetting).to receive(:find).and_return(nil)
    # Parallel.map_with_index をシーケンシャルに実行
    allow(Parallel).to receive(:map_with_index) do |enum, _opts, &block|
      enum.each_with_index.map { |item, idx| block.call(item, idx) }
    end
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "sequential processing (subtitles_to_sections_sequential)" do
    it "sets use_dakuten_font to true when cache hit has dakuten flag" do
      cache = FakeCache.new(1 => { section: cached_section, use_dakuten_font: true })

      converter = TestNovelConverter.new(setting, nil, false, nil, stream_io: StringIO.new)
      converter.test_cache = cache
      converter.test_sections = { 1 => original_section }

      html = HTML.new

      sections = converter.subtitles_to_sections_sequential(subtitles, html)

      expect(sections).to eq([cached_section])
      expect(converter.use_dakuten_font).to be(true)
    end

    it "keeps use_dakuten_font false when cache hit has no dakuten flag" do
      cache = FakeCache.new(1 => { section: cached_section, use_dakuten_font: false })

      converter = TestNovelConverter.new(setting, nil, false, nil, stream_io: StringIO.new)
      converter.test_cache = cache
      converter.test_sections = { 1 => original_section }

      html = HTML.new

      sections = converter.subtitles_to_sections_sequential(subtitles, html)

      expect(sections).to eq([cached_section])
      expect(converter.use_dakuten_font).to be(false)
    end
  end

  describe "parallel thread-based processing (subtitles_to_sections_parallel)" do
    it "aggregates use_dakuten_font from cache hits via thread_dakuten_flags" do
      cache = FakeCache.new(1 => { section: cached_section, use_dakuten_font: true })

      converter = TestNovelConverter.new(setting, nil, false, nil, stream_io: StringIO.new)
      converter.test_cache = cache
      converter.test_sections = { 1 => original_section }

      html = HTML.new

      # use_processes: false でスレッドベースの並列処理をテスト
      sections = converter.subtitles_to_sections_parallel(subtitles, html, use_processes: false)

      expect(sections).to eq([cached_section])
      expect(converter.use_dakuten_font).to be(true)
    end

    it "keeps use_dakuten_font false when no dakuten in cache hits" do
      cache = FakeCache.new(1 => { section: cached_section, use_dakuten_font: false })

      converter = TestNovelConverter.new(setting, nil, false, nil, stream_io: StringIO.new)
      converter.test_cache = cache
      converter.test_sections = { 1 => original_section }

      html = HTML.new

      sections = converter.subtitles_to_sections_parallel(subtitles, html, use_processes: false)

      expect(sections).to eq([cached_section])
      expect(converter.use_dakuten_font).to be(false)
    end
  end

  describe "parallel chunked processing (subtitles_to_sections_parallel_chunked)" do
    it "aggregates use_dakuten_font from cache hits via chunk_dakuten_from_cache" do
      cache = FakeCache.new(1 => { section: cached_section, use_dakuten_font: true })

      converter = TestNovelConverter.new(setting, nil, false, nil, stream_io: StringIO.new)
      converter.test_cache = cache
      converter.test_sections = { 1 => original_section }

      html = HTML.new
      section_save_dir = Pathname.new(temp_dir)

      # チャンクベースの並列処理をテスト
      sections = converter.subtitles_to_sections_parallel_chunked(
        subtitles, html, section_save_dir, nil, 1
      )

      expect(sections).to eq([cached_section])
      expect(converter.use_dakuten_font).to be(true)
    end

    it "keeps use_dakuten_font false when no dakuten in cache hits" do
      cache = FakeCache.new(1 => { section: cached_section, use_dakuten_font: false })

      converter = TestNovelConverter.new(setting, nil, false, nil, stream_io: StringIO.new)
      converter.test_cache = cache
      converter.test_sections = { 1 => original_section }

      html = HTML.new
      section_save_dir = Pathname.new(temp_dir)

      sections = converter.subtitles_to_sections_parallel_chunked(
        subtitles, html, section_save_dir, nil, 1
      )

      expect(sections).to eq([cached_section])
      expect(converter.use_dakuten_font).to be(false)
    end
  end

  describe "per-section dakuten detection (cache store)" do
    it "stores correct per-section dakuten flag on cache miss" do
      # キャッシュミスの場合、変換処理が走る
      cache = FakeCache.new({}) # 空のキャッシュ（全てミス）

      # 濁点マーカーを含むセクション
      section_with_dakuten = {
        "subtitle" => "第1話",
        "element" => { "body" => "濁点゛含む本文" },
        "chapter" => ""
      }

      converter = TestNovelConverter.new(setting, nil, false, nil, stream_io: StringIO.new)
      converter.test_cache = cache
      converter.test_sections = { 1 => section_with_dakuten }

      html = HTML.new

      converter.subtitles_to_sections_sequential(subtitles, html)

      # キャッシュに保存されたエントリを確認
      expect(cache.stored_entries.size).to eq(1)
      expect(cache.stored_entries.first[:use_dakuten_font]).to be(true)
    end

    it "stores false for sections without dakuten markers" do
      cache = FakeCache.new({})

      # 濁点マーカーを含まないセクション
      section_without_dakuten = {
        "subtitle" => "第1話",
        "element" => { "body" => "通常の本文" },
        "chapter" => ""
      }

      converter = TestNovelConverter.new(setting, nil, false, nil, stream_io: StringIO.new)
      converter.test_cache = cache
      converter.test_sections = { 1 => section_without_dakuten }

      html = HTML.new

      converter.subtitles_to_sections_sequential(subtitles, html)

      expect(cache.stored_entries.size).to eq(1)
      expect(cache.stored_entries.first[:use_dakuten_font]).to be(false)
    end
  end
end
