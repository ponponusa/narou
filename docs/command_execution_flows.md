# コマンド実行フローチャート

## 概要

このドキュメントでは、Narou.rb MOD の各コマンドの実行フローを詳細に説明します。
入力から出力までの処理の流れと、関連するファイル、クラス、メソッドを把握できます。

---

## 1. download コマンド

小説をダウンロードするコマンド。

### 1-1.入力

- Nコード（例: `n9669bk`）
- URL（例: `https://ncode.syosetu.com/n9669bk/`）
- 対話モード（引数なし）

### 1-2.フローチャート

```bash
[ユーザー入力]
  ↓
Command::Download#execute
  ↓
引数チェック
  ├─ [引数あり] → 引数を targets に設定
  └─ [引数なし] → interactive_mode() → 対話入力
  ↓
各 target についてループ
  ↓
凍結チェック (Narou.novel_frozen?)
  ├─ [凍結中] → スキップ & エラーカウント
  └─ [非凍結] → 続行
  ↓
ダウンロード済みチェック
  ├─ [済み & --force なし] → スキップ
  └─ [未 or --force あり] → 続行
  ↓
Downloader.new(target, force: force, from_download: true)
  ↓
Downloader#initialize
  ├─ get_target_type(target) → :ncode or :url 判定
  ├─ SiteSetting.find(url) → サイト設定取得
  └─ @setting に格納
  ↓
Downloader#start_download
  ↓
  ┌─────────────────────────────────┐
  │ Downloader#start_download 詳細 │
  └─────────────────────────────────┘
  ├─ get_novel_data_dir → 保存先ディレクトリ決定
  │   └─ 小説データ/サイト名/Nコード タイトル/
  ├─ get_toc_data → 目次ページ取得・解析
  │   ├─ HTTP GET リクエスト
  │   ├─ SiteSetting のパターンで解析
  │   └─ タイトル、作者、話数リスト取得
  ├─ create_novel_directory → ディレクトリ作成
  │   ├─ 小説ディレクトリ作成
  │   ├─ raw/ ディレクトリ作成
  │   └─ 本文/ ディレクトリ作成
  ├─ Database への登録 or 更新
  │   ├─ Database#create_new_id → 新規ID採番
  │   ├─ メタデータ格納
  │   └─ Database#save_database → database.yaml 保存
  ├─ toc.yaml 保存
  │   └─ Inventory.save → toc.yaml 作成
  ├─ setting.ini, converter.rb, replace.txt コピー
  │   └─ プリセットから小説ディレクトリへコピー
  ├─ download_subtitles → 各話ダウンロード
  │   ├─ 各話 URL にアクセス
  │   ├─ HTML 取得
  │   ├─ raw/{話数}.html 保存
  │   └─ convert_to_text → 本文/{話数}_サブタイトル.txt 保存
  ├─ 調査ログ.txt 作成
  └─ status: :ok 返却
  ↓
[--no-convert なし]
  ↓
Command::Convert.execute!(id)
  └─ 変換処理へ（後述）
  ↓
[--freeze オプション]
  ↓
Command::Freeze.execute!(id)
  └─ freeze.yaml に追加
  ↓
[--remove オプション]
  ↓
Command::Remove.execute!(id)
  └─ 削除処理へ（後述）
  ↓
[--mail オプション]
  ↓
Command::Send.execute!(id)
  └─ メール送信処理
  ↓
[完了]
```

### 1-3.関連ファイル

| ファイルパス | 役割 |
|-------------|------|
| `lib/command/download.rb` | Download コマンド実装 |
| `lib/downloader.rb` | ダウンロード処理本体 |
| `lib/database.rb` | データベース管理 |
| `lib/sitesetting.rb` | サイト設定管理 |
| `lib/inventory.rb` | YAML ファイル I/O |
| `webnovel/サイト名/` | サイト別設定ディレクトリ |

### 1-4.主要クラス・メソッド

| クラス | メソッド | 説明 |
|--------|---------|------|
| `Command::Download` | `execute(argv)` | コマンドエントリポイント |
| `Command::Download` | `interactive_mode()` | 対話モード処理 |
| `Command::Download` | `valid_target?(target)` | ターゲット検証 |
| `Downloader` | `initialize(target, options)` | ダウンローダー初期化 |
| `Downloader` | `start_download()` | ダウンロード実行 |
| `Downloader` | `get_toc_data()` | 目次データ取得 |
| `Downloader` | `download_subtitles()` | 各話ダウンロード |
| `Downloader` | `convert_to_text(html)` | HTML→テキスト変換 |
| `Database` | `create_new_id()` | 新規ID採番 |
| `Database` | `save_database()` | データベース保存 |
| `SiteSetting` | `find(url)` | URLからサイト設定取得 |

---

## 2. convert コマンド

小説をEPUB/MOBIに変換するコマンド。

### 2-1.入力

- 小説ID（例: `0`, `1`）
- Nコード（例: `n9669bk`）
- タイトル（例: `無職転生`）
- ファイルパス（例: `mynovel.txt`）

### 2-2.フローチャート

```bash
[ユーザー入力]
  ↓
Command::Convert#execute
  ↓
init(argv)
  ├─ 引数チェック（空ならヘルプ表示）
  ├─ --output オプション解析
  └─ --encoding オプション解析
  ↓
main(argv)
  ↓
build_device_names → デバイスリスト構築
  ├─ [--multi-device 指定] → カンマ区切りで複数デバイス
  └─ [未指定] → device 設定値を使用
  ↓
各デバイスについてループ
  ↓
デバイスフック適用
  ├─ @device.get_hook_module
  └─ change_settings → デバイス固有設定適用
  ↓
convert_novels(argv)
  ↓
  ┌──────────────────────────────┐
  │ convert_novels 詳細          │
  └──────────────────────────────┘
  ↓
tagname_to_ids(argv) → タグ名→ID変換
  ↓
各 target についてループ
  ↓
ターゲット種別判定
  ├─ [ファイルパス] → convert_txt_to_ebook_file
  └─ [小説ID/Nコード/タイトル] → 続行
  ↓
小説データ取得
  ├─ Downloader.get_data_by_target(target)
  └─ Database から小説情報取得
  ↓
小説ディレクトリ取得
  └─ Downloader.get_novel_data_dir_by_target(target)
  ↓
NovelConverter.new(target, options)
  ↓
NovelConverter#convert
  ↓
  ┌──────────────────────────────┐
  │ NovelConverter#convert 詳細  │
  └──────────────────────────────┘
  ├─ load_novel_data → toc.yaml, setting.ini 読み込み
  ├─ load_replace_patterns → replace.txt 読み込み
  ├─ require converter.rb → カスタム変換スクリプト読み込み
  ├─ create_output_filename → 出力ファイル名決定
  │   └─ [著者名] タイトル.txt
  ├─ convert_main → メイン変換処理
  │   ├─ 本文/*.txt ファイル読み込み
  │   ├─ replace_patterns 適用
  │   ├─ converter.rb の変換メソッド実行
  │   ├─ 目次構造構築
  │   ├─ 全話テキスト結合
  │   └─ [著者名] タイトル.txt 出力
  ├─ [--no-epub なし]
  │   └─ convert_to_epub
  │       ├─ AozoraEpub3 実行
  │       │   └─ ruby AozoraEpub3 -enc UTF-8 -dst 出力先 入力ファイル
  │       └─ [著者名] タイトル.epub 生成
  ├─ [device=kindle & --no-mobi なし]
  │   └─ convert_to_mobi
  │       ├─ kindlegen 実行
  │       │   └─ kindlegen [著者名] タイトル.epub
  │       ├─ [著者名] タイトル.mobi 生成
  │       └─ [--no-strip なし] → KindleStrip.strip (DRM除去)
  ├─ [device=kobo]
  │   └─ convert_to_kepub
  │       └─ [著者名] タイトル.kepub.epub 生成
  └─ [--make-zip]
      └─ create_zip_file
          └─ i文庫用 ZIP 作成
  ↓
[convert.copy-to 設定あり]
  ↓
copy_to_specified_folder
  └─ 指定フォルダへコピー
  ↓
[デバイス接続中]
  ↓
send_to_device
  ├─ @device.get_device_path → デバイスパス取得
  └─ ファイル転送
  ↓
[--no-open なし & Web UI でない]
  ↓
open_novel_folder
  └─ 保存フォルダをファイルマネージャで開く
  ↓
[完了]
```

### 2-3.関連ファイル

| ファイルパス | 役割 |
|-------------|------|
| `lib/command/convert.rb` | Convert コマンド実装 |
| `lib/novelconverter.rb` | 小説変換処理本体 |
| `lib/converterbase.rb` | 変換処理基底クラス |
| `lib/device.rb` | デバイス管理 |
| `lib/kindlestrip.rb` | Kindle MOBI Strip処理 |
| `小説データ/サイト名/Nコード タイトル/setting.ini` | 小説設定 |
| `小説データ/サイト名/Nコード タイトル/converter.rb` | カスタム変換 |
| `小説データ/サイト名/Nコード タイトル/replace.txt` | 置換ルール |

### 2-4.主要クラス・メソッド

| クラス | メソッド | 説明 |
|--------|---------|------|
| `Command::Convert` | `execute(argv)` | コマンドエントリポイント |
| `Command::Convert` | `init(argv)` | 初期化処理 |
| `Command::Convert` | `main(argv)` | メイン処理 |
| `Command::Convert` | `convert_novels(argv)` | 小説変換ループ |
| `NovelConverter` | `initialize(target, options)` | コンバーター初期化 |
| `NovelConverter` | `convert()` | 変換実行 |
| `NovelConverter` | `convert_main()` | メイン変換処理 |
| `NovelConverter` | `convert_to_epub()` | EPUB変換 |
| `NovelConverter` | `convert_to_mobi()` | MOBI変換 |
| `ConverterBase` | `load_novel_data()` | 小説データ読み込み |
| `ConverterBase` | `load_replace_patterns()` | 置換パターン読み込み |
| `Device` | `get_device(name)` | デバイス取得 |
| `KindleStrip` | `strip(mobi_path)` | MOBI Strip実行 |

---

## 3. update コマンド

登録済み小説を更新チェックするコマンド。

### 3-1.入力

- 小説ID（例: `0`, `1`）
- Nコード（例: `n9669bk`）
- タイトル（例: `無職転生`）
- 引数なし（全小説対象）

### 3-2.フローチャート

```bash
[ユーザー入力]
  ↓
Command::Update#execute
  ↓
引数チェック
  ├─ [引数あり] → 指定小説のみ
  └─ [引数なし] → Database の全小説
  ↓
凍結チェック (freeze.yaml)
  ├─ [凍結中] → スキップ（--force で強制更新可）
  └─ [非凍結] → 続行
  ↓
各小説についてループ
  ↓
Database から小説データ取得
  ↓
Downloader.new(toc_url, force: false, from_download: false)
  ↓
Downloader#start_download(from_update: true)
  ↓
  ┌──────────────────────────────┐
  │ 更新チェック処理             │
  └──────────────────────────────┘
  ├─ get_toc_data → 最新目次取得
  ├─ 既存 toc.yaml 読み込み
  ├─ 話数比較
  │   ├─ [新着なし] → スキップ
  │   └─ [新着あり] → 続行
  ├─ 新着話のみダウンロード
  │   ├─ download_subtitles(new_subtitles_only)
  │   ├─ raw/{新話数}.html 保存
  │   └─ 本文/{新話数}_サブタイトル.txt 保存
  ├─ toc.yaml 更新
  │   └─ 新着話を subtitles に追加
  ├─ Database 更新
  │   ├─ general_lastup 更新
  │   ├─ novel_subtitle_count 更新
  │   └─ save_database
  └─ 調査ログ.txt 追記
  ↓
[--convert オプション or デフォルト設定]
  ↓
Command::Convert.execute!(id)
  └─ 変換処理へ
  ↓
[--send オプション]
  ↓
Command::Send.execute!(id)
  └─ 送信処理へ
  ↓
[完了]
```

### 3-3.関連ファイル

| ファイルパス | 役割 |
|-------------|------|
| `lib/command/update.rb` | Update コマンド実装 |
| `lib/downloader.rb` | ダウンロード処理（更新モード） |
| `lib/database.rb` | データベース管理 |

### 3-4.主要クラス・メソッド

| クラス | メソッド | 説明 |
|--------|---------|------|
| `Command::Update` | `execute(argv)` | コマンドエントリポイント |
| `Downloader` | `start_download(from_update: true)` | 更新モードダウンロード |
| `Database` | `get_data(type, value)` | 小説データ取得 |

---

## 4. remove コマンド

小説を削除するコマンド。

### 4-1.入力

- 小説ID（例: `0`, `1`）
- Nコード（例: `n9669bk`）
- タイトル（例: `無職転生`）

### 4-2.フローチャート

```bash
[ユーザー入力]
  ↓
Command::Remove#execute
  ↓
引数チェック（必須）
  ↓
tagname_to_ids(argv) → タグ名→ID変換
  ↓
各 target についてループ
  ↓
小説データ取得
  └─ Downloader.get_data_by_target(target)
  ↓
確認ダイアログ表示（Webモードでない場合）
  ├─ "#{title} を削除しますか？"
  ├─ [No] → スキップ
  └─ [Yes] → 続行
  ↓
Database からエントリ削除
  ├─ Database.delete(id)
  └─ Database.save_database
  ↓
freeze.yaml から削除（凍結中の場合）
  └─ freeze データから id 削除
  ↓
[--with-file オプション]
  ↓
小説ディレクトリ削除
  ├─ novel_dir = Downloader.get_novel_data_dir_by_target(target)
  ├─ FileUtils.rm_rf(novel_dir)
  └─ 小説データ/サイト名/Nコード タイトル/ 全削除
  ↓
[完了]
```

### 4-3.関連ファイル

| ファイルパス | 役割 |
|-------------|------|
| `lib/command/remove.rb` | Remove コマンド実装 |
| `lib/database.rb` | データベース管理 |

### 4-4.主要クラス・メソッド

| クラス | メソッド | 説明 |
|--------|---------|------|
| `Command::Remove` | `execute(argv)` | コマンドエントリポイント |
| `Database` | `delete(id)` | エントリ削除 |
| `Downloader` | `get_novel_data_dir_by_target` | ディレクトリパス取得 |

---

## 5. freeze / unfreeze コマンド

小説を凍結・凍結解除するコマンド。

### 5-1.入力

- 小説ID（例: `0`, `1`）
- Nコード（例: `n9669bk`）
- タイトル（例: `無職転生`）

### 5-2.フローチャート

```bash
[ユーザー入力]
  ↓
Command::Freeze#execute (or Unfreeze#execute)
  ↓
tagname_to_ids(argv) → タグ名→ID変換
  ↓
各 target についてループ
  ↓
小説データ取得
  └─ Downloader.get_data_by_target(target)
  ↓
[freeze コマンド]
  ├─ freeze.yaml に id 追加
  ├─ Database の frozen フラグを true に更新
  └─ "#{title} を凍結しました" 表示
  ↓
[unfreeze コマンド]
  ├─ freeze.yaml から id 削除
  ├─ Database の frozen フラグを false に更新
  └─ "#{title} の凍結を解除しました" 表示
  ↓
Database.save_database
  ↓
freeze.yaml 保存
  ↓
[完了]
```

### 5-3.関連ファイル

| ファイルパス | 役割 |
|-------------|------|
| `lib/command/freeze.rb` | Freeze コマンド実装 |
| `.narou/freeze.yaml` | 凍結状態管理 |
| `.narou/database.yaml` | データベース（frozen フラグ） |

---

## 6. list コマンド

登録済み小説一覧を表示するコマンド。

### 6-1.入力

- オプションなし（全小説表示）
- `--grep PATTERN`（タイトル/作者検索）
- `--kind [連載|短編]`（種別フィルター）
- `--tag TAG`（タグフィルター）

### 6-2.フローチャート

```bash
[ユーザー入力]
  ↓
Command::List#execute
  ↓
オプション解析
  ├─ --grep → 検索パターン設定
  ├─ --kind → 種別フィルター設定
  └─ --tag → タグフィルター設定
  ↓
Database.each → 全小説ループ
  ↓
フィルター適用
  ├─ grep パターンマッチ
  ├─ kind 種別チェック
  └─ tag タグチェック
  ↓
[マッチ] → 一覧に追加
[非マッチ] → スキップ
  ↓
ソート処理
  └─ ID順、タイトル順など
  ↓
表形式で出力
  ├─ ID
  ├─ タイトル
  ├─ 作者
  ├─ サイト名
  ├─ 最終更新日
  └─ 凍結状態
  ↓
[完了]
```

---

## 7. web コマンド（Web UI起動）

Web UIサーバーを起動するコマンド。

### 7-1.入力

- `--port PORT`（ポート指定）
- `--host HOST`（ホスト指定）
- `--no-browser`（ブラウザ自動起動なし）

### 7-2.フローチャート

```bash
[ユーザー入力]
  ↓
Command::Web#execute
  ↓
設定読み込み
  ├─ ポート設定（デフォルト: 5678）
  └─ ホスト設定（デフォルト: localhost）
  ↓
Puma サーバー初期化
  ├─ Narou::AppServer 起動
  ├─ Narou::PushServer 起動（WebSocket）
  └─ Narou::WebWorker 起動（タスク処理）
  ↓
ルーティング設定
  ├─ API v2 ルート登録
  ├─ Legacy API ルート登録
  └─ 静的ファイル配信設定
  ↓
[--no-browser なし]
  ↓
ブラウザ自動起動
  └─ システムブラウザで http://localhost:5678 を開く
  ↓
サーバー待機
  ├─ HTTP リクエスト受付
  ├─ WebSocket 接続管理
  └─ Ctrl+C で終了
  ↓
[完了]
```

### 7-3.関連ファイル

| ファイルパス | 役割 |
|-------------|------|
| `lib/command/web.rb` | Web コマンド実装 |
| `lib/web/appserver.rb` | HTTP サーバー本体 |
| `lib/web/pushserver.rb` | WebSocket サーバー |
| `lib/web/web_worker.rb` | タスクキュー管理 |
| `lib/web/api/v2/` | API v2 エンドポイント群 |

---

## 8. API v2 エンドポイント実行フロー

### POST /api/v2/novels/download（小説ダウンロード）

```bash
[HTTPリクエスト]
  ↓
Narou::API::V2::Novels#download
  ↓
リクエストボディ解析
  ├─ targets: [Nコード/URL配列]
  ├─ force: boolean
  └─ convert_after_download: boolean
  ↓
バリデーション
  ├─ targets が空 → 400 Bad Request
  └─ 正常 → 続行
  ↓
各 target についてループ
  ↓
小説データ取得（IDの場合）
  └─ Database.instance[target]
  ↓
Task 作成
  ├─ Narou::Task.new(type: :download)
  ├─ novel_id, novel_title, novel_author 設定
  └─ max_retries: 0
  ↓
WebWorker にタスク追加
  └─ Narou::WebWorker.push_task(task) do
      ├─ CommandLine.run!('download', target)
      ├─ [convert_after_download = true]
      │   └─ 変換タスク作成
      │       ├─ Narou::Task.new(type: :convert)
      │       └─ WebWorker.push_task(convert_task)
      ├─ AppServer.clear_all_cache
      └─ push_server.send_all(:'table.reload')
     end
  ↓
レスポンス返却
  └─ { success: true, data: { task_ids: [...] } }
  ↓
[バックグラウンド実行]
  ↓
WebWorker がタスク処理
  ├─ Task#start! → status: :running
  ├─ download コマンド実行
  ├─ Task#complete! → status: :completed
  └─ notification_task_updated → PushServer 通知
  ↓
[convert_after_download = true]
  ↓
変換タスク自動実行
  ├─ Task#start! → status: :running
  ├─ convert コマンド実行
  └─ Task#complete! → status: :completed
  ↓
[完了]
```

### POST /api/v2/novels/convert（小説変換）

```bash
[HTTPリクエスト]
  ↓
Narou::API::V2::Novels#convert
  ↓
リクエストボディ解析
  ├─ ids: [小説ID配列]
  └─ no_open: boolean
  ↓
バリデーション & 存在チェック
  ├─ 存在しないID → not_found_ids に追加
  └─ 存在するID → 続行
  ↓
各 id についてループ
  ↓
Task 作成
  ├─ Narou::Task.new(type: :convert)
  └─ novel_id, novel_title, novel_author 設定
  ↓
WebWorker にタスク追加
  └─ Narou::WebWorker.push_task(task) do
      ├─ CommandLine.run!('convert', '--no-open', id)
      └─ AppServer.clear_all_cache
     end
  ↓
レスポンス返却
  └─ { success: true, data: { task_ids: [...] } }
  ↓
[バックグラウンド実行]
  └─ WebWorker がタスク処理
  ↓
[完了]
```

---

## 9. タスクキュー管理フロー

### 9-1.タスクライフサイクル

```bash
[タスク作成]
  ↓
Narou::Task.new
  ├─ id: UUID自動生成
  ├─ type: :download | :convert | :update | :remove
  ├─ status: :queued
  └─ created_at: Time.now
  ↓
WebWorker.push_task(task) { block }
  ├─ @tasks[task.id] = task
  ├─ キューに追加
  └─ notification_task_updated
  ↓
WebWorker スレッドがキューから取得
  ↓
Task#start!
  ├─ status → :running
  ├─ started_at → Time.now
  └─ notification_task_updated
  ↓
ブロック実行
  ├─ [正常終了] → Task#complete!
  ├─ [例外発生] → Task#fail!(error)
  └─ [中断] → Task#cancel!
  ↓
履歴に移動
  ├─ @tasks から削除
  └─ @task_history に追加（最大100件）
  ↓
notification_task_updated
  └─ PushServer 経由で Web UI に通知
  ↓
[完了]
```

### 9-2.タスク操作API

```bash
[一時停止リクエスト]
POST /api/v2/tasks/:id/pause
  ↓
WebWorker.pause_task(id)
  ├─ Task#pause! → status: :paused
  └─ notification_task_updated
  ↓
[再開リクエスト]
POST /api/v2/tasks/:id/resume
  ↓
WebWorker.resume_task(id)
  ├─ Task#resume! → status: :running or :queued
  └─ notification_task_updated
  ↓
[キャンセルリクエスト]
POST /api/v2/tasks/:id/cancel
  ↓
WebWorker.cancel_task(id)
  ├─ [キュー待ち] → Task#cancel! & 履歴へ移動
  ├─ [実行中] → スレッドに Interrupt 送信
  └─ notification_task_updated
```

---

## 共通処理フロー

### ID・Nコード・タイトル→小説データ変換

```bash
[入力: target]
  ↓
Downloader.get_data_by_target(target)
  ↓
target 種別判定
  ├─ [数値] → Database[target.to_i]
  ├─ [Nコード] → Database.get_data("toc_url", "対応URL")
  ├─ [URL] → Database.get_data("toc_url", url)
  └─ [タイトル] → Database.get_data("title", target)
  ↓
[小説データ返却]
```

### サイト設定の取得

```bash
[入力: URL]
  ↓
SiteSetting.find(url)
  ↓
webnovel/ ディレクトリから検索
  ├─ 各サイトの setting.yaml 読み込み
  ├─ url パターンマッチング
  └─ [マッチ] → SiteSetting オブジェクト返却
  ↓
SiteSetting には以下を含む:
  ├─ サイト名
  ├─ URL パターン
  ├─ 目次ページ解析パターン
  ├─ 本文ページ解析パターン
  └─ カスタム処理設定
```

---

## データベース更新タイミング一覧

| 操作 | 更新されるファイル | 更新内容 |
|------|------------------|---------|
| download | `database.yaml` | 新規エントリ追加 |
| update | `database.yaml` | `general_lastup`, `novel_subtitle_count` 更新 |
| freeze | `database.yaml`, `freeze.yaml` | `frozen` フラグ、凍結リスト更新 |
| unfreeze | `database.yaml`, `freeze.yaml` | `frozen` フラグ、凍結リスト更新 |
| remove | `database.yaml`, `freeze.yaml` | エントリ削除、凍結リスト削除 |
| tag | `database.yaml` | `tags` 配列更新 |
| convert | `latest_convert.yaml` | 最後に変換した小説ID |

---

## エラーハンドリングフロー

### ダウンロードエラー

```bash
Downloader#start_download
  ↓
[HTTP エラー]
  ├─ 404 Not Found → "小説が見つかりません"
  ├─ 503 Service Unavailable → "サーバーが応答しません"
  └─ その他 → "ダウンロードに失敗しました"
  ↓
Task#fail!(error_message)
  ├─ status → :failed
  ├─ error → { message, class, backtrace }
  └─ notification_task_updated
  ↓
[ユーザーに通知]
```

### 変換エラー

```bash
NovelConverter#convert
  ↓
[AozoraEpub3 エラー]
  ├─ "AozoraEpub3 が見つかりません"
  ├─ "EPUB 変換に失敗しました"
  └─ ログ出力
  ↓
[kindlegen エラー]
  ├─ "kindlegen が見つかりません"
  ├─ "MOBI 変換に失敗しました"
  └─ ログ出力
  ↓
Task#fail!(error_message)
```

---

## まとめ

各コマンドは以下のような共通構造を持ちます:

1. **入力解析**: 引数・オプションの解析
2. **バリデーション**: 入力値の検証
3. **データ取得**: Database や SiteSetting からデータ取得
4. **メイン処理**: ダウンロード、変換、削除などの実処理
5. **データ更新**: Database や YAML ファイルの更新
6. **出力**: 標準出力やファイル出力
7. **後処理**: 自動変換、送信、フォルダオープンなど

Web API の場合はさらに:

1. **タスク作成**: Narou::Task オブジェクト生成
2. **キュー登録**: WebWorker へのタスク追加
3. **非同期実行**: バックグラウンドでの処理実行
4. **通知**: PushServer 経由での進捗通知

これらのフローを理解することで、Narou.rb MOD の内部動作を把握し、
機能拡張やデバッグを効率的に行うことができます。
