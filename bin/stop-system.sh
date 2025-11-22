#!/bin/bash
#
# AI開発システム停止スクリプト
# 全デーモンを停止
#

set -uo pipefail

echo "=========================================="
echo "Stopping AI Development System"
echo "=========================================="

# デーモンを停止
echo "Stopping Planner Daemon..."
pkill -f "planner-daemon.sh" 2>/dev/null && echo "  Stopped" || echo "  Not running"

echo "Stopping Worker Daemon..."
pkill -f "worker-daemon.sh" 2>/dev/null && echo "  Stopped" || echo "  Not running"

echo "Stopping Watcher..."
pkill -f "watcher.sh" 2>/dev/null && echo "  Stopped" || echo "  Not running"

# fswatch プロセスも停止
echo "Stopping fswatch processes..."
pkill -f "fswatch.*queue" 2>/dev/null && echo "  Stopped" || echo "  Not running"

sleep 1

# 確認
REMAINING=$(ps aux | grep -E "(planner-daemon|worker-daemon|watcher.sh)" | grep -v grep | wc -l)
if [ "$REMAINING" -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "System Stopped Successfully"
    echo "=========================================="
else
    echo ""
    echo "Warning: Some processes may still be running"
    ps aux | grep -E "(planner-daemon|worker-daemon|watcher.sh)" | grep -v grep
fi
