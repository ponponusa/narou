# プロセス管理とポート競合の処理

## 概要

narou-modは堅牢なプロセス管理機能を提供し、サーバーの起動・終了時に発生する問題を自動的に検出・解決します。

## 機能

### 1. 自動プロセス検出

サーバー起動時に、以下をチェックします:

- 既存のnarou-modプロセスが実行中かどうか
- 必要なポート(デフォルト: 5678, 5679, 4321)が使用可能かどうか
- プロセス情報ファイル(`tmp/pids/*.pid`)の整合性

### 2. ポート競合検出

起動時に以下のポートをチェックします:

- **5678**: バックエンドAPI(Puma)
- **5679**: PushServer(WebSocket)
- **4321**: フロントエンド(Astro dev server)

ポートが既に使用されている場合、使用しているプロセスを特定して表示します。

### 3. インタラクティブなクリーンアップ

プロセスやポートの競合が検出された場合、以下の選択肢を提示します:

```bash
サービス 'narou-backend' は既に起動しています (PID: 12345)

プロセス情報:
- 起動時刻: 2025-11-18T14:30:00+09:00
- ポート: 5678
- プラットフォーム: x86_64-linux

自動的にクリーンアップしますか? (y/N):
```

### 4. 強制起動オプション

`--force`オプションを使用すると、既存プロセスを自動的に停止して起動します:

```bash
bundle exec ruby narou.rb web --force
```

## プロセス情報ファイル

プロセス情報は`tmp/pids/`ディレクトリに保存されます:

```bash
tmp/pids/
├── narou-backend.pid    # バックエンドプロセス情報
├── narou-backend.port   # 使用ポート
├── narou-frontend.pid   # フロントエンドプロセス情報
└── narou-frontend.port  # 使用ポート
```

### PIDファイルの構造

```json
{
  "pid": 12345,
  "ppid": 12344,
  "started_at": "2025-11-18T14:30:00+09:00",
  "platform": "x86_64-linux",
  "ruby_version": "3.4.7",
  "service": "narou-backend",
  "port": 5678,
  "metadata": {
    "host": "127.0.0.1",
    "frontend_enabled": true
  }
}
```

## 使用例

### 通常起動

```bash
bundle exec ruby narou.rb web
```

競合がある場合、自動的に検出して対話的に処理します。

### 強制起動

```bash
bundle exec ruby narou.rb web --force
```

既存プロセスを自動的に停止して起動します。

### プロセスのクリーンアップ

```bash
./bin/cleanup_processes.sh
```

または

```bash
./bin/cleanup_processes.sh -y  # 自動承認
```

## トラブルシューティング

### ポート競合エラー

```bash
ポート 5678 は既に使用されています。

使用しているプロセス:
12345 12344 user ruby narou.rb web
```

**対処法:**

1. 表示されたプロセスを手動で停止: `kill 12345`
2. クリーンアップスクリプトを実行: `./bin/cleanup_processes.sh`
3. 別のポートを指定: `narou web -p 8000`
4. 強制起動: `narou web --force`

### Windows/WSL、ホスト/Docker環境での注意点

Windows側とWSL側や、ホスト側とDocker側で別々にプロセスが起動している可能性があります:

1. **Windows/ホストOS側を確認**: タスクマネージャーまたは`tasklist | findstr ruby`や、ホストOSのプロセス管理ツールで確認
2. **WSL/Docker側を確認**: `ps aux | grep ruby`
3. **両方をクリーンアップ**: 各環境で`cleanup_processes.sh`を実行

### PIDファイルが残っている

プロセスが異常終了した場合、PIDファイルが残ることがあります:

```bash
rm -f tmp/pids/*.pid tmp/pids/*.port
```

または起動時に自動的にクリーンアップされます。

## 内部実装

### Narou::ProcessManager

プロセス管理を担当するクラス。主な機能:

- `register_process(port:, metadata:)` - プロセス情報を登録
- `process_running?(pid)` - プロセスの実行状態を確認
- `port_in_use?(port, host)` - ポートの使用状態を確認
- `cleanup_stale_process!` - 古いプロセスをクリーンアップ
- `check_port_conflict!(port, host)` - ポート競合を検出
- `stop_process(signal:, timeout:)` - プロセスを停止

### プラットフォーム対応

ポート使用プロセスの特定は各プラットフォームに対応:

- **Linux**: `lsof`, `ss`コマンド
- **macOS**: `lsof`コマンド
- **Windows**: `netstat`, `tasklist`コマンド

## セキュリティ

- PIDファイルはローカルファイルシステムのみに保存
- プロセス停止には適切なシグナル(TERM → KILL)を使用
- 権限エラーを適切にハンドリング

## 参考資料

- [process_manager.rb](../lib/narou/process_manager.rb) - 実装
- [process_manager_spec.rb](../spec/narou/process_manager_spec.rb) - テスト
- [cleanup_processes.sh](../bin/cleanup_processes.sh) - クリーンアップスクリプト
