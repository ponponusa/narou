# Legacy Web UI 機能一覧

このドキュメントは、Legacy Web UI（Sinatra + HAML版）の機能を整理したリファレンスです。新しいSvelte/Astro版Web UIの開発時に参照してください。

## アーキテクチャ概要

- **フレームワーク**: Sinatra（Ruby製Webフレームワーク）
- **テンプレートエンジン**: HAML
- **スタイル**: Bootstrap 3 + SCSS
- **リアルタイム通信**: WebSocket（PushServer）
- **主要ファイル**:
  - `lib/web/appserver.rb`: メインサーバー、ルーティング定義
  - `lib/web/views/*.haml`: HAMLテンプレート
  - `lib/web/public/`: 静的ファイル（JS、CSS、画像等）
  - `lib/web/api/`: APIエンドポイント（v1: Legacy、v2: Modern REST）

## ページ構成

### 1. メインページ (`/`)

**ファイル**: `lib/web/views/index.haml`

#### ヘッダーナビゲーション

**表示メニュー**:

- 全ての項目を表示 / 表示する項目を設定
- 小説リストの幅を広げる（ショートカット: `W`）
- 凍結中以外を表示（ショートカット: `Shift+F`）
- 凍結中を表示（ショートカット: `F`）
- 変換設定ページは新規タブで開く
- ボタンをページ上部に表示
- ボタンを画面下部に表示
- 個別メニューを編集
- 個別メニューの表示スタイルを選択
- 表示設定を全てリセット

**選択メニュー**:

- 表示されている小説を選択（ショートカット: `Ctrl+A`）
- 全ての小説を選択（ショートカット: `Shift+A`）
- 選択を全て解除（ショートカット: `ESC`）
- シングル選択モード（ショートカット: `S`）
- 範囲選択モード（ショートカット: `R`）
- ハイブリッド選択モード（ショートカット: `H`）

**タグメニュー**:

- タグ一覧表示
- 選択した小説のタグを編集（ショートカット: `T`）

**ツールメニュー**:

- D&Dウィンドウを開く
- CSV形式でリストをダウンロード
- CSVファイルからインポート
- メモ帳（別ページ）
- メモ帳（ポップアップ）

**オプションメニュー**:

- 環境設定...
- ヘルプ...
- Narou.rb について
- サーバを再起動
- サーバをシャットダウン

#### キューインジケーター

リアルタイムでタスクキューの状態を表示：

- 実行中タスク数
- 待機中タスク数
- キャンセルボタン（全処理中断）

#### コンソールパネル

- コマンド実行ログのリアルタイム表示
- 並行処理（concurrency）有効時は2カラム表示
- 操作ボタン:
  - 処理を中断
  - 全ての履歴を取得
  - 表示と履歴を削除
  - 拡大/縮小

#### 操作パネル（コントロールパネル）

**Download**:

- 新規ダウンロード
- 選択した小説を強制再ダウンロード

**Update**:

- 選択した小説を更新
- 最新話掲載日を確認
- タグを指定して更新
- 表示されている小説を更新
- 凍結済みでも更新

**クイック更新ボタン**:

- 最新話掲載日をなろうAPIで確認（`な`ボタン）
- その他の小説の最新話掲載日を確認（`他`ボタン）
- modifiedタグが付いた小説を更新（更新アイコン）

**Send**:

- 選択した小説を端末に送信
- hotentryを送信
- 端末の栞データをバックアップ

**Freeze**:

- 選択した小説を凍結
- 選択した小説の凍結を解除

**Remove**:

- 選択した小説を削除

**Convert**:

- 選択した小説を変換

**Other**:

- 選択した小説の最新の差分を表示
- 選択した小説の調査状況ログを表示
- 選択した小説の保存フォルダを開く
- 選択した小説のバックアップを作成
- 選択した小説の設定の未設定項目に共通設定を焼付ける
- 選択した小説をメールで送信

**Eject**:

- 端末を取り出す
- 今すぐ端末を取り出す

#### 小説一覧テーブル

- DataTableベースの動的テーブル
- パフォーマンスモード: 大量データ時の軽量表示
- フィルター機能: テキスト検索
- 各小説の詳細情報表示:
  - ID、タイトル、著者、サイト名
  - 更新日時、最新話掲載日
  - タグ（カラーラベル表示）
  - フリーズ状態
  - 各種アクション（設定、ダウンロード、作者コメント等）

#### コンテキストメニュー

**範囲選択メニュー**:

- 選択
- 解除
- 反転
- キャンセル

**タグカラー選択メニュー**:

- Green、Yellow、Blue、Magenta、Cyan、Red、White

### 2. 環境設定ページ (`/settings`)

**ファイル**: `lib/web/views/settings.haml`

**タブ構成**:

- 基本設定
- ダウンロード設定
- 変換設定
- 更新設定
- デバイス設定
- メール設定
- サーバー設定
- その他設定
- 置換設定

**機能**:

- グローバル設定（全小説共通）の編集
- ローカル設定（カレントディレクトリ固有）の編集
- 置換パターンの設定（正規表現サポート）
- リアルタイム設定検証
- 保存時のエラー表示
- サーバー再起動ボタン

### 3. ヘルプページ (`/help`)

**ファイル**: `lib/web/views/help.haml`

**コンテンツ**:

- ブックマークレット機能説明
  - 「Narou.rb MODでダウンロード」ブックマークレット
  - 「メールで送信」ブックマークレット
  - ダウンロードボタン挿入ブックマークレット
- 操作説明
- ショートカットキー一覧
- FAQ

### 4. メモ帳ページ (`/notepad`)

**ファイル**: `lib/web/views/notepad.haml`

**機能**:

- 簡易テキストエディタ
- 自動保存（サーバー側に保存）
- リアルタイム同期（WebSocket経由）
- 複数ブラウザ間で同期

### 5. 個別メニュー編集ページ (`/edit_menu`)

**ファイル**: `lib/web/views/edit_menu.haml`

**機能**:

- 小説一覧の各行に表示するカスタムメニューの編集
- メニューラベルとコマンドの組み合わせ設定
- ライブプレビュー機能
- テンプレートから選択機能

### 6. 小説個別設定ページ (`/novels/:id/setting`)

**ファイル**: `lib/web/views/novels/setting.haml`

**機能**:

- 個別小説の`setting.ini`編集
- 未設定項目には共通設定が適用される旨の説明表示
- force設定による上書き状態の視覚的表示
- 置換パターン設定
- この小説を変換ボタン
- フォルダを開くボタン
- コンソール表示（変換時）

### 7. 小説ダウンロード情報ページ (`/novels/:id/download`)

小説のダウンロード履歴や詳細情報を表示するページ（詳細は個別ファイル確認が必要）。

### 8. 作者コメントページ (`/novels/:id/author_comments`)

**ファイル**: `lib/web/views/novels/author_comments.haml`

作者のコメント（あとがき、前書き等）を表示するページ。

## API エンドポイント

### API v1 (Legacy)

**システム関連** (`lib/web/api/v1/system.rb`):

- `POST /api/cancel` - タスクキャンセル
- `GET /api/get_queue_size` - キューサイズ取得
- `GET /api/history` - コマンド履歴取得
- `POST /api/clear_history` - 履歴クリア
- `GET /api/version/current.json` - 現在のバージョン
- `GET /api/version/latest.json` - 最新バージョン確認
- `GET /api/sort_state` - ソート状態
- `GET /api/server/status` - サーバーステータス
- `POST /api/server/restart` - サーバー再起動
- `POST /api/server/stop` - サーバー停止

**設定関連** (`lib/web/api/v1/settings.rb`):

- `POST /api/update_general_lastup` - 最新話掲載日更新
- `POST /api/setting_burn` - 設定の焼付け

**タグ関連** (`lib/web/api/v1/tags.rb`):

- `GET /api/tag_list` - タグ一覧（HTML）
- `GET /api/tag_list.json` - タグ一覧（JSON）
- `POST /api/taginfo.json` - タグ情報取得
- `POST /api/edit_tag` - タグ編集
- `POST /api/change_tag_color` - タグカラー変更

**小説操作関連** (`lib/web/api/v1/novels.rb`):

- `GET /api/list` - 小説一覧取得（GET）
- `POST /api/list` - 小説一覧取得（POST、フィルター付き）
- `POST /api/convert` - 変換実行
- `POST /api/download` - ダウンロード実行
- `POST /api/download_force` - 強制再ダウンロード
- `POST /api/mail` - メール送信
- `POST /api/update` - 更新実行
- `POST /api/update_by_tag` - タグ指定更新
- `POST /api/send` - 端末送信
- `POST /api/backup_bookmark` - 栞バックアップ
- `POST /api/freeze` - フリーズ切替
- `POST /api/freeze_on` - フリーズON
- `POST /api/freeze_off` - フリーズOFF
- `POST /api/remove` - 削除
- `POST /api/remove_with_file` - ファイルごと削除
- `GET /api/story` - ストーリー情報取得

**ユーティリティ関連** (`lib/web/api/v1/utilities.rb`):

- `GET /api/notepad/read` - メモ帳読込
- `POST /api/notepad/save` - メモ帳保存
- `POST /api/eject` - 端末取り出し
- `POST /api/diff` - 差分表示
- `GET /api/diff_list` - 差分リスト
- `POST /api/diff_clean` - 差分クリーンアップ
- `POST /api/folder` - フォルダを開く
- `POST /api/backup` - バックアップ作成
- `POST /api/inspect` - 調査ログ表示
- `GET /api/csv/download` - CSV出力
- `POST /api/csv/import` - CSVインポート
- `GET /api/download4ssl` - SSL経由ダウンロード
- `GET /api/downloadable.gif` - ダウンロード可能判定画像
- `GET /api/validate_url_regexp_list` - URL正規表現バリデーション

### API v2 (Modern REST)

**小説関連** (`lib/web/api/v2/novels.rb`):

- `GET /api/v2/novels` - 小説一覧
- `GET /api/v2/novels/:id` - 小説詳細
- `POST /api/v2/novels/download` - ダウンロード
- `POST /api/v2/novels/update` - 更新
- `POST /api/v2/novels/convert` - 変換
- `POST /api/v2/novels/freeze` - フリーズ操作
- `POST /api/v2/novels/send` - 送信
- `DELETE /api/v2/novels/:id` - 削除
- `GET /api/v2/novels/:id/story` - ストーリー詳細

**小説設定関連** (`lib/web/api/v2/novel_settings.rb`):

- `GET /api/v2/novels/:id/settings` - 設定取得
- `PUT /api/v2/novels/:id/settings` - 設定更新

**システム関連** (`lib/web/api/v2/system.rb`):

- `GET /api/v2/system/version` - バージョン情報
- `GET /api/v2/system/queue` - キュー情報
- `GET /api/v2/system/status` - システムステータス
- `POST /api/v2/cancel` - 全キャンセル
- `POST /api/v2/console/clear` - コンソールクリア
- `POST /api/v2/server/stop` - サーバー停止
- `POST /api/v2/server/restart` - サーバー再起動

**タグ関連** (`lib/web/api/v2/tags.rb`):

- `GET /api/v2/tags` - タグ一覧
- `POST /api/v2/tags/info` - タグ情報
- `POST /api/v2/tags/edit` - タグ編集
- `POST /api/v2/tags/add` - タグ追加
- `POST /api/v2/tags/delete` - タグ削除
- `POST /api/v2/tags/color` - タグカラー変更

**設定関連** (`lib/web/api/v2/settings.rb`):

- `GET /api/v2/settings` - 全設定取得
- `GET /api/v2/settings/variables` - 設定変数定義取得
- `PUT /api/v2/settings` - 設定更新

**タスク関連** (`lib/web/api/v2/tasks.rb`):

- `GET /api/v2/tasks` - タスク一覧
- `GET /api/v2/tasks/summary` - タスクサマリー
- `GET /api/v2/tasks/:id` - タスク詳細
- `POST /api/v2/tasks/:id/cancel` - タスクキャンセル
- `POST /api/v2/tasks/:id/pause` - タスク一時停止
- `POST /api/v2/tasks/:id/resume` - タスク再開

## ウィジェット機能

**ダウンロードウィジェット** (`/widget/download`):

- ブックマークレットからの小説ダウンロード
- URL指定ダウンロード

**D&Dウィジェット** (`/widget/drag_and_drop`):

- ドラッグ＆ドロップによる小説追加
- ポップアップウィンドウ表示

**メモ帳ウィジェット** (`/widget/notepad`):

- ポップアップメモ帳
- リアルタイム同期

## パーシャル（部分テンプレート）

- `_header.haml`: 共通ヘッダー
- `_queue.haml`: キューインジケーター
- `_about.haml`: アバウトダイアログ
- `_diff_list.haml`: 差分リスト表示
- `_edit_replace_txt.haml`: 置換テキスト編集
- `_move_to_top.haml`: トップへ移動ボタン
- `_rebooting.haml`: 再起動中メッセージ
- `partial/csv_import.haml`: CSVインポートフォーム
- `partial/download_form.haml`: ダウンロードフォーム

## JavaScript機能（主要なもの）

**ファイル**: `lib/web/public/resources/` 配下

- **Narou.Action**: 各種操作（ダウンロード、更新、変換等）の実行
- **Narou.Console**: コンソール表示管理
- **Narou.Notification**: プッシュ通知管理（WebSocket）
- **Narou.Storage**: localStorage管理
- **Narou.ContextMenu**: カスタムコンテキストメニュー
- **Narou.Template**: テンプレート処理
- **Narou.Notepad**: メモ帳機能
- **DataTable**: 小説一覧テーブルの動的表示・フィルタリング・ソート

## リアルタイム通信（WebSocket）

**PushServer** (`lib/web/pushserver.rb`):

- サーバー→クライアント間のリアルタイム通信
- イベント配信機能
- 主要イベント:
  - `console.push`: コンソールログ配信
  - `server.rebooted`: サーバー再起動通知
  - `server.update.*`: システム更新通知
  - `device.ejectable`: デバイス取り出し可能状態通知
  - `queue.size`: キューサイズ更新通知
  - `notepad.sync`: メモ帳同期通知

## 認証機能

- **Basic認証**: `server-basic-auth.enable`で有効化
- ユーザー名・パスワードは`global_setting`に保存
- 全ページに適用（Rack::Auth::Basic使用）

## CORS設定

- APIエンドポイント（`/api`配下）に対してCORSヘッダーを付与
- `Access-Control-Allow-Origin: *`
- 新しいフロントエンド（Astro/Svelte）との連携を想定

## 静的ファイル配信

- `lib/web/public/`: Legacy UI用静的ファイル
  - `resources/`: JavaScript、CSS、画像
  - `theme/`: テーマファイル（Bootstrap）
  - `swagger-ui/`: Swagger UI
  - `favicon.ico`, `robots.txt`

## パフォーマンス最適化

- **大量データ対応**:
  - パフォーマンスモード（軽量表示）
  - DataTableのページネーション
  - タグ表示の簡素化
- **Bootsnap対応**: Ruby起動高速化（オプション）

## 開発モード機能

- Sinatra::Reloader: 自動リロード
- BetterErrors: エラー画面拡張（デバッグ時）

## 移行ガイド（Legacy → 新UI）

### 実装済み機能（新UI側）

- 小説一覧表示（NovelList.svelte）
- タスクキュー管理（TaskQueuePage.svelte）
- 環境設定（SettingsPage.svelte）
- API v2エンドポイント活用

### 未実装/要検討機能（新UI側）

- ブックマークレット機能
- D&Dウィンドウ
- メモ帳（リアルタイム同期）
- 個別メニュー編集
- 作者コメント表示
- 差分表示機能
- CSV インポート/エクスポート
- ショートカットキー対応
- コンテキストメニュー（右クリックメニュー）
- 範囲選択モード/ハイブリッド選択モード
- コンソールログのリアルタイム表示（並行処理対応）

### 新UIでの設計方針

- API v2を優先的に使用（RESTful設計）
- WebSocketはPushServerを活用（リアルタイム通知）
- Svelte 5のReactive仕組み（`$state`, `$derived`）を活用
- Tailwind CSS v4でスタイリング（Bootstrapから移行）
- TypeScript + 型安全なAPI呼び出し

## まとめ

Legacy Web UIは非常に多機能で、以下の特徴があります：

1. **豊富な操作機能**: ダウンロード、更新、変換、送信、削除等の全操作に対応
2. **高度な選択機能**: 複数選択、範囲選択、タグ指定等、柔軟な小説選択
3. **リアルタイム性**: WebSocketによるコンソールログ配信、メモ帳同期
4. **カスタマイズ性**: 個別メニュー、置換設定、表示設定等、高いカスタマイズ性
5. **ブックマークレット**: ブラウザから直接ダウンロード可能
6. **CSV連携**: エクスポート・インポート機能
7. **デバイス連携**: Kindle等への送信、栞バックアップ

新しいSvelte/Astro版Web UIでは、これらの機能を段階的に移行・再実装していく必要があります。優先度の高い機能（小説一覧、ダウンロード、更新、変換、設定）は既に実装済みまたは実装中です。
