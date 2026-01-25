# frozen_string_literal: true

require 'spec_helper'
require 'narou/section_cache/file_lock'
require 'tmpdir'

RSpec.describe Narou::SectionCache::FileLock do
  let(:temp_dir) { Dir.mktmpdir }
  let(:lock_file) { File.join(temp_dir, 'test.lock') }

  after { FileUtils.rm_rf(temp_dir) }

  describe '#initialize' do
    it 'デフォルトのタイムアウトは30秒であること' do
      lock = described_class.new(lock_file)
      expect(lock.instance_variable_get(:@timeout)).to eq(30)
    end

    it 'タイムアウトをカスタマイズできること' do
      lock = described_class.new(lock_file, timeout: 60)
      expect(lock.instance_variable_get(:@timeout)).to eq(60)
    end
  end

  describe '#with_lock' do
    it '排他ロックを取得してブロックを実行すること' do
      lock = described_class.new(lock_file)
      executed = false

      lock.with_lock do
        executed = true
        expect(File.exist?(lock_file)).to be true
      end

      expect(executed).to be true
    end

    it '共有ロックを取得できること' do
      lock = described_class.new(lock_file)
      executed = false

      lock.with_lock(exclusive: false) do
        executed = true
      end

      expect(executed).to be true
    end

    it 'ブロックの戻り値を返すこと' do
      lock = described_class.new(lock_file)

      result = lock.with_lock do
        'success'
      end

      expect(result).to eq('success')
    end

    it 'タイムアウト時に例外を発生すること' do
      lock1 = described_class.new(lock_file)
      lock2 = described_class.new(lock_file, timeout: 0.1)

      lock1.with_lock do
        expect {
          lock2.with_lock { }
        }.to raise_error(Narou::SectionCache::FileLock::TimeoutError)
      end
    end

    it '共有ロック同士は同時取得できること' do
      lock1 = described_class.new(lock_file, timeout: 1)
      lock2 = described_class.new(lock_file, timeout: 1)

      executed = false
      lock1.with_lock(exclusive: false) do
        lock2.with_lock(exclusive: false) do
          executed = true
        end
      end

      expect(executed).to be true
    end
  end
end
