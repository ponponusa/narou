# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/narou/parsers/parser_selector"
require "novel/sitesetting"

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
    let(:user_config) { {} }

    before do
      allow(Narou::Parsers::ConfigManager).to receive(:load_parser_config).and_return(user_config)
      allow(Narou::Parsers::ConfigManager).to receive(:load_global_config).and_return({
        "default_engine" => "nokogiri"
      })
    end

    it "適切なパーサーを選択できる" do
      parser = described_class.select(site_setting)
      expect(parser).to be_a(Narou::Parsers::NarouParser)
    end

    it "domain が設定されていない場合はエラーを raise する" do
      allow(site_setting).to receive(:[]).with("domain").and_return(nil)
      
      expect {
        described_class.select(site_setting)
      }.to raise_error(Narou::Parsers::ParserError, /domain が設定されていません/)
    end

    it "novel_id を指定した場合は小説ごとのエンジンを使用する" do
      allow(Narou::Parsers::ConfigManager).to receive(:get_engine_for_novel).with("123").and_return("legacy")
      
      parser = described_class.select(site_setting, novel_id: "123")
      expect(parser).to be_a(Narou::Parsers::LegacyParser)
    end
  end
end
