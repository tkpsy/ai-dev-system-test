#!/bin/bash
#
# Worker実行スクリプト
# タスクファイルを読み込んで、Claudeに渡し、結果を処理する
#

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <task_file>" >&2
    exit 1
fi

TASK_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$TASK_FILE" ]; then
    echo "Error: Task file not found: $TASK_FILE" >&2
    exit 1
fi

# タスクIDを取得
task_id=$(basename "$TASK_FILE" .json)

# タスクJSONからworktree情報を取得
WORKTREE_PATH=$(jq -r '.worktree.path // empty' "$TASK_FILE")
WORKTREE_BRANCH=$(jq -r '.worktree.branch // empty' "$TASK_FILE")

# Worktreeのセットアップ
if [ -n "$WORKTREE_PATH" ] && [ -n "$WORKTREE_BRANCH" ]; then
    echo "Setting up git worktree..."
    echo "  Path: $WORKTREE_PATH"
    echo "  Branch: $WORKTREE_BRANCH"

    # worktreeディレクトリが存在しない場合のみ作成
    if [ ! -d "$BASE_DIR/$WORKTREE_PATH" ]; then
        cd "$BASE_DIR"

        # ブランチが存在するか確認
        if git show-ref --verify --quiet "refs/heads/$WORKTREE_BRANCH"; then
            # 既存ブランチから worktree 作成
            git worktree add "$WORKTREE_PATH" "$WORKTREE_BRANCH" 2>&1 || {
                echo "Warning: Failed to create worktree, continuing anyway..." >&2
            }
        else
            # 新規ブランチで worktree 作成
            git worktree add "$WORKTREE_PATH" -b "$WORKTREE_BRANCH" 2>&1 || {
                echo "Warning: Failed to create worktree, continuing anyway..." >&2
            }
        fi

        cd - > /dev/null
        echo "  Worktree created successfully"
    else
        echo "  Worktree already exists"
    fi
fi

# 一時ファイルにClaudeの出力を保存
TEMP_OUTPUT=$(mktemp)
TEMP_JSON=$(mktemp)
trap "rm -f $TEMP_OUTPUT $TEMP_JSON" EXIT

# 作業ディレクトリを設定
if [ -n "$WORKTREE_PATH" ] && [ -d "$BASE_DIR/$WORKTREE_PATH" ]; then
    WORK_DIR="$BASE_DIR/$WORKTREE_PATH"
    echo "Working in: $WORK_DIR"
else
    WORK_DIR="$BASE_DIR"
    echo "Working in base directory (no worktree): $WORK_DIR"
fi

# Workerプロンプトとタスクを結合して Claude に渡す
# 重要: Claude を worktree ディレクトリで実行
(
    cd "$WORK_DIR"
    {
        cat "$BASE_DIR/prompts/worker.md"
        echo ""
        echo "---"
        echo ""
        echo "## タスク内容"
        echo ""
        echo "タスクファイル: \`$TASK_FILE\`"
        echo ""
        echo '```json'
        cat "$TASK_FILE"
        echo '```'
        echo ""
        echo "上記のタスクを実装し、完了後に結果JSONを標準出力に出力してください。"
    } | claude --print --dangerously-skip-permissions
) > "$TEMP_OUTPUT" 2>&1

# jq で JSON を抽出・検証
# 1. ```json ... ``` ブロックを抽出、なければ {} の最も外側を抽出
if grep -q '```json' "$TEMP_OUTPUT"; then
    # ```json ... ``` から抽出（最後のブロック）
    sed -n '/```json/,/```/p' "$TEMP_OUTPUT" | sed '1d;$d' | jq '.' > "$TEMP_JSON" 2>/dev/null
else
    # 最後の { ... } ブロックを抽出してjqで検証
    grep -o '{.*}' "$TEMP_OUTPUT" | tail -1 | jq '.' > "$TEMP_JSON" 2>/dev/null
fi

if [ ! -s "$TEMP_JSON" ]; then
    echo "Error: Failed to extract valid JSON from Claude output" >&2
    echo "Claude output (last 100 lines):" >&2
    tail -100 "$TEMP_OUTPUT" >&2
    exit 1
fi

# Python で JSON を解析してファイルを作成
python3 - "$TEMP_JSON" "$TASK_FILE" "$BASE_DIR" "$task_id" << 'PYTHON_SCRIPT'
import sys
import json
import os
import re
from datetime import datetime

json_file = sys.argv[1]
task_file = sys.argv[2]
base_dir = sys.argv[3]
task_id = sys.argv[4]

# jq で検証済みの JSON を読み込む
with open(json_file, 'r') as f:
    result = json.load(f)

# ディレクトリ作成
os.makedirs(f"{base_dir}/queue/worker-results", exist_ok=True)

# 結果ファイルを作成
result_file = f"{base_dir}/queue/worker-results/result-{task_id}.json"
with open(result_file, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
print(f"Created result file: {result_file}")

PYTHON_SCRIPT

# Worker完了後の Git 操作
if [ -n "$WORKTREE_PATH" ] && [ -n "$WORKTREE_BRANCH" ] && [ -d "$BASE_DIR/$WORKTREE_PATH" ]; then
    # 結果JSONから status を確認
    WORKER_STATUS=$(jq -r '.status' "$BASE_DIR/queue/worker-results/result-${task_id}.json")

    if [ "$WORKER_STATUS" = "completed" ]; then
        echo ""
        echo "Git operations..."
        cd "$BASE_DIR/$WORKTREE_PATH"

        # 変更があるか確認
        if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
            echo "  Committing changes..."

            # 全変更を add
            git add -A

            # タスク情報を取得
            TASK_TITLE=$(jq -r '.title' "$TASK_FILE")

            # Commit
            git commit -m "$TASK_TITLE

Task ID: $task_id
Task Issue: #$(jq -r '.task_issue' "$TASK_FILE")

🤖 Implemented by AI Worker" || {
                echo "Warning: Commit failed" >&2
            }

            # Push
            echo "  Pushing to remote..."
            git push -u origin "$WORKTREE_BRANCH" 2>&1 || {
                echo "Warning: Push failed" >&2
            }

            # PR作成
            if [ -n "${GITHUB_REPO:-}" ]; then
                echo "  Creating Pull Request..."
                TASK_ISSUE=$(jq -r '.task_issue' "$TASK_FILE")
                PR_BODY="Closes #${TASK_ISSUE}

## 実装内容
このPRは自動実装システムによって作成されました。

Task: $TASK_TITLE
"
                PR_URL=$(gh pr create \
                    --repo "$GITHUB_REPO" \
                    --base main \
                    --head "$WORKTREE_BRANCH" \
                    --title "$TASK_TITLE" \
                    --body "$PR_BODY" 2>&1) || {
                    echo "Warning: PR creation failed: $PR_URL" >&2
                    PR_URL=""
                }

                if [ -n "$PR_URL" ]; then
                    echo "  PR created: $PR_URL"

                    # Issue に PR リンクをコメント
                    gh issue comment "$TASK_ISSUE" \
                        --repo "$GITHUB_REPO" \
                        --body "🔗 Pull Request: $PR_URL" 2>&1 || {
                        echo "Warning: Failed to comment on issue" >&2
                    }
                fi
            fi
        else
            echo "  No changes to commit"
        fi

        cd - > /dev/null
    else
        echo "Worker status is not 'completed', skipping git operations"
    fi
fi
