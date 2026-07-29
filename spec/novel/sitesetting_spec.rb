# frozen_string_literal: true

require "lib/novel/sitesetting"

RSpec.describe SiteSetting do
  CURRENT_EPISODE_LIST_HTML = <<~HTML
    <li class="episode-list__chapter">
      <div class="episode-list__chapter-title">第一章</div>
    </li>
    <li class="episode-list__item">
      <a href="./12.html" class="episode-list__link">
        <span class="episode-list__mark"></span>
        <span class="episode-list__title" >第十二話</span>
        <time class="episode-list__date" itemprop="datePublished" datetime="2026-07-23T23:09Z">2026/07/23 23:09</time>
        <span class="episode-list__revision" title="2026/07/24 09:43改稿">(<u>改</u>)</span>
      </a>
    </li>
  HTML

  describe "ハーメルンR18設定" do
    subject(:setting) do
      described_class.load_file(
        File.expand_path("../../webnovel/h.syosetu.org.yaml", __dir__)
      )
    end

    it "matches h.syosetu.org URLs and keeps the R18 domain for downloads" do
      expect(setting.multi_match_once("https://h.syosetu.org/novel/420341/", "url")).to be_truthy
      expect(setting["toc_url"]).to eq("https://h.syosetu.org/novel/420341/")
      expect(setting["novel_info_url"]).to eq(
        "https://h.syosetu.org/?mode=ss_detail&nid=420341"
      )
      expect(setting["confirm_over18"]).to be(true)
      expect(setting["cookie"]).to eq("over18=off")
      expect(setting["sitename"]).to eq("ハーメルン")
    end

    it "does not match the all-ages domain" do
      expect(setting.multi_match_once("https://syosetu.org/novel/420959/", "url")).to be_nil
    end
  end

  %w(syosetu.org.yaml h.syosetu.org.yaml).each do |filename|
    describe "#{filename} の現行目次構造" do
      subject(:setting) do
        described_class.load_file(
          File.expand_path("../../webnovel/#{filename}", __dir__)
        )
      end

      it "extracts chapter, episode, and revision metadata" do
        expect(setting.multi_match_once(CURRENT_EPISODE_LIST_HTML, "subtitles")).to be_truthy
        expect(setting["chapter"]).to eq("第一章")
        expect(setting["index"]).to eq("12")
        expect(setting["href"]).to eq("12.html")
        expect(setting["subtitle"]).to eq("第十二話")
        expect(setting["subdate"]).to eq("2026/07/23 23:09")
        expect(setting["subupdate"]).to eq("2026/07/24 09:43")
      end

      it "accepts a non-empty mark and an omitted revision span" do
        html = CURRENT_EPISODE_LIST_HTML
               .sub(
                 '<span class="episode-list__mark"></span>',
                 '<span class="episode-list__mark">NEW</span>'
               )
               .sub(%r{\s*<span class="episode-list__revision".*?</span>}m, "")

        expect(setting.multi_match_once(html, "subtitles")).to be_truthy
        expect(setting["index"]).to eq("12")
        expect(setting["subtitle"]).to eq("第十二話")
        expect(setting["subupdate"]).to be_blank
      end
    end
  end
end
