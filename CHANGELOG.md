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
