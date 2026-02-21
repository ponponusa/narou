# 依存パッケージ メジャーバージョンアップ調査

調査日: 2026-02-21
対象バージョン: narou-mod 3.1.2
Ruby要件: >= 3.4.0

## 概要

`bundle outdated` で検出されたメジャーバージョンアップ対象の gem について、
破壊的変更・移行難易度・依存関係によるブロック状況を調査した。

## 更新不可 (依存関係でブロック)

### diff-lcs 1.6.2 → 2.0.0

- **ブロック要因:** `rspec-expectations` / `rspec-mocks` が `diff-lcs (>= 1.2.0, < 2.0)` で制約
- **gemspec 制約:** `~> 1.6`
- **主な破壊的変更:**
  - Ruby >= 3.2 必須
  - `Diff::LCS.LCS` (大文字) メソッド削除 → `Diff::LCS.lcs` (小文字) を使用
  - `htmldiff` バイナリ削除
  - `ed`/`reverse_ed` 出力フォーマット削除
  - 内部クラス (`Change`, `ContextChange`, `Hunk`, `Block`) のイミュータブル `Data` 対応による再構成
- **対応:** RSpec 側の対応待ち (RSpec 4.x または 3.14+ でのconstraint緩和)

### unicode-display_width 2.6.0 → 3.2.0

- **ブロック要因:** `strings` gem (tty-box/tty-markdown 経由) が `unicode-display_width (>= 1.5, < 3.0)` で制約
- **gemspec 制約:** `>= 1.5, < 3.0`
- **主な破壊的変更:**
  - String拡張 (`"str".display_width`) が自動ロードされなくなる → `require "unicode/display_width/string_ext"` が必要
  - 非推奨エイリアス `display_size` / `display_length` 削除
  - 第3位置引数が非推奨化 → キーワード引数 (`ambiguous:`, `emoji:`, `overwrite:`) へ移行
  - 絵文字幅がデフォルトで有効化
- **対応:** TTY エコシステム (`strings` gem) の対応待ち

### wisper 2.0.1 → 3.0.0

- **ブロック要因:** `tty-reader` が `wisper (~> 2.0)` で制約
- **主な破壊的変更:**
  - Ruby >= 2.7 必須
  - Ruby 3.0+ キーワード引数構文のサポート追加
  - 実質的な API 変更は少ない
- **対応:** `tty-reader` の対応待ち

## 更新可能

### ruby-prof 1.7.2 → 2.0.2

- **gemspec 制約:** `~> 1.7` (開発依存のみ)
- **移行難易度:** 低
- **主な破壊的変更:**
  - Ruby >= 3.2 必須
  - `RubyProf::MEMORY` 計測モード削除
  - 非推奨の互換性API削除 (pre-1.0 時代のレガシーAPI)
  - Printer オプションがハッシュからキーワード引数に変更:
    ```ruby
    # Before
    printer.print(STDOUT, :min_percent => 2, :sort_method => :self_time)
    # After
    printer.print(STDOUT, min_percent: 2, sort_method: :self_time)
    ```
  - 新規依存: `base64`, `ostruct`
- **影響範囲:** 開発用のみ。ランタイムへの影響なし
- **対応手順:** gemspec の制約を `~> 2.0` に変更

### puma 6.6.1 → 7.2.0

- **gemspec 制約:** `~> 6.4`
- **移行難易度:** 低〜中
- **主な破壊的変更:**
  - Ruby >= 3.0 必須
  - コールバックフック名の全面変更:
    | 旧名 | 新名 |
    |---|---|
    | `on_worker_boot` | `before_worker_boot` |
    | `on_worker_shutdown` | `before_worker_shutdown` |
    | `on_restart` | `before_restart` |
    | `on_booted` | `after_booted` |
    | `on_stopped` | `after_stopped` |
    | `on_refork` | `before_refork` |
    | `on_thread_start` | `before_thread_start` |
    | `on_thread_exit` | `before_thread_exit` |
    | `on_worker_fork` | `before_worker_fork` |
  - `preload_app!` がクラスタモードでデフォルト有効
  - レスポンスヘッダが小文字に統一
  - `HTTP_VERSION` 環境変数が Rack > 3.1 で設定されなくなる
  - `persistent_timeout` デフォルト 65秒に増加
  - フックにブロック必須 (未指定で ArgumentError)
  - `ruby_engine` メソッド削除
- **影響範囲:** Sinatra Web アプリ。フックを使用していなければ影響は限定的
- **対応手順:**
  1. gemspec の制約を `~> 7.0` に変更
  2. コードベース内の `on_*` フック使用箇所を検索・リネーム
  3. ヘッダの大文字小文字に依存するミドルウェアの確認

### haml 5.2.2 → 7.2.0

- **gemspec 制約:** `>= 5.2.2, < 6` (意図的に 6.x 以上をブロック)
- **移行難易度:** 高
- **主な破壊的変更 (Haml 6.0 - テンプレートエンジン完全書き直し):**
  - `Haml::Engine` インターフェース変更 → `Haml::Template` を使用:
    ```ruby
    # Before (Haml 5)
    Haml::Engine.new("%p Hello").render
    # After (Haml 6+)
    Haml::Template.new { "%p Hello" }.render
    ```
  - 多数のヘルパー削除: `haml_concat`, `haml_tag`, `haml_tag_if`, `html_attrs`, `list_of`, `tab_up`/`tab_down`, `with_tabs`, `is_haml?`, `block_is_haml?`, `init_haml_helpers`, `non_haml`, `flatten`, `html_escape`
  - 残存ヘルパー: `find_and_preserve`, `preserve`, `surround`, `precede`, `succeed`, `capture_haml`
  - `Haml::Buffer` 完全削除
  - ネストされたHash属性は `data` と `aria` のみサポート
  - ダッシュ (`-`) スクリプト行でのキャプチャ廃止 (= 行のみ yield 対応)
  - `:ruby` フィルターから `haml_io` アクセス不可
  - Boolean属性リストがHTML5仕様に限定
- **主な破壊的変更 (Haml 7.0):**
  - Ruby >= 3.2 必須
  - デフォルト `attr_quote` がシングルクォート → ダブルクォートに変更
- **影響範囲:** 全 `.haml` テンプレートの監査が必要
- **対応手順:**
  1. gemspec の制約を `>= 7.0` に変更
  2. `Haml::Engine` の直接使用箇所を `Haml::Template` に移行
  3. 削除されたヘルパーの使用箇所を特定・代替実装
  4. 全テンプレートの動作確認

## パッチ/マイナーアップデート (2026-02-21 適用済み)

| Gem | 更新前 | 更新後 |
|-----|--------|--------|
| bootsnap | 1.21.1 | 1.23.0 |
| google-protobuf | 4.33.4 | 4.33.5 |
| json | 2.18.0 | 2.18.1 |
| net-imap | 0.6.2 | 0.6.3 |
| nokogiri | 1.19.0 | 1.19.1 |
| parser | 3.3.10.1 | 3.3.10.2 |
| prism | 1.8.0 | 1.9.0 |
| rack | 3.2.4 | 3.2.5 |
| rspec-support | 3.13.6 | 3.13.7 |
| rubocop | 1.82.1 | 1.84.2 |
