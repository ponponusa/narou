# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "lib/narou/parsers/config_manager"

RSpec.describe Narou::Parsers::ConfigManager do
  let(:test_root) { Dir.mktmpdir }
  let(:test_script_dir) { Dir.mktmpdir }

  before do
    # Narou.root_dir と Narou.script_dir をモック
    allow(Narou).to receive(:root_dir).and_return(Pathname.new(test_root))
    allow(Narou).to receive(:script_dir).and_return(Pathname.new(test_script_dir))

    # テスト用のデフォルト設定ファイルを作成
    create_test_default_configs
  end

  after do
    FileUtils.rm_rf(test_root)
    FileUtils.rm_rf(test_script_dir)
  end

  def create_test_default_configs
    # Nokogiri 用デフォルト設定
    nokogiri_dir = File.join(test_script_dir, "preset/parsers")
    FileUtils.mkdir_p(nokogiri_dir)
    File.write(
      File.join(nokogiri_dir, "test.example.com.yaml"),
      YAML.dump({
        "name" => "Test Site",
        "domain" => "test.example.com",
        "body_selectors" => [
          { "selector" => "div.body", "priority" => 10 }
        ]
      })
    )

    # Legacy 用デフォルト設定
    legacy_dir = File.join(test_script_dir, "webnovel")
    FileUtils.mkdir_p(legacy_dir)
    File.write(
      File.join(legacy_dir, "test.example.com.yaml"),
      YAML.dump({
        "name" => "Test Site",
        "domain" => "test.example.com",
        "body_pattern" => "<div>(?<body>.+?)</div>"
      })
    )
  end

  describe ".load_global_config" do
    it "グローバル設定が存在しない場合、デフォルトを作成して返す" do
      config = described_class.load_global_config

      expect(config["default_engine"]).to eq("nokogiri")
      expect(config["novels"]).to eq({})

      # ファイルが作成されているか確認
      path = File.join(test_root, ".narou/parser_config.yaml")
      expect(File.exist?(path)).to be true
    end

    it "既存のグローバル設定を読み込む" do
      # 事前に設定ファイルを作成
      config_path = File.join(test_root, ".narou/parser_config.yaml")
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, YAML.dump({
        "default_engine" => "legacy",
        "novels" => { "n1234ab" => { "engine" => "nokogiri" } }
      }))

      config = described_class.load_global_config

      expect(config["default_engine"]).to eq("legacy")
      expect(config["novels"]["n1234ab"]["engine"]).to eq("nokogiri")
    end
  end

  describe ".load_parser_config" do
    context "Nokogiri エンジンの場合" do
      it "ユーザー設定とデフォルト設定をマージする" do
        # 事前にユーザー設定を作成（一部の設定のみオーバーライド）
        user_path = File.join(test_root, ".narou/parsers/test.example.com.yaml")
        FileUtils.mkdir_p(File.dirname(user_path))
        File.write(user_path, YAML.dump({
          "name" => "Custom Config",
          "last_successful_selectors" => {
            "body_selectors" => {
              "selector" => "div.custom",
              "date" => "2024-01-01"
            }
          }
        }))

        config = described_class.load_parser_config("test.example.com", "nokogiri")

        # ユーザー設定が優先される
        expect(config["name"]).to eq("Custom Config")
        expect(config["last_successful_selectors"]["body_selectors"]["selector"]).to eq("div.custom")

        # デフォルト設定も含まれる（重要！）
        expect(config["domain"]).to eq("test.example.com")
        expect(config["body_selectors"]).to be_a(Array)
        expect(config["body_selectors"].first["selector"]).to eq("div.body")
      end

      it "ユーザー設定が存在しない場合はデフォルト設定のみを返す" do
        config = described_class.load_parser_config("test.example.com", "nokogiri")

        expect(config["name"]).to eq("Test Site")
        expect(config["domain"]).to eq("test.example.com")
        expect(config["body_selectors"]).to be_a(Array)

        # ユーザー設定ファイルは作成されない
        user_path = File.join(test_root, ".narou/parsers/test.example.com.yaml")
        expect(File.exist?(user_path)).to be false
      end
    end

    context "Legacy エンジンの場合" do
      it "webnovel/ からデフォルト設定を読み込む" do
        config = described_class.load_parser_config("test.example.com", "legacy")

        expect(config["name"]).to eq("Test Site")
        expect(config["body_pattern"]).to include("<div>")

        # ユーザー設定ファイルは自動作成されない
        user_path = File.join(test_root, ".narou/legacy_parsers/test.example.com.yaml")
        expect(File.exist?(user_path)).to be false
      end

      it "ユーザー設定とデフォルト設定をマージする" do
        # 事前にユーザー設定を作成（バージョン情報をオーバーライド）
        user_path = File.join(test_root, ".narou/legacy_parsers/test.example.com.yaml")
        FileUtils.mkdir_p(File.dirname(user_path))
        File.write(user_path, YAML.dump({
          "version" => "2.0",
          "body_pattern" => "<div class=\"new\">(?<body>.+?)</div>"
        }))

        config = described_class.load_parser_config("test.example.com", "legacy")

        # ユーザー設定が優先される
        expect(config["version"]).to eq("2.0")
        expect(config["body_pattern"]).to include("class=\"new\"")

        # デフォルト設定も含まれる
        expect(config["name"]).to eq("Test Site")
        expect(config["domain"]).to eq("test.example.com")
      end

      it "ユーザー設定が存在しない場合はデフォルト設定のみを返す" do
        config = described_class.load_parser_config("test.example.com", "legacy")

        expect(config["name"]).to eq("Test Site")
        expect(config["domain"]).to eq("test.example.com")
        expect(config["body_pattern"]).to be_a(String)

        # ユーザー設定ファイルは作成されない
        user_path = File.join(test_root, ".narou/legacy_parsers/test.example.com.yaml")
        expect(File.exist?(user_path)).to be false
      end
    end
  end

  describe ".get_engine_for_novel / .set_engine_for_novel" do
    it "小説ごとのエンジン設定を取得・保存できる" do
      # 初期状態: デフォルトエンジンを返す
      engine = described_class.get_engine_for_novel("n1234ab")
      expect(engine).to eq("nokogiri")

      # エンジンを設定
      described_class.set_engine_for_novel("n1234ab", "legacy")

      # 設定が反映されているか確認
      engine = described_class.get_engine_for_novel("n1234ab")
      expect(engine).to eq("legacy")
    end
  end

  describe ".update_successful_selector" do
    it "成功したセレクタを記録する" do
      # まずデフォルト設定を読み込んでユーザー設定として保存
      config = described_class.load_parser_config("test.example.com", "nokogiri")
      described_class.save_parser_config("test.example.com", config, "nokogiri")

      # セレクタを記録（新しいシグネチャ: domain, selector_key, selector, engine）
      described_class.update_successful_selector(
        "test.example.com",
        "body_selectors",
        "div.new-body",
        "nokogiri"
      )

      # 設定を再読み込みして確認
      config = described_class.load_parser_config("test.example.com", "nokogiri")
      last_successful = config.dig("last_successful_selectors", "body_selectors")

      expect(last_successful["selector"]).to eq("div.new-body")
      expect(last_successful["date"]).to match(/\d{4}-\d{2}-\d{2}/)
    end
  end

  describe ".record_selector_history" do
    before do
      # ユーザー設定ファイルを作成
      config = described_class.load_parser_config("test.example.com", "nokogiri")
      described_class.save_parser_config("test.example.com", config, "nokogiri")
    end

    it "セレクタ履歴を記録する（初回）" do
      described_class.record_selector_history(
        "test.example.com",
        "body_selectors",
        "div.body-v1",
        "nokogiri"
      )

      config = described_class.load_parser_config("test.example.com", "nokogiri")
      history = config.dig("selector_history", "body_selectors")

      expect(history).to be_a(Array)
      expect(history.size).to eq(1)
      expect(history[0]["selector"]).to eq("div.body-v1")
      expect(history[0]["success_count"]).to eq(1)
      expect(history[0]["first_success"]).to match(/\d{4}-\d{2}-\d{2}/)
    end

    it "同じセレクタの成功回数をインクリメントする" do
      # 1回目
      described_class.record_selector_history(
        "test.example.com",
        "body_selectors",
        "div.body-v1",
        "nokogiri"
      )

      # 2回目（同じセレクタ）
      described_class.record_selector_history(
        "test.example.com",
        "body_selectors",
        "div.body-v1",
        "nokogiri"
      )

      config = described_class.load_parser_config("test.example.com", "nokogiri")
      history = config.dig("selector_history", "body_selectors")

      expect(history.size).to eq(1)
      expect(history[0]["success_count"]).to eq(2)
    end

    it "セレクタ変更を検出して記録する" do
      # 古いセレクタを記録
      described_class.record_selector_history(
        "test.example.com",
        "body_selectors",
        "div.old-selector",
        "nokogiri"
      )

      # 新しいセレクタを記録（変更検出）
      described_class.record_selector_history(
        "test.example.com",
        "body_selectors",
        "div.new-selector",
        "nokogiri"
      )

      config = described_class.load_parser_config("test.example.com", "nokogiri")
      history = config.dig("selector_history", "body_selectors")

      expect(history.size).to eq(2)

      new_entry = history.find { |h| h["selector"] == "div.new-selector" }
      expect(new_entry["detected_change"]).to match(/\d{4}-\d{2}-\d{2}/)
      expect(new_entry["replaced_selector"]).to eq("div.old-selector")
    end
  end

  describe ".record_selector_change" do
    it "変更ログに記録する" do
      described_class.record_selector_change(
        "test.example.com",
        "body_selectors",
        "div.old",
        "div.new",
        "nokogiri"
      )

      change_log = described_class.get_change_log("test.example.com")

      expect(change_log).to be_a(Array)
      expect(change_log.size).to eq(1)
      expect(change_log[0]["selector_key"]).to eq("body_selectors")
      expect(change_log[0]["old_selector"]).to eq("div.old")
      expect(change_log[0]["new_selector"]).to eq("div.new")
      expect(change_log[0]["engine"]).to eq("nokogiri")
    end
  end

  describe ".get_selector_history" do
    it "セレクタ履歴を取得する" do
      # まず履歴を記録
      config = described_class.load_parser_config("test.example.com", "nokogiri")
      described_class.save_parser_config("test.example.com", config, "nokogiri")

      described_class.record_selector_history(
        "test.example.com",
        "body_selectors",
        "div.test",
        "nokogiri"
      )

      history = described_class.get_selector_history("test.example.com", "nokogiri")

      expect(history).to be_a(Hash)
      expect(history["body_selectors"]).to be_a(Array)
      expect(history["body_selectors"].size).to eq(1)
    end

    it "ユーザー設定がない場合は空のハッシュを返す" do
      history = described_class.get_selector_history("nonexistent.example.com", "nokogiri")
      expect(history).to eq({})
    end
  end

  describe ".get_change_log" do
    it "全ドメインの変更ログを取得する" do
      described_class.record_selector_change(
        "test1.example.com",
        "body_selectors",
        "div.old1",
        "div.new1",
        "nokogiri"
      )

      described_class.record_selector_change(
        "test2.example.com",
        "body_selectors",
        "div.old2",
        "div.new2",
        "nokogiri"
      )

      change_log = described_class.get_change_log

      expect(change_log).to be_a(Hash)
      expect(change_log.keys).to include("test1.example.com", "test2.example.com")
    end

    it "特定ドメインの変更ログを取得する" do
      described_class.record_selector_change(
        "test.example.com",
        "body_selectors",
        "div.old",
        "div.new",
        "nokogiri"
      )

      change_log = described_class.get_change_log("test.example.com")

      expect(change_log).to be_a(Array)
      expect(change_log.size).to eq(1)
      expect(change_log[0]["old_selector"]).to eq("div.old")
    end
  end

  describe "Legacy parser archive functions" do
    before do
      # アーカイブディレクトリとファイルを作成
      archive_dir = File.join(test_script_dir, "preset/parsers/legacy_archive/test.example.com")
      FileUtils.mkdir_p(archive_dir)

      File.write(
        File.join(archive_dir, "v1.0.yaml"),
        YAML.dump({
          "name" => "Test Site",
          "domain" => "test.example.com",
          "version" => "1.0",
          "body_pattern" => "<div>(?<body>.+?)</div>"
        })
      )

      File.write(
        File.join(archive_dir, "v2.0.yaml"),
        YAML.dump({
          "name" => "Test Site",
          "domain" => "test.example.com",
          "version" => "2.0",
          "body_pattern" => "<div class=\"new\">(?<body>.+?)</div>"
        })
      )
    end

    describe ".get_legacy_version_history" do
      it "利用可能なバージョンのリストを取得する" do
        versions = described_class.get_legacy_version_history("test.example.com")

        expect(versions).to be_a(Array)
        expect(versions).to include("1.0", "2.0")
        expect(versions).to eq(versions.sort)
      end

      it "アーカイブがない場合は空の配列を返す" do
        versions = described_class.get_legacy_version_history("nonexistent.example.com")
        expect(versions).to eq([])
      end
    end

    describe ".load_archived_legacy_parser" do
      it "指定バージョンのアーカイブを読み込む" do
        parser = described_class.load_archived_legacy_parser("test.example.com", "1.0")

        expect(parser).to be_a(Hash)
        expect(parser["version"]).to eq("1.0")
        expect(parser["body_pattern"]).to include("<div>")
      end

      it "存在しないバージョンの場合はnilを返す" do
        parser = described_class.load_archived_legacy_parser("test.example.com", "99.0")
        expect(parser).to be_nil
      end
    end
  end
end
