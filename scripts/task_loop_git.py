#!/usr/bin/env python3
"""Git checkpoint helpers for the AreaMatrix task loop.

The helper intentionally uses only the Python standard library so the runner can
use it in fresh local checkouts.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class GitError(RuntimeError):
    def __init__(self, message: str, returncode: int = 1) -> None:
        super().__init__(message)
        self.returncode = returncode


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_json(path: Path, default: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def run_git(root: Path, args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        message = "git " + " ".join(args)
        if detail:
            message += f": {detail}"
        raise GitError(message, proc.returncode)
    return proc


def ensure_git_repo(root: Path) -> Path:
    proc = run_git(root, ["rev-parse", "--show-toplevel"], check=True)
    top = Path(proc.stdout.strip()).resolve()
    if top != root.resolve():
        raise GitError(f"ROOT_DIR must be the git root: expected {top}, got {root.resolve()}")
    return top


def status_short(root: Path) -> list[str]:
    proc = run_git(root, ["status", "--short"], check=True)
    return [line for line in proc.stdout.splitlines() if line.strip()]


def ensure_clean_worktree(root: Path) -> None:
    dirty = status_short(root)
    if dirty:
        preview = "\n".join(dirty[:20])
        raise GitError(
            "git checkpoint requires a clean worktree before live execution.\n"
            "Commit the current infrastructure changes first, or run with GIT_CHECKPOINT=off.\n"
            f"Current changes:\n{preview}"
        )


def current_branch(root: Path) -> str:
    proc = run_git(root, ["branch", "--show-current"], check=True)
    branch = proc.stdout.strip()
    if not branch:
        raise GitError("detached HEAD is not supported for task-loop Git checkpoints")
    return branch


def branch_exists(root: Path, branch: str) -> bool:
    proc = run_git(root, ["show-ref", "--verify", "--quiet", f"refs/heads/{branch}"], check=False)
    return proc.returncode == 0


def safe_run_id(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    return cleaned or datetime.now().strftime("%Y%m%d_%H%M%S")


def remote_url(root: Path, remote: str) -> str:
    proc = run_git(root, ["remote", "get-url", remote], check=True)
    return proc.stdout.strip()


def upstream_branch(root: Path) -> str:
    proc = run_git(
        root,
        ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
        check=False,
    )
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def ahead_behind(root: Path, upstream: str) -> tuple[int, int]:
    proc = run_git(root, ["rev-list", "--left-right", "--count", f"{upstream}...HEAD"], check=True)
    left, right = proc.stdout.strip().split()
    return int(right), int(left)


def push_branch(root: Path, remote: str, branch: str, set_upstream: bool) -> None:
    args = ["push"]
    if set_upstream:
        args.append("--set-upstream")
    args.extend([remote, f"HEAD:{branch}"])
    run_git(root, args, check=True)


def maybe_push_existing_ahead(root: Path, remote: str, set_upstream: bool) -> dict[str, Any]:
    upstream = upstream_branch(root)
    if not upstream:
        return {"upstream": "", "ahead": 0, "behind": 0, "pushed_existing": False}
    ahead, behind = ahead_behind(root, upstream)
    if behind:
        raise GitError(f"current branch is behind upstream {upstream}; pull/rebase before push mode")
    if ahead:
        push_branch(root, remote, current_branch(root), set_upstream)
    return {
        "upstream": upstream,
        "ahead": ahead,
        "behind": behind,
        "pushed_existing": bool(ahead),
    }


def parse_changed_paths(status_lines: list[str]) -> list[str]:
    paths: list[str] = []
    for line in status_lines:
        if len(line) < 4:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path)
    return sorted(dict.fromkeys(paths))


def diff_name_status(root: Path) -> list[str]:
    proc = run_git(root, ["diff", "--name-status", "HEAD"], check=True)
    return [line for line in proc.stdout.splitlines() if line.strip()]


def commit_message(
    label: str,
    phase: str,
    task_name: str,
    attempts: int,
    run_id: str,
    copy_log: str,
    verify_log: str,
    summary_file: str,
) -> tuple[str, str]:
    title = f"task-loop: complete {label}"
    body = "\n".join(
        [
            f"Phase: {phase}",
            f"Task: {task_name}",
            f"Attempts: {attempts}",
            f"Run: {run_id}",
            f"Copy log: {copy_log}",
            f"Verify log: {verify_log}",
            f"Summary: {summary_file}",
        ]
    )
    return title, body


def evidence_message(label: str, completed_commit: str) -> tuple[str, str]:
    title = f"task-loop: record checkpoint evidence {label}"
    body = f"Completed commit: {completed_commit}"
    return title, body


def path_for_git(root: Path, path: Path) -> str | None:
    if not path:
        return None
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return None


def commit_evidence_files(
    root: Path,
    label: str,
    completed_commit: str,
    progress_file: Path | None,
    summary_file: Path | None,
) -> str:
    paths = [
        path
        for path in [
            path_for_git(root, progress_file) if progress_file else None,
            path_for_git(root, summary_file) if summary_file else None,
        ]
        if path
    ]
    if not paths:
        return ""
    run_git(root, ["add", "--", *paths], check=True)
    staged = run_git(root, ["diff", "--cached", "--name-only"], check=True).stdout.splitlines()
    if not staged:
        return ""
    title, body = evidence_message(label, completed_commit)
    run_git(root, ["commit", "-m", title, "-m", body], check=True)
    return run_git(root, ["rev-parse", "HEAD"], check=True).stdout.strip()


def update_progress(progress_file: Path, label: str, evidence: dict[str, Any]) -> None:
    if not progress_file:
        return
    data = read_json(progress_file, {"version": 1, "tasks": {}})
    tasks = data.setdefault("tasks", {})
    entry = tasks.setdefault(label, {})
    if not isinstance(entry, dict):
        entry = {}
        tasks[label] = entry
    entry["git_checkpoint_status"] = evidence.get("status", "")
    entry["git_branch"] = evidence.get("branch", "")
    entry["git_commit"] = evidence.get("commit", "")
    entry["git_push_status"] = evidence.get("push_status", "")
    entry["git_remote"] = evidence.get("remote", "")
    entry["git_changed_files"] = evidence.get("changed_files", [])
    entry["updated_at"] = utc_now()
    data["updated_at"] = utc_now()
    write_json(progress_file, data)


def update_summary(summary_file: Path, label: str, evidence: dict[str, Any]) -> None:
    if not summary_file or not summary_file.exists():
        return
    data = read_json(summary_file, {})
    tasks = data.setdefault("tasks", {})
    task = tasks.setdefault(label, {})
    if not isinstance(task, dict):
        task = {}
        tasks[label] = task
    task["git"] = evidence
    data["updated_at"] = utc_now()
    write_json(summary_file, data)


def write_evidence(
    progress_file: Path | None,
    summary_file: Path | None,
    label: str,
    evidence: dict[str, Any],
) -> None:
    if progress_file is not None:
        update_progress(progress_file, label, evidence)
    if summary_file is not None:
        update_summary(summary_file, label, evidence)


def command_preflight(args: argparse.Namespace) -> int:
    if args.mode == "off" or args.dry_run:
        print(json.dumps({"status": "skipped", "mode": args.mode, "dry_run": args.dry_run}))
        return 0

    root = ensure_git_repo(args.root_dir)
    ensure_clean_worktree(root)

    branch = current_branch(root)
    created_branch = ""
    if branch == "main":
        if args.branch_policy == "require-task-branch":
            raise GitError("GIT_BRANCH_POLICY=require-task-branch refuses to run on main")
        if args.branch_policy == "auto":
            created_branch = f"codex/areamatrix-task-loop-{safe_run_id(args.run_id)}"
            if branch_exists(root, created_branch):
                run_git(root, ["checkout", created_branch], check=True)
            else:
                run_git(root, ["checkout", "-b", created_branch], check=True)
            branch = current_branch(root)

    push_info: dict[str, Any] = {}
    remote = ""
    if args.mode == "push":
        remote = remote_url(root, args.push_remote)
        push_info = maybe_push_existing_ahead(root, args.push_remote, args.push_set_upstream)

    print(
        json.dumps(
            {
                "status": "ok",
                "mode": args.mode,
                "branch": branch,
                "created_branch": created_branch,
                "remote": remote,
                "push": push_info,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


def command_checkpoint(args: argparse.Namespace) -> int:
    if args.mode == "off" or args.dry_run:
        evidence = {
            "status": "skipped",
            "mode": args.mode,
            "dry_run": args.dry_run,
            "updated_at": utc_now(),
        }
        write_evidence(args.progress_file, args.summary_file, args.label, evidence)
        print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
        return 0

    root = ensure_git_repo(args.root_dir)
    branch = current_branch(root)

    evidence: dict[str, Any] = {
        "status": "pending",
        "mode": args.mode,
        "branch": branch,
        "remote": args.push_remote if args.mode == "push" else "",
        "label": args.label,
        "phase": args.phase,
        "task_name": args.task_name,
        "attempts": args.attempts,
        "run_id": args.run_id,
        "copy_log": args.copy_log,
        "verify_log": args.verify_log,
        "summary_file": str(args.summary_file) if args.summary_file else "",
        "changed_files": [],
        "status_short": [],
        "diff_name_status": [],
        "commit": "",
        "push_status": "not_requested" if args.mode == "commit" else "pending",
        "updated_at": utc_now(),
    }

    diff_check = run_git(root, ["diff", "--check"], check=False)
    if diff_check.returncode != 0:
        evidence["status"] = "git_diff_check_failed"
        evidence["error"] = (diff_check.stderr or diff_check.stdout).strip()
        write_evidence(args.progress_file, args.summary_file, args.label, evidence)
        print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
        return 11

    before_status = status_short(root)
    evidence["status_short"] = before_status
    evidence["changed_files"] = parse_changed_paths(before_status)
    evidence["diff_name_status"] = diff_name_status(root)
    if not before_status:
        evidence["status"] = "no_changes"
        write_evidence(args.progress_file, args.summary_file, args.label, evidence)
        print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
        return 0

    run_git(root, ["add", "-A"], check=True)
    staged = run_git(root, ["diff", "--cached", "--name-status"], check=True).stdout.splitlines()
    evidence["staged_name_status"] = [line for line in staged if line.strip()]
    if not evidence["staged_name_status"]:
        evidence["status"] = "no_staged_changes"
        write_evidence(args.progress_file, args.summary_file, args.label, evidence)
        print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
        return 0

    title, body = commit_message(
        args.label,
        args.phase,
        args.task_name,
        args.attempts,
        args.run_id,
        args.copy_log,
        args.verify_log,
        str(args.summary_file) if args.summary_file else "",
    )
    run_git(root, ["commit", "-m", title, "-m", body], check=True)
    evidence["commit"] = run_git(root, ["rev-parse", "HEAD"], check=True).stdout.strip()
    if args.mode == "push":
        # Record the intended final push state before committing evidence. If the
        # push fails, the failure branch rewrites the evidence and commits that
        # local failure state before returning non-zero.
        evidence["status"] = "pushed"
        evidence["push_status"] = "pushed"
    else:
        evidence["status"] = "committed"
    evidence["updated_at"] = utc_now()
    write_evidence(args.progress_file, args.summary_file, args.label, evidence)
    evidence_commit = commit_evidence_files(
        root,
        args.label,
        str(evidence["commit"]),
        args.progress_file,
        args.summary_file,
    )
    if evidence_commit:
        evidence["evidence_commit"] = evidence_commit

    if args.mode == "push":
        try:
            remote_url(root, args.push_remote)
            push_branch(root, args.push_remote, branch, args.push_set_upstream)
            evidence["status"] = "pushed"
            evidence["push_status"] = "pushed"
        except GitError as exc:
            evidence["status"] = "git_push_failed"
            evidence["push_status"] = "failed"
            evidence["error"] = str(exc)
            evidence["updated_at"] = utc_now()
            write_evidence(args.progress_file, args.summary_file, args.label, evidence)
            failure_evidence_commit = commit_evidence_files(
                root,
                args.label,
                str(evidence["commit"]),
                args.progress_file,
                args.summary_file,
            )
            if failure_evidence_commit:
                evidence["push_failure_evidence_commit"] = failure_evidence_commit
            print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
            return 20

    evidence["updated_at"] = utc_now()
    print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
    return 0


def command_commit_run_summary(args: argparse.Namespace) -> int:
    if args.mode == "off" or args.dry_run:
        print(json.dumps({"status": "skipped", "mode": args.mode, "dry_run": args.dry_run}))
        return 0

    root = ensure_git_repo(args.root_dir)
    branch = current_branch(root)
    index_file = args.run_summary_root / "index.json"
    allowed = {
        path
        for path in [
            path_for_git(root, args.summary_file),
            path_for_git(root, index_file),
        ]
        if path
    }
    if not allowed:
        print(json.dumps({"status": "skipped", "reason": "summary outside git root"}))
        return 0

    dirty = status_short(root)
    if not dirty:
        print(json.dumps({"status": "no_changes", "run_id": args.run_id}))
        return 0

    changed = set(parse_changed_paths(dirty))
    unexpected = sorted(path for path in changed if path not in allowed)
    if unexpected:
        raise GitError(
            "run summary checkpoint found unexpected dirty paths after task checkpoint: "
            + ", ".join(unexpected[:20])
        )

    run_git(root, ["add", "--", *sorted(allowed)], check=True)
    staged = run_git(root, ["diff", "--cached", "--name-only"], check=True).stdout.splitlines()
    if not staged:
        print(json.dumps({"status": "no_staged_changes", "run_id": args.run_id}))
        return 0

    title = f"task-loop: finalize run {args.run_id}"
    body = f"Summary: {args.summary_file}"
    run_git(root, ["commit", "-m", title, "-m", body], check=True)
    commit = run_git(root, ["rev-parse", "HEAD"], check=True).stdout.strip()
    status = "committed"

    if args.mode == "push":
        try:
            remote_url(root, args.push_remote)
            push_branch(root, args.push_remote, branch, args.push_set_upstream)
            status = "pushed"
        except GitError as exc:
            print(
                json.dumps(
                    {
                        "status": "git_push_failed",
                        "run_id": args.run_id,
                        "commit": commit,
                        "error": str(exc),
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )
            return 20

    print(
        json.dumps(
            {"status": status, "run_id": args.run_id, "commit": commit, "branch": branch},
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    preflight = subparsers.add_parser("preflight")
    preflight.add_argument("--root-dir", type=Path, required=True)
    preflight.add_argument("--mode", choices=["off", "commit", "push"], required=True)
    preflight.add_argument(
        "--branch-policy",
        choices=["auto", "require-task-branch", "current"],
        required=True,
    )
    preflight.add_argument("--push-remote", default="origin")
    preflight.add_argument("--push-set-upstream", action="store_true")
    preflight.add_argument("--run-id", required=True)
    preflight.add_argument("--dry-run", action="store_true")
    preflight.set_defaults(func=command_preflight)

    checkpoint = subparsers.add_parser("checkpoint")
    checkpoint.add_argument("--root-dir", type=Path, required=True)
    checkpoint.add_argument("--mode", choices=["off", "commit", "push"], required=True)
    checkpoint.add_argument("--push-remote", default="origin")
    checkpoint.add_argument("--push-set-upstream", action="store_true")
    checkpoint.add_argument("--dry-run", action="store_true")
    checkpoint.add_argument("--label", required=True)
    checkpoint.add_argument("--phase", required=True)
    checkpoint.add_argument("--task-name", required=True)
    checkpoint.add_argument("--attempts", type=int, required=True)
    checkpoint.add_argument("--run-id", required=True)
    checkpoint.add_argument("--copy-log", default="")
    checkpoint.add_argument("--verify-log", default="")
    checkpoint.add_argument("--progress-file", type=Path)
    checkpoint.add_argument("--summary-file", type=Path)
    checkpoint.set_defaults(func=command_checkpoint)

    run_summary = subparsers.add_parser("commit-run-summary")
    run_summary.add_argument("--root-dir", type=Path, required=True)
    run_summary.add_argument("--mode", choices=["off", "commit", "push"], required=True)
    run_summary.add_argument("--push-remote", default="origin")
    run_summary.add_argument("--push-set-upstream", action="store_true")
    run_summary.add_argument("--dry-run", action="store_true")
    run_summary.add_argument("--run-id", required=True)
    run_summary.add_argument("--summary-file", type=Path, required=True)
    run_summary.add_argument("--run-summary-root", type=Path, required=True)
    run_summary.set_defaults(func=command_commit_run_summary)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args) or 0)
    except GitError as exc:
        print(json.dumps({"status": "error", "error": str(exc)}, ensure_ascii=False, sort_keys=True))
        return exc.returncode or 1


if __name__ == "__main__":
    raise SystemExit(main())
