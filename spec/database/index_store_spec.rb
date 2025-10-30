# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Database::IndexStore do
  let(:store) { described_class.new }
  let(:toc_url) { "http://example.com/n1234/" }
  let(:title) { "テスト作品" }

  let(:data_hash) do
    {
      1 => { "toc_url" => toc_url, "title" => title },
      2 => { "toc_url" => "http://example.com/n9999/", "title" => "別作品" }
    }
  end

  before do
    Inventory.clear
    base = Narou.local_setting_dir
    if base
      FileUtils.rm_f(base.join("#{described_class::INVENTORY_NAME}.yaml"))
      FileUtils.rm_f(base.join("#{described_class::INVENTORY_NAME}.yaml.backup"))
    end
  end

  it "indexes and looks up entries" do
    store.reconcile(data_hash)
    expect(store.lookup_by_toc_url(toc_url)).to eq(1)
    expect(store.lookup_by_title(title)).to eq(1)
  end

  it "updates indexes on upsert and delete" do
    store.reconcile({})
    store.upsert(3, { "toc_url" => "http://example.com/n3000/", "title" => "三話" })
    expect(store.lookup_by_toc_url("http://example.com/n3000/")).to eq(3)

    store.delete(3, { "toc_url" => "http://example.com/n3000/", "title" => "三話" })
    expect(store.lookup_by_toc_url("http://example.com/n3000/")).to be_nil
  end
end
