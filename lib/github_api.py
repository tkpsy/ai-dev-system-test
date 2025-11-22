#!/usr/bin/env python3
"""
GitHub API ラッパー
gh CLI を使用してGitHub操作を行う
"""

import subprocess
import json
import sys
from typing import Optional, List, Dict, Any


class GitHubAPI:
    def __init__(self, repo: str):
        """
        Args:
            repo: GitHub リポジトリ (owner/repo 形式)
        """
        self.repo = repo

    def create_issue(
        self,
        title: str,
        body: str,
        labels: Optional[List[str]] = None
    ) -> int:
        """
        GitHub Issue を作成

        Args:
            title: Issue タイトル
            body: Issue 本文
            labels: ラベルのリスト

        Returns:
            作成された Issue 番号
        """
        cmd = [
            "gh", "issue", "create",
            "--repo", self.repo,
            "--title", title,
            "--body", body
        ]

        if labels:
            for label in labels:
                cmd.extend(["--label", label])

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True
            )
            # gh issue create は Issue URL を返す
            # https://github.com/owner/repo/issues/123 → 123
            issue_url = result.stdout.strip()
            issue_number = int(issue_url.split('/')[-1])
            return issue_number
        except subprocess.CalledProcessError as e:
            print(f"Error creating issue: {e.stderr}", file=sys.stderr)
            raise

    def add_comment(self, issue_number: int, body: str) -> None:
        """
        Issue にコメントを追加

        Args:
            issue_number: Issue 番号
            body: コメント本文
        """
        cmd = [
            "gh", "issue", "comment", str(issue_number),
            "--repo", self.repo,
            "--body", body
        ]

        try:
            subprocess.run(cmd, capture_output=True, text=True, check=True)
        except subprocess.CalledProcessError as e:
            print(f"Error adding comment to issue #{issue_number}: {e.stderr}", file=sys.stderr)
            raise

    def update_labels(
        self,
        issue_number: int,
        add_labels: Optional[List[str]] = None,
        remove_labels: Optional[List[str]] = None
    ) -> None:
        """
        Issue のラベルを更新

        Args:
            issue_number: Issue 番号
            add_labels: 追加するラベル
            remove_labels: 削除するラベル
        """
        cmd = ["gh", "issue", "edit", str(issue_number), "--repo", self.repo]

        if add_labels:
            cmd.extend(["--add-label", ",".join(add_labels)])

        if remove_labels:
            cmd.extend(["--remove-label", ",".join(remove_labels)])

        try:
            subprocess.run(cmd, capture_output=True, text=True, check=True)
        except subprocess.CalledProcessError as e:
            print(f"Error updating labels for issue #{issue_number}: {e.stderr}", file=sys.stderr)
            raise

    def get_issue(self, issue_number: int) -> Dict[str, Any]:
        """
        Issue の情報を取得

        Args:
            issue_number: Issue 番号

        Returns:
            Issue 情報の辞書
        """
        cmd = [
            "gh", "issue", "view", str(issue_number),
            "--repo", self.repo,
            "--json", "number,title,body,state,labels,comments"
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"Error getting issue #{issue_number}: {e.stderr}", file=sys.stderr)
            raise

    def list_issues(
        self,
        labels: Optional[List[str]] = None,
        state: str = "open"
    ) -> List[Dict[str, Any]]:
        """
        Issue の一覧を取得

        Args:
            labels: フィルタするラベル
            state: Issue の状態 (open, closed, all)

        Returns:
            Issue 情報のリスト
        """
        cmd = [
            "gh", "issue", "list",
            "--repo", self.repo,
            "--state", state,
            "--json", "number,title,labels",
            "--limit", "100"
        ]

        if labels:
            cmd.extend(["--label", ",".join(labels)])

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"Error listing issues: {e.stderr}", file=sys.stderr)
            raise


if __name__ == "__main__":
    # テスト用
    import os

    repo = os.getenv("GITHUB_REPO", "owner/repo")
    api = GitHubAPI(repo)

    print(f"GitHub API wrapper initialized for {repo}")
    print("Available methods:")
    print("  - create_issue(title, body, labels)")
    print("  - add_comment(issue_number, body)")
    print("  - update_labels(issue_number, add_labels, remove_labels)")
    print("  - get_issue(issue_number)")
    print("  - list_issues(labels, state)")
