# frozen_string_literal: true

require 'spec_helper'
require 'narou/section_cache'
require 'tmpdir'

RSpec.describe Narou::SectionCache do
  let(:temp_dir) { Dir.mktmpdir }
  let(:archive_path) { temp_dir }
  let(:setting) do
    double('NovelSetting',
      archive_path: archive_path,
      enable_yokogaki: false,
      enable_ruby: true,
      enable_strip_decoration_tag: false,
      settings: {
        'enable_yokogaki' => false,
        'enable_ruby' => true,
        'enable_strip_decoration_tag' => false
      }
    )
  end
  let(:cache) { described_class.new(setting: setting) }

  after { FileUtils.rm_rf(temp_dir) }

  describe '#chapters_dir' do
    it '設定ハッシュ配下の chapters ディレクトリのパスを返すこと' do
      expected = File.join(archive_path, 'chapters', cache.instance_variable_get(:@settings_hash_prefix))
      expect(cache.chapters_dir).to eq(expected)
    end
  end

  describe '#chapters_base_dir' do
    it 'chapters ベースディレクトリのパスを返すこと' do
      expect(cache.chapters_base_dir).to eq(File.join(archive_path, 'chapters'))
    end
  end

  describe '#compute_source_hash' do
    it 'セクション全体のハッシュを計算すること' do
      section = {
        'chapter' => '第一章',
        'subtitle' => '第一話',
        'element' => {
          'data_type' => 'html',
          'body' => '<p>本文</p>'
        }
      }

      hash = cache.compute_source_hash(section)

      expect(hash).to start_with('sha256:')
    end

    it '同一セクションは同一ハッシュを返すこと' do
      section = { 'subtitle' => '第一話', 'element' => { 'body' => '本文' } }

      expect(cache.compute_source_hash(section)).to eq(cache.compute_source_hash(section))
    end

    it 'data_type が変わるとハッシュも変わること' do
      section_html = {
        'subtitle' => '第一話',
        'element' => { 'data_type' => 'html', 'body' => '本文' }
      }
      section_text = {
        'subtitle' => '第一話',
        'element' => { 'data_type' => 'text', 'body' => '本文' }
      }

      expect(cache.compute_source_hash(section_html)).not_to eq(
        cache.compute_source_hash(section_text)
      )
    end
  end

  describe '#get' do
    let(:section) do
      {
        'index' => 1,
        'chapter' => '第一章',
        'subtitle' => '第一話',
        'element' => { 'data_type' => 'html', 'body' => '<p>本文</p>' }
      }
    end

    let(:converted_section) do
      {
        'chapter' => '第一章',
        'subtitle' => '第一話',
        'element' => { 'body' => '変換済み本文' }
      }
    end

    context 'キャッシュが存在する場合' do
      before do
        cache.store(index: 1, original_section: section, converted_section: converted_section)
        cache.flush
      end

      it 'キャッシュエントリを返すこと' do
        result = cache.get(index: 1, original_section: section)

        expect(result).not_to be_nil
        expect(result[:section]['element']['body']).to eq('変換済み本文')
        expect(result[:use_dakuten_font]).to eq(false)
      end
    end

    context 'ソースが変更されている場合' do
      before do
        cache.store(index: 1, original_section: section, converted_section: converted_section)
        cache.flush
      end

      it 'nil を返すこと' do
        modified_section = section.merge('element' => { 'body' => '新しい本文' })
        result = cache.get(index: 1, original_section: modified_section)

        expect(result).to be_nil
      end
    end

    context 'キャッシュが存在しない場合' do
      it 'nil を返すこと' do
        result = cache.get(index: 999, original_section: section)

        expect(result).to be_nil
      end
    end
  end

  describe '#store' do
    let(:section) do
      {
        'index' => 1,
        'subtitle' => '第一話',
        'element' => { 'body' => '本文' }
      }
    end

    let(:converted) do
      {
        'subtitle' => '第一話',
        'element' => { 'body' => '変換済み' }
      }
    end

    it 'キャッシュエントリを保存すること' do
      cache.store(index: 1, original_section: section, converted_section: converted)
      cache.flush

      result = cache.get(index: 1, original_section: section)
      expect(result).not_to be_nil
    end
  end

  describe '#valid_settings?' do
    context '設定が変更されていない場合' do
      before do
        cache.save_meta
      end

      it 'true を返すこと' do
        expect(cache.valid_settings?).to be true
      end
    end

    context '設定が変更された場合' do
      before do
        cache.save_meta
        allow(setting).to receive(:enable_ruby).and_return(false)
        allow(setting).to receive(:settings).and_return(
          setting.settings.merge('enable_ruby' => false)
        )
      end

      it '新しい設定用のディレクトリが作成されること' do
        new_cache = described_class.new(setting: setting)

        # 新しいキャッシュは別ディレクトリを使用
        expect(new_cache.chapters_dir).not_to eq(cache.chapters_dir)
      end

      it '新しいキャッシュでは valid_settings? が false を返すこと（meta.yaml がないため）' do
        new_cache = described_class.new(setting: setting)
        expect(new_cache.valid_settings?).to be false
      end
    end

    context 'converter_version が変更された場合' do
      it '初期化時にキャッシュがクリアされること' do
        # 古いバージョンのメタを作成
        FileUtils.mkdir_p(cache.chapters_dir)
        meta = {
          'version' => 1,
          'settings_hash' => cache.instance_variable_get(:@settings_hash),
          'converter_version' => '1.0.0', # 古いバージョン
          'created_at' => Time.now.iso8601
        }
        File.write(File.join(cache.chapters_dir, 'meta.yaml'), YAML.dump(meta))

        # ダミーのチャンクファイルを作成
        File.write(File.join(cache.chapters_dir, 'chunk_0001-0200.zst'), 'dummy')

        # 新しいキャッシュインスタンスを作成（validate_and_repair_cache が実行される）
        new_cache = described_class.new(setting: setting)

        # キャッシュがクリアされていること
        expect(File.exist?(File.join(new_cache.chapters_dir, 'chunk_0001-0200.zst'))).to be false
      end

      it '全設定ハッシュ配下のキャッシュが削除されること' do
        # 現在のキャッシュを作成
        FileUtils.mkdir_p(cache.chapters_dir)
        meta = {
          'version' => 1,
          'settings_hash' => cache.instance_variable_get(:@settings_hash),
          'converter_version' => '1.0.0', # 古いバージョン
          'created_at' => Time.now.iso8601
        }
        File.write(File.join(cache.chapters_dir, 'meta.yaml'), YAML.dump(meta))
        File.write(File.join(cache.chapters_dir, 'chunk_0001-0200.zst'), 'dummy')

        # 別の設定ハッシュのキャッシュも作成
        other_cache_dir = File.join(cache.chapters_base_dir, 'othersettings1234')
        FileUtils.mkdir_p(other_cache_dir)
        File.write(File.join(other_cache_dir, 'chunk_0001-0200.zst'), 'other_dummy')

        # 新しいキャッシュインスタンスを作成（clear_all_settings_caches が実行される）
        described_class.new(setting: setting)

        # 両方のキャッシュが削除されていること
        expect(Dir.exist?(other_cache_dir)).to be false
      end
    end
  end

  describe '#validate_and_repair_cache' do
    context 'フルハッシュがディレクトリと一致しない場合' do
      it 'キャッシュがクリアされること' do
        # 異なるハッシュでメタを作成（衝突シミュレーション）
        FileUtils.mkdir_p(cache.chapters_dir)
        meta = {
          'version' => 1,
          'settings_hash' => 'sha256:different_hash_value',
          'converter_version' => Narou::VERSION,
          'created_at' => Time.now.iso8601
        }
        File.write(File.join(cache.chapters_dir, 'meta.yaml'), YAML.dump(meta))
        File.write(File.join(cache.chapters_dir, 'chunk_0001-0200.zst'), 'dummy')

        # 新しいインスタンスで検証
        new_cache = described_class.new(setting: setting)

        expect(File.exist?(File.join(new_cache.chapters_dir, 'chunk_0001-0200.zst'))).to be false
      end
    end
  end

  describe '#merge_and_flush' do
    it '複数のエントリをマージして保存すること' do
      pending_stores = [
        {
          index: 1,
          original: { 'subtitle' => '第1話', 'element' => { 'body' => '本文1' } },
          converted: { 'subtitle' => '第1話', 'element' => { 'body' => '変換済み1' } },
          use_dakuten_font: false
        },
        {
          index: 2,
          original: { 'subtitle' => '第2話', 'element' => { 'body' => '本文2' } },
          converted: { 'subtitle' => '第2話', 'element' => { 'body' => '変換済み2' } },
          use_dakuten_font: true
        }
      ]

      cache.merge_and_flush(pending_stores)

      # 新しいインスタンスで確認
      new_cache = described_class.new(setting: setting)
      result1 = new_cache.get(
        index: 1,
        original_section: { 'subtitle' => '第1話', 'element' => { 'body' => '本文1' } }
      )
      expect(result1[:section]['element']['body']).to eq('変換済み1')
      expect(result1[:use_dakuten_font]).to eq(false)

      result2 = new_cache.get(
        index: 2,
        original_section: { 'subtitle' => '第2話', 'element' => { 'body' => '本文2' } }
      )
      expect(result2[:use_dakuten_font]).to eq(true)
    end
  end

  describe '#cleanup_old_caches' do
    let(:old_dir) { File.join(archive_path, 'chapters', 'oldcache') }

    before do
      # 古いキャッシュディレクトリを作成（1時間以上前の更新時刻を設定）
      FileUtils.mkdir_p(old_dir)
      File.write(File.join(old_dir, 'meta.yaml'), 'test')
      # 2時間前に更新されたことにする
      FileUtils.touch(old_dir, mtime: Time.now - 7200)
    end

    it '1時間以上前の古いキャッシュを削除すること' do
      cache.cleanup_old_caches

      expect(Dir.exist?(old_dir)).to be false
    end

    it '1時間以内の古いキャッシュは削除しないこと' do
      # 30分前に更新されたことにする
      FileUtils.touch(old_dir, mtime: Time.now - 1800)

      cache.cleanup_old_caches

      expect(Dir.exist?(old_dir)).to be true
    end

    it 'ロックを取得して削除すること' do
      expect(cache).to receive(:with_lock).and_call_original

      cache.cleanup_old_caches
    end
  end

  describe '#clear' do
    before do
      (1..600).each do |i|
        section = { 'index' => i, 'subtitle' => "第#{i}話", 'element' => { 'body' => "本文#{i}" } }
        converted = { 'subtitle' => "第#{i}話", 'element' => { 'body' => "変換済み#{i}" } }
        cache.store(index: i, original_section: section, converted_section: converted)
      end
      cache.flush
    end

    it '全てのキャッシュをクリアすること' do
      cache.clear

      section = { 'index' => 1, 'subtitle' => '第1話', 'element' => { 'body' => '本文1' } }
      expect(cache.get(index: 1, original_section: section)).to be_nil
    end
  end

  describe '#with_lock' do
    it 'プロセス間ロックを取得して処理を実行すること' do
      executed = false

      cache.with_lock do
        executed = true
      end

      expect(executed).to be true
    end
  end

  describe '#statistics' do
    it '統計情報を返すこと' do
      stats = cache.statistics

      expect(stats).to include(:hit_count, :miss_count, :hit_rate)
    end

    it 'ヒット率を正しく計算すること' do
      section = { 'subtitle' => '第1話', 'element' => { 'body' => '本文' } }
      converted = { 'subtitle' => '第1話', 'element' => { 'body' => '変換済み' } }

      cache.store(index: 1, original_section: section, converted_section: converted)
      cache.flush

      # 1回ミス、1回ヒット
      cache.get(index: 999, original_section: section)
      cache.get(index: 1, original_section: section)

      stats = cache.statistics
      expect(stats[:hit_count]).to eq(1)
      expect(stats[:miss_count]).to eq(1)
      expect(stats[:hit_rate]).to eq(50.0)
    end
  end
end
