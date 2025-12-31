# frozen_string_literal: true

require "spec_helper"
require "lib/narou/parsers/legacy_parser"
require "lib/novel/sitesetting"

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

  describe "統合テスト: SiteSettingとの連携" do
    context "実際のSiteSettingを使用する場合" do
      let(:html) do
        <<~HTML
          <div id="novel_honbun">これは本文です。</div>
          <div id="novel_p">これは前書きです。</div>
          <div id="novel_a">これは後書きです。</div>
        HTML
      end

      before do
        # multi_matchが正しく呼び出されるかモック
        allow(site_setting).to receive(:multi_match).with(html, "body_pattern", "introduction_pattern", "postscript_pattern") do
          setting_values["body_pattern"] = "これは本文です。"
          setting_values["introduction_pattern"] = "これは前書きです。"
          setting_values["postscript_pattern"] = "これは後書きです。"
          true
        end
      end

      it "SiteSettingのmulti_matchを使用してパースする" do
        result = parser.parse_section(html)

        # multi_matchが呼び出されたことを確認
        expect(site_setting).to have_received(:multi_match).with(html, "body_pattern", "introduction_pattern", "postscript_pattern")

        # パース結果が正しいことを確認
        expect(result["body"]).to eq("これは本文です。")
        expect(result["introduction"]).to eq("これは前書きです。")
        expect(result["postscript"]).to eq("これは後書きです。")
        expect(result["data_type"]).to eq("html")
      end

      it "SiteSettingの値が正しく取得される" do
        result = parser.parse_section(html)

        # SiteSettingから値を取得している
        expect(result["body"]).to eq(site_setting["body_pattern"])
        expect(result["introduction"]).to eq(site_setting["introduction_pattern"])
        expect(result["postscript"]).to eq(site_setting["postscript_pattern"])
      end
    end

    context "multi_matchが失敗する場合" do
      let(:html) { "<div>パターンにマッチしないHTML</div>" }

      before do
        allow(site_setting).to receive(:multi_match).with(html, "body_pattern", "introduction_pattern", "postscript_pattern") do
          setting_values["body_pattern"] = ""
          setting_values["introduction_pattern"] = ""
          setting_values["postscript_pattern"] = ""
          false
        end
      end

      it "本文が空の場合はAllSelectorsFailedErrorを発生させる" do
        expect {
          parser.parse_section(html)
        }.to raise_error(Narou::Parsers::AllSelectorsFailedError)
      end
    end
  end
end
