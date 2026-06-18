"""Guarded lightweight task archival for ./dev tasks complete."""

from __future__ import annotations

from argparse import Namespace
from dataclasses import dataclass
from datetime import date
from pathlib import Path
import shutil

from .common import ToolError
from .tasks import (
    ACTIVE_ROOT,
    DONE_ROOT,
    LightweightTask,
    _display_path,
    discover_lightweight_tasks,
    validate_lightweight_tasks,
)


@dataclass(frozen=True)
class CompletePreview:
    task: LightweightTask
    target_dir: Path
    completed: str


def _active_task_by_id(root: Path, task_id: int) -> LightweightTask:
    tasks = discover_lightweight_tasks(root, include_done=False)
    for task in tasks:
        if task.id == task_id:
            return task
    available = ", ".join(str(task.id) for task in tasks) or "none"
    raise ToolError(f"unknown active lightweight task id: {task_id}; available active task ids: {available}", code=1)


def _replace_yaml_value(text: str, key: str, value: str) -> str:
    lines = text.splitlines()
    replaced = False
    for index, line in enumerate(lines):
        if line.startswith(f"{key}:"):
            lines[index] = f"{key}: {value}"
            replaced = True
            break
    if not replaced:
        lines.append(f"{key}: {value}")
    return "\n".join(lines).rstrip() + "\n"


def _ensure_healthy(root: Path) -> None:
    errors = validate_lightweight_tasks(root)
    if errors:
        raise ToolError(
            "lightweight task structure is not healthy; run ./dev tasks doctor before completing a task.",
            code=1,
        )


def _complete_preview(root: Path, args: Namespace) -> CompletePreview:
    if args.task_id < 1:
        raise ToolError("./dev tasks complete requires a positive numeric task id.", code=2)
    _ensure_healthy(root)
    task = _active_task_by_id(root, args.task_id)
    completed = args.date or date.today().isoformat()
    target_dir = root / DONE_ROOT / completed[:4] / task.path.name
    if target_dir.exists():
        raise ToolError(f"completed lightweight task path already exists: {_display_path(target_dir, root)}", code=1)
    return CompletePreview(task=task, target_dir=target_dir, completed=completed)


def _write_completed_yaml(task: LightweightTask, completed: str) -> None:
    text = task.yaml_path.read_text(encoding="utf-8")
    text = _replace_yaml_value(text, "status", "done")
    text = _replace_yaml_value(text, "updated", completed)
    task.yaml_path.write_text(text, encoding="utf-8")


def run_tasks_complete(root: Path, args: Namespace) -> int:
    preview = _complete_preview(root, args)
    source = _display_path(preview.task.path, root)
    target = _display_path(preview.target_dir, root)
    if not args.write:
        print("Lightweight task complete preview")
        print(f"- task: {preview.task.id}.{preview.task.slug}")
        print(f"- from: {source}/")
        print(f"- to: {target}/")
        print("- status: done")
        print()
        print("Add --write --confirm-pass to archive this active task.")
        return 0

    if not args.confirm_pass:
        raise ToolError("./dev tasks complete --write requires --confirm-pass.", code=2)

    _write_completed_yaml(preview.task, preview.completed)
    preview.target_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(preview.task.path), str(preview.target_dir))
    print(f"archived lightweight task: {target}/")
    return 0
