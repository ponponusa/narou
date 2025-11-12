# 更新履歴 - ChangeLog

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
