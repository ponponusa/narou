#!/bin/bash

# Narou-mod Server Restart Script
# This script stops all running servers and restarts them in the background

echo "Stopping all existing server processes..."

# Stop frontend processes (npm/astro)
pkill -9 -f "npm.*dev" 2>/dev/null || true
pkill -9 -f "astro" 2>/dev/null || true

# Stop backend processes (narou.rb web)
pkill -9 -f "narou.rb web" 2>/dev/null || true
pkill -9 -f "ruby.*narou.rb.*web" 2>/dev/null || true
pkill -9 -f "narou-mod web" 2>/dev/null || true

echo "Waiting for processes to terminate..."
sleep 3

echo "Clearing bootsnap cache..."
rm -rf /home/ponta/git/narou-mod/tmp/bootsnap-cache/*

echo "Starting backend server..."
cd /home/ponta/git/narou-mod
nohup bundle exec ruby narou.rb web --no-browser > backend.log 2>&1 &
BACKEND_PID=$!

echo "Waiting for backend to initialize..."
sleep 5

# Check if backend process is still running
if ! ps -p $BACKEND_PID > /dev/null 2>&1; then
    echo "❌ Backend server failed to start. Check backend.log for details."
    cat backend.log
    exit 1
fi

echo "Starting frontend server..."
cd /home/ponta/git/narou-mod/frontend
nohup npm run dev > frontend.log 2>&1 &
FRONTEND_PID=$!

echo "Waiting for frontend to initialize..."
sleep 10

# Check server status by process, not by port
echo "Checking server status..."
BACKEND_RUNNING=false
FRONTEND_RUNNING=false

if ps -p $BACKEND_PID > /dev/null 2>&1; then
    BACKEND_RUNNING=true
    echo "✅ Backend server is running (PID: $BACKEND_PID)"
else
    echo "❌ Backend server stopped unexpectedly"
    echo "Backend log:"
    tail -20 backend.log
fi

if ps -p $FRONTEND_PID > /dev/null 2>&1; then
    FRONTEND_RUNNING=true
    echo "✅ Frontend server is running (PID: $FRONTEND_PID)"
else
    echo "❌ Frontend server stopped unexpectedly"
    echo "Frontend log:"
    tail -20 frontend/frontend.log
fi

if [ "$BACKEND_RUNNING" = true ] && [ "$FRONTEND_RUNNING" = true ]; then
    echo ""
    echo "✅ All servers are running successfully!"
    echo "  - Backend: http://localhost:5678 (PID: $BACKEND_PID)"
    echo "  - Frontend: http://localhost:4321 (PID: $FRONTEND_PID)"
    echo ""
    echo "Server restart completed."
else
    echo ""
    echo "❌ Some servers failed to start. Check the logs for details."
    exit 1
fi