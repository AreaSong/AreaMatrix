#!/usr/bin/env python3
"""State helpers for the AreaMatrix task loop.

This module intentionally uses only the Python standard library so the shell
runner can depend on it in fresh local checkouts.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


VERIFY_PASS_RE = re.compile(r"(?m)^[ \t]*VERIFY_RESULT:[ \t]*PASS[ \t]*$")
VERIFY_FAIL_RE = re.compile(r"(?m)^[ \t]*VERIFY_RESULT:[ \t]*FAIL[ \t]*$")


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


def progress_data(path: Path) -> dict[str, Any]:
    data = read_json(path, {"version": 1, "tasks": {}})
    tasks = data.setdefault("tasks", {})
    if not isinstance(tasks, dict):
        raise SystemExit("invalid progress file: tasks must be an object")
    return data


def task_key(label: str) -> tuple[int, int, int, str]:
    try:
        batch, task = label.split("/task-", 1)
        major, minor = batch.split("-", 1)
        return int(major), int(minor), int(task), label
    except ValueError:
        return 999, 999, 999, label


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def pid_alive(pid_text: str) -> bool:
    if not pid_text.isdigit():
        return False
    try:
        os.kill(int(pid_text), 0)
        return True
    except OSError:
        return False


def lock_info(lock_dir: Path) -> dict[str, Any]:
    pid_text = read_text(lock_dir / "pid")
    return {
        "exists": lock_dir.is_dir(),
        "pid": pid_text,
        "run_id": read_text(lock_dir / "run_id"),
        "operation": read_text(lock_dir / "operation"),
        "started_at": read_text(lock_dir / "started_at"),
        "command": read_text(lock_dir / "command"),
        "alive": pid_alive(pid_text),
    }


def verify_result(path_value: Any) -> str:
    if not isinstance(path_value, str) or not path_value:
        return "missing"
    path = Path(path_value)
    if not path.exists():
        return "missing"
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return "unreadable"
    if VERIFY_PASS_RE.search(text):
        return "pass"
    if VERIFY_FAIL_RE.search(text):
        return "fail"
    return "unfinished"


def stale_reason(entry: dict[str, Any], lock: dict[str, Any]) -> str | None:
    if entry.get("status") != "in_progress":
        return None
    active = bool(lock["alive"]) and entry.get("run_id") == lock.get("run_id")
    result = verify_result(entry.get("verify_log"))
    copy_log = entry.get("copy_log")
    copy_exists = isinstance(copy_log, str) and bool(copy_log) and Path(copy_log).exists()
    if active:
        return None
    if result == "pass":
        return None
    copy_state = "exists" if copy_exists else "missing"
    return f"no active matching lock; copy_log={copy_state}; verify={result}"


def stale_tasks(progress_path: Path, lock_dir: Path) -> list[tuple[str, dict[str, Any], str]]:
    data = progress_data(progress_path)
    lock = lock_info(lock_dir)
    stale: list[tuple[str, dict[str, Any], str]] = []
    for label, value in data.get("tasks", {}).items():
        if not isinstance(value, dict):
            continue
        reason = stale_reason(value, lock)
        if reason:
            stale.append((label, value, reason))
    return sorted(stale, key=lambda item: task_key(item[0]))


def backup_progress(progress_file: Path, backup_root: Path, reason: str) -> Path | None:
    if not progress_file.exists():
        return None
    backup_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = backup_root / f"progress-before-{reason}-{stamp}.json"
    shutil.copy2(progress_file, backup_file)
    return backup_file


def update_index(run_summary_root: Path, summary_file: Path) -> None:
    if not summary_file.exists():
        return
    summary = read_json(summary_file, {})
    index_file = run_summary_root / "index.json"
    index = read_json(index_file, {"version": 1, "runs": []})
    runs = index.setdefault("runs", [])
    if not isinstance(runs, list):
        runs = []
        index["runs"] = runs

    run_id = str(summary.get("run_id", ""))
    record = {
        "run_id": run_id,
        "status": summary.get("status", ""),
        "summary_file": str(summary_file),
        "phases": summary.get("phases", []),
        "start_from": summary.get("start_from", ""),
        "completed": summary.get("totals", {}).get("completed_in_run", 0),
        "retries": summary.get("totals", {}).get("retries", 0),
        "exit_code": summary.get("exit_code"),
        "started_at": summary.get("started_at", ""),
        "finished_at": summary.get("finished_at", ""),
        "updated_at": utc_now(),
    }

    runs = [item for item in runs if not isinstance(item, dict) or item.get("run_id") != run_id]
    runs.insert(0, record)
    index["runs"] = runs[:100]
    index["latest_run_id"] = run_id
    index["updated_at"] = utc_now()
    write_json(index_file, index)


def command_task_status(args: argparse.Namespace) -> int:
    data = progress_data(args.progress_file)
    entry = data.get("tasks", {}).get(args.label, {})
    status = entry.get("status") if isinstance(entry, dict) else None
    print(status if isinstance(status, str) else "pending")
    return 0


def command_mark_progress(args: argparse.Namespace) -> int:
    data = progress_data(args.progress_file)
    tasks = data.setdefault("tasks", {})
    entry = tasks.setdefault(args.label, {})
    if not isinstance(entry, dict):
        entry = {}
        tasks[args.label] = entry
    entry.update(
        {
            "status": args.status,
            "note": args.note,
            "updated_at": utc_now(),
        }
    )
    if args.copy_log:
        entry["copy_log"] = args.copy_log
    if args.verify_log:
        entry["verify_log"] = args.verify_log
    if args.attempts:
        entry["attempts"] = args.attempts
    if args.risk:
        entry["risk"] = args.risk
    if args.run_id:
        entry["run_id"] = args.run_id
    write_json(args.progress_file, data)
    return 0


def command_first_failed(args: argparse.Namespace) -> int:
    data = progress_data(args.progress_file)
    failed = [
        label
        for label, value in data.get("tasks", {}).items()
        if isinstance(value, dict) and value.get("status") == "failed"
    ]
    if failed:
        print(sorted(failed, key=task_key)[0])
    return 0


def command_count_completed(args: argparse.Namespace) -> int:
    data = progress_data(args.progress_file)
    count = sum(
        1
        for value in data.get("tasks", {}).values()
        if isinstance(value, dict) and value.get("status") == "completed"
    )
    print(count)
    return 0


def command_first_stale(args: argparse.Namespace) -> int:
    stale = stale_tasks(args.progress_file, args.lock_dir)
    if stale:
        print(stale[0][0])
    return 0


def command_clear_stale(args: argparse.Namespace) -> int:
    backup = backup_progress(args.progress_file, args.backup_root, "clear-stale")
    if backup:
        print(f"progress backup: {backup}")
    data = progress_data(args.progress_file)
    stale = stale_tasks(args.progress_file, args.lock_dir)
    for label, _, _ in stale:
        data.get("tasks", {}).pop(label, None)
    data["updated_at"] = utc_now()
    write_json(args.progress_file, data)
    print(f"cleared stale in_progress records: {len(stale)}")
    return 0


def command_reset_progress(args: argparse.Namespace) -> int:
    backup = backup_progress(args.progress_file, args.backup_root, "reset")
    if backup:
        print(f"progress backup: {backup}")
    else:
        print("progress file does not exist; no backup needed")
    write_json(args.progress_file, {"version": 1, "tasks": {}})
    print(f"progress reset: {args.progress_file}")
    return 0


def print_lock_fragment(lock_dir: Path) -> None:
    lock = lock_info(lock_dir)
    if not lock["exists"]:
        print("- lock: none")
        return
    print("- lock: present")
    print(f"- lock_alive: {'yes' if lock['alive'] else 'no'}")
    print(f"- lock_pid: {lock['pid'] or 'unknown'}")
    print(f"- lock_run_id: {lock['run_id'] or 'unknown'}")
    print(f"- lock_operation: {lock['operation'] or 'unknown'}")
    print(f"- lock_started_at: {lock['started_at'] or 'unknown'}")
    if lock["command"]:
        print(f"- lock_command: {lock['command']}")


def command_status_fragment(args: argparse.Namespace) -> int:
    print(f"- lock_dir: {args.lock_dir}")
    print_lock_fragment(args.lock_dir)
    latest_log = ""
    if args.log_root.is_dir():
        latest_logs = sorted(path for path in args.log_root.iterdir() if path.is_dir() and path.name.startswith("20"))
        if latest_logs:
            latest_log = str(latest_logs[-1])
    print(f"- latest_log_dir: {latest_log or 'None'}")

    data = progress_data(args.progress_file)
    counts: dict[str, int] = {}
    recent: list[tuple[str, str, str, str]] = []
    for label, value in data.get("tasks", {}).items():
        if not isinstance(value, dict):
            continue
        status = value.get("status", "pending")
        counts[status] = counts.get(status, 0) + 1
        if status in {"failed", "blocked", "in_progress"}:
            recent.append((value.get("updated_at", ""), label, status, value.get("note", "")))

    print(f"- progress_entries: {sum(counts.values())}")
    for status in ["completed", "in_progress", "failed", "blocked", "pending"]:
        if status in counts:
            print(f"- {status}: {counts[status]}")
    for _, label, status, note in sorted(recent, reverse=True)[:5]:
        suffix = f" - {note}" if note else ""
        print(f"- recent_{status}: {label}{suffix}")

    stale = stale_tasks(args.progress_file, args.lock_dir)
    print(f"- stale_in_progress: {len(stale)}")
    for label, entry, reason in stale[:5]:
        note = entry.get("note", "")
        suffix = f" - {note}" if note else ""
        print(f"- recent_stale_in_progress: {label}{suffix} ({reason})")
    if stale:
        print("- stale_recovery: bash scripts/run_area_matrix_task_pipeline.sh --resume-stale")
        print("- stale_clear: bash scripts/run_area_matrix_task_pipeline.sh --clear-stale")
    return 0


def command_init_summary(args: argparse.Namespace) -> int:
    now = utc_now()
    summary = {
        "version": 1,
        "run_id": args.run_id,
        "status": "running",
        "started_at": now,
        "updated_at": now,
        "root_dir": args.root_dir,
        "model": args.model,
        "model_reasoning_effort": args.model_reasoning_effort,
        "dry_run": args.dry_run,
        "codex_bin": args.codex_bin,
        "risk_gate": args.risk_gate,
        "risk_policy": args.risk_policy,
        "max_retries": args.max_retries,
        "max_tasks": args.max_tasks,
        "start_from": args.start_from,
        "progress_file": args.progress_file,
        "log_root": args.log_root,
        "copy_root": args.copy_root,
        "verify_root": args.verify_root,
        "git": {
            "checkpoint": args.git_checkpoint,
            "branch_policy": args.git_branch_policy,
            "push_remote": args.git_push_remote,
            "push_set_upstream": args.git_push_set_upstream,
            "active_branch": args.git_active_branch,
        },
        "phases": args.phases.split() if args.phases else [],
        "totals": {
            "task_count": args.total_tasks,
            "completed_in_run": 0,
            "retries": 0,
        },
        "tasks": {},
    }
    write_json(args.summary_file, summary)
    return 0


def command_record_summary(args: argparse.Namespace) -> int:
    if not args.summary_file.exists():
        return 0
    data = read_json(args.summary_file, {})
    tasks = data.setdefault("tasks", {})
    tasks[args.label] = {
        "phase": args.phase,
        "task_name": args.task_name,
        "status": args.status,
        "attempts": args.attempts,
        "risk": args.risk,
        "copy_log": args.copy_log,
        "verify_log": args.verify_log,
        "note": args.note,
        "updated_at": utc_now(),
    }
    totals = data.setdefault("totals", {})
    totals["completed_in_run"] = args.completed
    totals["retries"] = args.retries
    data["updated_at"] = utc_now()
    write_json(args.summary_file, data)
    return 0


def command_finalize_summary(args: argparse.Namespace) -> int:
    if not args.summary_file.exists():
        return 0
    data = read_json(args.summary_file, {})
    data["status"] = args.status
    data["exit_code"] = args.exit_code
    data["finished_at"] = utc_now()
    data["updated_at"] = utc_now()
    if args.note:
        data["note"] = args.note
    totals = data.setdefault("totals", {})
    totals["completed_in_run"] = args.completed
    totals["retries"] = args.retries
    write_json(args.summary_file, data)
    update_index(args.run_summary_root, args.summary_file)
    return 0


def command_update_index(args: argparse.Namespace) -> int:
    update_index(args.run_summary_root, args.summary_file)
    return 0


def add_common_path(parser: argparse.ArgumentParser, name: str, required: bool = True) -> None:
    parser.add_argument(name, type=Path, required=required)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    task_status = subparsers.add_parser("task-status")
    add_common_path(task_status, "--progress-file")
    task_status.add_argument("--label", required=True)
    task_status.set_defaults(func=command_task_status)

    mark = subparsers.add_parser("mark-progress")
    add_common_path(mark, "--progress-file")
    mark.add_argument("--label", required=True)
    mark.add_argument("--status", required=True)
    mark.add_argument("--note", default="")
    mark.add_argument("--copy-log", default="")
    mark.add_argument("--verify-log", default="")
    mark.add_argument("--attempts", type=int, default=0)
    mark.add_argument("--risk", default="")
    mark.add_argument("--run-id", default="")
    mark.set_defaults(func=command_mark_progress)

    first_failed = subparsers.add_parser("first-failed")
    add_common_path(first_failed, "--progress-file")
    first_failed.set_defaults(func=command_first_failed)

    count_completed = subparsers.add_parser("count-completed")
    add_common_path(count_completed, "--progress-file")
    count_completed.set_defaults(func=command_count_completed)

    first_stale = subparsers.add_parser("first-stale")
    add_common_path(first_stale, "--progress-file")
    add_common_path(first_stale, "--lock-dir")
    first_stale.set_defaults(func=command_first_stale)

    clear_stale = subparsers.add_parser("clear-stale")
    add_common_path(clear_stale, "--progress-file")
    add_common_path(clear_stale, "--lock-dir")
    add_common_path(clear_stale, "--backup-root")
    clear_stale.set_defaults(func=command_clear_stale)

    reset = subparsers.add_parser("reset-progress")
    add_common_path(reset, "--progress-file")
    add_common_path(reset, "--backup-root")
    reset.set_defaults(func=command_reset_progress)

    status = subparsers.add_parser("status-fragment")
    add_common_path(status, "--progress-file")
    add_common_path(status, "--lock-dir")
    add_common_path(status, "--log-root")
    status.set_defaults(func=command_status_fragment)

    init_summary = subparsers.add_parser("init-summary")
    add_common_path(init_summary, "--summary-file")
    init_summary.add_argument("--run-id", required=True)
    init_summary.add_argument("--root-dir", required=True)
    init_summary.add_argument("--model", required=True)
    init_summary.add_argument("--model-reasoning-effort", required=True)
    init_summary.add_argument("--dry-run", action="store_true")
    init_summary.add_argument("--codex-bin", default="")
    init_summary.add_argument("--risk-gate", required=True)
    init_summary.add_argument("--risk-policy", required=True)
    init_summary.add_argument("--max-retries", type=int, required=True)
    init_summary.add_argument("--max-tasks", type=int, required=True)
    init_summary.add_argument("--start-from", default="")
    init_summary.add_argument("--progress-file", required=True)
    init_summary.add_argument("--log-root", required=True)
    init_summary.add_argument("--copy-root", required=True)
    init_summary.add_argument("--verify-root", required=True)
    init_summary.add_argument("--phases", default="")
    init_summary.add_argument("--total-tasks", type=int, required=True)
    init_summary.add_argument("--git-checkpoint", default="off")
    init_summary.add_argument("--git-branch-policy", default="auto")
    init_summary.add_argument("--git-push-remote", default="origin")
    init_summary.add_argument("--git-push-set-upstream", default="1")
    init_summary.add_argument("--git-active-branch", default="")
    init_summary.set_defaults(func=command_init_summary)

    record = subparsers.add_parser("record-summary")
    add_common_path(record, "--summary-file")
    record.add_argument("--label", required=True)
    record.add_argument("--phase", required=True)
    record.add_argument("--task-name", required=True)
    record.add_argument("--status", required=True)
    record.add_argument("--attempts", type=int, required=True)
    record.add_argument("--risk", default="")
    record.add_argument("--copy-log", default="")
    record.add_argument("--verify-log", default="")
    record.add_argument("--note", default="")
    record.add_argument("--completed", type=int, required=True)
    record.add_argument("--retries", type=int, required=True)
    record.set_defaults(func=command_record_summary)

    finalize = subparsers.add_parser("finalize-summary")
    add_common_path(finalize, "--summary-file")
    add_common_path(finalize, "--run-summary-root")
    finalize.add_argument("--status", required=True)
    finalize.add_argument("--exit-code", type=int, required=True)
    finalize.add_argument("--note", default="")
    finalize.add_argument("--completed", type=int, required=True)
    finalize.add_argument("--retries", type=int, required=True)
    finalize.set_defaults(func=command_finalize_summary)

    update = subparsers.add_parser("update-index")
    add_common_path(update, "--summary-file")
    add_common_path(update, "--run-summary-root")
    update.set_defaults(func=command_update_index)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
