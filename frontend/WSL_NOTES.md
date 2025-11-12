# WSL環境での開発に関する注意事項

## 問題: 開発サーバーの起動が遅い

WSL2環境（特にWindows filesystemをマウントしている場合）では、`npm run dev`での開発サーバー起動に時間がかかる、または起動しない場合があります。

### 原因

- WSL2のファイルシステムパフォーマンスの問題
- `/mnt/c/`配下のWindowsファイルシステムへのアクセスが遅い
- Node.jsの依存関係解決やHMRの監視処理が重い

### 推奨される回避策

#### 方法1: ビルド+プレビュー（推奨）

開発時も以下のコマンドを使用することを推奨します：

```bash
cd frontend

# 1. ビルド
npm run build

# 2. プレビューサーバー起動
npm run preview -- --host 0.0.0.0 --port 4321
```

**利点**:

- 起動が安定している
- プロダクション環境に近い状態でテスト可能
- パフォーマンスが良い

**欠点**:

- コード変更時に手動でリビルドが必要（HMRなし）

#### 方法2: WSLのホームディレクトリに移動

プロジェクトをWSLのネイティブファイルシステムに配置：

```bash
# プロジェクトをWSLホームにコピー
cp -r /mnt/c/git/narou ~/narou
cd ~/narou/frontend

# 通常通り起動
npm run dev
```

**利点**:

- `npm run dev`が高速に動作
- HMRが正常に機能

**欠点**:

- Windowsエクスプローラーからのアクセスが少し不便
- 同期が必要

#### 方法3: Docker環境の利用（今後検討）

Dockerコンテナ内で開発環境を構築する方法も検討できます。

## ネットワーク設定

WSL2では`localhost`が正しく動作しないことがあります。

### 解決策

IPアドレスを明示的に指定：

```bash
# WSL2のIPアドレスを確認
ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
# 例: 172.26.39.220
```

**設定ファイル**:

- `frontend/.env`: `PUBLIC_API_BASE_URL`にIPアドレスを設定
- `frontend/astro.config.mjs`: `server.host`を`'0.0.0.0'`に設定

## 起動手順（WSL環境）

### バックエンド起動

```bash
cd /mnt/c/git/narou
bundle exec ruby narou.rb web -p 33000
```

### フロントエンド起動（推奨方法）

```bash
cd /mnt/c/git/narou/frontend

# ビルド
npm run build

# プレビュー
npm run preview -- --host 0.0.0.0 --port 4321
```

**アクセスURL**:

- フロントエンド: `http://<WSL_IP>:4321/`
- バックエンド API: `http://<WSL_IP>:33000/`

例: `http://172.26.39.220:4321/`

## トラブルシューティング

### サーバーが起動しない

```bash
# プロセスを確認
ps aux | grep "astro\|ruby.*narou.rb web"

# ポートを確認
lsof -i :4321
lsof -i :33000

# 必要に応じてプロセスを停止
kill <PID>
```

### ビルドエラー

```bash
# キャッシュをクリア
cd frontend
rm -rf node_modules .astro dist
npm install
npm run build
```

### APIに接続できない

1. バックエンドが起動しているか確認
2. `.env`ファイルのIPアドレスが正しいか確認
3. ファイアウォールの設定を確認

## 参考情報

- [WSL2のファイルシステムパフォーマンス](https://learn.microsoft.com/ja-jp/windows/wsl/compare-versions#performance-across-os-file-systems)
- [Astro - Server Options](https://docs.astro.build/en/reference/configuration-reference/#server-options)
