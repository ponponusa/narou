# 更新履歴 - ChangeLog

## 2.1.0 (未リリース)

### 破壊的変更

- **WEBサーバーのデーモンモードを削除**
  - Puma 7.0以降でデーモン機能が削除されたため、フォアグラウンド実行のみに変更
  - `--daemon`, `--no-daemon` オプションを削除
  - サーバーは常にフォアグラウンドで実行され、`Ctrl+C`で停止
  - `narou-mod restart` コマンドは使用不可（`Ctrl+C` → `narou-mod web` で再起動）

### 新機能

- **TUI（Text User Interface）強化**
  - `tty-markdown`, `tty-spinner`, `tty-box`, `tty-prompt` を導入
  - CLI出力をMarkdown形式で見やすく表示
  - スピナーやボックス表示でユーザビリティ向上

- **ログファイル出力オプション追加**
  - `--log-file FILE` オプションを追加（例: `narou-mod web --log-file app.log`）
  - 標準出力とファイル出力を切り替え可能

### 変更点

- `lib/command/output_helper.rb` モジュールを追加（TUI出力の一元管理）
- `lib/command/web.rb`, `stop.rb`, `restart.rb` の出力を `OutputHelper` 経由に変更
- フロントエンド起動処理を簡素化（フォアグラウンド実行に最適化）

### バグ修正

- **Web UI実行時のインタラクティブプロンプト問題を修正**
  - Web UI経由でコマンドを実行した際に、コンソールに `**** y/N` などのインタラクティブなプロンプトが表示される問題を修正
  - `lib/command/web.rb`: `TTYHelper.ask_yes_no` を使用してプロセス競合時の確認プロンプトを非対話モード対応に変更
  - `lib/tty_helper.rb`: `Narou.web?` をチェックし、Web UI実行時は自動的に非対話モードにする
  - `lib/input.rb`: `Narou::Input.confirm` でも `Narou.web?` をチェックし、Web UI実行時は `nontty_default` を返すように修正
  - `lib/command/web.rb`: `start_server` メソッドで `Narou.web = true` を設定し、Web UI モードを有効化
  - テストケースを追加: `spec/input_spec.rb`, `spec/tty_helper_spec.rb`

- **フロントエンドサーバー起動時のエラーを修正**
  - `lib/command/web.rb`: `start_frontend` メソッドの `fork` ブロック内で `STDOUT`/`STDERR`/`STDIN` 定数を使用
  - 親プロセスで `$stdout` が `Narou::Logger` に置き換わった後に `fork` すると、子プロセスで `$stdout.reopen` がエラーになる問題を修正
  - Rubocop の `Style/GlobalStdStream` 警告を該当箇所で無効化（コメントで理由を説明）
  - テストケースを追加: `spec/command/web_spec.rb` に `#start_frontend` のテスト

- **EPUB ダウンロードリンクが機能しない問題を修正**
  - API v2 に EPUB ダウンロードエンドポイント `GET /api/v2/novels/:id/epub` を追加
  - デバイスに応じた拡張子（`.epub`, `.kepub.epub` など）に対応
  - ダウンロード時のファイル名を `[著者名] タイトル.拡張子` の形式に統一（RFC 5987形式でエンコード）
  - CORS設定に `Access-Control-Expose-Headers: Content-Disposition` を追加してブラウザがファイル名を取得できるように修正
  - フロントエンドでRFC 5987形式（`filename*=UTF-8''...`）のデコード処理を実装
  - EPUB ファイルが存在しない場合は適切なエラーメッセージを返す
  
- **Web UI実行時のCLI出力問題を修正**
  - `web` コマンドに `--verbose` オプションを追加
  - Web UI のコンソールへの出力は継続、CLI側は `--verbose` 指定時のみ出力
  - `lib/web/streaminglogger.rb`: verbose フラグに応じて CLI 出力を制御
  - テストケースを追加: `spec/command/web_spec.rb`

- **Web UI実行時のHTML出力問題を修正**
  - `lib/web/appserver.rb`: Web UI コンソール向けのHTML出力がCLIのターミナルに表示される問題を修正
  - `Narou.web?` をチェックし、Web UI 実行時は HTML 出力を `$stdout` ではなく `$stderr` に出力
  - 起動メッセージなどのHTML形式出力がターミナルに表示されなくなった

### Web UI機能追加

- **タスクキュー管理の細分化**
  - バックエンド実装:
    - タスクオブジェクトを導入し、各タスクの詳細情報を管理
    - タスク状態の詳細管理（queued, running, completed, failed, canceled）
    - タスクごとにID、タイプ、小説情報、経過時間を追跡
    - タスク履歴の保持（最大100件）
    - エラー情報の詳細記録（エラーメッセージ、例外クラス、バックトレース）
    - API v2に新規エンドポイント追加:
      - `GET /api/v2/tasks`: タスク一覧取得
      - `GET /api/v2/tasks/summary`: タスクサマリー取得
      - `GET /api/v2/tasks/:id`: 特定タスク取得
    - PushServerで `notification.task.updated` イベントを送信
    - ダウンロード・変換APIがタスクIDを返すように変更
    - テストコードを追加: `spec/web/task_spec.rb`
  - フロントエンド実装:
    - TaskQueueコンポーネントでサーバータスク状態をリアルタイム表示
    - 実行中タスク、キュー待ちタスクを可視化
    - 経過時間、タスクタイプ、メッセージを表示
    - 5秒ごとに自動更新 + PushServerからの即時通知
    - API型定義を追加: `Task`, `TaskSummary`, `TaskStatus`
    - Legacy APIは既存の一括管理のまま維持

- **ヘッダーUIの改善**
  - PushServer アイコンのステータス表示を削除（サーバーステータスと機能が重複）
  - より簡潔なヘッダーレイアウトに変更

- **小説情報へのリンク追加**
  - 著者名にクリック可能なリンクを追加（小説一覧とモーダル）
  - サイト名にクリック可能なリンクを追加（小説一覧とモーダル）
  - バックエンドで `author_url` と `site_top_url` を生成
  - フロントエンドで条件付きリンク表示を実装

### ドキュメント更新

- **OpenAPI ドキュメントの更新**
  - `docs/openapi.yaml`: Novel スキーマに `author_url`, `site_name`, `site_top_url`, `toc_url` フィールドを追加
  - EPUB ダウンロードエンドポイントのドキュメント化済み

- **データベース構造のドキュメント化**
  - `docs/database_structure.md`: 新規作成
  - 小説データのスキーマを詳細に文書化
  - データベース操作APIの使用例を追加
  - よく使われるクエリパターンを記載

### systemd / タスクスケジューラについて

- 本バージョンではsystemdユニットファイルやWindowsタスクスケジューラの提供は行いません
- バックグラウンド実行が必要な場合は、ユーザー側で設定をお願いします

## 2.0.0

- プロモタグ機能を実装
  - 小説タイトル、著者名に付加されたプロモーション文をプロモタグとして抽出するように
    -（デフォルトで無効 = 以前と同様にタイトルと著者名を扱う）
  - 指定キーワードをプロモタグとして扱うフィルタ機能を追加
- コマンド名とgemモジュール名を「narou-mod」に変更
  - バージョン表記も「narou-mod x.y.z」に変更
- 不正なYAML読込を例外化しないように修正
  - 設定ファイルの読み込みエラーを警告扱いに変更
- 更新情報取得処理をGitHub Releases API経由に変更
  - narou-mod web の更新チェック処理を刷新
- WSL環境のブラウザ起動処理をwslview経由対応に
- Web UI: テーブル項目を整理
  - テーブル内のボタンをアクションカラムに集約
  - タイトルテキストを小説ページへのリンクに変更
  - 小説タイトル下部にプロモタグ表示欄を追加
- Web UI: ヘルプ画面が機能していなかったので修正
- 全体的な処理の最適化
  - キャッシュ処理の改善
  - 不要なオブジェクト生成の削減
  - 古いjsライブラリ利用箇所が残っていたので修正
  - js/cssリソースのバージョン管理を強化
- その他、細かな修正

## 1.6.0

- Linux デバイス検出時に Web UI が落ちることがあるので修正
- Web UI 起動時の処理を安定化

## ~~1.5.0~~

## 1.4.0

- SCSSの修正漏れで画面が乱れていた件を修正

## 1.3.0

-非推奨になっていたscssを修正

## 1.2.0

- ビルドにWindows向けgemファイルを追加
- その他、細かな修正

## 1.1.0

- Windows環境におけるYAML読込エラーの修正
- 小説一覧テーブルにおける行選択時のスタイルを修正
- その他、細かな修正

## 1.0.0

- テキスト/EPUB変換処理の高速化
  - 主に話数の多い（1000話オーバーなど）小説で顕著に効果があります
  - ※小説掲載サイトからの取得ロジックに変更はないため、取得速度は変化はありません（変更予定もなし）
- JavaScriptライブラリの更新、変更
  - update jQuery 1.11.1 -> 3.7.1
  - update datatables.js 1.10.10 -> 2.3.4
  - update bootstrap 3.3.5 -> 3.4.1
  - and more...
- Rubyパッケージの更新、変更
  - supported Ruby version 2.3.0~ -> 3.4.0~
  - add puma/bootsnap/and more...
  - update sinatra/ActiveSuport/tilt/and more...
- Digest認証からBasic認証に変更
  - Rack3.1からDigest認証が非対応となったため
- その他、細かな修正

> これより以前は[whiteleaf7/narou](https://raw.githubusercontent.com/whiteleaf7/narou/refs/heads/develop/ChangeLog.md)を参照してください
