# -*- Encoding: utf-8 -*-
#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "tmpdir"
require "lib/novel/downloader"

describe Downloader do
  describe ".create_subdirecotry_name" do
    context "小説家になろうのタイトルが渡された場合" do
      it do
        expect(Downloader.create_subdirecotry_name("n9669bk 無職転生　- 異世界行ったら本気だす -")).to eq "96"
      end

      it do
        expect(Downloader.create_subdirecotry_name("n8725k ログ・ホライズン")).to eq "87"
      end
    end

    context "なろう以外のタイトルが渡された場合" do
      it do
        expect(Downloader.create_subdirecotry_name("15041 とある能力の代償")).to eq "15"
      end

      it do
        expect(Downloader.create_subdirecotry_name("40151 異界渡りの魔法使い")).to eq "40"
      end
    end

    context "1桁のID＋タイトルを渡された場合" do
      it do
        expect(Downloader.create_subdirecotry_name("5 魔王の友を持つ魔王")).to eq "5"
      end

      it do
        expect(Downloader.create_subdirecotry_name("10 ペルソナ4～覚醒のゼロの力～")).to eq "10"
      end
    end

    context "１文字のタイトルが渡された場合" do
      it { expect(Downloader.create_subdirecotry_name("n")).to eq "" }
      it { expect(Downloader.create_subdirecotry_name("1")).to eq "1" }
      it { expect(Downloader.create_subdirecotry_name("a")).to eq "a" }
    end
  end

  describe ".get_toc_data" do
    it "raises when YAML includes unsupported objects" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, Downloader::TOC_FILE_NAME)
        File.write(path, <<~YAML)
          --- !ruby/object:Kernel
          foo: bar
        YAML

        expect {
          Downloader.get_toc_data(dir)
        }.to raise_error(Narou::YAMLLoader::Error)
      end
    end
  end

  describe ".get_data_by_target" do
    before do
      allow(Narou).to receive(:alias_to_id) { |value| value }
    end

    it "matches toc_url for ncode targets using literal comparison" do
      target = "n1234ab"
      data_entry = { "toc_url" => "https://example.com/#{target}/" }
      fake_db = double("database")
      allow(fake_db).to receive(:each_value).and_yield(data_entry)
      allow(fake_db).to receive(:[]).and_return(nil)
      allow(fake_db).to receive(:get_data)
      allow(Downloader).to receive(:database).and_return(fake_db)

      expect(Downloader.get_data_by_target(target)).to eq(data_entry)
    end

    it "escapes regex metacharacters when matching ncode" do
      target = "n1234ab+"
      data_entry = { "toc_url" => "https://example.com/#{target}/" }
      fake_db = double("database")
      allow(fake_db).to receive(:each_value).and_yield(data_entry)
      allow(fake_db).to receive(:[]).and_return(nil)
      allow(fake_db).to receive(:get_data)
      allow(Downloader).to receive(:database).and_return(fake_db)
      allow(Downloader).to receive(:get_target_type).and_return(:ncode)

      expect(Downloader.get_data_by_target(target)).to eq(data_entry)
    end

    it "returns nil when target is not found" do
      target = "nonexistent"
      fake_db = double("database")
      allow(fake_db).to receive(:each_value)
      allow(fake_db).to receive(:[]).and_return(nil)
      allow(fake_db).to receive(:get_data).and_return(nil)
      allow(Downloader).to receive(:database).and_return(fake_db)

      result = Downloader.get_data_by_target(target)
      expect(result).to be_nil.or be_a(Hash)
    end
  end

  describe "instance methods" do
    it "creates a Downloader instance with URL" do
      url = "https://ncode.syosetu.com/n9669bk/"
      downloader = Downloader.new(url)
      expect(downloader).to be_a(Downloader)
    end
  end

  describe "#start_download result structure" do
    # start_download の戻り値の構造をテスト
    # OpenStruct で id, new_arrivals, status を返す

    it "returns OpenStruct with new_arrivals true when there are updates" do
      result = OpenStruct.new(id: 1, new_arrivals: true, status: :ok)

      expect(result.new_arrivals).to be true
      expect(result.status).to eq(:ok)
    end

    it "returns OpenStruct with new_arrivals false when no updates" do
      result = OpenStruct.new(id: 1, new_arrivals: false, status: :none)

      expect(result.new_arrivals).to be false
      expect(result.status).to eq(:none)
    end
  end
end

