# frozen_string_literal: true

require "spec_helper"
require "lib/narou/parsers/parser_error"

RSpec.describe Narou::Parsers do
  describe "パーサーエラークラス" do
    describe Narou::Parsers::ParserError do
      it "基底エラークラスとして動作する" do
        error = Narou::Parsers::ParserError.new("test error")
        expect(error).to be_a(StandardError)
        expect(error.message).to eq("test error")
      end
    end

    describe Narou::Parsers::SelectorNotFoundError do
      it "セレクタ情報を保持する" do
        error = Narou::Parsers::SelectorNotFoundError.new("div.test", "本文")
        expect(error.selector).to eq("div.test")
        expect(error.context).to eq("本文")
        expect(error.message).to include("div.test")
        expect(error.message).to include("本文")
      end
    end

    describe Narou::Parsers::AllSelectorsFailedError do
      it "試行したセレクタリストを保持する" do
        selectors = [
          { "selector" => "div.test1", "priority" => 10 },
          { "selector" => "div.test2", "priority" => 5 }
        ]
        error = Narou::Parsers::AllSelectorsFailedError.new("body_selectors", selectors)

        expect(error.selector_key).to eq("body_selectors")
        expect(error.tried_selectors).to eq(selectors)
        expect(error.message).to include("body_selectors")
        expect(error.message).to include("div.test1")
      end
    end

    describe Narou::Parsers::StructureChangedError do
      it "URL と最後に成功したセレクタを保持する" do
        error = Narou::Parsers::StructureChangedError.new(
          "https://example.com/novel/1",
          "div.old-selector"
        )

        expect(error.url).to eq("https://example.com/novel/1")
        expect(error.last_successful_selector).to eq("div.old-selector")
        expect(error.message).to include("サイト構造が変更")
        expect(error.message).to include("div.old-selector")
      end
    end
  end
end
