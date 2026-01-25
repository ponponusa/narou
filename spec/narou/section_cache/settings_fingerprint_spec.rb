# frozen_string_literal: true

require 'spec_helper'
require 'narou/section_cache/settings_fingerprint'

RSpec.describe Narou::SectionCache::SettingsFingerprint do
  describe '.compute' do
    let(:setting) do
      double('NovelSetting',
        enable_yokogaki: false,
        enable_convert_num_to_kanji: true,
        enable_ruby: true,
        enable_strip_decoration_tag: false,
        settings: {
          'enable_yokogaki' => false,
          'enable_convert_num_to_kanji' => true,
          'enable_ruby' => true,
          'enable_strip_decoration_tag' => false
        }
      )
    end

    it '設定値からハッシュを計算すること' do
      hash = described_class.compute(setting)

      expect(hash).to start_with('sha256:')
      expect(hash.length).to eq(71)
    end

    it '同一設定は同一ハッシュを返すこと' do
      hash1 = described_class.compute(setting)
      hash2 = described_class.compute(setting)

      expect(hash1).to eq(hash2)
    end

    it '設定が変わるとハッシュも変わること' do
      hash1 = described_class.compute(setting)

      allow(setting).to receive(:enable_ruby).and_return(false)
      allow(setting).to receive(:settings).and_return(
        setting.settings.merge('enable_ruby' => false)
      )

      hash2 = described_class.compute(setting)

      expect(hash1).not_to eq(hash2)
    end
  end

  describe '.cache_affecting_settings' do
    it 'キャッシュに影響する設定名のリストを返すこと' do
      settings = described_class.cache_affecting_settings

      expect(settings).to include('enable_yokogaki')
      expect(settings).to include('enable_ruby')
      expect(settings).to include('enable_strip_decoration_tag')
    end
  end
end
