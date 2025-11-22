#!/bin/bash
#
# AI開発システム起動スクリプト
# 全デーモンを起動してシステムを開始
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"

# GITHUB_REPO チェック
if [ -z "${GITHUB_REPO:-}" ]; then
    echo "Error: GITHUB_REPO environment variable not set" >&2
    echo "Example: export GITHUB_REPO='username/repo'" >&2
    exit 1
fi

echo "=========================================="
echo "AI Development System"
echo "=========================================="
echo "Repository: $GITHUB_REPO"
echo "Base Directory: $BASE_DIR"
echo ""

# ログディレクトリ作成
mkdir -p "$LOG_DIR"

# 既存のデーモンを停止
echo "Stopping existing daemons..."
pkill -f "planner-daemon.sh" 2>/dev/null || true
pkill -f "worker-daemon.sh" 2>/dev/null || true
pkill -f "watcher.sh" 2>/dev/null || true
sleep 2

# Planner Daemon 起動
echo "Starting Planner Daemon..."
nohup "$SCRIPT_DIR/planner-daemon.sh" > "$LOG_DIR/planner-daemon.log" 2>&1 &
PLANNER_PID=$!
echo "  PID: $PLANNER_PID"

# Worker Daemon 起動
echo "Starting Worker Daemon..."
nohup "$SCRIPT_DIR/worker-daemon.sh" > "$LOG_DIR/worker-daemon.log" 2>&1 &
WORKER_PID=$!
echo "  PID: $WORKER_PID"

# Watcher 起動
echo "Starting Watcher..."
nohup "$SCRIPT_DIR/watcher.sh" > "$LOG_DIR/watcher.log" 2>&1 &
WATCHER_PID=$!
echo "  PID: $WATCHER_PID"

sleep 2

echo ""
echo "=========================================="
echo "System Started Successfully"
echo "=========================================="
echo "Planner Daemon: $PLANNER_PID"
echo "Worker Daemon:  $WORKER_PID"
echo "Watcher:        $WATCHER_PID"
echo ""
echo "Logs:"
echo "  Planner: $LOG_DIR/planner-daemon.log"
echo "  Worker:  $LOG_DIR/worker-daemon.log"
echo "  Watcher: $LOG_DIR/watcher.log"
echo ""
echo "To stop the system:"
echo "  $SCRIPT_DIR/stop-system.sh"
echo ""
echo "To view logs:"
echo "  tail -f $LOG_DIR/*.log"
echo "=========================================="
