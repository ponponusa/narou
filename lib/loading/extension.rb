# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "open-uri"
require "lib/core/inventory"

# open-uri で http → https へのリダイレクトを有効にする
require "open_uri_redirections"

module Narou
  module OpenURIOptions
    DEFAULT_USER_AGENT =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:141.0) Gecko/20100101 Firefox/141.0".freeze
    NAVIGATION_HEADERS = {
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
      "Accept-Language" => "ja,en-US;q=0.9,en;q=0.8",
      "Upgrade-Insecure-Requests" => "1",
      "Sec-Fetch-Dest" => "document",
      "Sec-Fetch-Mode" => "navigate",
      "Sec-Fetch-Site" => "none",
      "Sec-Fetch-User" => "?1"
    }.freeze

    module_function

    def build(add)
      configured_user_agent = Inventory.load("local_setting")["user-agent"]
      {
        "User-Agent" => configured_user_agent || DEFAULT_USER_AGENT
      }.merge(add)
    end
  end
end

# open-uri に渡すオプションを生成（必要に応じて extensions/*.rb でオーバーライドする）
def make_open_uri_options(add)
  Narou::OpenURIOptions.build(add)
end

def make_open_uri_navigation_options(add)
  make_open_uri_options(Narou::OpenURIOptions::NAVIGATION_HEADERS.merge(add))
end

#
# 安全なファイルの書き込み
#
# ファイルに直接上書きしないで、一旦別名で作成してからファイル名変更をすることで、
# ファイル書き込み中のPCクラッシュ等でデータが飛ばない様にする
#
require "securerandom"

def File.write(path, string, *options, mode: nil)
  return super if mode

  dirpath = File.dirname(path)
  FileUtils.makedirs(dirpath) unless Dir.exist?(dirpath)
  temp_path = File.join(dirpath, SecureRandom.hex(15))
  section_dir_name = if defined?(Downloader::SECTION_SAVE_DIR_NAME)
                       Downloader::SECTION_SAVE_DIR_NAME
                     end
  if File.extname(path) == ".yaml" && File.basename(dirpath) != section_dir_name
    backup = "#{path}.backup"
  end

  res = super(temp_path, string, *options)
  if backup
    super(backup, string, *options)
  end
  File.rename(temp_path, path)
  res
end
