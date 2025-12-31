# frozen_string_literal: true

require "spec_helper"
require "lib/narou/parsers/parser_selector"
require "lib/novel/sitesetting"

RSpec.describe Narou::Parsers::ParserSelector do
  let(:site_setting) do
    setting = double("SiteSetting")
    allow(setting).to receive(:[]).with("domain").and_return("ncode.syosetu.com")
    setting
  end

  before do
    # Narou.root_dir と Narou.script_dir をモック
    allow(Narou).to receive(:root_dir).and_return(Pathname.new(Dir.mktmpdir))
    allow(Narou).to receive(:script_dir).and_return(Pathname.new(File.expand_path("../../", __dir__)))
  end

  describe ".determine_engine" do
    context "小説IDが指定されていない場合" do
      it "グローバル設定のデフォルトエンジンを返す" do
        # グローバル設定をモック
        allow(Narou::Parsers::ConfigManager).to receive(:load_global_config).and_return({
          "default_engine" => "nokogiri"
        })

        engine = described_class.determine_engine(nil)
        expect(engine).to eq("nokogiri")
      end

      it "グローバル設定がない場合は nokogiri を返す" do
        allow(Narou::Parsers::ConfigManager).to receive(:load_global_config).and_return({})

        engine = described_class.determine_engine(nil)
        expect(engine).to eq("nokogiri")
      end
    end

    context "小説IDが指定されている場合" do
      it "小説ごとのエンジン設定を返す" do
        allow(Narou::Parsers::ConfigManager).to receive(:get_engine_for_novel).with("123").and_return("legacy")

        engine = described_class.determine_engine("123")
        expect(engine).to eq("legacy")
      end
    end
  end

  describe ".create_parser" do
    let(:user_config) { {} }

    context "legacy エンジンの場合" do
      it "LegacyParser を生成する" do
        parser = described_class.create_parser("ncode.syosetu.com", "legacy", site_setting, user_config, nil)
        expect(parser).to be_a(Narou::Parsers::LegacyParser)
      end
    end

    context "nokogiri エンジンの場合" do
      it "NarouParser を生成する" do
        parser = described_class.create_parser("ncode.syosetu.com", "nokogiri", site_setting, user_config, nil)
        expect(parser).to be_a(Narou::Parsers::NarouParser)
      end

      it "kakuyomu.jp の場合は KakuyomuParser を生成する" do
        allow(site_setting).to receive(:[]).with("domain").and_return("kakuyomu.jp")
        parser = described_class.create_parser("kakuyomu.jp", "nokogiri", site_setting, user_config, nil)
        expect(parser).to be_a(Narou::Parsers::KakuyomuParser)
      end

      it "未知のドメインの場合は NokogiriParser を生成する" do
        allow(site_setting).to receive(:[]).with("domain").and_return("unknown-site.com")
        parser = described_class.create_parser("unknown-site.com", "nokogiri", site_setting, user_config, nil)
        expect(parser).to be_a(Narou::Parsers::NokogiriParser)
      end
    end
  end

  describe ".select" do
    before do
      allow(Narou::Parsers::ConfigManager).to receive(:load_global_config).and_return({
        "default_engine" => "nokogiri"
      })
    end

    context "Nokogiriエンジンの場合" do
      let(:parser_config) do
        {
          "name" => "小説家になろう",
          "domain" => "ncode.syosetu.com",
          "body_selectors" => [
            { "selector" => "div.js-novel-text", "priority" => 10 }
          ],
          "introduction_selectors" => [
            { "selector" => "div.p-novel__text--preface", "priority" => 10 }
          ]
        }
      end

      before do
        # Nokogiriエンジンの場合はpreset/parsers/から設定を読み込む
        allow(Narou::Parsers::ConfigManager).to receive(:load_parser_config)
          .with("ncode.syosetu.com", "nokogiri")
          .and_return(parser_config)
      end

      it "適切なパーサーを選択できる" do
        parser = described_class.select(site_setting)
        expect(parser).to be_a(Narou::Parsers::NarouParser)
      end

      it "パーサーの設定に必要なセレクタが含まれている" do
        parser = described_class.select(site_setting)
        expect(parser.config).to include("body_selectors")
        expect(parser.config["body_selectors"]).to be_an(Array)
        expect(parser.config["body_selectors"].first).to include("selector")
      end

      it "preset/parsers/配下の設定ファイルが読み込まれる" do
        parser = described_class.select(site_setting)
        # パーサーの設定がpreset/parsers/の内容を含んでいることを確認
        expect(parser.config["name"]).to eq("小説家になろう")
        expect(parser.config["domain"]).to eq("ncode.syosetu.com")
      end
    end

    context "Legacyエンジンの場合" do
      let(:user_config) { {} }

      before do
        allow(Narou::Parsers::ConfigManager).to receive(:get_engine_for_novel).with("123").and_return("legacy")
        allow(Narou::Parsers::ConfigManager).to receive(:load_parser_config)
          .with("ncode.syosetu.com", "legacy")
          .and_return(user_config)
      end

      it "novel_id を指定した場合は小説ごとのエンジンを使用する" do
        parser = described_class.select(site_setting, novel_id: "123")
        expect(parser).to be_a(Narou::Parsers::LegacyParser)
      end
    end

    it "domain が設定されていない場合はエラーを raise する" do
      allow(site_setting).to receive(:[]).with("domain").and_return(nil)

      expect {
        described_class.select(site_setting)
      }.to raise_error(Narou::Parsers::ParserError, /domain が設定されていません/)
    end
  end

  describe "統合テスト: 実際の設定ファイルを使用" do
    before do
      # 実際のスクリプトディレクトリを使用
      allow(Narou).to receive(:script_dir).and_return(Pathname.new(File.expand_path("../../", __dir__)))
    end

    context "ncode.syosetu.com の場合" do
      let(:real_site_setting) do
        setting = double("SiteSetting")
        allow(setting).to receive(:[]).with("domain").and_return("ncode.syosetu.com")
        setting
      end

      it "preset/parsers/ncode.syosetu.com.yaml から設定を読み込む" do
        # ConfigManagerのモックを解除して実際のファイルを読み込む
        allow(Narou::Parsers::ConfigManager).to receive(:load_global_config).and_call_original
        allow(Narou::Parsers::ConfigManager).to receive(:load_parser_config).and_call_original

        parser = described_class.select(real_site_setting)

        # パーサーが正しく生成される
        expect(parser).to be_a(Narou::Parsers::NarouParser)

        # 設定に必要なセレクタが含まれている
        expect(parser.config["body_selectors"]).to be_a(Array)
        expect(parser.config["body_selectors"].size).to be > 0
        expect(parser.config["body_selectors"].first).to include("selector", "priority")

        # 小説家になろうの設定が正しく読み込まれている
        expect(parser.config["name"]).to eq("小説家になろう")
        expect(parser.config["domain"]).to eq("ncode.syosetu.com")

        # 前書き・後書きのセレクタも含まれている
        expect(parser.config["introduction_selectors"]).to be_a(Array)
        expect(parser.config["postscript_selectors"]).to be_a(Array)
      end
    end

    context "kakuyomu.jp の場合" do
      let(:kakuyomu_site_setting) do
        setting = double("SiteSetting")
        allow(setting).to receive(:[]).with("domain").and_return("kakuyomu.jp")
        setting
      end

      it "preset/parsers/kakuyomu.jp.yaml から設定を読み込む" do
        allow(Narou::Parsers::ConfigManager).to receive(:load_global_config).and_call_original
        allow(Narou::Parsers::ConfigManager).to receive(:load_parser_config).and_call_original

        parser = described_class.select(kakuyomu_site_setting)

        expect(parser).to be_a(Narou::Parsers::KakuyomuParser)
        expect(parser.config["body_selectors"]).to be_a(Array)
        expect(parser.config["name"]).to eq("カクヨム")
      end
    end

    context "レガシーエンジンを使用する場合" do
      # このテストケースはspec/parsers/legacy_parser_spec.rbで詳細にテストされているため
      # ここではパーサーが正しく生成されることのみを確認する
      it "レガシーパーサーが生成される" do
        legacy_setting = double("SiteSetting")
        allow(legacy_setting).to receive(:[]).with("domain").and_return("ncode.syosetu.com")
        allow(legacy_setting).to receive(:yaml).and_return({})

        allow(Narou::Parsers::ConfigManager).to receive(:load_global_config).and_return({
          "default_engine" => "legacy"
        })
        allow(Narou::Parsers::ConfigManager).to receive(:load_parser_config)
          .with("ncode.syosetu.com", "legacy")
          .and_return({})

        parser = described_class.select(legacy_setting)
        expect(parser).to be_a(Narou::Parsers::LegacyParser)
      end
    end
  end
end
