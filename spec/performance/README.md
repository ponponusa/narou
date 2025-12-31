# パフォーマンステスト

Narou.rb MOD のパフォーマンステストツール群です。大量データ環境でのボトルネック特定と最適化のために使用します。

## 概要

このディレクトリには以下のテストツールが含まれています:

1. **YAMLデータベース生成・ベンチマーク** (`yaml_database_generator.rb`)
   - `database.yaml`, `freeze.yaml`, `toc.yaml` などのテストデータ生成
   - 読み込み・検索・ソート・更新処理の性能測定

2. **小説データ生成・ベンチマーク** (`novel_data_generator.rb`)
   - `小説データ/` ディレクトリ配下の raw/txt ファイル生成
   - HTML→TXT変換、ファイル結合、読み込み処理の性能測定

3. **統合パフォーマンステスト** (`performance_test.rb`)
   - 上記2つを統合した総合テスト
   - 自動レポート生成と最適化推奨事項の提示

## クイックスタート

### 1. 簡易テスト（1000件）

```bash
# クイックテスト実行（データ生成→ベンチマーク→レポート生成）
ruby spec/performance/performance_test.rb quick

# レポート確認
cat performance_report.txt

# テストデータ削除
ruby spec/performance/performance_test.rb cleanup
```

### 2. フルテスト（50000件）

```bash
# フルテスト実行（データ生成→ベンチマーク→レポート生成）
# 注意: 数GB〜数十GBのディスク容量を使用します
ruby spec/performance/performance_test.rb full 50000

# 最適化推奨事項の分析
ruby spec/performance/performance_test.rb analyze

# テストデータ削除
ruby spec/performance/performance_test.rb cleanup
```

## 個別ツールの使い方

### YAMLデータベース生成・ベンチマーク

```bash
# テストデータ生成（50000件）
ruby spec/performance/yaml_database_generator.rb generate 50000

# 読み込みベンチマーク
ruby spec/performance/yaml_database_generator.rb benchmark-read

# 操作ベンチマーク（検索・ソート・更新）
ruby spec/performance/yaml_database_generator.rb benchmark-ops

# 全ベンチマーク実行
ruby spec/performance/yaml_database_generator.rb benchmark-all

# テストデータ削除
ruby spec/performance/yaml_database_generator.rb cleanup
```

### 小説データ生成・ベンチマーク

```bash
# テストデータ生成（1000件、デフォルト）
ruby spec/performance/novel_data_generator.rb generate

# テストデータ生成（50000件）
# 注意: 数十GBのディスク容量を使用します
ruby spec/performance/novel_data_generator.rb generate 50000

# HTML→TXT変換ベンチマーク
ruby spec/performance/novel_data_generator.rb benchmark-html

# TXTファイル結合ベンチマーク（EPUB変換向け）
ruby spec/performance/novel_data_generator.rb benchmark-concat

# ファイル読み込みベンチマーク
ruby spec/performance/novel_data_generator.rb benchmark-read

# 全ベンチマーク実行
ruby spec/performance/novel_data_generator.rb benchmark-all

# テストデータ削除
ruby spec/performance/novel_data_generator.rb cleanup
```

## 生成されるデータ

### YAMLデータベース

- **場所**: `.narou_perf_test/`
- **ファイル**:
  - `database.yaml`: 小説メタデータ（タイトル、著者、URL、統計情報など）
  - `freeze.yaml`: 凍結状態データ
  - `toc.yaml`: 目次データ（エピソード一覧）
- **サイズ例**: 50000件で約200-300MB

### 小説データ

- **場所**: `小説データ_perf_test/`
- **構造**:

  ```bash
  小説データ_perf_test/
  ├── 0/
  │   ├── raw/
  │   │   ├── 1.html
  │   │   ├── 2.html
  │   │   └── ...
  │   └── txt/
  │       ├── 1.txt
  │       ├── 2.txt
  │       └── ...
  ├── 1/
  │   ├── raw/
  │   └── txt/
  └── ...
  ```

- **規模パターン**:
  - 短編: 1話、約5000文字
  - 短編集: 3-10話、各3000文字
  - 中編: 30-100話、各5000文字
  - 長編: 100-300話、各6000文字
  - 大長編: 300-1000話、各7000文字
  - 超長編: 1000-3000話、各8000文字
  - 極長編: 3000-10000話、各5000文字
- **サイズ例**: 1000件で約500MB-2GB、50000件で数十GB

## ベンチマーク項目

### YAMLデータベース

1. **読み込み性能**
   - `database.yaml` の読み込み時間
   - `freeze.yaml` の読み込み時間
   - `toc.yaml` の読み込み時間

2. **操作性能**
   - ID検索（1000回）
   - タイトル検索（1000回）
   - タグフィルタリング（1000回）
   - 更新日時ソート（100回）
   - データ更新 + YAML書き込み（10回）

### 小説データ

1. **ファイル読み込み性能**
   - 1000ファイルの連続読み込み時間

2. **HTML→TXT変換性能**
   - 10小説分のHTML→TXT変換時間
   - 1ファイルあたりの変換時間

3. **TXTファイル結合性能**
   - 10小説分のエピソード結合時間（EPUB変換向け）
   - 1小説あたりの結合時間

## パフォーマンス目標値

以下は推奨される性能目標です:

### YAMLデータベース（50000件）

- 読み込み: 5秒以内
- ID検索（1000回）: 0.1秒以内
- タイトル検索（1000回）: 10秒以内
- ソート（100回）: 30秒以内
- 書き込み（10回）: 50秒以内

### 小説データ

- ファイル読み込み（1000件）: 5秒以内
- HTML→TXT変換（1ファイル）: 10ms以内
- TXTファイル結合（1小説）: 100ms以内

## 最適化推奨事項

パフォーマンステスト実行後、以下のような最適化が推奨される場合があります:

### 1. データベース最適化

**問題**: YAMLファイルサイズが大きく、読み込み・検索が遅い

**推奨**:
- SQLite や PostgreSQL などの RDBMS 導入
- インデックス機能によるクエリ高速化
- トランザクション処理による整合性保証

### 2. キャッシュ強化

**問題**: 頻繁なYAML読み込みでパフォーマンス低下

**推奨**:
- `Inventory.load` のキャッシュ機構強化
- メモリベースのキャッシュレイヤー追加
- LRU（Least Recently Used）キャッシュ戦略

### 3. 並列処理導入

**問題**: 大量データの一括処理に時間がかかる

**推奨**:
- マルチスレッド/プロセスによる並列変換
- バッチ処理のチャンク分割
- 非同期I/O活用

### 4. 圧縮形式サポート

**問題**: 大量の小説データによるディスク使用量

**推奨**:
- zstd 圧縮形式のサポート実装
- 透過的な圧縮・展開処理
- ストリーミング処理による メモリ効率化

## トラブルシューティング

### ディスク容量不足

```bash
# 現在の使用量を確認
du -sh .narou_perf_test 小説データ_perf_test

# 不要なデータを削除
ruby spec/performance/performance_test.rb cleanup
```

### メモリ不足

大量データ生成時にメモリ不足になる場合:

```bash
# 生成件数を減らす
ruby spec/performance/performance_test.rb full 10000

# または段階的に生成
ruby spec/performance/yaml_database_generator.rb generate 10000
ruby spec/performance/novel_data_generator.rb generate 2000
```

### 処理時間が長い

```bash
# クイックテストで先に確認
ruby spec/performance/performance_test.rb quick

# 個別ツールで段階的に実行
ruby spec/performance/yaml_database_generator.rb generate 10000
ruby spec/performance/yaml_database_generator.rb benchmark-all
```

## 注意事項

1. **ディスク容量**: 50000件のフルテストでは数十GB必要です
2. **実行時間**: フルテストは数分〜数十分かかる場合があります
3. **データ削除**: テスト後は必ず `cleanup` を実行してください
4. **本番環境**: 本番データと混在しないよう注意してください

## 関連ドキュメント

- [データベース構造ドキュメント](../../docs/database_structure.md)
- [小説データ構造ドキュメント](../../docs/novel_data_structure.md)
- [コマンド実行フロー](../../docs/command_execution_flows.md)

## ライセンス

このツールは Narou.rb MOD の一部として MIT ライセンスで提供されます。

