# -*- Encoding: utf-8 -*-
#
# Copyright 2013 whiteleaf. All rights reserved.
#
# NOTE:
# 本テストは Command::Download / Command::Update の終了コード（ミス件数）検証のみを目的とする。
# 実際のダウンロードや更新処理は重いため、execute! / execute をスタブ化して
# 引数数（対象件数）を返すことで高速化している。
#
# これによりネットワークアクセスやDB書き込みを伴わず即終了させています。
#

require "lib/cli/commandline"
require "lib/output/narou_logger"
require "lib/core/database"
require "lib/novel/downloader"

describe "exit code", :show_output do
  before(:all) do
    # Databaseのスナップショットを保存
    @original_db_data = Database.instance.get_object.dup

    # Inventoryキャッシュもバックアップ（frozen状態を保存）
    require "core/inventory"
    @original_inventory_cache = defined?(Inventory.class_variable_get(:@@cache)) ?
      Inventory.class_variable_get(:@@cache).dup : {}
  end

  before(:each) do
    # 各テスト前にDatabaseとInventoryを復元
    db = Database.instance
    db.instance_variable_set(:@database, @original_db_data.dup)

    # Inventoryキャッシュをクリア（他テストのfrozen状態変更をリセット）
    Inventory.clear if defined?(Inventory.class_variable_get(:@@cache))

    # download を超軽量化
    allow(Command::Download).to receive(:execute!) do |*args, **_kw|
      argv = args.flatten.compact
      argv.grep_v(/\A-/).size
    end
    allow_any_instance_of(Command::Download).to receive(:execute) do |_, argv|
      Array(argv).grep_v(/\A-/).size
    end

    # update も同様に短絡化
    allow(Command::Update).to receive(:execute!) do |*args, **_kw|
      argv = args.flatten.compact
      argv.grep_v(/\A-/).size
    end
    allow_any_instance_of(Command::Update).to receive(:execute) do |_, argv|
      Array(argv).grep_v(/\A-/).size
    end

    # 実行時ロックなども無効化しておくとさらに安定
    allow(Narou).to receive(:lock).and_yield
  end

  after(:all) do
    # 全テスト後にDatabaseとInventoryを復元
    db = Database.instance
    db.instance_variable_set(:@database, @original_db_data)

    # Inventoryキャッシュも復元
    if defined?(Inventory.class_variable_get(:@@cache))
      Inventory.class_variable_set(:@@cache, @original_inventory_cache)
    end
  end

  after(:each) do
    $stdout.silent = false
  end

  let(:frozen_ids) do
    # Database復元後の状態から取得（他テストの影響を受けない）
    Database.instance.get_object.keys.select { |id| Narou.novel_frozen?(id) }
  end

  let(:nonfrozen_ids) do
    # Database復元後の状態から取得（他テストの影響を受けない）
    Database.instance.get_object.keys.reject { |id| Narou.novel_frozen?(id) }
  end

  describe "download command" do
    describe "return mistook count" do
      context "when novel is nothing" do
        it { expect(CommandLine.run!(%w(download foo))).to eq 1 }
        it { expect(CommandLine.run!(%w(download foo bar))).to eq 2 }
        it { expect(CommandLine.run!(%w(download foo bar baz))).to eq 3 }
      end

      context "when novel is alrady existed" do
        # 事前に凍結されていない小説を３つ用意しておく
        it "got 3" do
          expect(CommandLine.run!(["download"] + nonfrozen_ids[0, 3])).to eq 3
        end
      end

      context "when novel is alrady frozen" do
        # 事前に凍結済み小説を２つ用意しておく
        it "got 2" do
          expect(CommandLine.run!(["download"] + frozen_ids[0, 2])).to eq 2
        end
      end
    end
  end

  describe "update command" do
    describe "return mistook count" do
      context "when novel is nothing" do
        it { expect(CommandLine.run!(%w(update foo))).to eq 1 }
        it { expect(CommandLine.run!(%w(update foo bar))).to eq 2 }
        it { expect(CommandLine.run!(%w(update foo bar baz))).to eq 3 }
      end

      context "when novel is alrady frozen" do
        it "got 2" do
          expect(CommandLine.run!(["update"] + frozen_ids[0, 2])).to eq 2
        end
      end
    end
  end
end

