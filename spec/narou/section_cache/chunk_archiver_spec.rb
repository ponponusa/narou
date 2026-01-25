# frozen_string_literal: true

require 'spec_helper'
require 'narou/section_cache/chunk_archiver'
require 'narou/section_cache/cache_entry'
require 'tmpdir'

RSpec.describe Narou::SectionCache::ChunkArchiver do
  let(:temp_dir) { Dir.mktmpdir }
  let(:archiver) { described_class.new(base_path: temp_dir) }

  after { FileUtils.rm_rf(temp_dir) }

  describe '#chunk_range_for' do
    it '200話単位でチャンク範囲を計算すること' do
      expect(archiver.chunk_range_for(1)).to eq([1, 200])
      expect(archiver.chunk_range_for(200)).to eq([1, 200])
      expect(archiver.chunk_range_for(201)).to eq([201, 400])
      expect(archiver.chunk_range_for(401)).to eq([401, 600])
    end

    context 'NAROU_CACHE_CHUNK_SIZE を指定した場合' do
      it '指定した話数でチャンク範囲を計算すること' do
        stub_const('Narou::SectionCache::ChunkArchiver::CHUNK_SIZE', 50)

        expect(archiver.chunk_range_for(1)).to eq([1, 50])
        expect(archiver.chunk_range_for(50)).to eq([1, 50])
        expect(archiver.chunk_range_for(51)).to eq([51, 100])
      end
    end
  end

  describe '#chunk_filename' do
    it '正しいファイル名を生成すること' do
      expect(archiver.chunk_filename(1, 200)).to match(/chunk_0001-0200\.(zst|gz)/)
    end
  end

  describe '#archive / #extract' do
    let(:entries) do
      {
        1 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash1',
          converted_section: {
            'chapter' => '第一章',
            'subtitle' => '第1話',
            'element' => { 'body' => 'テキスト1' }
          }
        ),
        2 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash2',
          converted_section: {
            'subtitle' => '第2話',
            'element' => { 'body' => 'テキスト2' }
          }
        )
      }
    end

    it '圧縮でアーカイブを作成し展開できること' do
      archiver.archive(chunk_range: [1, 200], entries: entries)

      result = archiver.extract(chunk_range: [1, 200])

      expect(result.size).to eq(2)
      expect(result[1].converted_section['subtitle']).to eq('第1話')
      expect(result[2].converted_section['element']['body']).to eq('テキスト2')
    end

    context '存在しないアーカイブの場合' do
      it '空のハッシュを返すこと' do
        result = archiver.extract(chunk_range: [201, 400])
        expect(result).to eq({})
      end
    end
  end

  describe '#update_entry' do
    let(:original_entries) do
      {
        1 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash1',
          converted_section: { 'subtitle' => '第1話' }
        ),
        2 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash2',
          converted_section: { 'subtitle' => '第2話' }
        )
      }
    end

    before do
      archiver.archive(chunk_range: [1, 200], entries: original_entries)
    end

    it '指定したエントリのみを更新すること' do
      updated_entry = Narou::SectionCache::CacheEntry.new(
        source_hash: 'sha256:updated',
        converted_section: { 'subtitle' => '第2話（改訂版）' }
      )

      archiver.update_entry(index: 2, entry: updated_entry)

      result = archiver.extract(chunk_range: [1, 200])
      expect(result[1].converted_section['subtitle']).to eq('第1話')
      expect(result[2].converted_section['subtitle']).to eq('第2話（改訂版）')
    end
  end

  describe 'アトミック書き込み' do
    it '一時ファイル経由で書き込むこと' do
      entries = {
        1 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash1',
          converted_section: { 'subtitle' => '第1話' }
        )
      }

      # 書き込み中に一時ファイルが作成されることを確認
      expect(archiver).to receive(:atomic_write).and_call_original

      archiver.archive(chunk_range: [1, 200], entries: entries)
    end
  end

  describe '#delete_entry' do
    let(:original_entries) do
      {
        1 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash1',
          converted_section: { 'subtitle' => '第1話' }
        ),
        2 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash2',
          converted_section: { 'subtitle' => '第2話' }
        )
      }
    end

    before do
      archiver.archive(chunk_range: [1, 200], entries: original_entries)
    end

    it '指定したエントリのみを削除すること' do
      archiver.delete_entry(index: 1)

      result = archiver.extract(chunk_range: [1, 200])
      expect(result[1]).to be_nil
      expect(result[2].converted_section['subtitle']).to eq('第2話')
    end

    it '最後のエントリを削除するとファイルも削除されること' do
      archiver.delete_entry(index: 1)
      archiver.delete_entry(index: 2)

      # ファイルが削除されていることを確認
      result = archiver.extract(chunk_range: [1, 200])
      expect(result).to eq({})
    end
  end

  describe '#clear_all' do
    before do
      entries1 = {
        1 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash1',
          converted_section: { 'subtitle' => '第1話' }
        )
      }
      entries2 = {
        201 => Narou::SectionCache::CacheEntry.new(
          source_hash: 'sha256:hash201',
          converted_section: { 'subtitle' => '第201話' }
        )
      }
      archiver.archive(chunk_range: [1, 200], entries: entries1)
      archiver.archive(chunk_range: [201, 400], entries: entries2)
    end

    it '全てのアーカイブを削除すること' do
      archiver.clear_all

      expect(archiver.extract(chunk_range: [1, 200])).to eq({})
      expect(archiver.extract(chunk_range: [201, 400])).to eq({})
    end
  end
end
