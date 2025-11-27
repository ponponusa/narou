# 開発環境セットアップガイド

このドキュメントでは、Narou.rb MOD の開発に必要な Node.js v24 と Ruby 3.4 以降のインストール方法を解説します。

## 必要なバージョン

| ツール  | 必須バージョン | 推奨バージョン |
| ------- | -------------- | -------------- |
| Node.js | v24.0.0 以上   | v24.x LTS      |
| Ruby    | 3.4.0 以上     | 3.4.x          |

> **Note**: プロジェクトルートに `.nvmrc`（Node.js）が配置されています。
> nvm を使用すると、このファイルから自動的にバージョンが設定されます。

---

## Windows 向けセットアップ

### Node.js のインストール（nvm-windows 推奨）

#### 1. nvm-windows のインストール

1. [nvm-windows Releases](https://github.com/coreybutler/nvm-windows/releases) から最新の `nvm-setup.exe` をダウンロード
2. インストーラーを実行し、指示に従ってインストール
3. **PowerShell または コマンドプロンプトを再起動**

#### 2. Node.js v24 のインストール

```powershell
# 利用可能なバージョンを確認
nvm list available

# Node.js v24 をインストール
nvm install 24

# v24 を使用するように設定
nvm use 24

# バージョン確認
node -v
# => v24.x.x
```

#### 3. プロジェクトでの自動切り替え

nvm-windows は `.nvmrc` を自動で読み込みません。プロジェクトディレクトリで手動で切り替えてください：

```powershell
cd path\to\narou-mod
nvm use 24
```

### Ruby のインストール（RubyInstaller + MSYS2 推奨）

#### 1. RubyInstaller のダウンロード

1. [RubyInstaller Downloads](https://rubyinstaller.org/downloads/) にアクセス
2. **Ruby+Devkit 3.4.x (x64)** をダウンロード（Devkit 付きを選択）

#### 2. インストール

1. ダウンロードしたインストーラーを実行
2. 「Add Ruby executables to your PATH」にチェックを入れる
3. 「Associate .rb and .rbw files with this Ruby installation」にチェックを入れる
4. インストール完了後、MSYS2 のセットアップ画面が表示される
5. **「MSYS2 and MINGW development toolchain」を選択してインストール**（Enter キーを押す）

#### 3. バージョン確認

```powershell
ruby -v
# => ruby 3.4.x ...

gem -v
# => 3.x.x
```

#### 4. Bundler のインストール

```powershell
gem install bundler
```

---

## Linux 向けセットアップ

### Node.js のインストール

#### オプション A: nvm（推奨）

```bash
# nvm のインストール
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# シェルを再起動、または以下を実行
source ~/.bashrc  # bash の場合
source ~/.zshrc   # zsh の場合

# Node.js v24 をインストール
nvm install 24

# デフォルトに設定
nvm alias default 24

# バージョン確認
node -v
# => v24.x.x
```

> **Tip**: nvm は `.nvmrc` ファイルを自動で認識します。プロジェクトディレクトリに入ると自動で切り替わります（`nvm use` の実行が必要な場合もあります）。

#### オプション B: nodenv

```bash
# nodenv のインストール（git clone 方式）
git clone https://github.com/nodenv/nodenv.git ~/.nodenv
cd ~/.nodenv && src/configure && make -C src

# PATH に追加（~/.bashrc または ~/.zshrc に追記）
echo 'export PATH="$HOME/.nodenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(nodenv init -)"' >> ~/.bashrc
source ~/.bashrc

# node-build プラグインをインストール
git clone https://github.com/nodenv/node-build.git ~/.nodenv/plugins/node-build

# Node.js v24 をインストール
nodenv install 24.0.0
nodenv global 24.0.0

# バージョン確認
node -v
```

#### オプション C: mise（旧 rtx）

mise は Node.js と Ruby の両方を管理できる万能ツールです。

```bash
# mise のインストール
curl https://mise.run | sh

# PATH に追加（~/.bashrc または ~/.zshrc に追記）
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

# Node.js v24 をインストール
mise use --global node@24

# バージョン確認
node -v
```

### Ruby のインストール

#### オプション A: rbenv（推奨）

```bash
# 依存パッケージのインストール（Ubuntu/Debian）
sudo apt update
sudo apt install -y build-essential libssl-dev libreadline-dev zlib1g-dev \
  libyaml-dev libffi-dev libgdbm-dev libncurses5-dev libgmp-dev

# rbenv のインストール
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
cd ~/.rbenv && src/configure && make -C src

# PATH に追加（~/.bashrc または ~/.zshrc に追記）
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# ruby-build プラグインをインストール
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# Ruby 3.4 をインストール
rbenv install 3.4.0
rbenv global 3.4.0

# バージョン確認
ruby -v
# => ruby 3.4.0 ...
```

> **Tip**: rbenv は `.ruby-version` ファイルを自動で認識します。

#### オプション B: mise（旧 rtx）

```bash
# mise がインストール済みの場合
mise use --global ruby@3.4

# バージョン確認
ruby -v
```

### Bundler のインストール

```bash
gem install bundler
```

---

## macOS 向けセットアップ

### Node.js のインストール（nvm 推奨）

```bash
# Homebrew で nvm をインストール
brew install nvm

# nvm ディレクトリを作成
mkdir ~/.nvm

# ~/.zshrc に追加
echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
echo '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"' >> ~/.zshrc
source ~/.zshrc

# Node.js v24 をインストール
nvm install 24
nvm alias default 24

# バージョン確認
node -v
```

### Ruby のインストール（rbenv 推奨）

```bash
# Homebrew で rbenv をインストール
brew install rbenv ruby-build

# ~/.zshrc に追加
echo 'eval "$(rbenv init -)"' >> ~/.zshrc
source ~/.zshrc

# Ruby 3.4 をインストール
rbenv install 3.4.0
rbenv global 3.4.0

# バージョン確認
ruby -v
```

---

## プロジェクトのセットアップ

バージョンマネージャーのセットアップが完了したら、プロジェクトの依存関係をインストールします。

### バックエンド（Ruby）

```bash
cd /path/to/narou-mod

# Ruby バージョンの確認（.ruby-version が読み込まれているか）
ruby -v
# => ruby 3.4.0 ...

# 依存関係のインストール
bundle install
```

### フロントエンド（Node.js）

```bash
cd /path/to/narou-mod/frontend

# Node.js バージョンの確認（.nvmrc が読み込まれているか）
node -v
# => v24.x.x

# 依存関係のインストール
npm install
```

---

## 開発サーバーの起動

```bash
# プロジェクトルートから
cd /path/to/narou-mod

# バックエンド + フロントエンドを同時起動
./bin/restart_servers.sh

# または個別に起動
# バックエンド
bundle exec ruby bin/narou-mod web

# フロントエンド（別ターミナル）
cd frontend && npm run dev
```

---

## トラブルシューティング

### Node.js 関連

#### nvm: command not found

シェルの設定ファイルに nvm の初期化スクリプトが追加されていない可能性があります。

```bash
# ~/.bashrc または ~/.zshrc を確認
cat ~/.bashrc | grep nvm
```

#### node: command not found（nvm インストール後）

```bash
# nvm で使用するバージョンを指定
nvm use 24
```

### Ruby 関連

#### rbenv: command not found

```bash
# PATH を確認
echo $PATH | grep rbenv

# 初期化スクリプトを再読み込み
source ~/.bashrc
```

#### OpenSSL 関連のエラー（Ruby インストール時）

```bash
# Ubuntu/Debian
sudo apt install libssl-dev

# macOS
brew install openssl
RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl)" rbenv install 3.4.0
```

#### libyaml 関連のエラー

```bash
# Ubuntu/Debian
sudo apt install libyaml-dev

# macOS
brew install libyaml
```

### Windows 固有の問題

#### MSYS2 関連のエラー

RubyInstaller の MSYS2 セットアップで問題が発生した場合：

```powershell
# MSYS2 を再セットアップ
ridk install 1 2 3
```

#### native extension のビルドエラー

```powershell
# MSYS2 の開発ツールチェーンを再インストール
ridk exec pacman -S --noconfirm mingw-w64-ucrt-x86_64-toolchain
```

---

## 参考リンク

- [nvm (Node Version Manager)](https://github.com/nvm-sh/nvm)
- [nvm-windows](https://github.com/coreybutler/nvm-windows)
- [nodenv](https://github.com/nodenv/nodenv)
- [rbenv](https://github.com/rbenv/rbenv)
- [RubyInstaller for Windows](https://rubyinstaller.org/)
- [mise (旧 rtx)](https://mise.jdx.dev/)
