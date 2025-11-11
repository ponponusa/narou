# Web UI REST API Endpoints (Legacy API v1)

> **注意**: このドキュメントは Legacy API (v1) の一覧です。  
> 新規開発では [API v2](./api_migration_guide.md) の使用を推奨します。

Narou.rb MOD の Web インターフェイスが利用する REST 形式の API 一覧です。  
各エンドポイントの用途と、内部で呼び出される主なコマンド／モジュール依存関係を整理しています。

> 備考  
>
> - ここに記載のコマンドは `Narou.web` 起動時に `Command.require_all` により事前ロードされます。  
> - `CommandLine.run!` は Narou CLI と同一のサブコマンド実装を呼び出します。  
> - 末尾が `*` の項目は非同期 (`Narou::WebWorker`) で実行され、完了後 PushServer 経由でイベントが配信されます。

## 関連ドキュメント

- [API Migration Guide](./api_migration_guide.md) - Legacy API v1 から API v2 への移行ガイド
- [OpenAPI Specification](./openapi.yaml) - API v2 の OpenAPI 仕様書

## エンドポイント一覧

| Method | Path | 概要 | 主な依存 (Command / モジュール) |
| --- | --- | --- | --- |
| GET | /api/novels/count | 登録小説の総数を返す | `Database` |
| GET | /api/novels/all_ids | 現在のフィルタ条件に一致する小説 ID を全件返す | `Database`, `Narou.novel_frozen?` |
| GET / POST | /api/list | DataTables 用の小説一覧データを返す | `Database`, フィルタ処理ヘルパー |
| POST | /api/cancel | WebWorker / Worker のキューをキャンセル | `Narou::WebWorker`, `Narou::Worker` |
| GET | /api/sort_state | 保存されたテーブルのソート状態を返す | `Inventory` (`server_setting`) |
| POST | /api/convert * | 選択小説を変換キューに投入 | `CommandLine.run!("convert")` |
| POST | /api/download * | 選択小説をダウンロードキューに投入（必要に応じメール送信） | `CommandLine.run!("download")` |
| POST | /api/download_force * | 強制ダウンロードを実行 | `CommandLine.run!("download", "--force")` |
| POST | /api/mail * | 選択小説をメール送信 | `CommandLine.run!("mail")` |
| POST | /api/update * | 小説を更新（全件または選択） | `Command::Update` |
| POST | /api/update_by_tag * | タグ条件で小説を更新 | `Command::Update` |
| POST | /api/send * | 端末送信を実行 | `CommandLine.run!("send")` |
| POST | /api/backup_bookmark * | しおりバックアップを実行 | `CommandLine.run!("send", "--backup-bookmark")` |
| POST | /api/freeze * | 凍結状態をトグル | `CommandLine.run!("freeze")` |
| POST | /api/freeze_on * | 凍結を有効化 | `CommandLine.run!("freeze", "--on")` |
| POST | /api/freeze_off * | 凍結を解除 | `CommandLine.run!("freeze", "--off")` |
| POST | /api/remove * | 小説を削除（必要ならキャッシュ更新） | `CommandLine.run!("remove", "--yes")` |
| POST | /api/remove_with_file * | 小説と生成物を削除 | `CommandLine.run!("remove", "--yes", "--with-file")` |
| POST | /api/diff * | 差分表示を実行（ログへ出力） | `CommandLine.run!("diff")` |
| GET | /api/diff_list | 差分履歴リストを表示 | `Command::Diff#get_diff_list` |
| POST | /api/diff_clean * | 差分履歴を削除 | `CommandLine.run!("diff", "--clean")` |
| POST | /api/inspect * | インスペクタを実行 | `CommandLine.run!("inspect")` |
| POST | /api/folder | 保存フォルダをエクスプローラ等で開く | `CommandLine.run!("folder")` |
| POST | /api/backup * | 小説データのバックアップ | `CommandLine.run!("backup")` |
| GET | /api/history | Web UI コンソールのログを取得 | `$stdout`, `$stdout2` |
| POST | /api/clear_history | PushServer とロガーの履歴をクリア | `Narou::PushServer` |
| GET | /api/tag_list | タグ一覧を HTML で返す | `Command::Tag` |
| POST | /api/taginfo.json | 選択小説のタグ情報サマリを返す | `Command::Tag`, `Database` |
| POST | /api/edit_tag | タグ付与／削除を実施 | `Command::Tag.execute!` |
| GET | /api/get_queue_size | WebWorker / Worker のキュー長を返す | `Narou::WebWorker`, `Narou::Worker` |
| POST | /api/update_general_lastup * | 更新日情報を再取得（必要なら modified タグも更新） | `CommandLine.run!("update", "--gl")`, `CommandLine.run!("update", "tag:modified")` |
| POST | /api/setting_burn * | 端末への書き込み設定を burn | `CommandLine.run!("setting", "--burn")` |
| POST | /api/change_tag_color | タグ色設定を保存しキャッシュをクリア | `Inventory` (`tag_colors`), PushServer |
| GET | /api/csv/download | 小説一覧を CSV としてダウンロード | `Command::Csv#generate` |
| POST | /api/csv/import | CSV から小説をインポート | `Command::Csv#import` |
| GET | /api/download4ssl * | SSL ブックマークレット用ダウンロード登録 | `CommandLine.run!("download")` |
| GET | /api/downloadable.gif | ダウンロード可否で返すボタン画像を切り替え | `Downloader.get_id_by_target` |
| GET | /api/validate_url_regexp_list | サイト設定に登録された URL 正規表現を返す | `SiteSetting` |
| GET | /api/version/current.json | 現在の Narou.rb バージョンを返す | `Narou::VERSION` |
| GET | /api/version/latest.json | 最新バージョンを照会 | `Narou.latest_version` |
| GET | /api/notepad/read | ノートパッドの内容を取得 | `File.read(notepad_text_path)` |
| POST | /api/notepad/save | ノートパッドの内容を保存 | `File.write`, PushServer |
| POST | /api/eject | 接続端末を取り外す（同期／非同期） | `Narou.get_device`, `Narou::WebWorker` |
| GET | /api/story | 小説情報とあらすじを取得 | `Downloader.get_toc_by_target`, `HTML#ln_to_br` |

この一覧を基に、起動時のモジュールロードおよび API テストケースを整備する際の依存把握に利用してください。
