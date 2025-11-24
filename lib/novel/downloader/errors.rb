# frozen_string_literal: true

#
# Downloader related error classes
#

class Downloader
  # 無効なターゲットが指定された
  class InvalidTarget < StandardError; end

  # ダウンロードを一時停止
  class SuspendDownload < StandardError; end

  # Ruby 3.1以前のためのTimeoutError
  class IO::TimeoutError; end

  # 404エラー
  class DownloaderNotFoundError < OpenURI::HTTPError
    def initialize
      super("404 not found", nil)
    end
  end

  # 強制リダイレクト
  class DownloaderForceRedirect < StandardError; end
end
