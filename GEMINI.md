# Repository Guidelines for Gemini (Backend / Ruby)

`narou-mod` のバックエンド（Ruby 製の小説変換ツール本体および Sinatra Web サーバ）向けに、Gemini (Antigravity) 用の開発ガイドおよびルールを定義します。
フロントエンド固有のルールは [frontend/GEMINI.md](frontend/GEMINI.md) を参照してください。

## Tech Stack

- **Ruby**: 3.4 以上 (`gem.required_ruby_version = ">= 3.4.0"`)。
- **Sinatra 4.x**: Web UI / REST API (`lib/web/appserver.rb` 起点)。`puma` で配信、`rack` 3 系。
- **ActiveSupport 8.x**: ドメイン側の汎用ユーティリティ。
- **Nokogiri / rubyzip / Haml / Tilt / Sass (sass-embedded)**: HTML 解析、EPUB 系出力、ビュー生成。
- **TTY 系 (`tty-box`, `tty-prompt`, `tty-spinner`, `tty-markdown`)**: CLI 表示。
- **RSpec**: テストランナー。
- **RuboCop / Reek**: 静的解析。
- **Bundler 2.7.2**: 開発・CI で固定。

## Project Structure & Module Organization

```
narou-mod/
├── narou.rb                # 開発時エントリ（インストール済み gem との競合回避を行い bin/ を読み込む）
├── narou-mod.gemspec       # gem 仕様（Linux/macOS と mingw でプラットフォーム別ビルド）
├── Gemfile / Gemfile.lock  # 開発依存
├── Rakefile                # 既定タスクは rake spec
├── bin/
│   └── narou-mod           # gem 配布版の実行ファイル本体
├── lib/
│   ├── core/               # コア機能・バージョン定義 (core/version.rb)
│   ├── narou/              # ドメインロジックの主要モジュール
│   ├── cli/                # CLI 基盤
│   │   └── command/        # サブコマンド群（download, convert, list, web, etc.）
│   ├── web/                # Sinatra ベース Web サーバ
│   │   ├── appserver.rb
│   │   ├── routes/         # ルーティング
│   │   ├── api/            # REST API
│   │   ├── views/          # Haml ビュー
│   │   ├── helpers/        # ビュー / ルートヘルパ
│   │   ├── workers/        # バックグラウンドワーカ
│   │   └── public/         # サーバが配信する静的ファイル
│   ├── conversion/         # 本文変換
│   ├── ebook/              # EPUB / 書籍化
│   ├── output/             # 出力フォーマッタ
│   ├── novel/              # 小説モデル
│   └── utilities/          # 汎用ユーティリティ
├── spec/                   # RSpec (各 lib 配下とほぼ対称)
├── webnovel/               # 対応サイト定義 YAML
├── preset/                 # 変換プリセット
├── template/               # テンプレート資産
├── scripts/                # 補助スクリプト (process_control.sh 等)
└── frontend/               # Astro + Svelte フロントエンド
```

## Build, Test, and Development Commands

すべてリポジトリルートで実行します。

- `bundle install`: gem 依存をインストール。
- `bundle exec ruby narou.rb web`: ローカル Web UI を起動。
- `bundle exec ruby narou.rb download <novel_id>`: 小説のダウンロードと変換実験用。
- `bundle exec rspec`: テスト全件実行。`bundle exec rspec spec/core/downloader_spec.rb` のように個別指定も可。
- `bundle exec rake`: RSpec を実行（`Rakefile`）。
- `bundle exec rubocop -A`: Ruby スタイル自動修正。
- `bundle exec reek`: コードスメル検査。
- `./scripts/process_control.sh --restart`: 起動中サーバを一括停止・再起動。

## Coding Style & Naming Conventions

- インデント: 2 スペース。
- 文字列: 原則として単一引用符 (`'`) を使用。
- 命名規則: ファイル名やメソッド名は `snake_case`、クラスやモジュール名は `CamelCase`、名前空間は `Narou::CamelCase`。
- 新規ファイル: 先頭に必ず `# frozen_string_literal: true` を記述。
- 静的解析: コミットやプッシュの前に `bundle exec rubocop` および `bundle exec reek` を実行し、警告を修正すること。

## Testing Guidelines

- RSpec テストは `spec/` 配下に `*_spec.rb` として配置。
- 外部 API やネットワーク接続、ファイルシステムの副作用はモック/スタブ化し、`spec/support/` や `spec/fixtures/` を最大限に活用。
- パフォーマンス関連のテストは `spec/performance/` に配置（CI では除外）。
- 変更や機能追加の際は、必ず対応するスペックを追加し、ローカルでテストをパスさせること。

## Gemini (Antigravity) Specific Rules

- **Git コミットの署名**:
  Git のコミット作成時、Author / Committer は必ず以下を設定してください。
  ```bash
  git config user.name "ponpon.USA"
  git config user.email "init0531.usa@gmail.com"
  ```
  ※ コマンド実行前に環境変数や `git config --local` で適切に設定されていることを確認してください。
- **変更の最小化**:
  意図しない広範囲のリファクタリングは避け、ユーザーの要求に対して必要最小限かつ影響度の低い修正を心がけてください。
- **計画モード (planning_mode) の遵守**:
  大幅な設計変更や曖昧な要求に対しては、まず調査を行い、`implementation_plan.md` を作成してユーザーの承認を得てから実装に進んでください。
- **GitHub CLI (`gh` コマンド) の利用**:
  本環境には GitHub CLI (`gh` コマンド) がインストールされており、利用可能です。プルリクエストの作成やIssueの管理、ステータスの確認など、GitHub上の操作を行う際は `gh` コマンドを積極的に活用してください。
