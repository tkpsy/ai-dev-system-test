#!/bin/bash
#
# Planner Daemon
# queue/requests/ を監視し、新しいリクエストを検出したらPlannerを起動
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Starting Planner Daemon..."
echo "Base Directory: $BASE_DIR"
echo "Watching: $BASE_DIR/queue/requests/"
echo ""

# requests ディレクトリを監視
fswatch -0 "$BASE_DIR/queue/requests" | while IFS= read -r -d '' file; do
    # .json ファイルのみ処理（.processed は除外）
    if [[ "$file" == *.json ]] && [[ "$file" != *.processed ]]; then
        echo "[Planner Daemon] Detected new request: $file"

        request_id=$(basename "$file" .json)
        log_file="$BASE_DIR/logs/planner-${request_id}.log"

        echo "[Planner Daemon] Starting Planner for $request_id..."
        echo "[Planner Daemon] Log: $log_file"

        # Plannerを起動（Print mode）
        # run-planner.sh を使ってプロンプトとリクエストを結合
        "$SCRIPT_DIR/run-planner.sh" "$file" > "$log_file" 2>&1

        planner_exit_code=$?

        if [ $planner_exit_code -eq 0 ]; then
            echo "[Planner Daemon] Planner completed successfully"

            # リクエストファイルを .processed にリネーム
            mv "$file" "${file}.processed"
            echo "[Planner Daemon] Marked as processed: ${file}.processed"
        else
            echo "[Planner Daemon] ERROR: Planner failed with exit code $planner_exit_code" >&2
            echo "[Planner Daemon] Check log: $log_file" >&2

            # エラー時は .error にリネーム
            mv "$file" "${file}.error"
            echo "[Planner Daemon] Marked as error: ${file}.error" >&2
        fi

        echo ""
    fi
done
