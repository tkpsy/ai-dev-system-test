#!/bin/bash
#
# Worker Daemon
# queue/tasks/ を監視し、新しいタスクを検出したらWorkerを起動
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Starting Worker Daemon..."
echo "Base Directory: $BASE_DIR"
echo "Watching: $BASE_DIR/queue/tasks/"
echo ""

# tasks ディレクトリを監視
fswatch -0 "$BASE_DIR/queue/tasks" | while IFS= read -r -d '' file; do
    # .json ファイルのみ処理（.processed は除外）
    if [[ "$file" == *.json ]] && [[ "$file" != *.processed ]]; then
        echo "[Worker Daemon] Detected new task: $file"

        task_id=$(basename "$file" .json)

        # タスクファイルから issue 番号を取得
        task_issue=$(jq -r '.task_issue // empty' "$file")

        # Issue のラベルをチェック（task_issue がある場合のみ）
        if [ -n "$task_issue" ] && [ -n "${GITHUB_REPO:-}" ]; then
            echo "[Worker Daemon] Checking issue #$task_issue labels..."

            # Issue のラベルを取得
            labels=$(gh issue view "$task_issue" --repo "$GITHUB_REPO" --json labels --jq '.labels[].name' 2>/dev/null || echo "")

            # status:ready があるかチェック
            if echo "$labels" | grep -q "status:ready"; then
                echo "[Worker Daemon] Issue #$task_issue has status:ready, proceeding..."
            else
                echo "[Worker Daemon] Issue #$task_issue does not have status:ready, skipping..."
                echo "[Worker Daemon] Current labels: $(echo "$labels" | tr '\n' ', ')"
                echo ""
                continue
            fi
        else
            echo "[Worker Daemon] No task_issue or GITHUB_REPO, proceeding without check..."
        fi

        log_file="$BASE_DIR/logs/worker-${task_id}.log"
        echo "[Worker Daemon] Starting Worker for $task_id..."
        echo "[Worker Daemon] Log: $log_file"

        # Workerを起動（Print mode）
        # run-worker.sh を使ってプロンプトとタスクを結合
        "$SCRIPT_DIR/run-worker.sh" "$file" > "$log_file" 2>&1

        worker_exit_code=$?

        if [ $worker_exit_code -eq 0 ]; then
            echo "[Worker Daemon] Worker completed successfully"

            # タスクファイルを .processed にリネーム
            mv "$file" "${file}.processed"
            echo "[Worker Daemon] Marked as processed: ${file}.processed"
        else
            echo "[Worker Daemon] ERROR: Worker failed with exit code $worker_exit_code" >&2
            echo "[Worker Daemon] Check log: $log_file" >&2

            # エラー時は .error にリネーム
            mv "$file" "${file}.error"
            echo "[Worker Daemon] Marked as error: ${file}.error" >&2
        fi

        echo ""
    fi
done
