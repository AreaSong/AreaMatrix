"""Guarded lightweight task creation for ./dev tasks create."""

from __future__ import annotations

from argparse import Namespace
from dataclasses import dataclass
from datetime import date
from pathlib import Path
import re

from .common import ToolError
from .tasks import (
    ACTIVE_ROOT,
    TASK_DIR_PATTERN,
    _candidate_task_dirs,
    _display_path,
    validate_lightweight_tasks,
)


SLUG_CHAR_PATTERN = re.compile(r"[^a-z0-9]+")
DEFAULT_FORBID_PATHS = [
    "workflow/versions/*/execution/",
    "workflow/versions/*/evidence/task-loop-runs/",
    ".codex/runtime/task-loop/",
    ".codex/task-loop-logs/",
    ".codex/task-loop-runs/",
    ".codex/task-loop-lock/",
]
DEFAULT_VALIDATION = ["./dev check"]


@dataclass(frozen=True)
class CreatePreview:
    task_id: int
    slug: str
    title: str
    task_dir: Path
    files: dict[str, str]


def _slug_from_title(title: str) -> str:
    slug = SLUG_CHAR_PATTERN.sub("-", title.strip().lower()).strip("-")
    slug = re.sub(r"-+", "-", slug)
    if not slug or not TASK_DIR_PATTERN.match(f"1.{slug}"):
        raise ToolError(
            "could not derive a valid slug from --title; pass --slug using lowercase letters, numbers, and hyphens.",
            code=2,
        )
    return slug


def _next_task_id(root: Path) -> int:
    ids: set[int] = set()
    for task_dir in _candidate_task_dirs(root):
        match = TASK_DIR_PATTERN.match(task_dir.name)
        if match:
            ids.add(int(match.group("id")))
    return max(ids, default=0) + 1


def _yaml_scalar(value: str) -> str:
    if value and re.match(r"^[A-Za-z0-9][A-Za-z0-9 _./:-]*$", value):
        return value
    return repr(value)


def _format_yaml_list(values: list[str]) -> str:
    return "\n".join(f"    - {_yaml_scalar(value)}" for value in values)


def _normalize_area_touch(area: str) -> str:
    return area if area.endswith("/") else f"{area}/"


def _task_yaml(args: Namespace, preview: CreatePreview, created: str, validation: list[str]) -> str:
    touch_paths = list(args.touch or [_normalize_area_touch(args.area)])
    forbid_paths = list(dict.fromkeys([*DEFAULT_FORBID_PATHS, *(args.forbid or [])]))
    return "\n".join(
        [
            f"id: {preview.task_id}",
            f"slug: {preview.slug}",
            f"title: {_yaml_scalar(preview.title)}",
            "status: todo",
            f"priority: {args.priority}",
            f"kind: {args.kind}",
            f"risk: {args.risk}",
            "",
            "scope:",
            f"  layer: {args.layer}",
            f"  area: {_yaml_scalar(args.area)}",
            f"  feature: {_yaml_scalar(args.feature)}",
            "",
            "paths:",
            "  touch:",
            _format_yaml_list(touch_paths),
            "  forbid:",
            _format_yaml_list(forbid_paths),
            "",
            "validation:",
            *[f"  - {_yaml_scalar(command)}" for command in validation],
            "",
            f"created: {created}",
            f"updated: {created}",
            "owner: tasks",
            "",
        ]
    )


def _task_md(args: Namespace, title: str, task_path: str, validation: list[str]) -> str:
    validation_lines = "\n".join(f"{index}. `{command}`" for index, command in enumerate(validation, start=1))
    return f"""# {title}

## Goal

Complete this lightweight task: {title}.

## Non-goals

- Do not promote this task into `workflow/versions/<version>/execution/**`.
- Do not create task-loop progress, logs, run summaries, locks, or checkpoints.
- Do not expand this task into version workflow planning unless the scope changes.

## Context

- Layer: `{args.layer}`
- Area: `{args.area}`
- Feature: `{args.feature}`

## Steps

1. Read `{task_path}/task.yaml`.
2. Make the smallest scoped change inside the allowed paths.
3. Run the validation commands from `task.yaml`.
4. Record the result and remaining risk in `{task_path}/evidence.md`.

## Validation

{validation_lines}
"""


def _verify_md(title: str, task_path: str) -> str:
    return f"""# Verify {title}

## Read

- `{task_path}/task.yaml`
- `{task_path}/task.md`
- `{task_path}/evidence.md`

## Check

- The implementation matches the task goal and non-goals.
- Changed paths stay inside `paths.touch`.
- No path under `paths.forbid` changed.
- Validation evidence is fresh and task-scoped.
- The task did not write workflow execution queue or task-loop runtime state.

## Pass

PASS only when the task goal is complete, validation evidence is present, and no
forbidden path or scope drift is found.

## Fail

FAIL when behavior is incomplete, validation is missing, forbidden paths changed,
or the task expanded into workflow-level work.
"""


def _evidence_md(title: str) -> str:
    return f"""# Evidence {title}

## Result

todo

## Changes

- Pending.

## Validation

- Pending.

## Notes

- Created by `./dev tasks create`.
"""


def _ensure_healthy(root: Path) -> None:
    if validate_lightweight_tasks(root):
        raise ToolError(
            "lightweight task structure is not healthy; run ./dev tasks doctor before creating a new task.",
            code=1,
        )


def _create_preview(root: Path, args: Namespace) -> CreatePreview:
    _ensure_healthy(root)
    title = args.title.strip()
    if not title:
        raise ToolError("./dev tasks create requires a non-empty --title.", code=2)

    slug = args.slug or _slug_from_title(title)
    if not TASK_DIR_PATTERN.match(f"1.{slug}"):
        raise ToolError("--slug must use lowercase letters, numbers, and hyphens.", code=2)

    task_id = _next_task_id(root)
    task_dir = root / ACTIVE_ROOT / f"{task_id}.{slug}"
    if task_dir.exists():
        raise ToolError(f"lightweight task path already exists: {_display_path(task_dir, root)}", code=1)

    created = args.date or date.today().isoformat()
    validation = list(args.validation or DEFAULT_VALIDATION)
    task_path = _display_path(task_dir, root)
    preview = CreatePreview(task_id=task_id, slug=slug, title=title, task_dir=task_dir, files={})
    return CreatePreview(
        task_id=task_id,
        slug=slug,
        title=title,
        task_dir=task_dir,
        files={
            "task.yaml": _task_yaml(args, preview, created, validation),
            "task.md": _task_md(args, title, task_path, validation),
            "verify.md": _verify_md(title, task_path),
            "evidence.md": _evidence_md(title),
        },
    )


def run_tasks_create(root: Path, args: Namespace) -> int:
    preview = _create_preview(root, args)
    display_dir = _display_path(preview.task_dir, root)
    if not args.write:
        print("Lightweight task create preview")
        print(f"- task: {display_dir}/")
        print(f"- id: {preview.task_id}")
        print(f"- slug: {preview.slug}")
        print(f"- title: {preview.title}")
        print("- status: todo")
        print()
        print("Files")
        for file_name in preview.files:
            print(f"- {display_dir}/{file_name}")
        print()
        print("Add --write to create this task under tasks/active.")
        return 0

    preview.task_dir.mkdir(parents=True, exist_ok=False)
    for file_name, content in preview.files.items():
        (preview.task_dir / file_name).write_text(content, encoding="utf-8")
    print(f"created lightweight task: {display_dir}/")
    return 0
