#!/usr/bin/env ruby
# frozen_string_literal: true

#
# レガシーパーサーアーカイブツール
#
# git履歴からwebnovel/*.yamlの全バージョンを取得し、
# preset/parsers/legacy_archive/{domain}/v{version}.yamlとして保存する
#

require "yaml"
require "fileutils"
require "pathname"

class LegacyParserArchiver
  WEBNOVEL_DIR = "webnovel"
  ARCHIVE_DIR = "preset/parsers/legacy_archive"

  def initialize(root_dir = Dir.pwd)
    @root_dir = Pathname.new(root_dir)
    @archive_dir = @root_dir.join(ARCHIVE_DIR)
  end

  # 全ドメインのアーカイブを作成
  def archive_all
    domains = find_all_domains
    puts "Found #{domains.size} domains to archive"

    domains.each do |domain|
      puts "\n== Archiving #{domain} =="
      archive_domain(domain)
    end

    puts "\n✓ Archive complete!"
  end

  # 特定ドメインのアーカイブを作成
  def archive_domain(domain)
    file_path = "#{WEBNOVEL_DIR}/#{domain}.yaml"

    # git履歴から全コミットを取得
    commits = get_git_commits(file_path)
    puts "  Found #{commits.size} commits"

    # バージョンごとにグループ化
    versions = extract_versions_from_commits(file_path, commits)
    puts "  Found #{versions.size} unique versions"

    # アーカイブに保存
    save_versions(domain, versions)
  end

  private

  # 全ドメイン一覧を取得
  def find_all_domains
    Dir.glob(@root_dir.join(WEBNOVEL_DIR, "*.yaml")).map do |path|
      File.basename(path, ".yaml")
    end.sort
  end

  # git履歴から指定ファイルの全コミットを取得
  def get_git_commits(file_path)
    output = `git log --all --format=%H -- #{file_path} 2>/dev/null`.strip
    return [] if output.empty?

    output.split("\n")
  rescue => e
    warn "Warning: Failed to get git commits for #{file_path}: #{e.message}"
    []
  end

  # 各コミットからバージョンを抽出
  def extract_versions_from_commits(file_path, commits)
    versions = {}

    commits.each do |commit|
      yaml_content = get_file_content_at_commit(commit, file_path)
      next unless yaml_content

      begin
        data = YAML.load(yaml_content, aliases: true)
        version = data["version"]

        # バージョンがない場合はスキップ
        next unless version

        # 同じバージョンの最新のもの（=最初に見つかったもの）のみを保存
        versions[version] ||= {
          version: version,
          content: yaml_content,
          commit: commit
        }
      rescue => e
        warn "  Warning: Failed to parse YAML at commit #{commit[0..7]}: #{e.message}"
      end
    end

    versions.values.sort_by { |v| v[:version] }
  end

  # 特定コミットでのファイル内容を取得
  def get_file_content_at_commit(commit, file_path)
    `git show #{commit}:#{file_path} 2>/dev/null`
  rescue => e
    warn "  Warning: Failed to get file content at commit #{commit[0..7]}: #{e.message}"
    nil
  end

  # バージョン情報をアーカイブに保存
  def save_versions(domain, versions)
    domain_archive_dir = @archive_dir.join(domain)
    FileUtils.mkdir_p(domain_archive_dir)

    versions.each do |version_info|
      version = version_info[:version]
      content = version_info[:content]
      commit = version_info[:commit]

      archive_file = domain_archive_dir.join("v#{version}.yaml")

      File.write(archive_file, content)
      puts "  ✓ Saved v#{version} (from commit #{commit[0..7]})"
    end
  end
end

# スクリプトとして実行された場合
if __FILE__ == $0
  require "optparse"

  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{__FILE__} [options] [domain]"

    opts.on("-a", "--all", "Archive all domains") do
      options[:all] = true
    end

    opts.on("-h", "--help", "Prints this help") do
      puts opts
      exit
    end
  end.parse!

  archiver = LegacyParserArchiver.new

  if options[:all]
    archiver.archive_all
  elsif ARGV[0]
    domain = ARGV[0]
    archiver.archive_domain(domain)
  else
    puts "Usage: ruby #{__FILE__} [--all] [domain]"
    puts "  --all: Archive all domains"
    puts "  domain: Archive specific domain (e.g., ncode.syosetu.com)"
    exit 1
  end
end
