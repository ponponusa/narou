# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "narou/parsers/config_manager"

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
      it "デフォルト設定を読み込む" do
        config = described_class.load_parser_config("test.example.com", "nokogiri")
        
        expect(config["name"]).to eq("Test Site")
        expect(config["body_selectors"]).to be_a(Array)
        
        # ユーザー設定ファイルは自動作成されない
        user_path = File.join(test_root, ".narou/parsers/test.example.com.yaml")
        expect(File.exist?(user_path)).to be false
      end

      it "既存のユーザー設定を読み込む" do
        # 事前にユーザー設定を作成
        user_path = File.join(test_root, ".narou/parsers/test.example.com.yaml")
        FileUtils.mkdir_p(File.dirname(user_path))
        File.write(user_path, YAML.dump({
          "name" => "Custom Config",
          "body_selectors" => [
            { "selector" => "div.custom", "priority" => 20 }
          ]
        }))

        config = described_class.load_parser_config("test.example.com", "nokogiri")
        
        expect(config["name"]).to eq("Custom Config")
        expect(config["body_selectors"].first["selector"]).to eq("div.custom")
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
end
