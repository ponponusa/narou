#!/bin/bash

# Narou-mod Server Restart Script
# This script stops all running servers and restarts them in the background

echo "Stopping all existing server processes..."

# Stop frontend processes
pkill -9 -f "npm.*dev" 2>/dev/null || true
pkill -9 -f "astro" 2>/dev/null || true

# Stop backend processes
pkill -9 -f "narou.rb web" 2>/dev/null || true
pkill -9 -f "ruby.*narou.rb.*web" 2>/dev/null || true

echo "Waiting for processes to terminate..."
sleep 3

echo "Clearing bootsnap cache..."
rm -rf /home/ponta/git/narou-mod/tmp/bootsnap-cache/*

echo "Starting backend server..."
cd /home/ponta/git/narou-mod
bundle exec ruby narou.rb web &
BACKEND_PID=$!

echo "Waiting for backend to initialize..."
sleep 5

echo "Starting frontend server..."
cd /home/ponta/git/narou-mod/frontend
nohup npm run dev > frontend.log 2>&1 &
FRONTEND_PID=$!

echo "Waiting for frontend to initialize..."
sleep 10

echo "Checking server status..."
if lsof -i :33000 >/dev/null 2>&1 && lsof -i :33001 >/dev/null 2>&1 && lsof -i :4321 >/dev/null 2>&1; then
    echo "✅ All servers are running successfully!"
    echo "  - Backend: http://localhost:33000 (PID: $BACKEND_PID)"
    echo "  - Frontend: http://localhost:4321 (PID: $FRONTEND_PID)"
    echo "  - WebSocket: localhost:33001"
else
    echo "❌ Some servers failed to start. Check the logs for details."
    exit 1
fi

echo "Server restart completed."