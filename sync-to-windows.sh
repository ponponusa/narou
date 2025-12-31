#!/bin/bash
# WSL環境からWindows側へnarou-modプロジェクトを同期するスクリプト

set -e

# カラー出力設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ヘルプ表示
show_help() {
    cat << EOF
${GREEN}使い方:${NC}
  $0 [同期元] [同期先]
  
${GREEN}説明:${NC}
  WSL環境からWindows環境へプロジェクトファイルを同期します。
  
${GREEN}引数:${NC}
  同期元    同期元ディレクトリのパス (デフォルト: rsync.env から読み込み)
  同期先    同期先ディレクトリのパス (デフォルト: rsync.env から読み込み)
  
${GREEN}設定ファイル (rsync.env):${NC}
  引数が指定されていない場合、カレントディレクトリまたはスクリプトと
  同じディレクトリの rsync.env ファイルから設定を読み込みます。
  
  rsync.env の例:
    SRC_DIR="$HOME/git/narou-mod"
    DEST_DIR="/mnt/c/git/narou"
  
${GREEN}優先順位:${NC}
  1. コマンドライン引数
  2. rsync.env ファイル
  3. エラー (設定が見つからない場合)
  
${GREEN}例:${NC}
  # 引数で指定
  $0 ~/git/narou-mod /mnt/c/git/narou
  
  # rsync.env を使用
  $0
  
${GREEN}オプション:${NC}
  -h, --help    このヘルプを表示
  
EOF
    exit 0
}

# ヘルプオプションのチェック
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
fi

# 同期元・同期先の設定
SRC_DIR=""
DEST_DIR=""

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. コマンドライン引数から取得
if [ -n "$1" ]; then
    SRC_DIR="$1"
fi
if [ -n "$2" ]; then
    DEST_DIR="$2"
fi

# 2. rsync.env ファイルから読み込み（引数が指定されていない場合）
if [ -z "$SRC_DIR" ] || [ -z "$DEST_DIR" ]; then
    # カレントディレクトリのrsync.envを優先
    if [ -f "./rsync.env" ]; then
        echo -e "${BLUE}カレントディレクトリの rsync.env を読み込んでいます...${NC}"
        source "./rsync.env"
    # スクリプトと同じディレクトリのrsync.envを次に確認
    elif [ -f "$SCRIPT_DIR/rsync.env" ]; then
        echo -e "${BLUE}$SCRIPT_DIR/rsync.env を読み込んでいます...${NC}"
        source "$SCRIPT_DIR/rsync.env"
    fi
fi

# 3. 設定の検証
if [ -z "$SRC_DIR" ]; then
    echo -e "${RED}エラー: 同期元ディレクトリが指定されていません${NC}"
    echo ""
    echo "以下のいずれかの方法で同期元を指定してください:"
    echo "  1. コマンドライン引数: $0 <同期元> <同期先>"
    echo "  2. rsync.env ファイルを作成: SRC_DIR=\"/path/to/source\""
    echo ""
    echo "詳細は '$0 --help' を参照してください"
    exit 1
fi

if [ -z "$DEST_DIR" ]; then
    echo -e "${RED}エラー: 同期先ディレクトリが指定されていません${NC}"
    echo ""
    echo "以下のいずれかの方法で同期先を指定してください:"
    echo "  1. コマンドライン引数: $0 <同期元> <同期先>"
    echo "  2. rsync.env ファイルを作成: DEST_DIR=\"/path/to/destination\""
    echo ""
    echo "詳細は '$0 --help' を参照してください"
    exit 1
fi

# パスの展開（~などを解決）
SRC_DIR=$(eval echo "$SRC_DIR")
DEST_DIR=$(eval echo "$DEST_DIR")

echo -e "${GREEN}=== narou-mod Windows同期スクリプト ===${NC}"
echo -e "同期元: ${YELLOW}${SRC_DIR}${NC}"
echo -e "同期先: ${YELLOW}${DEST_DIR}${NC}"
echo ""

# 同期元ディレクトリの存在チェック
if [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}エラー: 同期元ディレクトリが見つかりません: ${SRC_DIR}${NC}"
    exit 1
fi

# 同期先の親ディレクトリが存在しない場合は作成
DEST_PARENT=$(dirname "$DEST_DIR")
if [ ! -d "$DEST_PARENT" ]; then
    echo -e "${YELLOW}同期先の親ディレクトリを作成します: ${DEST_PARENT}${NC}"
    mkdir -p "$DEST_PARENT"
fi

# rsyncオプションの説明:
# -a: アーカイブモード（再帰的、パーミッション・タイムスタンプ保持）
# -v: 詳細表示
# -h: 人間が読みやすい形式でサイズ表示
# --delete: 同期先に存在するが同期元にないファイルを削除
# --exclude-from: 除外ファイルリストを指定
# --progress: 進捗表示
# --itemize-changes: 変更内容を詳細表示

RSYNC_OPTS=(
    -avh
    --delete
    --progress
    --itemize-changes
)

# .rsyncignoreファイルが存在する場合は除外設定として使用
if [ -f "$SRC_DIR/.rsyncignore" ]; then
    RSYNC_OPTS+=(--exclude-from="$SRC_DIR/.rsyncignore")
    echo -e "${GREEN}.rsyncignore を使用して除外設定を適用します${NC}"
else
    echo -e "${YELLOW}警告: .rsyncignore が見つかりません。すべてのファイルが同期されます${NC}"
fi

# 追加の除外パターン（WSL/Windows固有）
RSYNC_OPTS+=(
    --exclude='.git/'
    --exclude='node_modules/'
    --exclude='tmp/'
    --exclude='coverage/'
    --exclude='*.log'
    --exclude='.DS_Store'
    --exclude='Thumbs.db'
)

echo ""
echo -e "${GREEN}同期を開始します...${NC}"
echo ""

# rsync実行
if rsync "${RSYNC_OPTS[@]}" "$SRC_DIR/" "$DEST_DIR/"; then
    echo ""
    echo -e "${GREEN}✓ 同期が完了しました${NC}"
    echo -e "同期先: ${YELLOW}${DEST_DIR}${NC}"
    
    # Windows側のパスも表示
    WIN_PATH=$(echo "$DEST_DIR" | sed 's|/mnt/\(.\)|\U\1:|')
    echo -e "Windowsパス: ${YELLOW}${WIN_PATH}${NC}"
else
    echo ""
    echo -e "${RED}✗ 同期中にエラーが発生しました${NC}"
    exit 1
fi
