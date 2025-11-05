# frozen_string_literal: true

require "narou/promo_tag_extractor"

describe Narou::PromoTagExtractor do
  describe ".extract" do
    it "タイトルと作者の宣伝文言を取り除き、タグとして集約する" do
      result = described_class.extract(
        title: "【書籍化！】サンプル小説【アニメ化！】",
        author: "作者【受賞】"
      )

      expect(result.title).to eq("サンプル小説")
      expect(result.author).to eq("作者")
      expect(result.title_tags).to eq(["書籍化！", "アニメ化！"])
      expect(result.author_tags).to eq(["受賞"])
      expect(result.promo_tags).to eq(["書籍化！", "アニメ化！", "受賞"])
    end

    it "タグのみで構成されるタイトルは元の文字列を維持する" do
      source = "【書籍化！】"
      result = described_class.extract(title: source, author: nil)

      expect(result.title).to eq(source)
      expect(result.title_tags).to eq(["書籍化！"])
      expect(result.promo_tags).to eq(["書籍化！"])
    end

    it "余分な空白を整形する" do
      result = described_class.extract(title: "  【新連載】  テスト　タイトル  ", author: nil)

      expect(result.title).to eq("テスト タイトル")
      expect(result.title_tags).to eq(["新連載"])
      expect(result.promo_tags).to eq(["新連載"])
    end

    it "サンプルの宣伝文言を抽出してタイトルと著者を整形する" do
      title = "【書籍化決定！＋コミカライズ連載中】超弩級チート悪役令嬢の華麗なる復讐譚【完結済】"
      author = "みなと＠書籍版発売中！"
      result = described_class.extract(title: title, author: author)

      expect(result.title).to eq("超弩級チート悪役令嬢の華麗なる復讐譚")
      expect(result.author).to eq("みなと")
      expect(result.title_tags).to eq(["書籍化決定！", "コミカライズ連載中", "完結済"])
      expect(result.author_tags).to eq(["書籍版発売中！"])
      expect(result.promo_tags).to eq(["書籍化決定！", "コミカライズ連載中", "完結済", "書籍版発売中！"])
    end

    it "作品中の強調がプロモタグとして扱われない" do
      title = "ハズレ枠の【状態異常スキル】で最強になった俺がすべてを蹂躙するまで"
      result = described_class.extract(title: title, author: nil)

      expect(result.title).to eq(title)
      expect(result.title_tags).to be_empty
      expect(result.promo_tags).to be_empty
    end

    it "作品中のルビ風表記を保持する" do
      title = "ゲーム世界転生〈ダン活〉～ゲーマーは【ダンジョン就活のススメ】を 〈はじめから〉プレイする～"
      result = described_class.extract(title: title, author: nil)

      expect(result.title).to eq(title)
      expect(result.title_tags).to be_empty
      expect(result.promo_tags).to be_empty
    end

    it "タイトル本文を誤って削除しない" do
      source = "王都の不思議な隠れ家～晴れて離婚した令嬢は…～"
      result = described_class.extract(title: source, author: nil)

      expect(result.title).to eq(source)
      expect(result.promo_tags).to be_empty
    end
  end

  describe ".normalize_entry!" do
    let(:entry) do
      {
        "title" => "【書籍化！】サンプル【アニメ化！】",
        "author" => "著者【受賞】",
        "promo_tags" => ["古いタグ"],
        "promo_tags_title" => ["古いタグ"],
        "promo_tags_author" => ["古いタグ"]
      }
    end

    it "エントリを正規化し promo_tags を更新する" do
      updated = described_class.normalize_entry!(entry)

      expect(updated).to be true
      expect(entry["title"]).to eq("サンプル")
      expect(entry["author"]).to eq("著者")
      expect(entry["promo_tags"]).to eq(["書籍化！", "アニメ化！", "受賞"])
      expect(entry["promo_tags_title"]).to eq(["書籍化！", "アニメ化！"])
      expect(entry["promo_tags_author"]).to eq(["受賞"])
    end

    it "変更がない場合は false を返す" do
      described_class.normalize_entry!(entry)
      updated = described_class.normalize_entry!(entry)

      expect(updated).to be false
    end
  end
end
