# Repository Guidelines (Backend / Ruby)

`narou-mod` のバックエンド（Ruby 製の小説変換ツール本体および Sinatra Web サーバ）向けガイドです。リポジトリ全体は Ruby バックエンドと Astro/Svelte フロントエンドの 2 層構成で、フロントエンド固有のルールは [frontend/AGENTS.md](frontend/AGENTS.md) を参照してください。

## Tech Stack

- **Ruby**: 3.4 以上 (`gem.required_ruby_version = ">= 3.4.0"`)。CI も Ruby 3.4 で実行。
- **Sinatra 4.x**: Web UI / REST API (`lib/web/appserver.rb` 起点)。`puma` で配信、`rack` 3 系。
- **ActiveSupport 8.x**: ドメイン側の汎用ユーティリティ。
- **Nokogiri / rubyzip / Haml / Tilt / Sass (sass-embedded)**: HTML 解析、EPUB 系出力、ビュー生成。
- **TTY 系 (`tty-box`, `tty-prompt`, `tty-spinner`, `tty-markdown`)**: CLI 表示。
- **RSpec**: テストランナー。`rspec_junit_formatter` で CI 用 JUnit XML を出力。
- **RuboCop / Reek**: 静的解析。
- **Bundler 2.7.2**: 開発・CI で固定。
- **GitHub Actions**: `.github/workflows/ci.yml` で PR テスト、`release` / `draft` ブランチ push で Linux/macOS および Windows (mingw-ucrt) 向け gem ビルドとリリース作成。

## Project Structure & Module Organization

```
narou-mod/
├── narou.rb                # 開発時エントリ（インストール済み gem との競合回避を行い bin/ を読み込む）
├── narou-mod.gemspec       # gem 仕様（Linux/macOS と mingw でプラットフォーム別ビルド）
├── Gemfile / Gemfile.lock  # 開発依存（プラットフォーム別の bootsnap / win32ole を含む）
├── Rakefile                # 既定タスクは rake spec
├── bin/
│   └── narou-mod           # gem 配布版の実行ファイル本体
├── lib/
│   ├── core/               # コア機能・バージョン定義 (core/version.rb)
│   ├── narou/              # ドメインロジックの主要モジュール
│   ├── cli/                # CLI 基盤
│   │   ├── commandbase.rb
│   │   ├── commandline.rb
│   │   ├── input.rb
│   │   └── command/        # サブコマンド群（download, convert, list, web, etc.）
│   ├── web/                # Sinatra ベース Web サーバ
│   │   ├── appserver.rb
│   │   ├── routes/         # ルーティング
│   │   ├── api/            # REST API
│   │   ├── views/          # Haml ビュー
│   │   ├── helpers/        # ビュー / ルートヘルパ
│   │   ├── workers/        # バックグラウンドワーカ
│   │   ├── processors/     # 受信処理
│   │   ├── server/         # サーバ起動・管理
│   │   ├── overrides/      # Sinatra 拡張
│   │   ├── logging/
│   │   ├── config/
│   │   └── public/         # サーバが配信する静的ファイル
│   ├── conversion/         # 本文変換
│   ├── ebook/              # EPUB / 書籍化
│   ├── output/             # 出力フォーマッタ
│   ├── novel/              # 小説モデル
│   ├── utilities/          # 汎用ユーティリティ
│   ├── extensions/         # コア拡張
│   ├── mixin/              # 共有 mixin
│   └── loading/            # 遅延ロード補助
├── spec/                   # RSpec (各 lib 配下とほぼ対称、support/ と fixtures/ を共有)
│   ├── support/            # 共通ヘルパ
│   ├── fixtures/           # 固定入力
│   ├── data/               # テストデータ
│   └── performance/        # 性能テスト
├── webnovel/               # 対応サイト定義 YAML
├── preset/                 # 変換プリセット
├── template/               # テンプレート資産
├── scripts/                # 補助スクリプト (process_control.sh / .ps1, ダミーデータ生成 等)
├── frontend/               # Astro + Svelte フロントエンド（詳細は frontend/AGENTS.md）
├── .github/workflows/      # CI (ci.yml: テスト・gem ビルド・リリース)
├── CHANGELOG.md            # ユーザ向け変更履歴
└── README.md
```

## Build, Test, and Development Commands

すべてリポジトリルートで実行します。

- `bundle install`: gem 依存をインストール。
- `bundle exec ruby narou.rb web`: ローカル Web UI を起動して動作確認。
- `bundle exec ruby narou.rb download <novel_id>`: 変換実験用にソースを取得。
- `bundle exec rspec`: テスト全件実行。`bundle exec rspec spec/core/downloader_spec.rb` のようにファイル指定も可。
- `bundle exec rake`: 既定タスクとして RSpec を実行（`Rakefile`）。
- `bundle exec rubocop`（`-A` で自動修正）: Ruby スタイルチェック。
- `bundle exec reek`: コードスメル検査。
- `./scripts/process_control.sh --restart`（Unix） / `.\scripts\process_control.ps1 -Restart`（Windows）: 起動中サーバを一括停止・再起動。

### フロントエンドとの連携

- Web サーバはデフォルトで Sinatra 単体動作する。Astro フロントエンドを併用する開発フローは [frontend/AGENTS.md](frontend/AGENTS.md) を参照。
- フロントエンドのプロキシ先ポートは `frontend/public/backend-port.json` から動的に解決される（`.gitignore` 対象なのでローカル起動スクリプトに任せる）。
- gem ビルド時は CI で `frontend/dist/` を事前ビルドして gem に含める設計（`.github/workflows/ci.yml`）。

## Coding Style & Naming Conventions

- インデント 2 スペース、単純な文字列は単一引用符、ファイル名・メソッド名は `snake_case`。
- 名前空間は `Narou::CamelCase` 形式。CLI サブコマンドは `lib/cli/command/` の既存パターンに揃える。
- 新規ファイルは先頭に `# frozen_string_literal: true` を置き、可能なら ASCII で書く。
- 提出前に `bundle exec rubocop` と `bundle exec reek` を実行する。`.rubocop.yml` / `.reek` の設定に従う。
- ビューは Haml。`.haml-lint.yml` および `.scss-lint.yml` のルールに従う。

## Testing Guidelines

- RSpec は `spec/` 配下に `*_spec.rb` で配置し、`describe` / `context` を明確に区切る。
- ネットワークやファイルシステムの副作用はスタブ化し、`spec/support/` 配下のヘルパと `spec/fixtures/` を活用する。
- 性能関連は `spec/performance/` に隔離（CI 通常実行から外す運用）。
- 変更・修正には対応するスペックを追加し、レビュー前に `bundle exec rspec` を通す。
- CI は PR 時に Astro ビルドと RSpec を直列実行するため、ローカルでも両方通しておく。

## Commit & Pull Request Guidelines

- コミット件名は命令形（例: `Add downloader retry logic`）。関連 Issue は `#123` の形で参照。
- ユーザに影響する変更は `CHANGELOG.md` を更新し、PR には目的・実装方針・テスト内容を記載する。
- Web / UI まわりの変更ではスクリーンショットやログを添付し、マイグレーションや破壊的変更は明示する。
- ベースブランチ:
  - 通常の PR は `release`。
  - ステージング検証は `draft`。`release` / `draft` への push で gem ビルドおよび GitHub Release が走るため、マージは慎重に。

## Security & Configuration Tips

- シークレットはリポジトリへ含めない。`rsync.env` 等はサンプルのみコミット (`rsync.env.example`)。
- `webnovel/` 配下の YAML は追加・編集時に必ずローカルで動作確認する。
- エントリスクリプトの既定エンコーディングは UTF-8。取得したデータは変換前にサニタイズする。
- `narou.rb` はインストール済み gem との競合を避けるため `$LOAD_PATH` を加工している。エントリ周辺を触る際はこの初期化順序を崩さない。

## Agent-Specific Instructions

- 変更は最小・スコープを絞り、広範なリファクタは避ける。必要な場合は事前に Issue で合意を取る。
- 既存の公開 API・CLI 挙動を尊重する。互換性に影響しうる変更は PR 説明で明示する。
- Git のコミット author / committer は `ponpon.USA <init0531.usa@gmail.com>` を必ず使用する（本名や別アドレスを混入させないこと）。
- フロントエンド側の作業を行う際は [frontend/AGENTS.md](frontend/AGENTS.md) のガイドにも従う。
