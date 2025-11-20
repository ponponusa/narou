# Astro版 Web UI 機能一覧（現時点）

このドキュメントは、Astro + Svelte 5 + Tailwind CSS v4で実装された新しいWeb UIの機能を整理したリファレンスです。

**最終更新日**: 2025-11-20

## アーキテクチャ概要

- **フロントエンドフレームワーク**: Astro 5.15.4 + Svelte 5.43.5
- **スタイリング**: Tailwind CSS v4.1.17
- **言語**: TypeScript 5.9.3
- **状態管理**: Svelte 5 Runes（`$state`, `$derived`, `$effect`）
- **リアルタイム通信**: WebSocket（PushServerClient）
- **主要ディレクトリ**:
  - `frontend/src/pages/`: Astroページ定義
  - `frontend/src/components/`: Svelteコンポーネント
  - `frontend/src/lib/`: API・ユーティリティ
  - `frontend/src/layouts/`: 共通レイアウト
  - `frontend/src/styles/`: グローバルCSS

## ページ構成

### 1. メインページ (`/`)

**ファイル**: `frontend/src/pages/index.astro`

**コンポーネント構成**:

- `Header.svelte`: ヘッダーナビゲーション
- `ServerStoppedBanner.svelte`: サーバー停止バナー
- `NovelList.svelte`: 小説一覧メインコンポーネント
- `ConsolePanel.svelte`: コンソールログ表示
- `Footer.svelte`: フッター

**主要機能**:

- 小説一覧表示（テーブル形式）
- 複数選択機能（チェックボックス）
- フィルタリング・検索
- ページネーション
- ソート機能（各カラムヘッダークリック）
- レスポンシブ対応

### 2. タスクキューページ (`/tasks`)

**ファイル**: `frontend/src/pages/tasks.astro`

**コンポーネント構成**:

- `Header.svelte`
- `ServerStoppedBanner.svelte`
- `TaskQueuePage.svelte`: タスクキュー管理
- `ConsolePanel.svelte`
- `Footer.svelte`

**主要機能**:

- タスク一覧表示（実行中、待機中、一時停止、完了、失敗）
- タスクサマリーカード（5種類）
  - 実行中タスク数
  - 待機中タスク数
  - 一時停止中タスク数
  - 完了タスク数
  - 失敗タスク数
- サマリーカードクリックでフィルタリング
- 検索機能（novel_id、タイトル、著者で検索）
- ステータスフィルタ
- ソート機能（デフォルト: ステータス降順）
- タスク操作:
  - キャンセル
  - 一時停止
  - 再開
- カラム表示:
  - ID
  - タスクID
  - novel_id
  - 種別（ダウンロード、変換、更新等）
  - ステータス
  - タイトル
  - 著者
  - 開始日時（2行表示）
  - 終了日時（2行表示）
  - アクション
- ページネーション

### 3. 環境設定ページ (`/settings`)

**ファイル**: `frontend/src/pages/settings.astro`

**コンポーネント構成**:

- `Header.svelte`
- `ServerStoppedBanner.svelte`
- `Settings.svelte`: 設定編集コンポーネント
- `ConsolePanel.svelte`
- `Footer.svelte`

**主要機能**:

- タブ切り替え（ローカル設定 / グローバル設定）
- 設定項目の編集
  - テキスト入力
  - チェックボックス
  - セレクトボックス
  - 数値入力
- 設定保存（API v2経由）
- バリデーション・エラー表示
- 設定リセット機能

### 4. ヘルプページ (`/help`)

**ファイル**: `frontend/src/pages/help.astro`

**コンポーネント構成**:

- `Header.svelte`
- `ServerStoppedBanner.svelte`
- `ConsolePanel.svelte`
- `Footer.svelte`

**現状**: Under Construction（準備中）

**予定機能**:

- 操作説明
- ショートカットキー一覧
- FAQ
- ドキュメントリンク

### 5. デバッグ設定ページ (`/settings-debug`)

**ファイル**: `frontend/src/pages/settings-debug.astro`

**用途**: 開発者向けデバッグ用設定ページ

## 主要コンポーネント詳細

### Header.svelte

**機能**:

- ナビゲーションバー
- バージョン情報表示
- Bootsnap状態インジケーター
- タスクキューサイズ表示
- ダークモード切替（ThemeToggle）
- パワーメニュー（PowerMenu）
  - サーバー再起動
  - サーバー停止
- モバイルメニュー（MobileMenu）
- Aboutモーダル（AboutModal）
- ヘルプメニュー
- PushServer接続状態表示

### NovelList.svelte

**機能**:

- 小説一覧テーブル表示
- 複数選択機能（全選択、選択解除）
- アクションバー:
  - 新規追加（AddNovelModal）
  - ダウンロード
  - 更新
  - 変換
  - タグ編集（TagModal）
  - 凍結/解凍
  - 削除
  - CSV出力
- 検索・フィルタフォーム（折りたたみ可能）:
  - テキスト検索（タイトル、著者、あらすじ）
  - タグフィルタ
  - サイトフィルタ
  - ステータスフィルタ
  - 表示件数設定
  - ソート設定
- 列表示設定モーダル
  - 各カラムの表示/非表示切替
  - デバイスサイズに応じたデフォルト
- 各小説行の操作:
  - 詳細表示（NovelDetailModal）
  - ダウンロード
  - 変換設定（ConversionSettingsModal）
  - 更新
  - 凍結/解凍
  - EPUB出力
  - 削除
- タグ表示（カラーバッジ）
- ステータス表示（凍結、短編、連載中、完結等）
- ページネーション
- スクロールトップボタン
- 確認ダイアログ（削除時）
- ローディング・エラー表示
- リトライ機能（初回ロード時）
- PushServerイベント連携（novel.update、novel.insert）

### TaskQueuePage.svelte

**機能**:

- タスク一覧テーブル表示
- タスクサマリーカード（5種類、クリック可能）
- 検索フォーム（折りたたみ可能）:
  - novel_id / タイトル / 著者検索
  - ステータスフィルタ
  - 表示件数設定
  - ソート設定
- カラムヘッダーソート（クリック切替）
- タスク操作（アクションボタン）:
  - キャンセル
  - 一時停止
  - 再開
- 日時の2行表示（日付 + 時刻）
- ステータスバッジ表示
- ページネーション
- ローディング・エラー表示
- PushServerイベント連携（task.created、task.updated、task.completed、task.failed）

### Settings.svelte

**機能**:

- タブ切り替え（ローカル / グローバル）
- 設定カテゴリー別表示
- 動的フォーム生成（型に応じた入力フィールド）
- 保存ボタン
- リセットボタン
- バリデーション・エラー表示
- トースト通知

### ConsolePanel.svelte

**機能**:

- コンソールログのリアルタイム表示
- PushServerからのログ受信
- スクロール自動追従
- 折りたたみ/展開
- クリアボタン
- ANSI colorコード対応（予定）

### AddNovelModal.svelte

**機能**:

- モーダルダイアログ
- URL入力フィールド
- 追加ボタン
- キャンセルボタン
- バリデーション
- API連携（addNovel）

### TagModal.svelte

**機能**:

- モーダルダイアログ
- 選択中小説のタグ一覧表示
- タグの追加/削除
- タグカラー変更
- 保存ボタン
- API連携（getTagInfo、editTags、setTagColors）

### ConversionSettingsModal.svelte

**機能**:

- モーダルダイアログ
- 個別小説の変換設定編集
- setting.iniの表示・編集
- 保存ボタン
- API連携（NovelSettings API）

### NovelDetailModal.svelte

**機能**:

- モーダルダイアログ
- 小説の詳細情報表示:
  - タイトル、著者、サイト名
  - あらすじ
  - 話数、文字数、平均文字数
  - 更新日、最新話掲載日
  - タグ
  - ステータス
- 閉じるボタン

### ServerStoppedBanner.svelte

**機能**:

- サーバー停止時の警告バナー表示
- 再接続試行メッセージ
- 状態管理（isServerStopped store）

### PowerMenu.svelte

**機能**:

- ドロップダウンメニュー
- サーバー再起動
- サーバー停止
- 確認モーダル（ServerActionModal）
- API連携（restartServer、stopServer）

### ThemeToggle.svelte

**機能**:

- ライト/ダークモード切替
- アイコン表示（太陽/月）
- localStorage保存

### Toast.svelte

**機能**:

- トースト通知表示
- 成功/エラー/情報メッセージ
- 自動消去（3秒）
- アイコン表示

### LoadingScreen.svelte

**機能**:

- 全画面ローディングオーバーレイ
- スピナーアニメーション
- メッセージ表示

## API連携（lib/api.ts）

### 小説操作API

- `getNovels(params?)` - 小説一覧取得（フィルタ・ソート対応）
- `getNovel(id)` - 小説詳細取得
- `getNovelsCount()` - 小説総数取得
- `getAllNovelIds()` - 全小説ID取得
- `downloadNovels(targets, force)` - 複数ダウンロード
- `addNovel(url, force)` - 新規追加
- `downloadNovel(id, force)` - 個別ダウンロード
- `convertNovels(ids)` - 複数変換
- `convertNovel(id)` - 個別変換
- `updateNovels(ids?)` - 更新
- `removeNovels(ids, withFile)` - 複数削除
- `removeNovel(id, withFile)` - 個別削除
- `deleteNovel(id)` - 削除（API v2）
- `toggleFreeze(ids)` - 凍結トグル
- `freezeNovel(id)` - 凍結
- `unfreezeNovel(id)` - 凍結解除
- `getNovelStory(id)` - あらすじ取得
- `downloadEpub(id)` - EPUB出力

### タグ操作API

- `getTagList()` - タグ一覧取得
- `getTagInfo(ids)` - タグ情報取得
- `editTags(ids, states)` - タグ編集
- `setTagColors(colors)` - タグカラー設定
- `addTags(ids, tags)` - タグ追加
- `removeTags(ids, tags)` - タグ削除
- `editTag(ids, tag, action)` - 個別タグ編集

### タスク管理API

- `getTasks(status?, limit?)` - タスク一覧取得
- `getTaskSummary()` - タスクサマリー取得
- `getTask(taskId)` - タスク詳細取得
- `cancelTaskById(taskId)` - タスクキャンセル
- `pauseTask(taskId)` - タスク一時停止
- `resumeTask(taskId)` - タスク再開
- `cancelCurrentTask()` - 現在のタスクキャンセル
- `cancelAllTasks()` - 全タスクキャンセル
- `cancelTask(novelId)` - 小説IDでキャンセル

### キュー・システムAPI

- `getQueueSize()` - キューサイズ取得
- `getSystemStatus()` - システムステータス取得
- `getVersion()` - バージョン情報取得
- `cancelQueue()` - キューキャンセル
- `getCurrentVersion()` - 現在バージョン取得
- `getLatestVersion()` - 最新バージョン取得
- `getHistory()` - ログ履歴取得
- `clearHistory()` - ログ履歴クリア

### 設定API

- `getSettings()` - 全設定取得
- `getSettingVariables()` - 設定変数定義取得
- `updateSettings(settings)` - 設定更新（全体）
- `patchSettings(settings)` - 設定更新（部分）

### サーバー管理API

- `getServerStatus()` - サーバーステータス取得
- `restartServer()` - サーバー再起動
- `stopServer()` - サーバー停止

### ユーティリティAPI

- `downloadAsCSV()` - CSV出力（クライアントサイド）

## WebSocket通信（lib/pushserver.ts）

### PushServerClient

**機能**:

- WebSocket接続管理
- 自動再接続
- イベント配信
- ハートビート

**主要イベント**:

- `connected` - 接続成功
- `disconnected` - 切断
- `notification.queue` - キュー更新通知
- `console.push.*` - コンソールログ配信
- `novel.update` - 小説更新通知
- `novel.insert` - 小説追加通知
- `task.created` - タスク作成通知
- `task.updated` - タスク更新通知
- `task.completed` - タスク完了通知
- `task.failed` - タスク失敗通知

### 関数

- `getPushServer()` - PushServerClientインスタンス取得
- `initializePushServer()` - 初期化

## 状態管理（lib/stores/）

### serverStatus.ts

- `isServerStopped` - サーバー停止状態（Writable store）

### progressStore.ts

- `progressStore` - 進捗管理（Map<number, ProgressData>）
- PushServerイベントからの進捗データ更新

## スタイリング

### Tailwind CSS v4

- カスタムテーマ設定（`tailwind.config.js`）
- 14px基本フォントサイズ
- ダークモード対応（`@variant dark`）
- レスポンシブデザイン

### グローバルCSS（`src/styles/global.css`）

- ベースフォントサイズ: 14px
- 見出しサイズ: h1(1.4rem), h2(1.3rem), h3(1.2rem), h4(1.1rem), h5-h6(1rem)
- ダークモード変数

## セキュリティ・認証

**現状**: 未実装

**予定**:

- Basic認証対応（Backend側で実装済み）
- CORS設定（Backend側で実装済み）

## パフォーマンス最適化

- レイジーローディング（`client:load`ディレクティブ）
- ページネーション（大量データ対応）
- 仮想スクロール（検討中）
- API応答キャッシュ（検討中）

## 開発ツール

- **Vite**: 高速ビルド・HMR
- **TypeScript**: 型安全性
- **ESLint**: コード品質
- **Prettier**: コードフォーマット（検討中）

## ビルド・デプロイ

**ビルドコマンド**:

```bash
cd frontend
npm run build
```

**ビルド成果物**: `frontend/dist/`

**配信方法**:

- Sinatraサーバーが`frontend/dist/`を配信
- `/` → `index.html`
- `/_astro/*` → Astroアセット
- `/favicon.svg` → ファビコン

## 未実装機能（Legacy版にあってAstro版にない機能）

### UI機能

- [ ] ブックマークレット機能
- [ ] D&Dウィンドウ
- [ ] メモ帳（リアルタイム同期）
- [ ] 個別メニュー編集
- [ ] 作者コメント表示
- [ ] 差分表示機能
- [ ] CSVインポート
- [ ] ショートカットキー対応（一部のみ実装）
- [ ] コンテキストメニュー（右クリックメニュー）
- [ ] 範囲選択モード/ハイブリッド選択モード
- [ ] 並行処理対応コンソール（2カラム表示）
- [ ] Kindle端末取り出し機能
- [ ] 栞バックアップ機能
- [ ] hotentry送信機能
- [ ] フォルダを開く機能
- [ ] 調査ログ表示
- [ ] バックアップ作成機能
- [ ] メール送信機能
- [ ] タグ一覧表示（ヘッダー）

### 小説個別機能

- [ ] 小説個別設定ページ（`/novels/:id/setting`）
- [ ] 作者コメントページ（`/novels/:id/author_comments`）
- [ ] ダウンロード履歴ページ（`/novels/:id/download`）

### 設定機能

- [ ] 置換パターン設定
- [ ] 個別小説の置換パターン設定
- [ ] 設定カテゴリー別タブ（現在は2タブのみ）
- [ ] 設定の焼付け機能

### その他

- [ ] 初回アクセス時のウェルカムメッセージ
- [ ] システムアップデート機能（GitHub連携）
- [ ] パフォーマンスモード警告
- [ ] 表示項目カスタマイズ（すべて表示/設定）
- [ ] 小説リスト幅調整
- [ ] ボタン位置設定（上部/下部固定）
- [ ] 個別メニュースタイル選択

## 実装予定機能（優先度順）

### 高優先度

1. **小説個別設定ページ**: setting.ini編集UI
2. **置換パターン設定**: グローバル・個別両対応
3. **ショートカットキー**: 主要操作のキーバインド
4. **フォルダを開く**: ローカルフォルダアクセス

### 中優先度

1. **差分表示**: 更新差分の確認
2. **作者コメント表示**: 前書き・後書き閲覧
3. **CSVインポート**: 一括登録
4. **メモ帳**: リアルタイム同期メモ

### 低優先度

1. **ブックマークレット**: ブラウザ拡張
2. **D&Dウィンドウ**: ドラッグ＆ドロップUI
3. **コンテキストメニュー**: 右クリック操作

## まとめ

Astro版Web UIは、以下の特徴を持つモダンなフロントエンドです：

1. **高速・軽量**: Astro + Viteによる高速ビルド・HMR
2. **型安全**: TypeScript + 厳格な型定義
3. **リアクティブ**: Svelte 5 Runesによる効率的な状態管理
4. **モダンUI**: Tailwind CSS v4によるレスポンシブデザイン
5. **リアルタイム**: WebSocketによるライブアップデート
6. **API v2優先**: RESTful設計のモダンAPI活用

Legacy版の全機能を完全移行するには時間がかかりますが、主要機能（小説一覧、ダウンロード、変換、更新、削除、設定、タスクキュー）は既に実装済みです。今後、優先度に応じて段階的に機能を追加していきます。
