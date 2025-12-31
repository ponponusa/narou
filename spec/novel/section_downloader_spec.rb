# frozen_string_literal: true

require "spec_helper"
require "lib/novel/downloader"

RSpec.describe Downloader::SectionDownloader do
  let(:downloader) do
    # テスト用のダウンローダーインスタンスを作成
    # 実際のテストでは適切にモックする必要があります
    double("Downloader").tap do |d|
      d.extend(Downloader::SectionDownloader)
      allow(d).to receive(:instance_variable_get).with(:@setting).and_return(setting)
      allow(d).to receive(:instance_variable_get).with(:@parser).and_return(parser)
      allow(d).to receive(:instance_variable_set)
    end
  end

  let(:setting) do
    {
      "domain" => "test.example.com",
      "version" => "2.0"
    }
  end

  let(:parser) { nil }

  describe "#extract_used_selectors" do
    let(:mock_parser) do
      double("Parser").tap do |p|
        allow(p).to receive(:user_config).and_return({
          "last_successful_selectors" => {
            "body_selectors" => { "selector" => "div.body" },
            "introduction_selectors" => { "selector" => "div.intro" },
            "postscript_selectors" => { "selector" => "div.post" }
          }
        })
      end
    end

    it "パーサーから使用されたセレクタを抽出する" do
      # SectionDownloaderモジュールのインスタンスメソッドとして呼び出し
      instance = Object.new
      instance.extend(Downloader::SectionDownloader)

      selectors = instance.send(:extract_used_selectors, mock_parser)

      expect(selectors).to be_a(Hash)
      expect(selectors["body_selectors"]).to eq("div.body")
      expect(selectors["introduction_selectors"]).to eq("div.intro")
      expect(selectors["postscript_selectors"]).to eq("div.post")
    end

    it "セレクタがない場合は空のハッシュを返す" do
      empty_parser = double("Parser")
      allow(empty_parser).to receive(:user_config).and_return({})

      instance = Object.new
      instance.extend(Downloader::SectionDownloader)

      selectors = instance.send(:extract_used_selectors, empty_parser)

      expect(selectors).to eq({})
    end
  end

  describe "#extract_used_patterns" do
    let(:mock_setting) do
      {
        "body_pattern" => "<div>(?<body>.+?)</div>",
        "introduction_pattern" => "<div class=\"intro\">(?<introduction>.+?)</div>",
        "postscript_pattern" => "<div class=\"post\">(?<postscript>.+?)</div>"
      }
    end

    it "設定から使用された正規表現パターンを抽出する" do
      instance = Object.new
      instance.extend(Downloader::SectionDownloader)

      patterns = instance.send(:extract_used_patterns, mock_setting)

      expect(patterns).to be_a(Hash)
      expect(patterns["body_pattern"]).to include("<div>")
      expect(patterns["introduction_pattern"]).to include("intro")
      expect(patterns["postscript_pattern"]).to include("post")
    end

    it "パターンがない場合は空のハッシュを返す" do
      empty_setting = {}

      instance = Object.new
      instance.extend(Downloader::SectionDownloader)

      patterns = instance.send(:extract_used_patterns, empty_setting)

      expect(patterns).to eq({})
    end
  end

  describe "parser_info recording" do
    it "Nokogiriパーサー使用時にparser_infoを記録する" do
      # このテストは実際のa_section_downloadメソッドの動作を確認する統合テスト
      # モックの複雑さから、実際の動作確認は手動テストまたはE2Eテストで行うことを推奨
      skip "Integration test - requires full Downloader setup"
    end

    it "Legacyパーサー使用時にparser_infoを記録する" do
      # このテストは実際のa_section_downloadメソッドの動作を確認する統合テスト
      skip "Integration test - requires full Downloader setup"
    end
  end
end
