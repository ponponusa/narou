# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/narou/parsers/legacy_parser"
require "novel/sitesetting"

RSpec.describe Narou::Parsers::LegacyParser do
  let(:setting_values) { {} }
  let(:site_setting) do
    # モックの SiteSetting オブジェクトを作成
    setting = double("SiteSetting")
    allow(setting).to receive(:[]) do |key|
      setting_values[key]
    end
    allow(setting).to receive(:[]=) do |key, value|
      setting_values[key] = value
    end
    allow(setting).to receive(:multi_match)
    setting_values["toc_url"] = "https://example.com/n1234ab/"
    setting_values["data_type"] = "html"
    setting
  end

  let(:parser) { described_class.new(site_setting, {}, logger: Logger.new($stdout)) }

  describe "#parse_section" do
    context "正常にパースできる場合" do
      let(:html) do
        <<~HTML
          <div id="novel_honbun">本文です</div>
          <div id="novel_p">前書きです</div>
          <div id="novel_a">後書きです</div>
        HTML
      end

      before do
        allow(site_setting).to receive(:multi_match).with(html, "body_pattern", "introduction_pattern", "postscript_pattern")
        setting_values["body_pattern"] = "本文です"
        setting_values["introduction_pattern"] = "前書きです"
        setting_values["postscript_pattern"] = "後書きです"
      end

      it "本文・前書き・後書きを抽出できる" do
        result = parser.parse_section(html)

        expect(result["body"]).to eq("本文です")
        expect(result["introduction"]).to eq("前書きです")
        expect(result["postscript"]).to eq("後書きです")
        expect(result["data_type"]).to eq("html")
      end
    end

    context "本文が見つからない場合" do
      let(:html) { "<div>何もない</div>" }

      before do
        allow(site_setting).to receive(:multi_match).with(html, "body_pattern", "introduction_pattern", "postscript_pattern")
        setting_values["body_pattern"] = ""
        setting_values["introduction_pattern"] = ""
        setting_values["postscript_pattern"] = ""
      end

      it "AllSelectorsFailedError を raise する" do
        expect {
          parser.parse_section(html, { "href" => "/n1234ab/1/" })
        }.to raise_error(Narou::Parsers::AllSelectorsFailedError, /全てのセレクタで要素が見つかりませんでした/)
      end
    end
  end

  describe "#parse_novel_info" do
    context "正常にパースできる場合" do
      let(:html) do
        <<~HTML
          <title>テスト小説</title>
          <div class="author">テスト作者</div>
          <div class="story">これはテストです</div>
        HTML
      end

      before do
        allow(site_setting).to receive(:multi_match).with(html, "title", "author", "story")
        setting_values["title"] = "テスト小説"
        setting_values["author"] = "テスト作者"
        setting_values["story"] = "これはテストです"
      end

      it "小説情報を抽出できる" do
        result = parser.parse_novel_info(html)

        expect(result["title"]).to eq("テスト小説")
        expect(result["author"]).to eq("テスト作者")
        expect(result["story"]).to eq("これはテストです")
      end
    end

    context "タイトルが見つからない場合" do
      let(:html) { "<div>何もない</div>" }

      before do
        allow(site_setting).to receive(:multi_match).with(html, "title", "author", "story")
        setting_values["title"] = ""
        setting_values["author"] = ""
        setting_values["story"] = ""
      end

      it "ParserError を raise する" do
        expect {
          parser.parse_novel_info(html)
        }.to raise_error(Narou::Parsers::ParserError, /小説情報の抽出に失敗/)
      end
    end
  end

  describe "#detect_structure_change?" do
    it "常に false を返す" do
      expect(parser.detect_structure_change?("<html></html>")).to eq(false)
    end
  end

  describe "#update_successful_selector" do
    it "何も行わない" do
      expect {
        parser.update_successful_selector("body_selectors", "div.test")
      }.not_to raise_error
    end
  end
end
