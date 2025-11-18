# データベース構造ドキュメント

## 概要

Narou.rb MOD は、ローカルファイルシステム上に YAML 形式でデータを保存する軽量なデータベースシステムを使用しています。データベースの実装は `lib/database.rb` および `lib/inventory.rb` にあります。

## データベースファイル

- **ファイル名**: `database.db`（YAML形式）
- **保存場所**: プロジェクトルート直下
- **管理クラス**: `Database`（シングルトン）、`Inventory`
- **データ構造**: Hash（キー: 小説ID（整数）、値: 小説データ（Hash））

## 小説データのスキーマ

各小説は以下のフィールドを持つHashとしてデータベースに格納されます。

### 基本情報

| フィールド名 | 型 | 必須 | 説明 |
|------------|-----|------|------|
| `id` | Integer | ○ | 小説の一意識別子（自動採番） |
| `title` | String | ○ | 小説のタイトル |
| `author` | String | ○ | 作者名 |
| `file_title` | String | ○ | ファイルシステム上のディレクトリ名（Nコード + タイトル） |
| `toc_url` | String | ○ | 目次ページのURL |
| `sitename` | String | ○ | 掲載サイト名（例: "小説家になろう"） |
| `ncode` | String | - | サイト固有の識別コード（例: "n9669bk"） |

### 掲載サイト情報

| フィールド名 | 型 | 必須 | 説明 |
|------------|-----|------|------|
| `author_url` | String | - | 作者ページのURL（`lib/web/appserver.rb`で生成） |
| `site_top_url` | String | - | サイトトップページのURL（`toc_url`から生成） |

### 小説種別・状態

| フィールド名 | 型 | 必須 | 説明 |
|------------|-----|------|------|
| `novel_type` | Integer | ○ | 小説種別（`1`: 連載、`2`: 短編） |
| `end` | Boolean | - | 完結フラグ（`true`: 完結、`false`/`nil`: 未完結） |
| `frozen` | Boolean | - | 凍結フラグ（`true`で自動更新停止） |

### タグ・カテゴリ

| フィールド名 | 型 | 必須 | 説明 |
|------------|-----|------|------|
| `tags` | Array<String> | - | ユーザー定義タグ + 自動タグ（例: `["end", "404", "modified"]`） |

**自動タグの種類**:
- `end`: 完結済み
- `404`: 削除済み/非公開
- `modified`: ユーザーが手動で編集

### 日時情報

| フィールド名 | 型 | 必須 | 説明 |
|------------|-----|------|------|
| `last_update` | Time | ○ | ローカルでの最終更新日時 |
| `general_firstup` | Time | - | 初回掲載日時（サイトから取得） |
| `general_lastup` | Time | - | 最新話掲載日時（サイトから取得） |
| `novelupdated_at` | Time | - | サイト上での小説情報更新日時 |
| `new_arrivals_date` | Time | - | 新規追加日時 |
| `download_date` | Time | - | 最終ダウンロード日時 |
| `convert_date` | Time | - | 最終EPUB変換日時 |
| `send_date` | Time | - | 最終デバイス送信日時 |
| `newest_article_date` | Time | - | 最新話の掲載日時 |

### 数値情報

| フィールド名 | 型 | 必須 | 説明 |
|------------|-----|------|------|
| `general_all_no` | Integer | - | 総話数（連載のみ） |
| `length` | Integer | - | 総文字数 |

### その他のメタデータ

| フィールド名 | 型 | 必須 | 説明 |
|------------|-----|------|------|
| `story` | String | - | あらすじ・説明文 |
| `use_subdirectory` | Boolean | - | サブディレクトリ使用フラグ |
| `title_original` | String | - | プロモタグ除去前の元タイトル |
| `title_raw_latest` | String | - | 最新の生タイトル |
| `author_original` | String | - | プロモタグ除去前の元作者名 |
| `promo_tags` | Array<String> | - | 抽出されたプロモタグリスト |
| `promo_tags_title` | String | - | タイトルから抽出されたプロモタグ |
| `promo_tags_author` | String | - | 作者名から抽出されたプロモタグ |
| `info` | Hash | - | サイトAPIから取得した生の情報 |

## データベース操作API

### Databaseクラス（`lib/database.rb`）

```ruby
# シングルトンインスタンス取得
database = Database.instance

# データの取得
novel_data = database[id]                    # IDでアクセス
novel_data = database.get_data("title", "タイトル")  # フィールドで検索

# データの保存
database[id] = novel_data
database.save_database

# 存在確認
database.novel_exists?(id)  # => true/false

# 全IDの取得
database.ids  # => [1, 2, 3, ...]

# ソート
sorted_novels = database.sort_by("last_update", reverse: true)

# タグインデックスの取得
tag_index = database.tag_indexies  # => { "end" => [1, 5, 10], ... }
```

### よく使われるクエリパターン

```ruby
# 未完結の連載小説を取得
database.each_value do |data|
  next unless data["novel_type"] == 1
  next if data["end"] == true
  # 処理...
end

# 凍結されていない小説を取得
database.each_key do |id|
  next if Narou.novel_frozen?(id)
  # 処理...
end

# 特定タグの小説を取得
database.each_value do |data|
  tags = data["tags"] || []
  next unless tags.include?("end")
  # 処理...
end
```

## データの永続化

- **自動保存**: `Downloader`クラスでダウンロードや更新が完了すると自動的に保存
- **手動保存**: `database.save_database` メソッドで明示的に保存
- **保存形式**: YAML（`Inventory.save`経由）
- **バックアップ**: なし（必要に応じて手動でバックアップを推奨）

## 注意事項

1. **シングルトンパターン**: `Database`クラスはシングルトンのため、`Database.instance`でアクセス
2. **保存タイミング**: データを変更したら必ず`save_database`を呼ぶこと
3. **型の柔軟性**: YAMLベースのため、フィールドの存在確認（`data["field"]`）が重要
4. **日時フィールド**: `Time`オブジェクトとして保存（YAMLでシリアライズ可能）
5. **IDの自動採番**: `database.create_new_id`で自動生成（最大ID + 1）

## 関連ファイル

- `lib/database.rb`: メインのDatabaseクラス
- `lib/inventory.rb`: YAML永続化レイヤー
- `lib/downloader.rb`: データベース更新ロジック（`update_database`メソッド）
- `lib/novelinfo.rb`: サイトAPIとのデータ変換
- `lib/sitesetting.rb`: サイト固有の設定管理

## データベースの初期化

```ruby
# データベースディレクトリの初期化
Database.init

# 小説データ格納ディレクトリのパス
Database.archive_root_path  # => ".../小説データ/"
```

## API v2でのデータマッピング

`lib/web/api/v2/novels.rb`でデータベースのフィールドをAPI v2のレスポンスにマッピング:

```ruby
{
  id: data["id"],
  title: data["title"],
  author: data["author"],
  author_url: data["author_url"],     # 追加フィールド
  site_name: data["sitename"],
  site_top_url: site_top_url,          # 追加フィールド（動的生成）
  toc_url: data["toc_url"],
  novel_type: data["novel_type"],
  tags: data["tags"] || [],
  frozen: Narou.novel_frozen?(data["id"]),
  updated_at: data["last_update"],
  created_at: data["new_arrivals_date"]
}
```

## 今後の拡張予定

- SQLiteへの移行検討（パフォーマンス改善）
- インデックス機能の強化
- データベースマイグレーション機構
- 自動バックアップ機能
