#!/usr/bin/env python3
"""
Planner Results Watcher の処理スクリプト
Plannerの結果JSONを読み込み、GitHub Issueを作成する
"""

import json
import sys
import os
from pathlib import Path
from github_api import GitHubAPI


def process_planner_result(result_file: str) -> None:
    """
    Plannerの結果JSONを処理

    Args:
        result_file: 結果JSONファイルのパス
    """
    # 結果JSONを読み込み
    with open(result_file, 'r', encoding='utf-8') as f:
        result = json.load(f)

    repo = os.getenv('GITHUB_REPO')
    if not repo:
        print("Error: GITHUB_REPO environment variable not set", file=sys.stderr)
        sys.exit(1)

    api = GitHubAPI(repo)

    request_id = result['request_id']
    tasks = result['tasks']

    print(f"Processing planner result: {request_id}")
    print(f"Tasks: {len(tasks)}")

    # 各タスクごとにIssueを作成（全て即座に実行可能）
    created_issues = []
    for task in tasks:
        task_id = task['task_id']
        title = f"[TASK] {task_id} {task['title']}"
        body = f"""Task ID: {task_id}
Request ID: {request_id}
Task File: {task['task_file']}

## タスク詳細
{task['description']}
"""

        print(f"  Creating issue for {task_id}...")
        issue_number = api.create_issue(
            title=title,
            body=body,
            labels=['status:ready']
        )
        print(f"  Created issue #{issue_number}")

        created_issues.append({
            'task_id': task_id,
            'issue_number': issue_number
        })

        # task JSONファイルにissue番号を追記
        task_file = task['task_file']
        if os.path.exists(task_file):
            with open(task_file, 'r', encoding='utf-8') as f:
                task_data = json.load(f)

            task_data['task_issue'] = issue_number

            with open(task_file, 'w', encoding='utf-8') as f:
                json.dump(task_data, f, indent=2, ensure_ascii=False)

            print(f"  Updated {task_file} with issue number")

    # 処理完了: ファイルをリネーム
    processed_file = result_file + '.processed'
    os.rename(result_file, processed_file)
    print(f"Processed: {result_file} -> {processed_file}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <result_file>", file=sys.stderr)
        sys.exit(1)

    result_file = sys.argv[1]

    if not os.path.exists(result_file):
        print(f"Error: File not found: {result_file}", file=sys.stderr)
        sys.exit(1)

    try:
        process_planner_result(result_file)
    except Exception as e:
        print(f"Error processing planner result: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
