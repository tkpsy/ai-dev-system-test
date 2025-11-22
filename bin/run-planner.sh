#!/bin/bash
#
# Planner実行スクリプト
# リクエストファイルを読み込んで、Claudeに渡し、結果を処理する
#

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <request_file>" >&2
    exit 1
fi

REQUEST_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$REQUEST_FILE" ]; then
    echo "Error: Request file not found: $REQUEST_FILE" >&2
    exit 1
fi

# 一時ファイルにClaudeの出力を保存
TEMP_OUTPUT=$(mktemp)
TEMP_JSON=$(mktemp)
trap "rm -f $TEMP_OUTPUT $TEMP_JSON" EXIT

# Plannerプロンプトとリクエストを結合して Claude に渡す
{
    cat "$BASE_DIR/prompts/planner.md"
    echo ""
    echo "---"
    echo ""
    echo "## リクエスト内容"
    echo ""
    echo "リクエストファイル: \`$REQUEST_FILE\`"
    echo ""
    echo '```json'
    cat "$REQUEST_FILE"
    echo '```'
    echo ""
    echo "上記のリクエストに基づいて、単一のJSON構造を出力してください。"
} | claude --print > "$TEMP_OUTPUT" 2>&1

# jq で JSON を抽出・検証
# 1. ```json ... ``` ブロックを抽出、なければ {} の最も外側を抽出
if grep -q '```json' "$TEMP_OUTPUT"; then
    # ```json ... ``` から抽出
    sed -n '/```json/,/```/p' "$TEMP_OUTPUT" | sed '1d;$d' | jq '.' > "$TEMP_JSON" 2>/dev/null
else
    # 最後の { ... } ブロックを抽出してjqで検証
    grep -o '{.*}' "$TEMP_OUTPUT" | tail -1 | jq '.' > "$TEMP_JSON" 2>/dev/null
fi

if [ ! -s "$TEMP_JSON" ]; then
    echo "Error: Failed to extract valid JSON from Claude output" >&2
    echo "Claude output:" >&2
    cat "$TEMP_OUTPUT" >&2
    exit 1
fi

# Python で JSON を解析してファイルを作成
python3 - "$TEMP_JSON" "$REQUEST_FILE" "$BASE_DIR" << 'PYTHON_SCRIPT'
import sys
import json
import os
import re
from datetime import datetime

json_file = sys.argv[1]
request_file = sys.argv[2]
base_dir = sys.argv[3]

# jq で検証済みの JSON を読み込む
with open(json_file, 'r') as f:
    result = json.load(f)

# ディレクトリ作成
os.makedirs(f"{base_dir}/queue/tasks", exist_ok=True)
os.makedirs(f"{base_dir}/queue/planner-results", exist_ok=True)

# 各タスクファイルを作成
for task in result.get('tasks', []):
    task_id = task['task_id']
    task_file = f"{base_dir}/queue/tasks/task-{task_id}.json"
    with open(task_file, 'w') as f:
        json.dump(task, f, indent=2, ensure_ascii=False)
    print(f"Created task file: {task_file}")

# 結果ファイルを作成（tasksから task_file情報を追加）
result_with_files = result.copy()
result_with_files['tasks'] = [
    {
        'task_id': t['task_id'],
        'title': t['title'],
        'description': t.get('description', ''),
        'task_file': f"queue/tasks/task-{t['task_id']}.json"
    }
    for t in result.get('tasks', [])
]

request_id = result['request_id']
result_file = f"{base_dir}/queue/planner-results/result-{request_id}.json"
with open(result_file, 'w') as f:
    json.dump(result_with_files, f, indent=2, ensure_ascii=False)
print(f"Created result file: {result_file}")

PYTHON_SCRIPT
