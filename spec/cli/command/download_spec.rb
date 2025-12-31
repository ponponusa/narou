# frozen_string_literal: true

require "lib/cli/command/download"

RSpec.describe Command::Download do
  let(:command) { described_class.new }

  describe "#valid_target?" do
    it "returns true for ncode format" do
      allow(Downloader).to receive(:get_target_type).with("n9669bk").and_return(:ncode)
      expect(command.valid_target?("n9669bk")).to be true
    end

    it "returns true for valid URL" do
      url = "https://ncode.syosetu.com/n9669bk/"
      allow(Downloader).to receive(:get_target_type).with(url).and_return(:url)
      allow(SiteSetting).to receive(:find).with(url).and_return(double("site_setting"))
      expect(command.valid_target?(url)).to be true
    end

    it "returns false for invalid target" do
      allow(Downloader).to receive(:get_target_type).with("invalid").and_return(:other)
      expect(command.valid_target?("invalid")).to be false
    end

    it "returns false for URL without site setting" do
      url = "https://example.com/novel"
      allow(Downloader).to receive(:get_target_type).with(url).and_return(:url)
      allow(SiteSetting).to receive(:find).with(url).and_return(nil)
      expect(command.valid_target?(url)).to be false
    end
  end

  describe "#print_prompt" do
    it "returns true when user confirms" do
      allow(TTYHelper).to receive(:ask_yes_no).and_return(true)
      expect(command.print_prompt(["n9669bk"])).to be true
    end

    it "returns false when user declines" do
      allow(TTYHelper).to receive(:ask_yes_no).and_return(false)
      expect(command.print_prompt(["n9669bk"])).to be false
    end

    it "shows correct count in prompt" do
      expect(TTYHelper).to receive(:ask_yes_no).with("3件をダウンロードしますか？", default: true).and_return(true)
      command.print_prompt(%w(n1 n2 n3))
    end
  end

  describe "#interactive_mode" do
    it "returns empty array in web mode" do
      allow(Narou).to receive(:web?).and_return(true)
      expect(command.interactive_mode).to eq([])
    end
  end
end
