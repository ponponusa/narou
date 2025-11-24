# frozen_string_literal: true

require "lib/narou/promo_tag_extractor"

describe Narou::PromoTagExtractor do
  describe ".extract" do
    let(:enabled_config) { described_class.build_config(enabled: true) }

    it "タイトルと作者の宣伝文言を取り除き、タグとして集約する" do
      result = described_class.extract(
        title: "【書籍化！】サンプル小説【アニメ化！】",
        author: "作者【受賞】",
        config: enabled_config
      )

      expect(result.title).to eq("サンプル小説")
      expect(result.author).to eq("作者")
      expect(result.title_tags).to eq(["書籍化！", "アニメ化！"])
      expect(result.author_tags).to eq(["受賞"])
      expect(result.promo_tags).to eq(["書籍化！", "アニメ化！", "受賞"])
    end

    it "タグのみで構成されるタイトルは元の文字列を維持する（プロモタグなし扱い）" do
      source = "【書籍化！】"
      result = described_class.extract(title: source, author: nil, config: enabled_config)

      # タイトル全文がプロモタグになる場合は誤認識として、オリジナルをそのまま返す
      expect(result.title).to eq(source)
      expect(result.title_tags).to eq([])
      expect(result.promo_tags).to eq([])
    end

    it "余分な空白を整形する" do
      result = described_class.extract(
        title: "  【新連載】  テスト　タイトル  ",
        author: nil,
        config: enabled_config
      )

      expect(result.title).to eq("テスト タイトル")
      expect(result.title_tags).to eq(["新連載"])
      expect(result.promo_tags).to eq(["新連載"])
    end

    it "サンプルの宣伝文言を抽出してタイトルと著者を整形する" do
      title = "【書籍化決定！＋コミカライズ連載中】超弩級チート悪役令嬢の華麗なる復讐譚【完結済】"
      author = "みなと＠書籍版発売中！"
      result = described_class.extract(title: title, author: author, config: enabled_config)

      expect(result.title).to eq("超弩級チート悪役令嬢の華麗なる復讐譚")
      expect(result.author).to eq("みなと")
      expect(result.title_tags).to eq(["書籍化決定！", "コミカライズ連載中", "完結済"])
      expect(result.author_tags).to eq(["書籍版発売中！"])
      expect(result.promo_tags).to eq(["書籍化決定！", "コミカライズ連載中", "完結済", "書籍版発売中！"])
    end

    it "作品中の強調がプロモタグとして扱われない" do
      title = "ハズレ枠の【状態異常スキル】で最強になった俺がすべてを蹂躙するまで"
      result = described_class.extract(title: title, author: nil, config: enabled_config)

      expect(result.title).to eq(title)
      expect(result.title_tags).to be_empty
      expect(result.promo_tags).to be_empty
    end

    it "作品中のルビ風表記を保持する" do
      title = "ゲーム世界転生〈ダン活〉～ゲーマーは【ダンジョン就活のススメ】を 〈はじめから〉プレイする～"
      result = described_class.extract(title: title, author: nil, config: enabled_config)

      expect(result.title).to eq(title)
      expect(result.title_tags).to be_empty
      expect(result.promo_tags).to be_empty
    end

    it "タイトル本文を誤って削除しない" do
      source = "王都の不思議な隠れ家～晴れて離婚した令嬢は…～"
      result = described_class.extract(title: source, author: nil, config: enabled_config)

      expect(result.title).to eq(source)
      expect(result.promo_tags).to be_empty
    end

    it "設定を有効にしない限り宣伝文言を保持する" do
      result = described_class.extract(
        title: "【書籍化！】サンプル小説",
        author: "作者【受賞】"
      )

      expect(result.title).to eq("【書籍化！】サンプル小説")
      expect(result.author).to eq("作者【受賞】")
      expect(result.promo_tags).to be_empty
      expect(result.title_tags).to be_empty
      expect(result.author_tags).to be_empty
    end

    it "設定で追加したキーワードを除去する" do
      config = described_class.build_config(
        keywords: described_class::DEFAULT_PROMO_KEYWORDS + ["限定特典"],
        enabled: true
      )

      result = described_class.extract(
        title: "【限定特典】サンプルタイトル",
        author: nil,
        config: config
      )

      expect(result.title).to eq("サンプルタイトル")
      expect(result.title_tags).to eq(["限定特典"])
      expect(result.promo_tags).to eq(["限定特典"])
    end

    context "プロモタグを含まない長いタイトルの処理" do
      it "プロモタグが含まれていない場合は元のタイトルを保持する（ケース1）" do
        title = "底辺配信者だけどダンジョンで人気探索者を助けたら、なぜかやべぇ女として大バズりしてみんなから怖がられている"
        result = described_class.extract(title: title, author: nil, config: enabled_config)

        expect(result.title).to eq(title)
        expect(result.title_tags).to be_empty
        expect(result.promo_tags).to be_empty
      end

      it "プロモタグが含まれていない場合は元のタイトルを保持する（ケース2）" do
        title = "バーチャル美少年ダンジョンチューバー ～男が希少すぎる世界で、男装女子と言い張ってダンジョン配信します～"
        result = described_class.extract(title: title, author: nil, config: enabled_config)

        expect(result.title).to eq(title)
        expect(result.title_tags).to be_empty
        expect(result.promo_tags).to be_empty
      end

      it "プロモタグが含まれていない場合は元のタイトルを保持する（ケース3）" do
        title = "ユニークスキルのせいでハーレムを作る事が確定した哀れな中年冒険者が挑む現代ダンジョン配信物"
        result = described_class.extract(title: title, author: nil, config: enabled_config)

        expect(result.title).to eq(title)
        expect(result.title_tags).to be_empty
        expect(result.promo_tags).to be_empty
      end

      it "【連載版】タグを正しく抽出する" do
        title = "【連載版】実家住みおじさん、私道のど真ん中に湧いた邪魔なダンジョンと配信者どもをヘッドショットでぶっ潰す"
        result = described_class.extract(title: title, author: nil, config: enabled_config)

        expect(result.title).to eq("実家住みおじさん、私道のど真ん中に湧いた邪魔なダンジョンと配信者どもをヘッドショットでぶっ潰す")
        expect(result.title_tags).to eq(["連載版"])
        expect(result.promo_tags).to eq(["連載版"])
      end

      it "複数のプロモタグを正しく抽出し、本文を保持する" do
        title = "レアモンスター？それ、ただの害虫ですよ　～知らぬ間にダンジョン化した自宅での日常生活が配信されてバズったんですが～【コミック三巻発売！】"
        result = described_class.extract(title: title, author: nil, config: enabled_config)

        expect(result.title).to eq("レアモンスター？それ、ただの害虫ですよ ～知らぬ間にダンジョン化した自宅での日常生活が配信されてバズったんですが～")
        expect(result.title_tags).to eq(["コミック三巻発売！"])
        expect(result.promo_tags).to eq(["コミック三巻発売！"])
      end
    end
  end

  describe ".normalize_entry!" do
    let(:entry) do
      {
        "title" => "【書籍化！】サンプル【アニメ化！】",
        "author" => "著者【受賞】",
        "title_raw_latest" => "【書籍化！】サンプル【アニメ化！】",
        "title_original" => nil,
        "author_original" => nil,
        "promo_tags" => ["古いタグ"],
        "promo_tags_title" => ["古いタグ"],
        "promo_tags_author" => ["古いタグ"]
      }
    end
    let(:enabled_config) { described_class.build_config(enabled: true) }

    it "エントリを正規化し promo_tags を更新する" do
      updated = described_class.normalize_entry!(entry, config: enabled_config)

      expect(updated).to be true
      expect(entry["title"]).to eq("サンプル")
      expect(entry["author"]).to eq("著者")
      expect(entry["promo_tags"]).to eq(["書籍化！", "アニメ化！", "受賞"])
      expect(entry["promo_tags_title"]).to eq(["書籍化！", "アニメ化！"])
      expect(entry["promo_tags_author"]).to eq(["受賞"])
      expect(entry["title_original"]).to eq("【書籍化！】サンプル【アニメ化！】")
      expect(entry["author_original"]).to eq("著者【受賞】")
      expect(entry["title_raw_latest"]).to eq("【書籍化！】サンプル【アニメ化！】")
    end

    it "変更がない場合は false を返す" do
      described_class.normalize_entry!(entry, config: enabled_config)
      updated = described_class.normalize_entry!(entry, config: enabled_config)

      expect(updated).to be false
    end

    it "除去を無効化した場合は既存の値を保持する" do
      original = Marshal.load(Marshal.dump(entry))

      updated = described_class.normalize_entry!(entry, config: described_class.build_config(enabled: false))

      expect(updated).to be true
      expect(entry["title"]).to eq(original["title"])
      expect(entry["author"]).to eq(original["author"])
      expect(entry["promo_tags"]).to eq([])
      expect(entry["promo_tags_title"]).to eq([])
      expect(entry["promo_tags_author"]).to eq([])
      expect(entry["title_original"]).to eq(original["title_raw_latest"])
      expect(entry["title_raw_latest"]).to eq(original["title_raw_latest"])
    end

    it "オリジナルのタイトルから再適用できる" do
      entry = {
        "title" => "サンプル",
        "author" => "著者",
        "title_original" => "【書籍化！】サンプル【アニメ化！】",
        "author_original" => "著者【受賞】"
      }

      described_class.normalize_entry!(entry, config: enabled_config)

      expect(entry["title"]).to eq("サンプル")
      expect(entry["author"]).to eq("著者")
      expect(entry["promo_tags"]).to eq(["書籍化！", "アニメ化！", "受賞"])

      described_class.normalize_entry!(entry, config: described_class.build_config(enabled: false))

      expect(entry["title"]).to eq("【書籍化！】サンプル【アニメ化！】")
      expect(entry["author"]).to eq("著者【受賞】")
      expect(entry["promo_tags"]).to be_empty
      expect(entry["promo_tags_title"]).to be_empty
      expect(entry["promo_tags_author"]).to be_empty
    end
  end
end
