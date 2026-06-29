"""Command handlers for the Codex Operating System developer surface."""

from __future__ import annotations

from argparse import Namespace
import json
from pathlib import Path
import subprocess
import sys
from typing import Any

from .codex_os_registry import (
    apply_task_updates,
    default_registry,
    find_task,
    format_registry_tasks,
    lifecycle_warnings,
    load_registry,
    registry_path,
    require_registry,
    task_from_args,
    write_json,
)
from .codex_os_render import (
    render_dashboard,
    render_finish_summary,
    render_health_report,
    render_preflight_report,
    render_task_detail,
    render_thread_health,
)
from .codex_os_state import (
    DASHBOARD_NAME,
    HEALTH_REPORT_NAME,
    THREAD_HEALTH_NAME,
    ThreadRecord,
    build_snapshot,
    classify_thread,
    default_runtime_dir,
    default_state_db,
    iso_now,
    snapshot_to_json,
    thread_to_json,
)
from .common import ToolError


TEMPLATE_FILES = {
    "intake": "codex-intake-template.md",
    "handoff": "codex-handoff-template.md",
    "evidence": "codex-evidence-template.md",
    "closeout": "codex-closeout-template.md",
}


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _state_db_from_args(args: Namespace) -> Path:
    return Path(args.state_db).expanduser() if args.state_db else default_state_db()


def _runtime_dir_from_args(root: Path, args: Namespace) -> Path:
    return Path(args.runtime_dir) if args.runtime_dir else default_runtime_dir(root)


def _template_text(root: Path, template_name: str) -> str:
    template = root / ".codex" / "templates" / template_name
    if not template.is_file():
        raise ToolError(f"template not found: {template}", code=1)
    return template.read_text(encoding="utf-8")


def _fill_common_template(text: str, args: Namespace) -> str:
    if getattr(args, "lane", None):
        text = text.replace("Lane: Quick | Change | Mission-Critical | Explore | Review | Ops", f"Lane: {args.lane}")
    if getattr(args, "task_id", None):
        text = text.replace("<task-id>", args.task_id)
        text = text.replace("Task ID: <task-id>", f"Task ID: {args.task_id}")
        text = text.replace("任务 ID: <task-id>", f"任务 ID: {args.task_id}")
    return text


def _load_registry_and_task(runtime_dir: Path, task_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
    registry = require_registry(runtime_dir)
    task = find_task(registry, task_id)
    if task is None:
        raise ToolError(f"task not found: {task_id}", code=1)
    return registry, task


def _relative_path_exists(root: Path, value: str | None) -> bool:
    if not value:
        return False
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.exists()


def _task_needs_confirmation(task: dict[str, Any]) -> bool:
    return task.get("lane") == "Mission-Critical" or task.get("risk_level") in {"High", "Mission-Critical"}


def _thread_health_for_task(state_db: Path, project: str | None, task: dict[str, Any]) -> tuple[str, str]:
    owner_thread = task.get("owner_thread")
    if not owner_thread:
        return "WARN", "owner_thread is not set"
    try:
        snapshot = build_snapshot(state_db, project=project)
    except ToolError as exc:
        return "WARN", str(exc)
    for item in snapshot["threads"]:
        if item.thread.id == owner_thread:
            return "OK", f"{item.bucket}: {item.reason}"
    return "WARN", f"owner_thread not found in current project scope: {owner_thread}"


def _git_worktree_status(root: Path) -> str:
    proc = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        return f"WARN: git status unavailable ({proc.stderr.strip() or proc.returncode})"
    return "dirty" if proc.stdout.strip() else "clean"


def _task_loop_lock_status(root: Path) -> str:
    lock_dir = root / ".codex/runtime/task-loop/lock"
    if not lock_dir.exists():
        return "no live task-loop lock"
    activity = lock_dir / "activity.json"
    if activity.is_file():
        return f"lock present ({activity})"
    return f"lock present ({lock_dir})"


def _recommended_commands(task: dict[str, Any]) -> list[str]:
    lane = task.get("lane") or "Change"
    commands = ["./dev codex-os doctor"]
    validation = task.get("validation")
    if validation and _looks_like_command(str(validation)):
        commands.append(str(validation))
    elif lane == "Quick":
        commands.append("./dev check codex-os")
    elif lane == "Mission-Critical":
        commands.append("./dev check codex-os")
        commands.append("./dev check quality")
    else:
        commands.append("./dev check codex-os")
        commands.append("./dev check quality")
    return commands


def _looks_like_command(value: str) -> bool:
    text = value.strip()
    return text.startswith("./") and ";" not in text and "\n" not in text


def _preflight_check(name: str, status: str, detail: str = "") -> dict[str, str]:
    return {"name": name, "status": status, "detail": detail}


def _write_task_registry(runtime_dir: Path, registry: dict[str, Any]) -> Path:
    path = registry_path(runtime_dir)
    registry["updated_at"] = iso_now()
    write_json(path, registry)
    return path


def run_status(root: Path, args: Namespace) -> int:
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    print(render_thread_health(snapshot, limit=args.limit))
    return 0


def run_thread_health(root: Path, args: Namespace) -> int:
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    data = snapshot_to_json(snapshot, limit=args.limit)
    if args.write:
        path = _runtime_dir_from_args(root, args) / THREAD_HEALTH_NAME
        write_json(path, data)
        print(f"wrote {path}")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(render_thread_health(snapshot, limit=args.limit))
    return 0


def run_dashboard(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    registry = load_registry(runtime_dir)
    dashboard = render_dashboard(snapshot, registry)
    health_report = render_health_report(snapshot, registry)
    if args.write:
        _write_text(runtime_dir / DASHBOARD_NAME, dashboard)
        _write_text(runtime_dir / HEALTH_REPORT_NAME, health_report)
        write_json(runtime_dir / THREAD_HEALTH_NAME, snapshot_to_json(snapshot, limit=args.limit))
        print(f"wrote {runtime_dir / DASHBOARD_NAME}")
        print(f"wrote {runtime_dir / HEALTH_REPORT_NAME}")
        print(f"wrote {runtime_dir / THREAD_HEALTH_NAME}")
    else:
        print(dashboard)
        print()
        print(health_report)
    return 0


def run_registry(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    path = registry_path(runtime_dir)
    if args.registry_command == "init":
        return _run_registry_init(path, args)
    if args.registry_command == "status":
        registry = load_registry(runtime_dir)
        if registry is None:
            print(f"task registry: missing ({path})")
            return 1
        print(f"task registry: OK ({len(registry.get('tasks', []))} task(s))")
        return 0
    if args.registry_command == "list":
        registry = require_registry(runtime_dir)
        print(format_registry_tasks(registry.get("tasks", [])))
        return 0
    if args.registry_command == "add":
        return _run_registry_add(runtime_dir, path, args)
    if args.registry_command == "update":
        return _run_registry_update(runtime_dir, path, args)
    raise ToolError(f"unsupported registry command: {args.registry_command}", code=2)


def _run_registry_init(path: Path, args: Namespace) -> int:
    data = default_registry()
    if args.write:
        if path.exists() and not args.force:
            raise ToolError(f"registry already exists: {path}; use --force to overwrite", code=1)
        write_json(path, data)
        print(f"wrote {path}")
    else:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        print("Add --write to create the registry.")
    return 0


def _run_registry_add(runtime_dir: Path, path: Path, args: Namespace) -> int:
    registry = require_registry(runtime_dir)
    if find_task(registry, args.task_id):
        raise ToolError(f"task already exists: {args.task_id}", code=1)
    task = task_from_args(args)
    if args.write:
        registry["tasks"].append(task)
        registry["updated_at"] = iso_now()
        write_json(path, registry)
        print(f"added {args.task_id} to {path}")
    else:
        print(json.dumps(task, ensure_ascii=False, indent=2))
        print("Add --write to update the registry.")
    return 0


def _run_registry_update(runtime_dir: Path, path: Path, args: Namespace) -> int:
    registry = require_registry(runtime_dir)
    task = find_task(registry, args.task_id)
    if task is None:
        raise ToolError(f"task not found: {args.task_id}", code=1)
    updates = {
        "lane": args.lane,
        "status": args.status,
        "owner_thread": args.owner_thread,
        "handoff_file": args.handoff_file,
        "next_action": args.next_action,
        "validation": args.validation,
        "archive_recommendation": args.archive_recommendation,
        "risk_level": getattr(args, "risk_level", None),
        "confirmation_status": getattr(args, "confirmation_status", None),
        "evidence_file": getattr(args, "evidence_file", None),
        "closeout_file": getattr(args, "closeout_file", None),
        "evidence_note": getattr(args, "evidence_note", None),
        "closeout_note": getattr(args, "closeout_note", None),
        "validation_status": getattr(args, "validation_status", None),
        "automation_scope": getattr(args, "automation_scope", None),
    }
    updates = {key: value for key, value in updates.items() if value is not None}
    preview = dict(task)
    preview.update(updates)
    preview["updated_at"] = iso_now()
    if args.write:
        task.update(updates)
        task["updated_at"] = iso_now()
        registry["updated_at"] = iso_now()
        write_json(path, registry)
        print(f"updated {args.task_id} in {path}")
    else:
        print(json.dumps(preview, ensure_ascii=False, indent=2))
        print("Add --write to update the registry.")
    return 0


def run_preflight(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    task, checks, manual_confirmations = _build_preflight_checks(root, args, runtime_dir)

    has_fail = any(check["status"] == "FAIL" for check in checks)
    has_warn = any(check["status"] == "WARN" for check in checks)
    result = "FAIL" if has_fail else "WARN" if has_warn else "PASS"
    report = {
        "generated_at": iso_now(),
        "task_id": args.task_id,
        "strict": args.strict,
        "result": result,
        "checks": checks,
        "recommended_commands": _recommended_commands(task or {}) if task else ["./dev codex-os doctor"],
        "manual_confirmations": manual_confirmations,
    }
    if args.write_dashboard:
        _write_dashboard_files(root, args, runtime_dir)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(render_preflight_report(report))
    return 1 if args.strict and has_fail else 0


def _build_preflight_checks(
    root: Path,
    args: Namespace,
    runtime_dir: Path,
) -> tuple[dict[str, Any] | None, list[dict[str, str]], list[str]]:
    task: dict[str, Any] | None = None
    checks: list[dict[str, str]] = []
    manual_confirmations: list[str] = []
    registry = load_registry(runtime_dir)
    _append_registry_preflight_checks(args, registry, checks)
    task = _append_task_lookup_checks(root, args, registry, checks, manual_confirmations)
    git_status = _git_worktree_status(root)
    checks.append(_preflight_check("git worktree", "WARN" if git_status != "clean" else "OK", git_status))
    lock_status = _task_loop_lock_status(root)
    checks.append(_preflight_check("task-loop lock", "WARN" if lock_status.startswith("lock present") else "OK", lock_status))
    return task, checks, manual_confirmations


def _append_registry_preflight_checks(
    args: Namespace,
    registry: dict[str, Any] | None,
    checks: list[dict[str, str]],
) -> None:
    if registry is None:
        checks.append(_preflight_check("task registry", "FAIL" if args.strict else "WARN", "missing"))
    else:
        checks.append(_preflight_check("task registry", "OK", f"{len(registry.get('tasks', []))} task(s)"))


def _append_task_lookup_checks(
    root: Path,
    args: Namespace,
    registry: dict[str, Any] | None,
    checks: list[dict[str, str]],
    manual_confirmations: list[str],
) -> dict[str, Any] | None:
    if not args.task_id:
        return None
    if registry is None:
        checks.append(_preflight_check("task lookup", "FAIL", "registry is missing"))
        return None
    task = find_task(registry, args.task_id)
    if task is None:
        checks.append(_preflight_check("task lookup", "FAIL", f"task not found: {args.task_id}"))
        return None
    checks.append(_preflight_check("task lookup", "OK", task.get("status", "")))
    for warning in lifecycle_warnings(task):
        checks.append(_preflight_check("task lifecycle", "FAIL" if task.get("status") == "Done" else "WARN", warning))
    _append_task_preflight_checks(root, args, task, checks, manual_confirmations)
    return task


def _append_task_preflight_checks(
    root: Path,
    args: Namespace,
    task: dict[str, Any],
    checks: list[dict[str, str]],
    manual_confirmations: list[str],
) -> None:
    if task.get("handoff_file"):
        status = "OK" if _relative_path_exists(root, task.get("handoff_file")) else "WARN"
        checks.append(_preflight_check("handoff file", status, str(task.get("handoff_file"))))
    else:
        checks.append(_preflight_check("handoff file", "WARN", "not set"))
    checks.append(_preflight_check("validation", "OK" if task.get("validation") else "WARN", task.get("validation") or "not set"))
    state_status, state_detail = _thread_health_for_task(_state_db_from_args(args), args.project, task)
    checks.append(_preflight_check("owner thread", state_status, state_detail))
    if _task_needs_confirmation(task) and task.get("confirmation_status") != "Granted":
        checks.append(_preflight_check("manual confirmation", "WARN", "high-risk task requires explicit confirmation"))
        manual_confirmations.append("High or Mission-Critical task: confirm impact, risk, validation, and rollback before writes.")
    if task.get("archive_recommendation") == "archive":
        manual_confirmations.append("Archive recommendation is advisory only; thread archive still requires manual confirmation.")


def _write_dashboard_files(root: Path, args: Namespace, runtime_dir: Path) -> None:
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    registry = load_registry(runtime_dir)
    _write_text(runtime_dir / DASHBOARD_NAME, render_dashboard(snapshot, registry))
    _write_text(runtime_dir / HEALTH_REPORT_NAME, render_health_report(snapshot, registry))
    write_json(runtime_dir / THREAD_HEALTH_NAME, snapshot_to_json(snapshot, limit=getattr(args, "limit", 50)))


def run_task(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    if args.task_command == "list":
        registry = require_registry(runtime_dir)
        print(format_registry_tasks(registry.get("tasks", [])))
        return 0
    if args.task_command == "show":
        registry, task = _load_registry_and_task(runtime_dir, args.task_id)
        if args.json:
            print(json.dumps(task, ensure_ascii=False, indent=2))
        else:
            print(render_task_detail(task))
        return 0
    if args.task_command == "next":
        registry = require_registry(runtime_dir)
        task = _next_registry_task(registry.get("tasks", []), args.lane)
        if task is None:
            print("No next task.")
        elif args.json:
            print(json.dumps(task, ensure_ascii=False, indent=2))
        else:
            print(render_task_detail(task))
        return 0
    if args.task_command in {"start", "verify", "block"}:
        return _run_task_transition(root, runtime_dir, args)
    raise ToolError(f"unsupported codex-os task command: {args.task_command}", code=2)


def _next_registry_task(tasks: list[dict[str, Any]], lane: str | None) -> dict[str, Any] | None:
    terminal = {"Done", "Archived", "Abandoned"}
    for task in tasks:
        if lane and task.get("lane") != lane:
            continue
        if task.get("status") not in terminal:
            return task
    return None


def _run_task_transition(root: Path, runtime_dir: Path, args: Namespace) -> int:
    registry, task = _load_registry_and_task(runtime_dir, args.task_id)
    if args.task_command == "start":
        updates = {"status": "Running", "next_action": args.next_action, "automation_scope": args.automation_scope}
    elif args.task_command == "verify":
        updates = {"status": "Verifying", "validation": args.validation, "validation_status": "Running"}
    else:
        if not args.next_action:
            raise ToolError("blocking a task requires --next-action", code=1)
        updates = {"status": "Blocked", "next_action": args.next_action, "validation_status": args.validation_status or "Blocked"}
    preview = dict(task)
    preview.update({key: value for key, value in updates.items() if value is not None})
    preview["updated_at"] = iso_now()
    if args.write:
        apply_task_updates(task, updates)
        path = _write_task_registry(runtime_dir, registry)
        print(f"updated {args.task_id} in {path}")
    else:
        print(render_task_detail(preview))
        print("Add --write to update the registry.")
    return 0


def run_finish(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    registry, task = _load_registry_and_task(runtime_dir, args.task_id)
    _validate_finish_args(root, task, args)
    updates = _finish_updates(task, args)
    preview = dict(task)
    preview.update(updates)
    preview["updated_at"] = iso_now()
    summary = {
        "generated_at": iso_now(),
        "task_id": args.task_id,
        "status": args.status,
        "write": args.write,
        "result": "UPDATED" if args.write else "PREVIEW",
        "archive_recommendation": updates.get("archive_recommendation"),
        "warnings": _finish_warnings(args),
        "task": preview,
    }
    if args.write:
        apply_task_updates(task, updates)
        path = _write_task_registry(runtime_dir, registry)
        summary["updated_path"] = str(path)
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(render_finish_summary(summary))
    return 0


def _validate_finish_args(root: Path, task: dict[str, Any], args: Namespace) -> None:
    validation = args.validation or task.get("validation")
    evidence = args.evidence_file or args.closeout_file or args.evidence_note or args.closeout_note
    evidence = evidence or task.get("evidence_file") or task.get("closeout_file") or task.get("evidence_note") or task.get("closeout_note")
    if args.status == "Done" and not validation:
        raise ToolError("finish --status Done requires --validation or an existing validation summary", code=1)
    if args.status == "Done" and not evidence:
        raise ToolError("finish --status Done requires evidence or closeout reference", code=1)
    if args.status == "Blocked" and not (args.next_action or task.get("next_action") or args.handoff_file or task.get("handoff_file")):
        raise ToolError("finish --status Blocked requires --next-action or a handoff file", code=1)
    for key in ("evidence_file", "closeout_file", "handoff_file"):
        value = getattr(args, key, None)
        if value and not _relative_path_exists(root, value):
            raise ToolError(f"{key.replace('_', '-')} does not exist: {value}", code=1)


def _finish_updates(task: dict[str, Any], args: Namespace) -> dict[str, Any]:
    validation_status = args.validation_status
    if validation_status is None:
        validation_status = "Pass" if args.status == "Done" else "Blocked" if args.status == "Blocked" else task.get("validation_status")
    return {
        "status": args.status,
        "validation": args.validation,
        "validation_status": validation_status,
        "handoff_file": args.handoff_file,
        "evidence_file": args.evidence_file,
        "closeout_file": args.closeout_file,
        "evidence_note": args.evidence_note,
        "closeout_note": args.closeout_note,
        "next_action": args.next_action,
        "archive_recommendation": args.archive_recommendation,
        "finished_at": iso_now(),
    }


def _finish_warnings(args: Namespace) -> list[str]:
    warnings: list[str] = []
    if args.archive_recommendation == "archive":
        warnings.append("Archive recommendation does not archive a Codex thread; manual confirmation is still required.")
    if args.status == "Done" and args.validation_status in {"Skipped", "Blocked", "Not-Ready", "Fail"}:
        warnings.append("Done status paired with non-pass validation status; review before relying on this registry entry.")
    return warnings


def run_template(root: Path, args: Namespace, key: str) -> int:
    text = _template_text(root, TEMPLATE_FILES[key])
    sys.stdout.write(_fill_common_template(text, args))
    return 0


def run_archive_candidates(root: Path, args: Namespace) -> int:
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    candidates = [item for item in snapshot["threads"] if item.bucket == "Archive Candidate"]
    if args.json:
        print(json.dumps([thread_to_json(item) for item in candidates[: args.limit]], ensure_ascii=False, indent=2))
        return 0
    print("Archive candidates")
    print()
    print(f"- total: {len(candidates)}")
    print("- destructive operations: none")
    print()
    for item in candidates[: args.limit]:
        print(f"- {item.thread.updated_iso} | {item.age_days}d | {item.reason} | {item.thread.display_title}")
    return 0


def run_doctor(root: Path, args: Namespace) -> int:
    required = [
        root / ".codex" / "references" / "codex-operating-system.md",
        root / ".codex" / "templates" / "codex-intake-template.md",
        root / ".codex" / "templates" / "codex-handoff-template.md",
        root / ".codex" / "templates" / "codex-evidence-template.md",
        root / ".codex" / "templates" / "codex-closeout-template.md",
        root / ".codex" / "templates" / "task-registry.example.json",
    ]
    missing = [path for path in required if not path.is_file()]
    if missing:
        for path in missing:
            print(f"missing: {path}")
        return 1
    runtime_dir = _runtime_dir_from_args(root, args)
    registry = load_registry(runtime_dir)
    state_db = _state_db_from_args(args)
    if state_db.is_file():
        snapshot = build_snapshot(state_db, project=args.project)
        print(f"codex-os doctor: state OK ({snapshot['total_threads']} thread(s) in scope)")
    else:
        print(f"codex-os doctor: state WARN (missing {state_db})")
    print(f"codex-os doctor: registry {'OK' if registry is not None else 'WARN (missing)'}")
    print("codex-os doctor: docs/templates OK")
    return 0


def run_codex_os_command(root: Path, args: Namespace) -> int:
    if args.codex_os_command == "status":
        return run_status(root, args)
    if args.codex_os_command == "thread-health":
        return run_thread_health(root, args)
    if args.codex_os_command == "dashboard":
        return run_dashboard(root, args)
    if args.codex_os_command == "registry":
        return run_registry(root, args)
    if args.codex_os_command in TEMPLATE_FILES:
        return run_template(root, args, args.codex_os_command)
    if args.codex_os_command == "archive-candidates":
        return run_archive_candidates(root, args)
    if args.codex_os_command == "doctor":
        return run_doctor(root, args)
    if args.codex_os_command == "preflight":
        return run_preflight(root, args)
    if args.codex_os_command == "task":
        return run_task(root, args)
    if args.codex_os_command == "finish":
        return run_finish(root, args)
    raise ToolError(f"unsupported codex-os command: {args.codex_os_command}", code=2)


__all__ = ["ThreadRecord", "classify_thread", "run_codex_os_command"]
