#!/bin/bash
# frozen_string_literal: true

#
# Copyright 2025 ponponusa
#
# narou-mod プロセス管理スクリプト
# Usage: ./scripts/process_control.sh [--list|--restart|--kill] [--force]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# プロセス情報を収集
collect_processes() {
  # バックエンド: Rubyプロセスとpumaのみ（narou.rb web関連）
  local backend_pids=$(ps aux | grep -E "ruby.*narou\.rb.*web|puma.*\[narou-mod\]" | grep -v grep | awk '{print $2}' || true)

  # フロントエンド: npm/nodeプロセス（frontend配下のもの）
  # npmとastro関連のプロセスを検出
  local frontend_pids=$(ps aux | grep -E "npm run dev|node.*\.bin/astro" | grep -v grep | grep -v "process_control" | awk '{print $2}' || true)

  echo "$backend_pids|$frontend_pids"
}

# プロセス一覧を表示
show_list() {
  echo -e "${BLUE}=== narou-mod プロセス一覧 ===${NC}\n"

  # バックエンド: Ruby + Puma のみ
  local backend_pids=$(ps aux | grep -E "ruby.*narou\.rb.*web|puma.*\[narou-mod\]" | grep -v grep | awk '{print $2}' || true)

  # フロントエンド: npm + node/astro のみ
  local frontend_pids=$(ps aux | grep -E "npm run dev|node.*\.bin/astro" | grep -v grep | awk '{print $2}' || true)

  local has_processes=false

  # バックエンドプロセス
  if [ -n "$backend_pids" ]; then
    echo -e "${GREEN}Backend Server${NC} (Ruby/Sinatra API, Port: 5678)"
    printf "  ${YELLOW}%-8s %-12s %-10s %s${NC}\n" "PID" "TYPE" "PORT" "COMMAND"
    echo "$backend_pids" | while read -r pid; do
      if [ -n "$pid" ]; then
        local cmd=$(ps -p "$pid" -o cmd --no-headers 2>/dev/null || echo "不明")
        printf "  %-8s %-12s %-10s %s\n" "$pid" "Backend" "5678" "$cmd"
      fi
    done
    echo ""
    has_processes=true
  fi

  # フロントエンドプロセス
  if [ -n "$frontend_pids" ]; then
    echo -e "${GREEN}Frontend Server${NC} (Astro/Svelte, Port: 4321)"
    printf "  ${YELLOW}%-8s %-12s %-10s %s${NC}\n" "PID" "TYPE" "PORT" "COMMAND"
    echo "$frontend_pids" | while read -r pid; do
      if [ -n "$pid" ]; then
        local cmd=$(ps -p "$pid" -o cmd --no-headers 2>/dev/null || echo "不明")
        printf "  %-8s %-12s %-10s %s\n" "$pid" "Frontend" "4321" "$cmd"
      fi
    done
    echo ""
    has_processes=true
  fi

  if [ "$has_processes" = false ]; then
    echo -e "${YELLOW}実行中のプロセスは見つかりませんでした。${NC}"
  else
    # WebSocketポート情報（プロセスではなく設定ファイルから）
    if [ -f "$PROJECT_ROOT/frontend/.env" ]; then
      local ws_port=$(grep -oP 'PUBLIC_PUSH_SERVER_PORT=\K\d+' "$PROJECT_ROOT/frontend/.env" 2>/dev/null || echo "5679")
      echo -e "${GREEN}WebSocket Server${NC} (Port: $ws_port, バックエンドに含まれる)"
      echo ""
    fi
  fi
}

# プロセスを終了
kill_processes() {
  local force=$1

  local processes=$(collect_processes)
  local backend_pids=$(echo "$processes" | cut -d'|' -f1)
  local frontend_pids=$(echo "$processes" | cut -d'|' -f2)

  if [ -z "$backend_pids" ] && [ -z "$frontend_pids" ]; then
    echo -e "${YELLOW}終了するプロセスが見つかりませんでした。${NC}"
    return 0
  fi

  echo -e "${BLUE}=== プロセス終了 ===${NC}\n"

  # 確認プロンプト
  if [ "$force" != "true" ]; then
    echo "以下のプロセスを終了します:"

    if [ -n "$backend_pids" ]; then
      echo -e "\n${GREEN}Backend:${NC}"
      echo "$backend_pids" | while read -r pid; do
        if [ -n "$pid" ]; then
          local cmd=$(ps -p "$pid" -o cmd --no-headers 2>/dev/null || echo "不明")
          echo -e "  ${YELLOW}PID $pid${NC}: $cmd"
        fi
      done
    fi

    if [ -n "$frontend_pids" ]; then
      echo -e "\n${GREEN}Frontend:${NC}"
      echo "$frontend_pids" | while read -r pid; do
        if [ -n "$pid" ]; then
          local cmd=$(ps -p "$pid" -o cmd --no-headers 2>/dev/null || echo "不明")
          echo -e "  ${YELLOW}PID $pid${NC}: $cmd"
        fi
      done
    fi

    echo ""
    read -p "これらのプロセスを終了しますか? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}キャンセルしました。${NC}"
      return 1
    fi
  fi

  echo "プロセスを終了中..."

  # バックエンドプロセス終了
  if [ -n "$backend_pids" ]; then
    echo "$backend_pids" | while read -r pid; do
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "  Backend PID $pid を終了中..."
        kill "$pid" 2>/dev/null || true
        sleep 0.5

        # まだ生きていたら強制終了
        if kill -0 "$pid" 2>/dev/null; then
          echo "  Backend PID $pid を強制終了中..."
          kill -9 "$pid" 2>/dev/null || true
        fi
      fi
    done
  fi

  # フロントエンドプロセス終了
  if [ -n "$frontend_pids" ]; then
    echo "$frontend_pids" | while read -r pid; do
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "  Frontend PID $pid を終了中..."
        kill "$pid" 2>/dev/null || true
        sleep 0.5

        # まだ生きていたら強制終了
        if kill -0 "$pid" 2>/dev/null; then
          echo "  Frontend PID $pid を強制終了中..."
          kill -9 "$pid" 2>/dev/null || true
        fi
      fi
    done
  fi

  # パターンマッチでの追加クリーンアップ（取りこぼし対策）
  pkill -9 -f "node.*astro.*dev" 2>/dev/null || true
  pkill -9 -f "npm.*run.*dev" 2>/dev/null || true
  pkill -9 -f "narou.rb.*web" 2>/dev/null || true
  pkill -9 -f "puma.*narou" 2>/dev/null || true

  sleep 1
  echo -e "${GREEN}プロセス終了完了。${NC}"
}

# サーバーを起動
start_servers() {
  echo -e "${BLUE}=== サーバー起動 ===${NC}\n"

  cd "$PROJECT_ROOT"

  # Bootsnap キャッシュをクリア
  echo "Bootsnap キャッシュをクリア中..."
  rm -rf "$PROJECT_ROOT/tmp/bootsnap-cache/"* 2>/dev/null || true

  # バックエンド起動
  echo -e "\n${GREEN}バックエンドサーバーを起動中...${NC}"
  nohup bundle exec ruby bin/narou-mod web --no-browser > backend.log 2>&1 &
  BACKEND_PID=$!
  echo "  PID: $BACKEND_PID"

  echo "バックエンドの初期化を待機中..."
  sleep 5

  # バックエンドが起動しているか確認
  if ! ps -p $BACKEND_PID > /dev/null 2>&1; then
    echo -e "${RED}❌ バックエンドサーバーの起動に失敗しました。${NC}"
    echo "ログを確認してください: $PROJECT_ROOT/backend.log"
    tail -20 "$PROJECT_ROOT/backend.log"
    exit 1
  fi

  # ポート情報取得
  local backend_port=5678
  local ws_port=5679
  if [ -f "$PROJECT_ROOT/frontend/.env" ]; then
    backend_port=$(grep -oP '(?<=localhost:)\d+' "$PROJECT_ROOT/frontend/astro.config.mjs" 2>/dev/null | head -1 || echo "5678")
    ws_port=$(grep -oP 'PUBLIC_PUSH_SERVER_PORT=\K\d+' "$PROJECT_ROOT/frontend/.env" 2>/dev/null || echo "5679")
  fi

  # フロントエンドはバックエンドが自動起動するので待機のみ
  echo -e "\n${GREEN}フロントエンドサーバーの起動を待機中...${NC}"
  echo "  (バックエンドが自動的にフロントエンドを起動します)"
  sleep 10

  # フロントエンドプロセスを検索
  local frontend_pid=$(ps aux | grep -E "npm run dev" | grep -v grep | head -1 | awk '{print $2}')

  # 起動確認
  echo -e "\n${BLUE}=== サーバー状態確認 ===${NC}\n"

  local all_ok=true

  if ps -p $BACKEND_PID > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Backend Server${NC}"
    echo "   URL: http://localhost:$backend_port"
    echo "   PID: $BACKEND_PID"
  else
    echo -e "${RED}❌ Backend Server (起動失敗)${NC}"
    all_ok=false
  fi

  if [ -n "$frontend_pid" ] && ps -p $frontend_pid > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Frontend Server${NC}"
    echo "   URL: http://localhost:4321"
    echo "   PID: $frontend_pid"
  else
    echo -e "${RED}❌ Frontend Server (起動失敗)${NC}"
    all_ok=false
  fi

  echo -e "${GREEN}✅ WebSocket Server${NC}"
  echo "   Port: $ws_port"

  echo ""

  if [ "$all_ok" = true ]; then
    echo -e "${GREEN}✅ すべてのサーバーが正常に起動しました！${NC}"
    return 0
  else
    echo -e "${RED}❌ 一部のサーバーの起動に失敗しました。ログを確認してください。${NC}"
    return 1
  fi
}

# 再起動
restart_servers() {
  local force=$1

  echo -e "${BLUE}=== サーバー再起動 ===${NC}\n"

  # プロセスを終了
  kill_processes "$force"

  if [ $? -ne 0 ]; then
    # ユーザーがキャンセルした場合
    return 1
  fi

  echo ""
  sleep 2

  # サーバーを起動
  start_servers
}

# ヘルプ表示
show_help() {
  cat << EOF
${BLUE}narou-mod プロセス管理スクリプト${NC}

${GREEN}使い方:${NC}
  $0 [オプション]

${GREEN}オプション:${NC}
  --list      実行中のプロセス一覧と詳細を表示
  --restart   すべてのプロセスを終了して再起動
  --kill      すべてのプロセスを終了
  --force     --restart または --kill 実行時に確認を省略
  --help      このヘルプを表示

${GREEN}使用例:${NC}
  $0 --list                 # プロセス一覧を表示
  $0 --restart              # 確認後に再起動
  $0 --restart --force      # 確認なしで即座に再起動
  $0 --kill                 # 確認後に全プロセス終了
  $0 --kill --force         # 確認なしで即座に全プロセス終了

${GREEN}プロセスの役割:${NC}
  Backend Server   - Ruby (Sinatra) API サーバー (ポート: 5678)
  Frontend Server  - Astro + Svelte 開発サーバー (ポート: 4321)
  WebSocket Server - リアルタイム更新通知 (ポート: 5679)

EOF
}

# メイン処理
main() {
  local action=""
  local force=false

  # 引数解析
  while [[ $# -gt 0 ]]; do
    case $1 in
      --list)
        action="list"
        shift
        ;;
      --restart)
        action="restart"
        shift
        ;;
      --kill)
        action="kill"
        shift
        ;;
      --force)
        force=true
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        echo -e "${RED}エラー: 不明なオプション: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
    esac
  done

  # アクションが指定されていない場合はヘルプを表示
  if [ -z "$action" ]; then
    show_help
    exit 0
  fi

  # アクション実行
  case $action in
    list)
      show_list
      ;;
    kill)
      kill_processes "$force"
      ;;
    restart)
      restart_servers "$force"
      ;;
  esac
}

# スクリプト実行
main "$@"
