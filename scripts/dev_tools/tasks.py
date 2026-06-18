"""Lightweight task browser and structure validation."""

from __future__ import annotations

from argparse import Namespace
from dataclasses import dataclass
from pathlib import Path
import re
import sys
from typing import Any

from .backlog import discover_packages
from .changes import ChangeYAMLError, parse_yaml_subset
from .common import ToolError


TASKS_ROOT = Path("tasks")
ACTIVE_ROOT = TASKS_ROOT / "active"
DONE_ROOT = TASKS_ROOT / "done"
TASK_DIR_PATTERN = re.compile(r"^(?P<id>[1-9][0-9]*)\.(?P<slug>[a-z0-9][a-z0-9-]*)$")
DONE_YEAR_PATTERN = re.compile(r"^[0-9]{4}$")
TASK_STATUSES = {"todo", "in_progress", "blocked", "verify_ready", "done", "archived"}
ACTIVE_STATUSES = {"todo", "in_progress", "blocked", "verify_ready"}
DONE_STATUSES = {"done", "archived"}
TASK_PRIORITIES = {"p0", "p1", "p2", "p3"}
TASK_KINDS = {"feature", "bugfix", "refactor", "docs", "test", "tooling", "governance", "chore"}
TASK_RISKS = {"low", "medium", "high", "mission-critical"}
TASK_LAYERS = {"frontend", "backend", "core", "app", "scripts", "docs", "workflow", "governance", "assets"}
TASK_FILES = {"task": "task.md", "verify": "verify.md", "evidence": "evidence.md"}


@dataclass(frozen=True)
class LightweightTask:
    id: int
    slug: str
    title: str
    status: str
    priority: str
    kind: str
    risk: str
    layer: str
    area: str
    feature: str
    location: str
    path: Path
    yaml_path: Path
    updated: str


def _display_path(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def _string(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


def _mapping(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _task_location(task_dir: Path, root: Path) -> str:
    try:
        relative = task_dir.relative_to(root / DONE_ROOT)
        if relative.parts:
            return f"done/{relative.parts[0]}"
    except ValueError:
        pass
    return "active"


def _parse_task_dir(task_dir: Path, root: Path) -> LightweightTask | None:
    match = TASK_DIR_PATTERN.match(task_dir.name)
    if not match:
        return None
    yaml_path = task_dir / "task.yaml"
    if not yaml_path.is_file():
        return None
    try:
        data = parse_yaml_subset(yaml_path.read_text(encoding="utf-8"), yaml_path)
    except ChangeYAMLError as exc:
        raise ToolError(f"invalid lightweight task yaml: {exc}", code=1) from exc
    if not isinstance(data, dict):
        raise ToolError(f"{_display_path(yaml_path, root)}: task.yaml must be a mapping", code=1)

    task_id = int(match.group("id"))
    slug = match.group("slug")
    declared_id = data.get("id")
    if str(declared_id) != str(task_id):
        raise ToolError(f"{_display_path(yaml_path, root)}: id must match directory number {task_id}", code=1)
    declared_slug = data.get("slug")
    if declared_slug != slug:
        raise ToolError(f"{_display_path(yaml_path, root)}: slug must match directory slug {slug}", code=1)
    status = _string(data.get("status"), "todo")
    if status not in TASK_STATUSES:
        allowed = ", ".join(sorted(TASK_STATUSES))
        raise ToolError(f"{_display_path(yaml_path, root)}: status must be one of {allowed}", code=1)

    scope = _mapping(data.get("scope"))
    return LightweightTask(
        id=task_id,
        slug=slug,
        title=_string(data.get("title"), slug),
        status=status,
        priority=_string(data.get("priority"), ""),
        kind=_string(data.get("kind"), ""),
        risk=_string(data.get("risk"), ""),
        layer=_string(scope.get("layer"), ""),
        area=_string(scope.get("area"), ""),
        feature=_string(scope.get("feature"), ""),
        location=_task_location(task_dir, root),
        path=task_dir,
        yaml_path=yaml_path,
        updated=_string(data.get("updated"), ""),
    )


def _active_task_dirs(root: Path) -> list[Path]:
    active_root = root / ACTIVE_ROOT
    if not active_root.is_dir():
        return []
    return sorted(path for path in active_root.iterdir() if path.is_dir())


def _done_task_dirs(root: Path) -> list[Path]:
    done_root = root / DONE_ROOT
    if not done_root.is_dir():
        return []
    task_dirs: list[Path] = []
    for year_dir in sorted(path for path in done_root.iterdir() if path.is_dir()):
        task_dirs.extend(sorted(path for path in year_dir.iterdir() if path.is_dir()))
    return task_dirs


def _candidate_task_dirs(root: Path) -> list[Path]:
    return [*_active_task_dirs(root), *_done_task_dirs(root)]


def discover_lightweight_tasks(root: Path, *, include_done: bool = True) -> list[LightweightTask]:
    """Return lightweight tasks sorted by numeric id and location."""

    dirs = _active_task_dirs(root)
    if include_done:
        dirs.extend(_done_task_dirs(root))
    tasks: list[LightweightTask] = []
    seen: dict[int, Path] = {}
    for task_dir in dirs:
        task = _parse_task_dir(task_dir, root)
        if task is None:
            continue
        if task.id in seen:
            first_path = _display_path(seen[task.id], root)
            second_path = _display_path(task.path, root)
            raise ToolError(
                f"duplicate lightweight task id {task.id}: {first_path} and {second_path}",
                code=1,
            )
        seen[task.id] = task.path
        tasks.append(task)
    return sorted(tasks, key=lambda task: (task.id, task.location, task.slug))


def validate_lightweight_tasks(root: Path) -> list[str]:
    """Return structural errors for lightweight task directories."""

    errors: list[str] = []
    active_root = root / ACTIVE_ROOT
    done_root = root / DONE_ROOT

    for task_dir in _active_task_dirs(root):
        if not TASK_DIR_PATTERN.match(task_dir.name):
            errors.append(f"{_display_path(task_dir, root)}: task directory must use <number>.<slug>")
        if not (task_dir / "task.yaml").is_file():
            errors.append(f"{_display_path(task_dir, root)}: missing task.yaml")

    if done_root.is_dir():
        for year_dir in sorted(path for path in done_root.iterdir() if path.is_dir()):
            if not DONE_YEAR_PATTERN.match(year_dir.name):
                errors.append(f"{_display_path(year_dir, root)}: done archive directory must be YYYY")
            for task_dir in sorted(path for path in year_dir.iterdir() if path.is_dir()):
                if not TASK_DIR_PATTERN.match(task_dir.name):
                    errors.append(f"{_display_path(task_dir, root)}: task directory must use <number>.<slug>")
                if not (task_dir / "task.yaml").is_file():
                    errors.append(f"{_display_path(task_dir, root)}: missing task.yaml")

    for task_dir in _candidate_task_dirs(root):
        if not TASK_DIR_PATTERN.match(task_dir.name) or not (task_dir / "task.yaml").is_file():
            continue
        try:
            task = _parse_task_dir(task_dir, root)
        except ToolError as exc:
            errors.append(str(exc))
            continue
        if task is None:
            continue
        missing = [file_name for file_name in TASK_FILES.values() if not (task_dir / file_name).is_file()]
        for file_name in missing:
            errors.append(f"{_display_path(task_dir / file_name, root)}: missing required task file")
        if task.location == "active" and task.status not in ACTIVE_STATUSES:
            allowed = ", ".join(sorted(ACTIVE_STATUSES))
            errors.append(f"{_display_path(task.yaml_path, root)}: active task status must be one of {allowed}")
        if task.location.startswith("done/") and task.status not in DONE_STATUSES:
            allowed = ", ".join(sorted(DONE_STATUSES))
            errors.append(f"{_display_path(task.yaml_path, root)}: done task status must be one of {allowed}")
        for field_name, value in [
            ("title", task.title),
            ("priority", task.priority),
            ("kind", task.kind),
            ("risk", task.risk),
            ("scope.layer", task.layer),
            ("scope.area", task.area),
            ("scope.feature", task.feature),
            ("updated", task.updated),
        ]:
            if not value:
                errors.append(f"{_display_path(task.yaml_path, root)}: missing {field_name}")
        if task.priority and task.priority not in TASK_PRIORITIES:
            allowed = ", ".join(sorted(TASK_PRIORITIES))
            errors.append(f"{_display_path(task.yaml_path, root)}: priority must be one of {allowed}")
        if task.kind and task.kind not in TASK_KINDS:
            allowed = ", ".join(sorted(TASK_KINDS))
            errors.append(f"{_display_path(task.yaml_path, root)}: kind must be one of {allowed}")
        if task.risk and task.risk not in TASK_RISKS:
            allowed = ", ".join(sorted(TASK_RISKS))
            errors.append(f"{_display_path(task.yaml_path, root)}: risk must be one of {allowed}")
        if task.layer and task.layer not in TASK_LAYERS:
            allowed = ", ".join(sorted(TASK_LAYERS))
            errors.append(f"{_display_path(task.yaml_path, root)}: scope.layer must be one of {allowed}")

    try:
        discover_lightweight_tasks(root)
    except ToolError as exc:
        errors.append(str(exc))
    return errors


def _format_task_rows(tasks: list[LightweightTask]) -> list[str]:
    rows: list[str] = []
    for task in tasks:
        cells = [
            str(task.id),
            task.path.name,
            task.location,
            task.status,
            task.priority,
            task.kind,
            task.layer,
            task.area,
            task.feature,
        ]
        rows.append(" | ".join(cells))
    return rows


def _format_task_table(title: str, tasks: list[LightweightTask]) -> str:
    rows = [
        title,
        "id | task | location | status | priority | kind | layer | area | feature",
        "---: | --- | --- | --- | --- | --- | --- | --- | ---",
    ]
    rows.extend(_format_task_rows(tasks))
    return "\n".join(rows)


def _summary_counts(root: Path, tasks: list[LightweightTask]) -> dict[str, int]:
    active = [task for task in tasks if task.location == "active"]
    done = [task for task in tasks if task.location.startswith("done/")]
    return {
        "active": len(active),
        "done": len(done),
        "blocked": sum(1 for task in active if task.status == "blocked"),
        "verify_ready": sum(1 for task in active if task.status == "verify_ready"),
        "backlog_packages": len(discover_packages(root)),
    }


def run_tasks_status(root: Path) -> int:
    tasks = discover_lightweight_tasks(root)
    counts = _summary_counts(root, tasks)
    print("Lightweight tasks")
    print()
    print("Summary")
    print(f"- active: {counts['active']}")
    print(f"- done: {counts['done']}")
    print(f"- blocked: {counts['blocked']}")
    print(f"- verify_ready: {counts['verify_ready']}")
    print(f"- backlog packages: {counts['backlog_packages']}")
    if not tasks:
        print()
        print("No lightweight tasks found under tasks/active or tasks/done.")
        print("Backlog packages remain available through ./dev backlog list.")
        return 0
    active = [task for task in tasks if task.location == "active"]
    done = [task for task in tasks if task.location.startswith("done/")]
    if active:
        print()
        print(_format_task_table("Active", active))
    if done:
        print()
        print(_format_task_table("Done", done))
    print()
    print("Backlog")
    print(f"- packages: {counts['backlog_packages']}")
    print("- hint: ./dev backlog list")
    return 0


def run_tasks_list(root: Path) -> int:
    tasks = discover_lightweight_tasks(root)
    if not tasks:
        print("No lightweight tasks found under tasks/active or tasks/done.")
        return 0
    print(_format_task_table("Lightweight tasks (active and done)", tasks))
    return 0


def run_tasks_doctor(root: Path) -> int:
    errors = validate_lightweight_tasks(root)
    if errors:
        print("lightweight tasks doctor: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    tasks = discover_lightweight_tasks(root)
    counts = _summary_counts(root, tasks)
    print("lightweight tasks doctor: OK")
    print(f"- active: {counts['active']}")
    print(f"- done: {counts['done']}")
    print(f"- backlog packages: {counts['backlog_packages']}")
    return 0


def _find_task(root: Path, task_id: int) -> LightweightTask:
    tasks = discover_lightweight_tasks(root)
    for task in tasks:
        if task.id == task_id:
            return task
    available = ", ".join(str(task.id) for task in tasks) or "none"
    raise ToolError(f"unknown lightweight task id: {task_id}; available task ids: {available}", code=1)


def _task_file_path(task: LightweightTask, section: str) -> Path:
    return task.path / TASK_FILES[section]


def _write_file(path: Path) -> int:
    if not path.is_file():
        raise ToolError(f"lightweight task file not found: {path}", code=1)
    sys.stdout.write(path.read_text(encoding="utf-8"))
    return 0


def _format_task_detail(root: Path, task: LightweightTask) -> str:
    files = ["task.yaml", "task.md", "verify.md", "evidence.md"]
    rows = [
        f"Task {task.id}: {task.slug}",
        f"- title: {task.title}",
        f"- status: {task.status}",
        f"- location: {task.location}",
        f"- priority: {task.priority}",
        f"- kind: {task.kind}",
        f"- risk: {task.risk}",
        f"- scope: {task.layer} / {task.area} / {task.feature}",
        f"- updated: {task.updated}",
        f"- path: {_display_path(task.path, root)}",
        "",
        "Files",
    ]
    rows.extend(f"- {file_name}: {_display_path(task.path / file_name, root)}" for file_name in files)
    rows.extend(["", "--- task.md ---", ""])
    task_md = task.path / "task.md"
    if task_md.is_file():
        rows.append(task_md.read_text(encoding="utf-8").rstrip())
    else:
        rows.append("(missing task.md)")
    return "\n".join(rows).rstrip() + "\n"


def run_tasks_show(root: Path, args: Namespace) -> int:
    task = _find_task(root, args.task_id)
    selected = [bool(args.task), bool(args.verify), bool(args.evidence)]
    if sum(selected) > 1:
        raise ToolError("./dev tasks show <id> accepts only one of --task, --verify, or --evidence.", code=2)
    if args.task:
        return _write_file(_task_file_path(task, "task"))
    if args.verify:
        return _write_file(_task_file_path(task, "verify"))
    if args.evidence:
        return _write_file(_task_file_path(task, "evidence"))
    sys.stdout.write(_format_task_detail(root, task))
    return 0


def run_tasks_command(root: Path, args: Namespace) -> int:
    """Run a lightweight task command."""

    if args.tasks_command == "status":
        return run_tasks_status(root)
    if args.tasks_command == "list":
        return run_tasks_list(root)
    if args.tasks_command == "doctor":
        return run_tasks_doctor(root)
    if args.tasks_command == "create":
        from .task_create import run_tasks_create

        return run_tasks_create(root, args)
    if args.tasks_command == "show":
        if args.task_id < 1:
            raise ToolError("./dev tasks show requires a positive numeric task id.", code=2)
        return run_tasks_show(root, args)
    raise ToolError(f"unsupported tasks command: {args.tasks_command}", code=2)
