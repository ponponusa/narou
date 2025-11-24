# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "uri"
require "net/http"

require "lib/narou/github_release"

module Narou
  class SystemUpdater
    Result = Struct.new(:status, :log, :remote_version, :asset_name, keyword_init: true)

    class Error < StandardError; end

    def self.update_from_github
      new.update_from_github
    end

    def initialize(release_client: GitHubRelease.new)
      @release_client = release_client
      @cleanup_targets = []
    end

    def update_from_github
      release = fetch_latest_release
      remote_version = parse_version(release.version)
      current_version = parse_version(Narou::VERSION)

      if remote_version.nil?
        raise Error, "GitHub リリースのバージョン情報を取得できませんでした"
      end

      if remote_version <= current_version
        message = <<~MSG.strip
          最新バージョン (#{remote_version}) はすでに適用済みです。
        MSG
        return Result.new(status: :nothing, log: message, remote_version: remote_version)
      end

      asset = select_asset(release.assets)
      unless asset
        raise Error, "対象プラットフォーム向けの gem アセットがリリースに含まれていません"
      end

      gem_path = download_asset(asset)
      success, install_log = install_gem(gem_path)
      log = build_log(remote_version, asset.name, install_log)

      status = success ? :success : :failure
      Result.new(status: status, log: log, remote_version: remote_version, asset_name: asset.name)
    ensure
      cleanup_tmp_artifacts
    end

    private

    attr_reader :release_client, :cleanup_targets

    def fetch_latest_release
      release_client.latest_release
    rescue GitHubRelease::Error => e
      raise Error, e.message
    end

    def parse_version(version_string)
      return nil unless version_string
      Gem::Version.new(version_string.to_s)
    rescue ArgumentError
      nil
    end

    def select_asset(assets)
      return nil if assets.nil? || assets.empty?
      if windows_platform?
        assets.find { |asset| asset.name&.include?("mingw-ucrt") } || assets.find { |asset| asset.name&.end_with?(".gem") }
      else
        assets.reject { |asset| asset.name&.include?("mingw-ucrt") }.find { |asset| asset.name&.end_with?(".gem") }
      end
    end

    def windows_platform?
      Gem.win_platform?
    end

    def download_asset(asset)
      raise Error, "ダウンロード URL が取得できませんでした" unless asset.download_url
      tmp_dir = Dir.mktmpdir("narou-mod-update")
      cleanup_targets << tmp_dir
      destination = File.join(tmp_dir, asset.name || "narou-mod.gem")

      uri = URI(asset.download_url)
      http_download(uri, destination)
      destination
    rescue StandardError => e
      raise Error, "gem アセットのダウンロードに失敗しました: #{e.class}: #{e.message}"
    end

    def http_download(uri, destination, limit = 5)
      raise Error, "ダウンロードがリダイレクト回数上限を超えました" if limit <= 0

      perform_download_request(uri) do |response|
        if response.is_a?(Net::HTTPRedirection)
          location = response["location"]
          raise Error, "リダイレクト先の URL が不正です" unless location && !location.empty?

          new_uri = build_redirect_uri(uri, location)
          return http_download(new_uri, destination, limit - 1)
        end

        response.value
        File.open(destination, "wb") do |file|
          response.read_body do |chunk|
            file.write(chunk)
          end
        end
      end
    rescue Net::HTTPRetriableError => e
      raise Error, "HTTP #{e.response.code} #{e.response.message}"
    rescue Net::HTTPExceptions => e
      raise Error, "HTTP #{e.response.code} #{e.response.message}"
    end

    def build_redirect_uri(current_uri, location)
      new_uri = URI.parse(location)
      new_uri = current_uri.merge(new_uri) if new_uri.relative?
      new_uri
    rescue URI::InvalidURIError
      raise Error, "リダイレクト先の URL が不正です"
    end

    def perform_download_request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "narou-mod/#{Narou::VERSION}"
        token = ENV["GITHUB_TOKEN"]
        request["Authorization"] = "Bearer #{token}" if token && !token.empty?
        http.request(request) do |response|
          return yield response if block_given?
          return response
        end
      end
    end

    def install_gem(path)
      command = [Gem.ruby, "-S", "gem", "install", path.to_s, "--no-document", "--local"]
      stdout, stderr, status = Open3.capture3(*command)
      [status.success?, (stdout + stderr).strip]
    end

    def build_log(remote_version, asset_name, install_log)
      header = <<~HEADER
        取得したリリースバージョン: #{remote_version}
        使用アセット: #{asset_name}
      HEADER
      [header.strip, install_log].reject(&:empty?).join("\n\n")
    end

    def cleanup_tmp_artifacts
      cleanup_targets.reverse_each do |path|
        FileUtils.remove_entry_secure(path) if path && File.exist?(path)
      rescue StandardError
        # クリーニング失敗は無視
      end
      cleanup_targets.clear
    end
  end
end
