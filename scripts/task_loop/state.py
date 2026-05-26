"""State, lock, progress, and summary helpers for the AreaMatrix task loop."""

from __future__ import annotations

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
        raise ValueError("invalid progress file: tasks must be an object")
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


def read_json_file(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


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
        "activity": read_json_file(lock_dir / "activity.json"),
        "alive": pid_alive(pid_text),
    }


def write_lock_activity(lock_dir: Path, values: dict[str, Any]) -> None:
    if not lock_dir.is_dir():
        return
    current = read_json_file(lock_dir / "activity.json")
    current.update(values)
    current["updated_at"] = utc_now()
    write_json(lock_dir / "activity.json", current)


def replace_lock_activity(lock_dir: Path, values: dict[str, Any]) -> None:
    if not lock_dir.is_dir():
        return
    next_values = dict(values)
    next_values["updated_at"] = utc_now()
    write_json(lock_dir / "activity.json", next_values)


def clear_lock_activity(lock_dir: Path) -> None:
    try:
        (lock_dir / "activity.json").unlink()
    except OSError:
        pass


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def human_duration(seconds: float) -> str:
    total = max(0, int(seconds))
    hours, rem = divmod(total, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h{minutes:02d}m{secs:02d}s"
    if minutes:
        return f"{minutes}m{secs:02d}s"
    return f"{secs}s"


def elapsed_since(value: Any) -> str:
    parsed = parse_time(value)
    if not parsed:
        return "unknown"
    return human_duration((datetime.now(timezone.utc) - parsed).total_seconds())


def log_file_status(path_value: Any) -> str:
    if not isinstance(path_value, str) or not path_value:
        return "unknown"
    path = Path(path_value)
    if not path.exists():
        return "missing"
    try:
        stat = path.stat()
    except OSError:
        return "unreadable"
    age = human_duration(datetime.now().timestamp() - stat.st_mtime)
    return f"exists size={stat.st_size}B updated_ago={age}"


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
    if active or result == "pass":
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


def task_status(progress_file: Path, label: str) -> str:
    data = progress_data(progress_file)
    entry = data.get("tasks", {}).get(label, {})
    status = entry.get("status") if isinstance(entry, dict) else None
    return status if isinstance(status, str) else "pending"


def mark_progress(
    progress_file: Path,
    label: str,
    status: str,
    note: str,
    copy_log: str = "",
    verify_log: str = "",
    attempts: int = 0,
    risk: str = "",
    run_id: str = "",
) -> None:
    data = progress_data(progress_file)
    tasks = data.setdefault("tasks", {})
    entry = tasks.setdefault(label, {})
    if not isinstance(entry, dict):
        entry = {}
        tasks[label] = entry
    entry.update({"status": status, "note": note, "updated_at": utc_now()})
    if copy_log:
        entry["copy_log"] = copy_log
    if verify_log:
        entry["verify_log"] = verify_log
    if attempts:
        entry["attempts"] = attempts
    if risk:
        entry["risk"] = risk
    if run_id:
        entry["run_id"] = run_id
    write_json(progress_file, data)


def first_failed(progress_file: Path) -> str:
    data = progress_data(progress_file)
    failed = [
        label
        for label, value in data.get("tasks", {}).items()
        if isinstance(value, dict) and value.get("status") == "failed"
    ]
    return sorted(failed, key=task_key)[0] if failed else ""


def first_stale(progress_file: Path, lock_dir: Path) -> str:
    stale = stale_tasks(progress_file, lock_dir)
    return stale[0][0] if stale else ""


def count_completed(progress_file: Path) -> int:
    data = progress_data(progress_file)
    return sum(
        1
        for value in data.get("tasks", {}).values()
        if isinstance(value, dict) and value.get("status") == "completed"
    )


def clear_stale(progress_file: Path, lock_dir: Path, backup_root: Path) -> list[str]:
    backup = backup_progress(progress_file, backup_root, "clear-stale")
    data = progress_data(progress_file)
    stale = stale_tasks(progress_file, lock_dir)
    for label, _, _ in stale:
        data.get("tasks", {}).pop(label, None)
    data["updated_at"] = utc_now()
    write_json(progress_file, data)
    messages = []
    if backup:
        messages.append(f"progress backup: {backup}")
    messages.append(f"cleared stale in_progress records: {len(stale)}")
    return messages


def reset_progress(progress_file: Path, backup_root: Path) -> list[str]:
    backup = backup_progress(progress_file, backup_root, "reset")
    write_json(progress_file, {"version": 1, "tasks": {}})
    messages = [f"progress backup: {backup}" if backup else "progress file does not exist; no backup needed"]
    messages.append(f"progress reset: {progress_file}")
    return messages


def read_control_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def status_fragment(progress_file: Path, lock_dir: Path, log_root: Path, drain_request_file: Path) -> str:
    lines: list[str] = [f"- lock_dir: {lock_dir}"]
    lock = lock_info(lock_dir)
    if not lock["exists"]:
        lines.append("- lock: none")
    else:
        lines.extend(
            [
                "- lock: present",
                f"- lock_alive: {'yes' if lock['alive'] else 'no'}",
                f"- lock_pid: {lock['pid'] or 'unknown'}",
                f"- lock_run_id: {lock['run_id'] or 'unknown'}",
                f"- lock_operation: {lock['operation'] or 'unknown'}",
                f"- lock_started_at: {lock['started_at'] or 'unknown'}",
            ]
        )
        if lock["command"]:
            lines.append(f"- lock_command: {lock['command']}")
        activity = lock.get("activity")
        if isinstance(activity, dict) and activity:
            stage = activity.get("stage") or "unknown"
            label = activity.get("task_label") or "unknown"
            attempt = activity.get("attempt") or "unknown"
            status = activity.get("status") or "unknown"
            started_at = activity.get("started_at") or "unknown"
            lines.extend(
                [
                    f"- live_activity: {stage} task={label} attempt={attempt} status={status}",
                    f"- live_activity_started_at: {started_at}",
                    f"- live_activity_elapsed: {elapsed_since(started_at)}",
                ]
            )
            if activity.get("pid"):
                pid = str(activity.get("pid"))
                lines.append(f"- live_activity_pid: {pid} alive={'yes' if pid_alive(pid) else 'no'}")
            if activity.get("prompt_file"):
                lines.append(f"- live_activity_prompt: {activity['prompt_file']}")
            if activity.get("output_file"):
                output_file = activity["output_file"]
                lines.append(f"- live_activity_log: {output_file}")
                lines.append(f"- live_activity_log_state: {log_file_status(output_file)}")
            if activity.get("exec_log_file"):
                exec_log_file = activity["exec_log_file"]
                lines.append(f"- live_activity_exec_log: {exec_log_file}")
                lines.append(f"- live_activity_exec_log_state: {log_file_status(exec_log_file)}")
            if activity.get("no_output_elapsed_seconds") is not None:
                lines.append(
                    f"- live_activity_no_output_elapsed: {human_duration(float(activity['no_output_elapsed_seconds']))}"
                )
            if activity.get("no_output_timeout_seconds") is not None:
                timeout_seconds = float(activity["no_output_timeout_seconds"])
                timeout = "disabled" if timeout_seconds <= 0 else human_duration(timeout_seconds)
                lines.append(f"- live_activity_no_output_timeout: {timeout}")
            if activity.get("codex_idle_timeout_seconds") is not None:
                timeout_seconds = float(activity["codex_idle_timeout_seconds"])
                timeout = "disabled" if timeout_seconds <= 0 else human_duration(timeout_seconds)
                lines.append(f"- live_activity_codex_idle_timeout: {timeout}")
            if activity.get("validation_child_running") is not None:
                lines.append(
                    f"- live_activity_validation_child_running: {'yes' if activity.get('validation_child_running') else 'no'}"
                )
            if activity.get("validation_child_count") is not None:
                lines.append(f"- live_activity_validation_child_count: {activity['validation_child_count']}")
            details = activity.get("validation_child_details")
            if isinstance(details, list):
                for detail in details[:5]:
                    lines.append(f"- live_activity_validation_child: {detail}")
            if activity.get("validation_scan_reason"):
                lines.append(f"- live_activity_validation_scan_reason: {activity['validation_scan_reason']}")
            if activity.get("meaningful_activity") is not None:
                lines.append(
                    f"- live_activity_meaningful_activity: {'yes' if activity.get('meaningful_activity') else 'no'}"
                )
            if activity.get("exec_activity_event_count") is not None:
                lines.append(f"- live_activity_exec_activity_events: {activity['exec_activity_event_count']}")
            if activity.get("child_restart") is not None and activity.get("child_restart_limit") is not None:
                lines.append(
                    f"- live_activity_child_restart: {activity['child_restart']}/{activity['child_restart_limit']}"
                )
            if activity.get("restart_delay_seconds") is not None:
                lines.append(
                    f"- live_activity_restart_delay: {human_duration(float(activity['restart_delay_seconds']))}"
                )
            if activity.get("command"):
                lines.append(f"- live_activity_command: {activity['command']}")

    drain = read_control_file(drain_request_file)
    lines.append(f"- drain_requested: {'yes' if drain else 'no'}")
    if drain:
        lines.append(f"- drain_target: {drain.get('target', 'after_current_task')}")
        lines.append(f"- drain_requested_at: {drain.get('requested_at', 'unknown')}")
        lines.append(f"- drain_run_id: {drain.get('lock_run_id', 'unknown') or 'unknown'}")

    latest_log = ""
    if log_root.is_dir():
        latest_logs = sorted(path for path in log_root.iterdir() if path.is_dir() and path.name.startswith("20"))
        if latest_logs:
            latest_log = str(latest_logs[-1])
    lines.append(f"- latest_log_dir: {latest_log or 'None'}")

    data = progress_data(progress_file)
    counts: dict[str, int] = {}
    recent: list[tuple[str, str, str, str]] = []
    for label, value in data.get("tasks", {}).items():
        if not isinstance(value, dict):
            continue
        status = value.get("status", "pending")
        counts[status] = counts.get(status, 0) + 1
        if status in {"failed", "blocked", "in_progress"}:
            recent.append((value.get("updated_at", ""), label, status, value.get("note", "")))

    lines.append(f"- progress_entries: {sum(counts.values())}")
    for status in ["completed", "in_progress", "failed", "blocked", "pending"]:
        if status in counts:
            lines.append(f"- {status}: {counts[status]}")
    for _, label, status, note in sorted(recent, reverse=True)[:5]:
        suffix = f" - {note}" if note else ""
        lines.append(f"- recent_{status}: {label}{suffix}")

    stale = stale_tasks(progress_file, lock_dir)
    lines.append(f"- stale_in_progress: {len(stale)}")
    for label, entry, reason in stale[:5]:
        note = entry.get("note", "")
        suffix = f" - {note}" if note else ""
        lines.append(f"- recent_stale_in_progress: {label}{suffix} ({reason})")
    if stale:
        lines.append("- stale_recovery: ./task-loop resume-stale")
        lines.append("- stale_clear: ./task-loop clear-stale")
    return "\n".join(lines) + "\n"


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
        "stop_after": summary.get("stop_after", ""),
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


def init_summary(summary_file: Path, values: dict[str, Any]) -> None:
    now = utc_now()
    summary = {
        "version": 1,
        "status": "running",
        "started_at": now,
        "updated_at": now,
        "totals": {"task_count": values.pop("total_tasks"), "completed_in_run": 0, "retries": 0},
        "tasks": {},
        **values,
    }
    write_json(summary_file, summary)


def record_summary(
    summary_file: Path,
    label: str,
    phase: str,
    task_name: str,
    status: str,
    attempts: int,
    risk: str,
    copy_log: str,
    verify_log: str,
    note: str,
    completed: int,
    retries: int,
) -> None:
    if not summary_file.exists():
        return
    data = read_json(summary_file, {})
    tasks = data.setdefault("tasks", {})
    tasks[label] = {
        "phase": phase,
        "task_name": task_name,
        "status": status,
        "attempts": attempts,
        "risk": risk,
        "copy_log": copy_log,
        "verify_log": verify_log,
        "note": note,
        "updated_at": utc_now(),
    }
    totals = data.setdefault("totals", {})
    totals["completed_in_run"] = completed
    totals["retries"] = retries
    data["updated_at"] = utc_now()
    write_json(summary_file, data)


def finalize_summary(
    summary_file: Path,
    run_summary_root: Path,
    status: str,
    exit_code: int,
    completed: int,
    retries: int,
    note: str = "",
) -> None:
    if not summary_file.exists():
        return
    data = read_json(summary_file, {})
    data["status"] = status
    data["exit_code"] = exit_code
    data["finished_at"] = utc_now()
    data["updated_at"] = utc_now()
    if note:
        data["note"] = note
    totals = data.setdefault("totals", {})
    totals["completed_in_run"] = completed
    totals["retries"] = retries
    write_json(summary_file, data)
    update_index(run_summary_root, summary_file)
