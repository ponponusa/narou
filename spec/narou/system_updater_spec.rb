# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "lib/narou/system_updater"

RSpec.describe Narou::SystemUpdater do
  let(:release_client) { instance_double(Narou::GitHubRelease) }
  let(:updater) { described_class.new(release_client: release_client) }

  before do
    allow(Gem).to receive(:win_platform?).and_return(false)
  end

  def build_asset(name:, url: "https://example.com/#{name}")
    Narou::GitHubRelease::Asset.new(
      name: name,
      download_url: url,
      content_type: "application/octet-stream",
      size: 1024
    )
  end

  def build_release(version:, assets:)
    Narou::GitHubRelease::Release.new(
      tag_name: "v#{version}",
      version: version,
      name: "v#{version}",
      html_url: "https://example.com/releases/v#{version}",
      assets: assets
    )
  end

  describe "#update_from_github" do
    it "returns :nothing when already up-to-date" do
      release = build_release(version: Narou::VERSION, assets: [build_asset(name: "narou-mod-#{Narou::VERSION}.gem")])
      allow(release_client).to receive(:latest_release).and_return(release)

      result = updater.update_from_github

      expect(result.status).to eq(:nothing)
      expect(result.log).to include("最新バージョン")
    end

    it "raises error when no suitable asset exists" do
      release = build_release(version: "999.0.0", assets: [])
      allow(release_client).to receive(:latest_release).and_return(release)

      expect { updater.update_from_github }.to raise_error(Narou::SystemUpdater::Error, /アセット/)
    end

    it "installs gem and returns success" do
      release = build_release(version: "999.0.0", assets: [build_asset(name: "narou-mod-999.0.0.gem")])
      allow(release_client).to receive(:latest_release).and_return(release)
      allow(updater).to receive(:download_asset).and_return("/tmp/narou-mod-999.0.0.gem")
      allow(updater).to receive(:install_gem).and_return([true, "install ok"])

      result = updater.update_from_github

      expect(result.status).to eq(:success)
      expect(result.log).to include("install ok")
      expect(result.asset_name).to eq("narou-mod-999.0.0.gem")
    end

    it "returns failure when gem install fails" do
      release = build_release(version: "999.0.0", assets: [build_asset(name: "narou-mod-999.0.0.gem")])
      allow(release_client).to receive(:latest_release).and_return(release)
      allow(updater).to receive(:download_asset).and_return("/tmp/narou-mod-999.0.0.gem")
      allow(updater).to receive(:install_gem).and_return([false, "install failed"])

      result = updater.update_from_github

      expect(result.status).to eq(:failure)
      expect(result.log).to include("install failed")
    end

    it "prefers mingw asset on Windows" do
      allow(Gem).to receive(:win_platform?).and_return(true)
      assets = [
        build_asset(name: "narou-mod-999.0.0.gem"),
        build_asset(name: "narou-mod-999.0.0-x64-mingw-ucrt.gem")
      ]
      release = build_release(version: "999.0.0", assets: assets)
      allow(release_client).to receive(:latest_release).and_return(release)
      allow(updater).to receive(:download_asset).and_return("/tmp/narou-mod-999.0.0-x64-mingw-ucrt.gem")
      allow(updater).to receive(:install_gem).and_return([true, "ok"])

      result = updater.update_from_github

      expect(result.asset_name).to eq("narou-mod-999.0.0-x64-mingw-ucrt.gem")
    end
  end

  describe "#http_download" do
    let(:source_uri) { URI("https://example.com/narou-mod.gem") }
    let(:tempfile) do
      file = Tempfile.new("narou-system-updater")
      file.close
      file
    end
    let(:destination) { tempfile.path }

    after do
      tempfile.unlink
    rescue StandardError
      # noop
    end

    it "follows HTTP redirects" do
      redirect_uri = "https://cdn.example.com/narou-mod.gem"
      redirect_response = Net::HTTPFound.new("1.1", "302", "Found")
      redirect_response["location"] = redirect_uri

      success_response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(success_response).to receive(:value).and_return(success_response)
      allow(success_response).to receive(:read_body).and_yield("chunk")

      expect(updater).to receive(:perform_download_request).with(source_uri).ordered.and_yield(redirect_response)
      expect(updater).to receive(:perform_download_request).with(URI(redirect_uri)).ordered.and_yield(success_response)

      updater.send(:http_download, source_uri, destination)

      expect(File.binread(destination)).to eq("chunk")
    end

    it "raises error when redirect location is missing" do
      redirect_response = Net::HTTPFound.new("1.1", "302", "Found")
      expect(updater).to receive(:perform_download_request).with(source_uri).and_yield(redirect_response)

      expect { updater.send(:http_download, source_uri, destination) }
        .to raise_error(Narou::SystemUpdater::Error, /リダイレクト先の URL が不正/)
    end
  end
end
