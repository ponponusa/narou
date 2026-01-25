# frozen_string_literal: true

require 'spec_helper'
require 'narou/section_cache/cache_entry'

RSpec.describe Narou::SectionCache::CacheEntry do
  describe '#initialize' do
    it 'エントリを正しく初期化すること' do
      converted_section = {
        'chapter' => '第一章',
        'subtitle' => '第一話',
        'element' => {
          'body' => '変換済み本文'
        }
      }

      entry = described_class.new(
        source_hash: 'sha256:abc123',
        converted_section: converted_section
      )

      expect(entry.source_hash).to eq('sha256:abc123')
      expect(entry.converted_section['chapter']).to eq('第一章')
    end
  end

  describe '#valid?' do
    let(:entry) do
      described_class.new(
        source_hash: 'sha256:abc123',
        converted_section: { 'subtitle' => '第一話' }
      )
    end

    context '有効なハッシュの場合' do
      it 'true を返すこと' do
        expect(entry.valid?(current_hash: 'sha256:abc123')).to be true
      end
    end

    context 'ハッシュが一致しない場合' do
      it 'false を返すこと' do
        expect(entry.valid?(current_hash: 'sha256:different')).to be false
      end
    end
  end

  describe '#to_h / .from_h' do
    it 'Hash との相互変換が正しく動作すること' do
      original = described_class.new(
        source_hash: 'sha256:abc123',
        converted_section: {
          'chapter' => '第一章',
          'subtitle' => '第一話',
          'element' => { 'body' => '本文' }
        }
      )

      hash = original.to_h
      restored = described_class.from_h(hash)

      expect(restored.source_hash).to eq(original.source_hash)
      expect(restored.converted_section).to eq(original.converted_section)
    end
  end
end
