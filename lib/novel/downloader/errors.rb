# frozen_string_literal: true

#
# Downloader related error classes
#

class Downloader
  CLOUDFLARE_CHALLENGE_MESSAGE =
    "Cloudflare のブラウザ確認によりアクセスが拒否されました。" \
    "この環境からは自動ダウンロードできないため、時間を置くか別のネットワーク環境から再試行してください"

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
