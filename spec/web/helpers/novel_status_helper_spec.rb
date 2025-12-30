# frozen_string_literal: true

require "lib/web/helpers/novel_status_helper"
require "lib/core/narou"
require "lib/core/inventory"

describe NovelStatusHelper do
  describe ".generate_novel_status" do
    let(:novel_id) { 1 }
    let(:base_data) do
      {
        "id" => novel_id,
        "title" => "テスト小説",
        "author" => "テスト作者",
        "tags" => [],
        "suspend" => false
      }
    end

    before do
      # Narou.novel_frozen? のスタブを設定
      allow(Narou).to receive(:novel_frozen?).and_return(false)
    end

    context "状態がない場合" do
      it "連載中を返す" do
        status = described_class.generate_novel_status(novel_id, base_data)
        expect(status).to eq("連載中")
      end
    end

    context "凍結されている場合" do
      before do
        allow(Narou).to receive(:novel_frozen?).with(novel_id).and_return(true)
      end

      it "凍結を返す" do
        status = described_class.generate_novel_status(novel_id, base_data)
        expect(status).to eq("凍結")
      end
    end

    context "完結している場合" do
      let(:data_with_end_tag) do
        base_data.merge("tags" => ["end"])
      end

      it "完結を返す" do
        status = described_class.generate_novel_status(novel_id, data_with_end_tag)
        expect(status).to eq("完結")
      end
    end

    context "削除されている場合" do
      let(:data_with_404_tag) do
        base_data.merge("tags" => ["404"])
      end

      it "削除を返す" do
        status = described_class.generate_novel_status(novel_id, data_with_404_tag)
        expect(status).to eq("削除")
      end
    end

    context "中断されている場合" do
      let(:data_with_suspend) do
        base_data.merge("suspend" => true)
      end

      it "中断を返す" do
        status = described_class.generate_novel_status(novel_id, data_with_suspend)
        expect(status).to eq("中断")
      end
    end

    context "複数の状態がある場合" do
      before do
        allow(Narou).to receive(:novel_frozen?).with(novel_id).and_return(true)
      end

      let(:data_with_multiple_states) do
        base_data.merge("tags" => ["end", "404"], "suspend" => true)
      end

      it "カンマ区切りで複数の状態を返す" do
        status = described_class.generate_novel_status(novel_id, data_with_multiple_states)
        expect(status).to eq("凍結, 完結, 削除, 中断")
      end
    end

    context "tagsがnilの場合" do
      let(:data_without_tags) do
        base_data.tap { |d| d.delete("tags") }
      end

      it "エラーにならず連載中を返す" do
        status = described_class.generate_novel_status(novel_id, data_without_tags)
        expect(status).to eq("連載中")
      end
    end

    context "凍結と完結の組み合わせ" do
      before do
        allow(Narou).to receive(:novel_frozen?).with(novel_id).and_return(true)
      end

      let(:data_frozen_and_end) do
        base_data.merge("tags" => ["end"])
      end

      it "凍結, 完結を返す" do
        status = described_class.generate_novel_status(novel_id, data_frozen_and_end)
        expect(status).to eq("凍結, 完結")
      end
    end

    context "完結と削除の組み合わせ" do
      let(:data_end_and_404) do
        base_data.merge("tags" => ["end", "404"])
      end

      it "完結, 削除を返す" do
        status = described_class.generate_novel_status(novel_id, data_end_and_404)
        expect(status).to eq("完結, 削除")
      end
    end

    context "関係ないタグが含まれる場合" do
      let(:data_with_other_tags) do
        base_data.merge("tags" => ["ファンタジー", "end", "長編"])
      end

      it "完結のみを状態として認識する" do
        status = described_class.generate_novel_status(novel_id, data_with_other_tags)
        expect(status).to eq("完結")
      end
    end
  end
end
