# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Narou
  class GitHubRelease
    Release = Struct.new(:tag_name, :version, :name, :html_url, :assets, keyword_init: true)
    Asset = Struct.new(:name, :download_url, :content_type, :size, keyword_init: true)

    class Error < StandardError; end

    API_ENDPOINT = "https://api.github.com/repos/ponponusa/narou-mod"
    DEFAULT_TIMEOUT = 15

    def initialize(token: ENV["GITHUB_TOKEN"], http: Net::HTTP, user_agent: nil)
      @token = token
      @http = http
      @user_agent = user_agent || default_user_agent
    end

    def latest_release
      uri = URI.join(API_ENDPOINT, "/releases/latest")
      response = perform_request(uri)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "GitHub API error: #{response.code} #{response.message}"
      end

      payload = JSON.parse(response.body)
      assets = Array(payload["assets"]).map do |asset|
        Asset.new(
          name: asset["name"],
          download_url: asset["browser_download_url"],
          content_type: asset["content_type"],
          size: asset["size"]
        )
      end

      Release.new(
        tag_name: payload["tag_name"],
        version: normalize_version(payload["tag_name"] || payload["name"]),
        name: payload["name"],
        html_url: payload["html_url"],
        assets: assets
      )
    rescue JSON::ParserError => e
      raise Error, "GitHub API response parse error: #{e.message}"
    end

    private

    attr_reader :token, :http, :user_agent

    def perform_request(uri)
      http.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: DEFAULT_TIMEOUT,
read_timeout: DEFAULT_TIMEOUT) do |client|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = user_agent
        request["Accept"] = "application/vnd.github+json"
        request["Authorization"] = "Bearer #{token}" if token && !token.empty?
        client.request(request)
      end
    rescue StandardError => e
      raise Error, "GitHub API request failed: #{e.class}: #{e.message}"
    end

    def normalize_version(source)
      return nil unless source
      source.to_s.sub(/^v/i, "")
    end

    def default_user_agent
      version = defined?(Narou::VERSION) ? Narou::VERSION : "unknown"
      "narou-mod/#{version}"
    end
  end
end
