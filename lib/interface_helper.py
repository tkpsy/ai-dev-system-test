#!/usr/bin/env python3
"""
Interface Helper
このセッションでInterfaceとして動作するためのヘルパー関数
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path
from github_api import GitHubAPI


def create_request(user_request: str, base_dir: str = ".") -> dict:
    """
    ユーザー要求からリクエストJSONを作成
    親Issueは作成せず、Plannerが作成するタスクIssueのみを使用

    Args:
        user_request: ユーザーの要求テキスト
        base_dir: ベースディレクトリ

    Returns:
        作成したリクエスト情報
    """
    # リクエストIDを生成
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    request_id = f"req-{timestamp}"

    # リクエストJSONを作成（parent_issueフィールドなし）
    request_data = {
        "request_id": request_id,
        "user_request": user_request,
        "timestamp": datetime.now().isoformat()
    }

    # ファイルに保存
    request_file = os.path.join(base_dir, "queue", "requests", f"{request_id}.json")
    os.makedirs(os.path.dirname(request_file), exist_ok=True)

    with open(request_file, 'w', encoding='utf-8') as f:
        json.dump(request_data, f, indent=2, ensure_ascii=False)

    print(f"✓ Created request: {request_file}")

    return {
        "request_id": request_id,
        "request_file": request_file
    }


def check_status(request_id: str, base_dir: str = ".") -> dict:
    """
    リクエストの状態を確認

    Args:
        request_id: リクエストID
        base_dir: ベースディレクトリ

    Returns:
        状態情報
    """
    result_file = os.path.join(
        base_dir,
        "queue",
        "planner-results",
        f"result-{request_id}.json"
    )

    if os.path.exists(result_file):
        with open(result_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    elif os.path.exists(result_file + '.processed'):
        with open(result_file + '.processed', 'r', encoding='utf-8') as f:
            return json.load(f)
    else:
        return {"status": "pending", "message": "Waiting for Planner..."}


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <command> [args...]")
        print("Commands:")
        print("  create <user_request>  - Create a new request")
        print("  status <request_id>    - Check request status")
        sys.exit(1)

    command = sys.argv[1]

    if command == "create":
        if len(sys.argv) < 3:
            print("Error: user_request required", file=sys.stderr)
            sys.exit(1)

        user_request = " ".join(sys.argv[2:])
        result = create_request(user_request)
        print(json.dumps(result, indent=2))

    elif command == "status":
        if len(sys.argv) < 3:
            print("Error: request_id required", file=sys.stderr)
            sys.exit(1)

        request_id = sys.argv[2]
        status = check_status(request_id)
        print(json.dumps(status, indent=2))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
