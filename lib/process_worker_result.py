#!/usr/bin/env python3
"""
Worker Results Watcher の処理スクリプト
Workerの結果JSONを読み込み、GitHub Issueにコメントを投稿する
"""

import json
import sys
import os
from github_api import GitHubAPI


def process_worker_result(result_file: str) -> None:
    """
    Workerの結果JSONを処理

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

    task_id = result['task_id']
    task_issue = result['task_issue']
    worker_id = result.get('worker_id', 'unknown')
    status = result['status']
    events = result['events']

    print(f"Processing worker result: {task_id}")
    print(f"Task issue: #{task_issue}")
    print(f"Worker: {worker_id}")
    print(f"Status: {status}")
    print(f"Events: {len(events)}")

    # 各イベントを処理
    for event in events:
        event_type = event['type']
        comment = event['comment']

        print(f"  Processing event: {event_type}")

        # Issueにコメント投稿
        api.add_comment(task_issue, comment)
        print(f"  Comment added to issue #{task_issue}")

        # ラベル変更
        if event_type == 'started':
            # ready → progress
            api.update_labels(
                task_issue,
                add_labels=['status:progress'],
                remove_labels=['status:ready']
            )
            print(f"  Label updated: ready → progress")

        elif event_type in ['completed', 'blocked']:
            # progress → review
            api.update_labels(
                task_issue,
                add_labels=['status:review'],
                remove_labels=['status:progress']
            )
            print(f"  Label updated: progress → review")

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
        process_worker_result(result_file)
    except Exception as e:
        print(f"Error processing worker result: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
