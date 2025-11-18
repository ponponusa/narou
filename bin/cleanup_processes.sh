#!/bin/bash
# frozen_string_literal: true

#
# Copyright 2013 ponponusa
#
# narou-mod関連のプロセスをクリーンナップするスクリプト
#

set -e

echo "narou-mod関連のプロセスを検索中..."

# narou-mod関連のプロセスを検索（自分自身は除外）
# Ruby プロセス (narou.rb) と Node プロセス (astro dev) の両方を検出
PIDS=$(ps aux | grep -E "ruby.*narou\.rb|astro dev|narou-mod" | grep -v grep | grep -v "cleanup_processes" | awk '{print $2}' || true)

if [ -z "$PIDS" ]; then
  echo "実行中のnarou-mod関連プロセスは見つかりませんでした。"
  exit 0
fi

echo "以下のプロセスが見つかりました:"
echo "$PIDS" | while read -r pid; do
  ps -p "$pid" -o pid,cmd --no-headers 2>/dev/null || true
done

echo ""

# -y フラグで自動承認
AUTO_YES=false
if [ "$1" = "-y" ]; then
  AUTO_YES=true
fi

if [ "$AUTO_YES" = false ]; then
  read -p "これらのプロセスを終了しますか? (y/N): " -n 1 -r
  echo ""
  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "キャンセルしました。"
    exit 0
  fi
fi

echo "プロセスを終了中..."
echo "$PIDS" | while read -r pid; do
  if kill -0 "$pid" 2>/dev/null; then
    echo "  PID $pid を終了中..."
    kill "$pid" 2>/dev/null || true
    sleep 0.5
    
    # まだ生きていたら強制終了
    if kill -0 "$pid" 2>/dev/null; then
      echo "  PID $pid を強制終了中..."
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
done

echo "クリーンナップ完了。"
