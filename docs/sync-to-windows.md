# Windows環境への同期スクリプト

WSL環境からWindows側のディレクトリへnarou-modプロジェクトを同期するためのスクリプトです。

## 概要

- **同期方式**: 同期元を主として、同期先を上書き
- **設定方法**: 引数指定、または rsync.env ファイル

## 使い方

### 方法1: rsync.env ファイルを使用（推奨）

1. **設定ファイルの作成**

   ```bash
   # サンプルファイルをコピー
   cp rsync.env.example rsync.env
   
   # 設定を編集
   nano rsync.env
   ```

2. **rsync.env の編集例**

   ```bash
   # 同期元ディレクトリ (WSL環境)
   SRC_DIR="$HOME/git/narou-mod"
   
   # 同期先ディレクトリ (Windows環境)
   # 例: /mnt/c/git/narou → C:\git\narou
   DEST_DIR="/mnt/c/git/narou"
   ```

3. **スクリプト実行**

   ```bash
   ./sync-to-windows.sh
   ```

### 方法2: コマンドライン引数で指定

```bash
./sync-to-windows.sh ~/git/narou-mod /mnt/c/git/narou
```

### 方法3: ヘルプを表示

```bash
./sync-to-windows.sh --help
```

## 設定の優先順位

1. **コマンドライン引数** - 最優先
2. **rsync.env ファイル** - カレントディレクトリまたはスクリプトと同じディレクトリ
3. **エラー** - 設定が見つからない場合

## 初回実行前の確認事項

1. **Windows側のディレクトリ確認**

   スクリプトは自動的に同期先のディレクトリを作成しますが、事前に確認したい場合:

   ```bash
   ls -la /mnt/c/git/
   ```

2. **除外ファイルの確認**

   `.rsyncignore` ファイルに記載されたパターンは同期から除外されます:

   ```bash
   cat .rsyncignore
   ```

## rsyncオプションの説明

スクリプトは以下のオプションでrsyncを実行します:

- `-a`: アーカイブモード（再帰的、パーミッション・タイムスタンプ保持）
- `-v`: 詳細表示
- `-h`: 人間が読みやすい形式でサイズ表示
- `--delete`: 同期先に存在するが同期元にないファイルを削除
- `--progress`: 進捗表示
- `--itemize-changes`: 変更内容を詳細表示
- `--exclude-from`: `.rsyncignore` からの除外設定を適用

## 除外される主なファイル・ディレクトリ

- `.git/` - Gitリポジトリデータ
- `node_modules/` - Node.js依存パッケージ
- `tmp/` - 一時ファイル
- `coverage/` - テストカバレッジデータ
- `小説データ/` - 小説データディレクトリ
- `*.log` - ログファイル

詳細は `.rsyncignore` ファイルを参照してください。

## 注意事項

### 同期方向について

このスクリプトは **一方向同期（WSL → Windows）** です。

- ✅ WSL側で行った変更がWindows側に反映されます
- ⚠️ Windows側で行った変更は **同期時に上書きされます**
- ⚠️ `--delete` オプションにより、Windows側のみに存在するファイルは削除されます

### 双方向同期が必要な場合

Windows側でも開発を行う場合は、以下のいずれかの方法を検討してください:

1. **Gitを使用した同期**

   ```bash
   # Windows側で変更をコミット
   cd C:\git\narou
   git add .
   git commit -m "Windows側での変更"
   
   # WSL側でpull
   cd ~/git/narou-mod
   git pull
   ```

2. **逆方向の同期スクリプト**

   Windows → WSL の同期が必要な場合は、`sync-from-windows.sh` を作成してください。

### パフォーマンスについて

WSLとWindows間のファイルアクセスは、同一ファイルシステム内よりも遅い場合があります。大量のファイルを同期する場合は時間がかかることがあります。

## トラブルシューティング

### エラー: 同期元/同期先ディレクトリが指定されていません

設定ファイルを作成するか、コマンドライン引数で指定してください:

```bash
# rsync.env を作成
cp rsync.env.example rsync.env
nano rsync.env

# または引数で指定
./sync-to-windows.sh ~/git/narou-mod /mnt/c/git/narou
```

### エラー: 同期元ディレクトリが見つかりません

rsync.env またはコマンドライン引数で指定したパスを確認してください:

```bash
# ホームディレクトリを確認
echo $HOME

# narou-modディレクトリの存在確認
ls -la ~/git/

# rsync.env の設定確認
cat rsync.env
```

### エラー: Permission denied

```bash
# スクリプトに実行権限を付与
chmod +x sync-to-windows.sh
```

### 同期先のWindowsパスが見つからない

```bash
# Cドライブのマウント確認
ls -la /mnt/c/

# 手動でディレクトリ作成
mkdir -p /mnt/c/git/narou
```

## カスタマイズ

### 同期先を変更する

rsync.env ファイルまたはコマンドライン引数で変更してください:

#### 方法1: rsync.env を編集

```bash
# rsync.env を編集
nano rsync.env

# 例: Dドライブに変更
DEST_DIR="/mnt/d/projects/narou"
```

#### 方法2: コマンドライン引数で指定

```bash
./sync-to-windows.sh ~/git/narou-mod /mnt/d/projects/narou
```

### 追加の除外パターンを設定

`.rsyncignore` ファイルに除外パターンを追加してください:

```bash
# .rsyncignore に追加
echo "my_custom_dir" >> .rsyncignore
echo "*.bak" >> .rsyncignore
```

## 関連ファイル

- `sync-to-windows.sh` - 同期スクリプト本体
- `rsync.env` - 同期設定ファイル（要作成）
- `rsync.env.example` - 設定ファイルのサンプル
- `.rsyncignore` - 除外パターン設定ファイル
- `AGENTS.md` - プロジェクト全体のガイドライン
