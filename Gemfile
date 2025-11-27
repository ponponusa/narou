source "https://rubygems.org"

# Specify your gem's dependencies in narou-mod.gemspec
gemspec

gem "parallel"
gem "ruby-prof", "~> 1.7", group: :development

# プラットフォーム固有の依存関係
# Windows専用: win32ole（Ruby 3.5+でdefault gemから外れる予定）
gem "win32ole", "~> 1.9", platforms: %i(mingw x64_mingw mswin)

# Unix系（Linux/macOS）専用: bootsnap（起動高速化）
gem "bootsnap", "~> 1.18", ">= 1.18.6", platforms: [:ruby]
