# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "narou"

describe Narou do
  before :each do
    Narou.flush_cache
  end

  describe ".last_commit_year" do
    it "should be commited year" do
      expect(Narou.last_commit_year).to eq Time.now.year
    end
  end

  describe ".global_setting_dir" do
    before :all do
      @original_name = Narou::GLOBAL_SETTING_DIR_NAME
      Narou.const_replace :GLOBAL_SETTING_DIR_NAME, ".narousetting_dummy"
      @global_dir_in_root = Pathname(".narousetting_dummy").expand_path(Narou.root_dir)
    end

    after :all do
      Narou.const_replace :GLOBAL_SETTING_DIR_NAME, @original_name
    end

    after do
      Dir.rmdir(Narou.global_setting_dir)
    end

    context ".narou があるディレクトリにはない場合" do
      it "ユーザーディレクトリにあるべき" do
        expect(Narou.global_setting_dir).to eq Pathname(".narousetting_dummy").expand_path("~")
      end
    end

    context ".narou があるディレクトリと同じ場所にある場合" do
      before do
        FileUtils.mkdir(@global_dir_in_root)
      end

      it "同じディレクトリにあるほうが優先されるべき" do
        expect(Narou.global_setting_dir).to eq @global_dir_in_root
      end
    end
  end

  describe ".latest_version" do
    let(:release_client) { instance_double(Narou::GitHubRelease) }
    let(:release) do
      Narou::GitHubRelease::Release.new(
        tag_name: "v9.9.9",
        version: "9.9.9",
        name: "v9.9.9",
        html_url: "https://example.com",
        assets: []
      )
    end

    it "GitHub Releases のバージョンを返す" do
      allow(Narou::GitHubRelease).to receive(:new).and_return(release_client)
      allow(release_client).to receive(:latest_release).and_return(release)

      expect(Narou.latest_version).to eq "9.9.9"
    end

    it "取得に失敗したら nil を返す" do
      allow(Narou::GitHubRelease).to receive(:new).and_return(release_client)
      allow(release_client).to receive(:latest_release).and_raise(Narou::GitHubRelease::Error.new("fail"))

      expect(Narou.latest_version).to be_nil
    end
  end
end
