# API Migration Guide: Legacy API v1 → API v2

このドキュメントは、Narou.rb MOD の Legacy API (v1) から新しい REST API (v2) への移行ガイドです。

## 概要

### Legacy API (v1)
- **ベースパス**: `/api/`
- **設計思想**: 元々の Web UI 用に設計された内部 API
- **特徴**:
  - HTML レスポンスと JSON レスポンスが混在
  - エンドポイント命名が一貫していない
  - 一部のエンドポイントが同期/非同期処理を混在
  - DataTables 専用のレスポンス形式を含む

### API v2
- **ベースパス**: `/api/v2/`
- **設計思想**: RESTful 設計原則に準拠した外部公開可能な API
- **特徴**:
  - 一貫した JSON レスポンス
  - リソース指向のエンドポイント設計（novels, tags, settings, system）
  - HTTP メソッドの正しい使用（GET, POST, PUT, PATCH, DELETE）
  - 標準的なエラーハンドリング

## モジュール別対応表

### 1. System (システム管理)

| Legacy API v1 | API v2 | 説明 | 変更点 |
|--------------|--------|------|--------|
| `GET /api/version/current.json` | `GET /api/v2/system/version` | バージョン情報取得 | レスポンス形式を統一 |
| `GET /api/get_queue_size` | `GET /api/v2/system/queue` | キューサイズ取得 | エンドポイント名を明確化 |
| `POST /api/cancel` | - | キャンセル操作 | v2 では未実装（予定） |
| `GET /api/history` | - | 履歴取得 | v2 では未実装（予定） |
| `POST /api/clear_history` | - | 履歴クリア | v2 では未実装（予定） |
| `GET /api/sort_state` | - | ソート状態取得 | v2 では未実装（予定） |
| - | `GET /api/v2/system/status` | システム状態取得 | v2 で新規追加 |

### 2. Novels (小説管理)

| Legacy API v1 | API v2 | 説明 | 変更点 |
|--------------|--------|------|--------|
| `GET /api/novels/count` | `GET /api/v2/novels?count_only=true` | 小説総数取得 | クエリパラメータ化 |
| `GET /api/novels/all_ids` | `GET /api/v2/novels?fields=id` | 全 ID 取得 | クエリパラメータ化 |
| `GET /api/list`<br>`POST /api/list` | `GET /api/v2/novels` | 小説一覧取得 | RESTful 化、DataTables 依存を削除 |
| - | `GET /api/v2/novels/:id` | 単一小説取得 | v2 で新規追加（RESTful） |
| `POST /api/download` | `POST /api/v2/novels/download` | ダウンロード | リソース名を明確化 |
| `POST /api/download_force` | `POST /api/v2/novels/download?force=true` | 強制ダウンロード | クエリパラメータ化 |
| `POST /api/convert` | `POST /api/v2/novels/convert` | 変換 | リソース名を明確化 |
| `POST /api/update`<br>`POST /api/update_by_tag` | - | 更新 | v2 では未実装（予定） |
| `POST /api/freeze`<br>`POST /api/freeze_on`<br>`POST /api/freeze_off` | `POST /api/v2/novels/freeze` | 凍結操作 | 単一エンドポイントに統合 |
| `POST /api/remove`<br>`POST /api/remove_with_file` | `POST /api/v2/novels/remove` | 削除 | 単一エンドポイントに統合 |
| `GET /api/story` | - | あらすじ取得 | v2 では `/api/v2/novels/:id` に統合予定 |
| `POST /api/mail` | - | メール送信 | v2 では未実装（予定） |
| `POST /api/send` | - | 端末送信 | v2 では未実装（予定） |

### 3. Tags (タグ管理)

| Legacy API v1 | API v2 | 説明 | 変更点 |
|--------------|--------|------|--------|
| `GET /api/tag_list` | - | タグ一覧（HTML） | HTML レスポンスは廃止 |
| `GET /api/tag_list.json` | `GET /api/v2/tags` | タグ一覧（JSON） | エンドポイント名を統一 |
| `POST /api/taginfo.json` | `POST /api/v2/tags/info` | タグ情報取得 | エンドポイント名を明確化 |
| `POST /api/edit_tag` | `POST /api/v2/tags/edit` | タグ一括編集 | そのまま移行 |
| - | `POST /api/v2/tags/add` | タグ追加 | v2 で新規追加（明示的操作） |
| - | `POST /api/v2/tags/delete` | タグ削除 | v2 で新規追加（明示的操作） |
| `POST /api/change_tag_color` | `POST /api/v2/tags/color` | タグ色変更 | エンドポイント名を簡潔化 |

### 4. Settings (設定管理)

| Legacy API v1 | API v2 | 説明 | 変更点 |
|--------------|--------|------|--------|
| - | `GET /api/v2/settings` | 設定一覧取得 | v2 で新規追加 |
| - | `GET /api/v2/settings/variables` | 設定変数一覧 | v2 で新規追加 |
| - | `PUT /api/v2/settings` | 設定一括更新 | v2 で新規追加 |
| - | `PATCH /api/v2/settings` | 設定部分更新 | v2 で新規追加 |
| `POST /api/update_general_lastup` | - | 一般最新話更新 | v2 では未実装（予定） |
| `POST /api/setting_burn` | - | 設定焼き付け | v2 では未実装（予定） |

### 5. Novel Settings (小説個別設定)

| Legacy API v1 | API v2 | 説明 | 変更点 |
|--------------|--------|------|--------|
| - | `GET /api/v2/novels/:id/settings` | 小説設定取得 | v2 で新規追加 |
| - | `PUT /api/v2/novels/:id/settings` | 小説設定更新 | v2 で新規追加 |

### 6. Utilities (ユーティリティ)

| Legacy API v1 | API v2 | 説明 | 変更点 |
|--------------|--------|------|--------|
| `GET /api/notepad/read` | - | ノートパッド読み取り | v2 では未実装（予定） |
| `POST /api/notepad/save` | - | ノートパッド保存 | v2 では未実装（予定） |
| `POST /api/eject` | - | デバイス取り外し | v2 では未実装（予定） |
| `POST /api/diff` | - | 差分表示 | v2 では未実装（予定） |
| `GET /api/diff_list` | - | 差分一覧 | v2 では未実装（予定） |
| `POST /api/diff_clean` | - | 差分クリア | v2 では未実装（予定） |
| `POST /api/folder` | - | フォルダを開く | v2 では未実装（予定） |
| `POST /api/backup` | - | バックアップ | v2 では未実装（予定） |
| `POST /api/inspect` | - | インスペクト | v2 では未実装（予定） |
| `GET /api/csv/download` | - | CSV ダウンロード | v2 では未実装（予定） |
| `POST /api/csv/import` | - | CSV インポート | v2 では未実装（予定） |
| `GET /api/download4ssl` | - | SSL ダウンロード | v2 では未実装（予定） |
| `GET /api/downloadable.gif` | - | ダウンロード可否画像 | v2 では未実装（予定） |
| `GET /api/validate_url_regexp_list` | - | URL 正規表現検証 | v2 では未実装（予定） |

## レスポンス形式の違い

### Legacy API v1

成功レスポンス例（統一されていない）:
```json
// パターン1: プレーンなデータ
{
  "count": 42
}

// パターン2: success フラグ付き
{
  "success": true,
  "data": { ... }
}

// パターン3: DataTables 専用形式
{
  "draw": 1,
  "data": [...],
  "recordsTotal": 100,
  "recordsFiltered": 50
}
```

エラーレスポンス例（統一されていない）:
```json
// パターン1
{
  "error": "エラーメッセージ"
}

// パターン2
{
  "success": false,
  "error": "エラーメッセージ"
}
```

### API v2

成功レスポンス例（統一されたエンベロープ形式）:
```json
{
  "status": "success",
  "data": {
    // リソースデータ
  },
  "meta": {
    "timestamp": "2025-11-11T00:00:00Z",
    "request_id": "uuid-here"
  }
}
```

リスト取得時:
```json
{
  "status": "success",
  "data": [...],
  "meta": {
    "total": 100,
    "count": 20,
    "page": 1,
    "per_page": 20,
    "timestamp": "2025-11-11T00:00:00Z"
  }
}
```

エラーレスポンス例（統一された形式）:
```json
{
  "status": "error",
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "入力値が不正です",
    "details": {
      "field": "id",
      "reason": "必須項目です"
    }
  },
  "meta": {
    "timestamp": "2025-11-11T00:00:00Z",
    "request_id": "uuid-here"
  }
}
```

## HTTP ステータスコードの使用

### Legacy API v1
- 主に `200 OK` を使用
- エラー時も `200` で返すことがある（`success: false` で判定）
- 一部のエンドポイントで `400`, `404`, `500` を使用

### API v2（標準的な使用）
- `200 OK`: 成功（GET, PUT, PATCH）
- `201 Created`: リソース作成成功（POST）
- `204 No Content`: 成功、レスポンスボディなし（DELETE）
- `400 Bad Request`: リクエストパラメータ不正
- `404 Not Found`: リソースが存在しない
- `422 Unprocessable Entity`: バリデーションエラー
- `500 Internal Server Error`: サーバー内部エラー

## 移行戦略

### フェーズ1: 並行運用（現在）
- Legacy API v1 と API v2 を両方提供
- 新規開発は API v2 を使用
- 既存の Web UI は Legacy API v1 を継続使用

### フェーズ2: 段階的移行
1. フロントエンド（Astro UI）を API v2 に移行
2. Legacy API v1 の使用状況をモニタリング
3. 未実装の v2 エンドポイントを順次追加

### フェーズ3: 非推奨化
- Legacy API v1 を非推奨（Deprecated）としてマーク
- ドキュメントで移行を推奨
- 猶予期間を設定

### フェーズ4: 廃止（将来）
- Legacy API v1 を完全に削除
- API v2 のみに統一

## 開発者向けガイドライン

### API v2 を使用すべき場合
- ✅ 新規機能の開発
- ✅ 外部ツールからの API 利用
- ✅ モバイルアプリ等の新規クライアント開発
- ✅ 長期的なメンテナンス性を重視する場合

### Legacy API v1 を使用する場合
- ⚠️ 既存の Web UI の一時的な保守（移行までの間）
- ⚠️ 緊急の不具合修正

### 推奨事項
1. 新規開発は必ず API v2 を使用する
2. Legacy API v1 を使用する場合は、移行計画を立てる
3. API v2 で不足している機能があれば、Issue を作成して提案する
4. エンドポイントの追加や変更は必ずテストを書く

## 関連ドキュメント

- [Web API Endpoints](./web_api_endpoints.md) - Legacy API v1 の完全な一覧
- [API Reference (TBD)](./api_reference.md) - API v2 の詳細リファレンス（予定）
- [OpenAPI Specification (TBD)](./openapi.yaml) - API v2 の OpenAPI 仕様書（予定）

## 変更履歴

- 2025-11-11: 初版作成（Legacy API v1 の System, Tags, Settings 分離完了時点）
