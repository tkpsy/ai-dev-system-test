#!/bin/bash
#
# Watcher デーモン
# Planner/Workerの結果JSONを監視し、GitHub操作を実行する
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$BASE_DIR/lib"

# 環境変数のチェック
if [ -z "${GITHUB_REPO:-}" ]; then
    echo "Error: GITHUB_REPO environment variable not set" >&2
    echo "Example: export GITHUB_REPO=owner/repo" >&2
    exit 1
fi

echo "Starting watchers..."
echo "GitHub Repo: $GITHUB_REPO"
echo "Base Directory: $BASE_DIR"

# Planner Results Watcher
echo "Starting Planner Results Watcher..."
fswatch -0 "$BASE_DIR/queue/planner-results" | while IFS= read -r -d '' file; do
    # .json ファイルのみ処理
    if [[ "$file" == *.json ]] && [[ "$file" != *.processed ]]; then
        echo "[Planner Watcher] Detected: $file"
        python3 "$LIB_DIR/process_planner_result.py" "$file" 2>&1 | \
            tee -a "$BASE_DIR/logs/planner-watcher.log"
    fi
done &

PLANNER_WATCHER_PID=$!

# Worker Results Watcher
echo "Starting Worker Results Watcher..."
fswatch -0 "$BASE_DIR/queue/worker-results" | while IFS= read -r -d '' file; do
    # .json ファイルのみ処理
    if [[ "$file" == *.json ]] && [[ "$file" != *.processed ]]; then
        echo "[Worker Watcher] Detected: $file"
        python3 "$LIB_DIR/process_worker_result.py" "$file" 2>&1 | \
            tee -a "$BASE_DIR/logs/worker-watcher.log"
    fi
done &

WORKER_WATCHER_PID=$!

echo "Watchers started successfully"
echo "  Planner Results Watcher PID: $PLANNER_WATCHER_PID"
echo "  Worker Results Watcher PID: $WORKER_WATCHER_PID"
echo ""
echo "Press Ctrl+C to stop..."

# シグナルハンドラ
trap 'echo "Stopping watchers..."; kill $PLANNER_WATCHER_PID $WORKER_WATCHER_PID 2>/dev/null; exit 0' SIGINT SIGTERM

# 両方のプロセスを待機
wait
