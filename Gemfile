source "https://rubygems.org"

# Specify your gem's dependencies in narou-mod.gemspec
gemspec

# ---------------------------------------------------------------------------
# 開発時のプラットフォーム固有依存関係
# ---------------------------------------------------------------------------
# NOTE: gem build 時はgemspecの条件分岐でプラットフォーム別にビルドされる。
#       以下は bundle install で開発環境に入れるためのもの。
#
# Windows専用: win32ole（Ruby 3.5+でdefault gemから外れる予定）
gem "win32ole", "~> 1.9", platforms: %i(mingw x64_mingw mswin)

# macOS/Linux専用: bootsnap（起動高速化、Windowsは非対応）
gem "bootsnap", "~> 1.18", ">= 1.18.6", platforms: [:ruby]
