"""Git checkpoint helpers for the AreaMatrix task loop."""

from __future__ import annotations

import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import state


class GitError(RuntimeError):
    def __init__(self, message: str, returncode: int = 1) -> None:
        super().__init__(message)
        self.returncode = returncode


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


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


def git_path_matches(pattern: str, path: str) -> bool:
    pattern = pattern.strip().lstrip("./")
    path = path.strip().lstrip("./")
    if not pattern:
        return False
    if pattern.endswith("/**"):
        prefix = pattern[:-3].rstrip("/")
        return path == prefix or path.startswith(prefix + "/")
    if pattern.endswith("/"):
        return path.startswith(pattern)
    return path == pattern


def dirty_paths_outside_allowed(status_lines: list[str], allowed_dirty_paths: list[str]) -> list[str]:
    unexpected: list[str] = []
    for line in status_lines:
        for path in status_line_paths(line):
            if not any(git_path_matches(pattern, path) for pattern in allowed_dirty_paths):
                unexpected.append(path)
    return unique_paths(unexpected)


def ensure_clean_worktree(root: Path, allowed_dirty_paths: list[str] | None = None) -> None:
    dirty = status_short(root)
    if not dirty:
        return
    if allowed_dirty_paths is not None:
        unexpected = dirty_paths_outside_allowed(dirty, allowed_dirty_paths)
        if not unexpected:
            return
        preview = "\n".join(unexpected[:20])
        allowed_preview = "\n".join(allowed_dirty_paths[:20])
        raise GitError(
            "git checkpoint resume-stale allows dirty worktree only inside the stale task scope.\n"
            "Commit or move unrelated infrastructure changes first, or run with GIT_CHECKPOINT=off for diagnostics.\n"
            f"Unexpected dirty paths:\n{preview}\n"
            f"Allowed dirty patterns:\n{allowed_preview}"
        )
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
    proc = run_git(root, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], check=False)
    return "" if proc.returncode != 0 else proc.stdout.strip()


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
    return {"upstream": upstream, "ahead": ahead, "behind": behind, "pushed_existing": bool(ahead)}


def parse_changed_paths(status_lines: list[str]) -> list[str]:
    paths: list[str] = []
    for line in status_lines:
        line_paths = status_line_paths(line)
        if not line_paths:
            continue
        paths.append(line_paths[-1])
    return sorted(dict.fromkeys(paths))


def diff_name_status(root: Path) -> list[str]:
    proc = run_git(root, ["diff", "--name-status", "HEAD"], check=True)
    return [line for line in proc.stdout.splitlines() if line.strip()]


def path_for_git(root: Path, path: Path | None) -> str | None:
    if not path:
        return None
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return None


def unique_paths(paths: list[str]) -> list[str]:
    return sorted(dict.fromkeys(path for path in paths if path))


def status_line_paths(line: str) -> list[str]:
    if len(line) < 4:
        return []
    path = line[3:]
    if " -> " in path:
        before, after = path.split(" -> ", 1)
        return [before, after]
    return [path]


def is_task_loop_log_path(path: str) -> bool:
    return path.startswith(".codex/task-loop-logs/")


def is_exec_stream_log_path(path: str) -> bool:
    return is_task_loop_log_path(path) and path.endswith(".exec.log")


def is_final_task_log_path(path: str) -> bool:
    return is_task_loop_log_path(path) and path.endswith(".log") and not is_exec_stream_log_path(path)


def skipped_checkpoint_path(path: str, allowed_paths: set[str]) -> bool:
    if path in allowed_paths:
        return False
    return is_task_loop_log_path(path)


def checkpoint_stage_paths(status_lines: list[str], allowed_paths: set[str]) -> tuple[list[str], list[str]]:
    stage_paths: list[str] = []
    skipped_paths: list[str] = []
    for line in status_lines:
        for path in status_line_paths(line):
            if skipped_checkpoint_path(path, allowed_paths):
                skipped_paths.append(path)
            else:
                stage_paths.append(path)
    return unique_paths(stage_paths), unique_paths(skipped_paths)


def existing_final_log_paths(root: Path, *logs: str) -> list[str]:
    paths: list[str] = []
    for value in logs:
        if not value:
            continue
        rel = path_for_git(root, Path(value))
        if rel and is_final_task_log_path(rel) and (root / rel).exists():
            paths.append(rel)
    return unique_paths(paths)


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


def update_progress(progress_file: Path | None, label: str, evidence: dict[str, Any]) -> None:
    if not progress_file:
        return
    data = state.read_json(progress_file, {"version": 1, "tasks": {}})
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
    state.write_json(progress_file, data)


def update_summary(summary_file: Path | None, label: str, evidence: dict[str, Any]) -> None:
    if not summary_file or not summary_file.exists():
        return
    data = state.read_json(summary_file, {})
    tasks = data.setdefault("tasks", {})
    task = tasks.setdefault(label, {})
    if not isinstance(task, dict):
        task = {}
        tasks[label] = task
    task["git"] = evidence
    data["updated_at"] = utc_now()
    state.write_json(summary_file, data)


def write_evidence(progress_file: Path | None, summary_file: Path | None, label: str, evidence: dict[str, Any]) -> None:
    update_progress(progress_file, label, evidence)
    update_summary(summary_file, label, evidence)


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
            path_for_git(root, progress_file),
            path_for_git(root, summary_file),
        ]
        if path
    ]
    if not paths:
        return ""
    run_git(root, ["add", "--", *paths], check=True)
    staged = run_git(root, ["diff", "--cached", "--name-only"], check=True).stdout.splitlines()
    if not staged:
        return ""
    run_git(root, ["commit", "-m", f"task-loop: record checkpoint evidence {label}", "-m", f"Completed commit: {completed_commit}"], check=True)
    return run_git(root, ["rev-parse", "HEAD"], check=True).stdout.strip()


def preflight(
    root_dir: Path,
    mode: str,
    branch_policy: str,
    push_remote: str,
    push_set_upstream: bool,
    run_id: str,
    dry_run: bool = False,
    allowed_dirty_paths: list[str] | None = None,
) -> dict[str, Any]:
    if mode == "off" or dry_run:
        return {"status": "skipped", "mode": mode, "dry_run": dry_run}

    root = ensure_git_repo(root_dir)
    ensure_clean_worktree(root, allowed_dirty_paths=allowed_dirty_paths)
    branch = current_branch(root)
    created_branch = ""
    if branch == "main":
        if branch_policy == "require-task-branch":
            raise GitError("GIT_BRANCH_POLICY=require-task-branch refuses to run on main")
        if branch_policy == "auto":
            created_branch = f"codex/areamatrix-task-loop-{safe_run_id(run_id)}"
            if branch_exists(root, created_branch):
                run_git(root, ["checkout", created_branch], check=True)
            else:
                run_git(root, ["checkout", "-b", created_branch], check=True)
            branch = current_branch(root)

    push_info: dict[str, Any] = {}
    remote = ""
    if mode == "push":
        remote = remote_url(root, push_remote)
        push_info = maybe_push_existing_ahead(root, push_remote, push_set_upstream)

    return {
        "status": "ok",
        "mode": mode,
        "branch": branch,
        "created_branch": created_branch,
        "remote": remote,
        "push": push_info,
    }


def checkpoint(
    root_dir: Path,
    mode: str,
    push_remote: str,
    push_set_upstream: bool,
    label: str,
    phase: str,
    task_name: str,
    attempts: int,
    run_id: str,
    copy_log: str,
    verify_log: str,
    progress_file: Path | None,
    summary_file: Path | None,
    dry_run: bool = False,
) -> dict[str, Any]:
    if mode == "off" or dry_run:
        evidence = {"status": "skipped", "mode": mode, "dry_run": dry_run, "updated_at": utc_now()}
        write_evidence(progress_file, summary_file, label, evidence)
        return evidence

    root = ensure_git_repo(root_dir)
    branch = current_branch(root)
    evidence: dict[str, Any] = {
        "status": "pending",
        "mode": mode,
        "branch": branch,
        "remote": push_remote if mode == "push" else "",
        "label": label,
        "phase": phase,
        "task_name": task_name,
        "attempts": attempts,
        "run_id": run_id,
        "copy_log": copy_log,
        "verify_log": verify_log,
        "summary_file": str(summary_file) if summary_file else "",
        "changed_files": [],
        "status_short": [],
        "diff_name_status": [],
        "commit": "",
        "push_status": "not_requested" if mode == "commit" else "pending",
        "updated_at": utc_now(),
    }

    diff_check = run_git(root, ["diff", "--check"], check=False)
    if diff_check.returncode != 0:
        evidence["status"] = "git_diff_check_failed"
        evidence["error"] = (diff_check.stderr or diff_check.stdout).strip()
        write_evidence(progress_file, summary_file, label, evidence)
        raise GitError(json.dumps(evidence, ensure_ascii=False, sort_keys=True), 11)

    before_status = status_short(root)
    final_log_paths = existing_final_log_paths(root, copy_log, verify_log)
    evidence_paths = unique_paths(
        [
            path
            for path in [
                path_for_git(root, progress_file),
                path_for_git(root, summary_file),
            ]
            if path
        ]
    )
    allowed_paths = set(final_log_paths + evidence_paths)
    stage_paths, skipped_log_paths = checkpoint_stage_paths(before_status, allowed_paths)
    stage_paths = unique_paths(stage_paths + final_log_paths)
    evidence["status_short"] = before_status
    evidence["pre_checkpoint_changed_files"] = parse_changed_paths(before_status)
    evidence["changed_files"] = stage_paths
    evidence["final_log_files"] = final_log_paths
    evidence["skipped_log_files"] = skipped_log_paths
    evidence["diff_name_status"] = diff_name_status(root)
    if not stage_paths:
        evidence["status"] = "no_changes"
        write_evidence(progress_file, summary_file, label, evidence)
        return evidence

    regular_stage_paths = [path for path in stage_paths if path not in final_log_paths]
    if regular_stage_paths:
        run_git(root, ["add", "--", *regular_stage_paths], check=True)
    if final_log_paths:
        run_git(root, ["add", "--force", "--", *final_log_paths], check=True)
    staged = run_git(root, ["diff", "--cached", "--name-status"], check=True).stdout.splitlines()
    evidence["staged_name_status"] = [line for line in staged if line.strip()]
    if not evidence["staged_name_status"]:
        evidence["status"] = "no_staged_changes"
        write_evidence(progress_file, summary_file, label, evidence)
        return evidence

    title, body = commit_message(label, phase, task_name, attempts, run_id, copy_log, verify_log, str(summary_file) if summary_file else "")
    run_git(root, ["commit", "-m", title, "-m", body], check=True)
    evidence["commit"] = run_git(root, ["rev-parse", "HEAD"], check=True).stdout.strip()
    evidence["status"] = "pushed" if mode == "push" else "committed"
    evidence["push_status"] = "pushed" if mode == "push" else evidence["push_status"]
    evidence["updated_at"] = utc_now()
    write_evidence(progress_file, summary_file, label, evidence)
    evidence_commit = commit_evidence_files(root, label, str(evidence["commit"]), progress_file, summary_file)
    if evidence_commit:
        evidence["evidence_commit"] = evidence_commit

    if mode == "push":
        try:
            remote_url(root, push_remote)
            push_branch(root, push_remote, branch, push_set_upstream)
        except GitError as exc:
            evidence["status"] = "git_push_failed"
            evidence["push_status"] = "failed"
            evidence["error"] = str(exc)
            evidence["updated_at"] = utc_now()
            write_evidence(progress_file, summary_file, label, evidence)
            failure_commit = commit_evidence_files(root, label, str(evidence["commit"]), progress_file, summary_file)
            if failure_commit:
                evidence["push_failure_evidence_commit"] = failure_commit
            raise GitError(json.dumps(evidence, ensure_ascii=False, sort_keys=True), 20)

    evidence["updated_at"] = utc_now()
    return evidence


def commit_run_summary(
    root_dir: Path,
    mode: str,
    push_remote: str,
    push_set_upstream: bool,
    run_id: str,
    summary_file: Path,
    run_summary_root: Path,
    dry_run: bool = False,
) -> dict[str, Any]:
    if mode == "off" or dry_run:
        return {"status": "skipped", "mode": mode, "dry_run": dry_run}

    root = ensure_git_repo(root_dir)
    branch = current_branch(root)
    index_file = run_summary_root / "index.json"
    allowed = {path for path in [path_for_git(root, summary_file), path_for_git(root, index_file)] if path}
    if not allowed:
        return {"status": "skipped", "reason": "summary outside git root"}

    dirty = status_short(root)
    if not dirty:
        return {"status": "no_changes", "run_id": run_id}

    changed = set(parse_changed_paths(dirty))
    unexpected = sorted(path for path in changed if path not in allowed)
    if unexpected:
        raise GitError("run summary checkpoint found unexpected dirty paths after task checkpoint: " + ", ".join(unexpected[:20]))

    run_git(root, ["add", "--", *sorted(allowed)], check=True)
    staged = run_git(root, ["diff", "--cached", "--name-only"], check=True).stdout.splitlines()
    if not staged:
        return {"status": "no_staged_changes", "run_id": run_id}

    run_git(root, ["commit", "-m", f"task-loop: finalize run {run_id}", "-m", f"Summary: {summary_file}"], check=True)
    commit = run_git(root, ["rev-parse", "HEAD"], check=True).stdout.strip()
    status = "committed"
    if mode == "push":
        try:
            remote_url(root, push_remote)
            push_branch(root, push_remote, branch, push_set_upstream)
            status = "pushed"
        except GitError as exc:
            raise GitError(
                json.dumps({"status": "git_push_failed", "run_id": run_id, "commit": commit, "error": str(exc)}, ensure_ascii=False, sort_keys=True),
                20,
            )
    return {"status": status, "run_id": run_id, "commit": commit, "branch": branch}
