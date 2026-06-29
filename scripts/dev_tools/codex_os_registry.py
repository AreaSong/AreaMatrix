"""Repo-local task registry helpers for Codex Operating System."""

from __future__ import annotations

from argparse import Namespace
import json
from pathlib import Path
from typing import Any

from .codex_os_state import LANES, REGISTRY_NAME, TASK_STATUSES, iso_now
from .common import ToolError

RISK_LEVELS = {"Low", "Medium", "High", "Mission-Critical"}
CONFIRMATION_STATUSES = {"Not Required", "Required", "Granted", "Blocked"}
VALIDATION_STATUSES = {"Not Started", "Recommended", "Running", "Pass", "Fail", "Blocked", "Not-Ready", "Skipped"}
AUTOMATION_SCOPES = {"observe-only", "registry-write", "validation-run", "manual-confirmation-required"}
ARCHIVE_RECOMMENDATIONS = {"keep", "archive", "review"}


def default_registry() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "generated_by": "./dev codex-os registry init",
        "updated_at": iso_now(),
        "tasks": [],
    }


def registry_path(runtime_dir: Path) -> Path:
    return runtime_dir / REGISTRY_NAME


def load_registry(runtime_dir: Path) -> dict[str, Any] | None:
    path = registry_path(runtime_dir)
    if not path.is_file():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    validate_registry(data, path)
    return data


def validate_registry(data: dict[str, Any], path: Path) -> None:
    if data.get("schema_version") != 1:
        raise ToolError(f"{path}: schema_version must be 1", code=1)
    tasks = data.get("tasks")
    if not isinstance(tasks, list):
        raise ToolError(f"{path}: tasks must be a list", code=1)
    for index, task in enumerate(tasks, start=1):
        if not isinstance(task, dict):
            raise ToolError(f"{path}: task #{index} must be an object", code=1)
        lane = task.get("lane")
        status = task.get("status")
        if lane and lane not in LANES:
            raise ToolError(f"{path}: task #{index} has invalid lane {lane!r}", code=1)
        if status and status not in TASK_STATUSES:
            raise ToolError(f"{path}: task #{index} has invalid status {status!r}", code=1)
        _validate_optional_enum(path, task, index, "risk_level", RISK_LEVELS)
        _validate_optional_enum(path, task, index, "confirmation_status", CONFIRMATION_STATUSES)
        _validate_optional_enum(path, task, index, "validation_status", VALIDATION_STATUSES)
        _validate_optional_enum(path, task, index, "automation_scope", AUTOMATION_SCOPES)
        _validate_optional_enum(path, task, index, "archive_recommendation", ARCHIVE_RECOMMENDATIONS)
        task_id = task.get("task_id")
        if not isinstance(task_id, str) or not task_id.strip():
            raise ToolError(f"{path}: task #{index} missing task_id", code=1)


def _validate_optional_enum(path: Path, task: dict[str, Any], index: int, key: str, allowed: set[str]) -> None:
    value = task.get(key)
    if value is not None and value != "" and value not in allowed:
        choices = ", ".join(sorted(allowed))
        raise ToolError(f"{path}: task #{index} has invalid {key} {value!r}; expected one of {choices}", code=1)


def require_registry(runtime_dir: Path) -> dict[str, Any]:
    registry = load_registry(runtime_dir)
    if registry is None:
        raise ToolError(f"task registry is missing: {registry_path(runtime_dir)}", code=1)
    return registry


def find_task(registry: dict[str, Any], task_id: str) -> dict[str, Any] | None:
    for task in registry.get("tasks", []):
        if isinstance(task, dict) and task.get("task_id") == task_id:
            return task
    return None


def task_from_args(args: Namespace) -> dict[str, Any]:
    lane = args.lane
    status = args.status
    if lane not in LANES:
        allowed = ", ".join(sorted(LANES))
        raise ToolError(f"lane must be one of {allowed}", code=1)
    if status not in TASK_STATUSES:
        allowed = ", ".join(sorted(TASK_STATUSES))
        raise ToolError(f"status must be one of {allowed}", code=1)
    task = {
        "task_id": args.task_id,
        "project": args.project_name or "AreaMatrix",
        "lane": lane,
        "status": status,
        "owner_thread": args.owner_thread or "",
        "handoff_file": args.handoff_file or "",
        "next_action": args.next_action or "",
        "validation": args.validation or "",
        "archive_recommendation": args.archive_recommendation or "keep",
        "updated_at": iso_now(),
    }
    for key in (
        "risk_level",
        "confirmation_status",
        "evidence_file",
        "closeout_file",
        "evidence_note",
        "closeout_note",
        "validation_status",
        "automation_scope",
    ):
        value = getattr(args, key, None)
        if value:
            task[key] = value
    return task


def task_status_counts(tasks: list[dict[str, Any]]) -> dict[str, int]:
    counts = {status: 0 for status in sorted(TASK_STATUSES)}
    for task in tasks:
        status = str(task.get("status", ""))
        if status:
            counts[status] = counts.get(status, 0) + 1
    return counts


def lifecycle_warnings(task: dict[str, Any]) -> list[str]:
    warnings: list[str] = []
    status = task.get("status")
    if status == "Done" and not task.get("validation"):
        warnings.append("Done task has no validation summary.")
    if status == "Done" and not (task.get("evidence_file") or task.get("closeout_file") or task.get("evidence_note") or task.get("closeout_note")):
        warnings.append("Done task has no evidence or closeout reference.")
    if status == "Blocked" and not (task.get("next_action") or task.get("handoff_file")):
        warnings.append("Blocked task has no next_action or handoff_file.")
    return warnings


def apply_task_updates(task: dict[str, Any], updates: dict[str, Any]) -> None:
    for key, value in updates.items():
        if value is not None:
            task[key] = value
    task["updated_at"] = iso_now()


def format_registry_tasks(tasks: list[dict[str, Any]]) -> str:
    lines = ["Task registry", ""]
    if not tasks:
        lines.append("(no registered tasks)")
        return "\n".join(lines) + "\n"
    lines.append("| Task | Project | Lane | Status | Next Action |")
    lines.append("|---|---|---|---|---|")
    for task in tasks:
        lines.append(
            f"| `{task.get('task_id', '')}` | {task.get('project', '')} | "
            f"{task.get('lane', '')} | {task.get('status', '')} | {task.get('next_action', '')} |"
        )
    return "\n".join(lines) + "\n"


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
