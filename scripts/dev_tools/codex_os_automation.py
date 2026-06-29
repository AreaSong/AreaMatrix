"""Automation and operations helpers for the Codex OS developer surface."""

from __future__ import annotations

from argparse import Namespace
from collections import Counter
import json
import os
from pathlib import Path
import shlex
import subprocess
import time
from typing import Any, Callable

from .codex_os_registry import (
    apply_task_updates,
    default_registry,
    find_task,
    lifecycle_warnings,
    load_registry,
    registry_path,
    require_registry,
    write_json,
)
from .codex_os_render import render_task_detail
from .codex_os_state import build_snapshot, default_runtime_dir, default_state_db, iso_now, thread_to_json
from .common import ToolError


CONTEXT_FILES = (
    "AGENTS.md",
    ".codex/README.md",
    ".codex/references/index.md",
    ".codex/references/codex-operating-system.md",
    ".codex/references/codex-operating-layer-playbook.md",
    ".ai-governance/README.md",
    "docs/README.md",
    "workflow/AGENTS.md",
    "workflow/README.md",
    "workflow/residuals/README.md",
)
HIGH_RISK_PATH_HINTS = (
    "core/migrations/",
    "docs/architecture/migration.md",
    "apps/macos/",
    "core/",
    "workflow/versions/",
)
HIGH_RISK_TEXT_HINTS = (
    "delete",
    "migration",
    "reindex",
    "staging",
    "icloud",
    "fsevents",
    "secret",
    "auth",
    "permission",
    "用户文件",
    "删除",
    "迁移",
    "权限",
)


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _state_db_from_args(args: Namespace) -> Path:
    return Path(args.state_db).expanduser() if args.state_db else default_state_db()


def _runtime_dir_from_args(root: Path, args: Namespace) -> Path:
    runtime_dir = Path(args.runtime_dir).expanduser() if args.runtime_dir else default_runtime_dir(root)
    _validate_runtime_dir(root, runtime_dir)
    return runtime_dir


def _validate_runtime_dir(root: Path, runtime_dir: Path) -> None:
    path = runtime_dir if runtime_dir.is_absolute() else root / runtime_dir
    _validate_no_workflow_execution_path(root, path, "runtime-dir")


def _validate_no_workflow_execution_path(root: Path, path: Path, label: str) -> None:
    if _is_workflow_execution_path(root, path):
        raise ToolError(f"Codex OS {label} must not write workflow/versions/<version>/execution/**", code=1)


def _is_workflow_execution_path(root: Path, path: Path) -> bool:
    resolved_root = root.resolve(strict=False)
    resolved_path = path.resolve(strict=False)
    candidates: list[tuple[str, ...]] = [resolved_path.parts]
    try:
        candidates.insert(0, resolved_path.relative_to(resolved_root).parts)
    except ValueError:
        pass
    return any(_parts_are_workflow_execution(candidate) for candidate in candidates)


def _parts_are_workflow_execution(parts: tuple[str, ...]) -> bool:
    for index in range(0, max(0, len(parts) - 3)):
        if parts[index] == "workflow" and parts[index + 1] == "versions" and parts[index + 3] == "execution":
            return True
    return False


def _write_task_registry(runtime_dir: Path, registry: dict[str, Any]) -> Path:
    path = registry_path(runtime_dir)
    registry["updated_at"] = iso_now()
    write_json(path, registry)
    return path


def _safe_name(value: str | None, fallback: str = "unassigned") -> str:
    text = (value or "").strip().lower()
    parts: list[str] = []
    previous_dash = False
    for char in text:
        if char.isalnum():
            parts.append(char)
            previous_dash = False
        elif not previous_dash:
            parts.append("-")
            previous_dash = True
    safe = "".join(parts).strip("-")
    return safe[:80] or fallback


def _timestamp_slug() -> str:
    return iso_now().replace("-", "").replace(":", "").replace("T", "-").replace("Z", "")


def relative_to_root(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def read_git_status_paths(root: Path) -> tuple[list[str], str]:
    proc = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        return [], proc.stderr.strip() or f"git status failed with {proc.returncode}"
    paths: list[str] = []
    for line in proc.stdout.splitlines():
        if len(line) < 4:
            continue
        value = line[3:].strip()
        if " -> " in value:
            paths.extend(part.strip() for part in value.split(" -> ", 1))
        else:
            paths.append(value)
    return sorted(dict.fromkeys(path for path in paths if path)), ""


def template_output_path(root: Path, args: Namespace, key: str) -> Path:
    output = getattr(args, "output", None)
    if output:
        path = Path(output).expanduser()
        resolved_path = path if path.is_absolute() else root / path
        _validate_no_workflow_execution_path(root, resolved_path, "--output")
        return resolved_path
    task_name = _safe_name(getattr(args, "task_id", None))
    return _runtime_dir_from_args(root, args) / key / f"{task_name}-{_timestamp_slug()}.md"


def update_task_reference(runtime_dir: Path, task_id: str | None, updates: dict[str, Any]) -> Path | None:
    if not task_id:
        return None
    registry = load_registry(runtime_dir)
    if registry is None:
        return None
    task = find_task(registry, task_id)
    if task is None:
        return None
    apply_task_updates(task, updates)
    return _write_task_registry(runtime_dir, registry)


def _relative_path_exists(root: Path, value: str | None) -> bool:
    if not value:
        return False
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.exists()


def _task_needs_confirmation(task: dict[str, Any]) -> bool:
    return task.get("lane") == "Mission-Critical" or task.get("risk_level") in {"High", "Mission-Critical"}


def registry_audit(root: Path, runtime_dir: Path) -> dict[str, Any]:
    path = registry_path(runtime_dir)
    registry = load_registry(runtime_dir)
    if registry is None:
        return {
            "generated_at": iso_now(),
            "registry_path": str(path),
            "result": "WARN",
            "task_count": 0,
            "issues": [{"severity": "WARN", "task_id": "", "message": "task registry is missing"}],
        }
    issues: list[dict[str, str]] = []
    task_ids = [task.get("task_id", "") for task in registry.get("tasks", []) if isinstance(task, dict)]
    for task_id, count in Counter(task_ids).items():
        if task_id and count > 1:
            issues.append({"severity": "FAIL", "task_id": task_id, "message": "duplicate task_id"})
    for task in registry.get("tasks", []):
        if not isinstance(task, dict):
            continue
        task_id = str(task.get("task_id", ""))
        for warning in lifecycle_warnings(task):
            severity = "FAIL" if task.get("status") == "Done" else "WARN"
            issues.append({"severity": severity, "task_id": task_id, "message": warning})
        for key in ("handoff_file", "evidence_file", "closeout_file"):
            value = task.get(key)
            if value and not _relative_path_exists(root, str(value)):
                issues.append({"severity": "WARN", "task_id": task_id, "message": f"{key} does not exist: {value}"})
        if _task_needs_confirmation(task) and task.get("confirmation_status") != "Granted":
            issues.append({"severity": "FAIL", "task_id": task_id, "message": "high-risk task is missing granted confirmation"})
    result = "FAIL" if any(issue["severity"] == "FAIL" for issue in issues) else "WARN" if issues else "OK"
    return {
        "generated_at": iso_now(),
        "registry_path": str(path),
        "result": result,
        "task_count": len(registry.get("tasks", [])),
        "issues": issues,
    }


def render_registry_audit(audit: dict[str, Any]) -> str:
    lines = ["Codex OS registry audit", ""]
    lines.append(f"- generated_at: {audit['generated_at']}")
    lines.append(f"- registry_path: {audit['registry_path']}")
    lines.append(f"- result: {audit['result']}")
    lines.append(f"- task_count: {audit['task_count']}")
    lines.append("")
    lines.append("Issues")
    lines.append("")
    if not audit["issues"]:
        lines.append("- none")
    else:
        for issue in audit["issues"]:
            task = f" `{issue['task_id']}`" if issue.get("task_id") else ""
            lines.append(f"- {issue['severity']}:{task} {issue['message']}")
    return "\n".join(lines).rstrip() + "\n"


def _load_task_if_present(runtime_dir: Path, task_id: str | None) -> dict[str, Any] | None:
    if not task_id:
        return None
    registry = load_registry(runtime_dir)
    return find_task(registry, task_id) if registry else None


def _next_registry_task(tasks: list[dict[str, Any]], lane: str | None) -> dict[str, Any] | None:
    terminal = {"Done", "Archived", "Abandoned"}
    for task in tasks:
        if lane and task.get("lane") != lane:
            continue
        if task.get("status") not in terminal:
            return task
    return None


def _recommended_commands(task: dict[str, Any]) -> list[str]:
    lane = task.get("lane") or "Change"
    commands = ["./dev codex-os doctor"]
    validation = task.get("validation")
    validation_commands = _validation_commands(str(validation)) if validation else []
    if validation_commands:
        commands.extend(validation_commands)
    elif lane == "Quick":
        commands.append("./dev check codex-os")
    elif lane == "Mission-Critical":
        commands.extend(["./dev check codex-os", "./dev check quality"])
    else:
        commands.extend(["./dev check codex-os", "./dev check quality"])
    return commands


def _validation_commands(value: str) -> list[str]:
    commands: list[str] = []
    for raw in value.replace("\n", ";").split(";"):
        candidate = _strip_validation_result(raw.strip())
        if _looks_like_command(candidate) and candidate not in commands:
            commands.append(candidate)
    return commands


def _strip_validation_result(value: str) -> str:
    for suffix in (
        ": PASS",
        ": FAIL",
        ": WARN",
        ": OK",
        ": BLOCKED",
        ": NOT-READY",
        ": SKIPPED",
        ": Pass",
        ": Fail",
    ):
        if value.endswith(suffix):
            return value[: -len(suffix)].strip()
    return value


def _looks_like_command(value: str) -> bool:
    prefixes = ("./", "python3 ", "PYTHONDONTWRITEBYTECODE=1 ", "cd ", "xcodebuild ", "git ", "bash ")
    return value.startswith(prefixes) and ";" not in value and "\n" not in value


def run_new(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    registry = load_registry(runtime_dir) or default_registry()
    task_id = args.task_id or _generated_task_id(args.title, args.lane)
    if find_task(registry, task_id):
        raise ToolError(f"task already exists: {task_id}", code=1)
    task = {
        "task_id": task_id,
        "project": args.project_name or "AreaMatrix",
        "title": args.title,
        "lane": args.lane,
        "status": args.status,
        "owner_thread": args.owner_thread or "",
        "handoff_file": args.handoff_file or "",
        "next_action": args.next_action or f"Start Codex OS task: {args.title}",
        "validation": args.validation or "",
        "archive_recommendation": "keep",
        "created_at": iso_now(),
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
    if args.recommend_validation:
        recommendation = build_validation_recommendation(root, args.path or [], include_changed=not bool(args.path))
        task["validation"] = "; ".join(item["command"] for item in recommendation["commands"])
        task["validation_status"] = "Recommended"
    if args.write:
        registry.setdefault("tasks", []).append(task)
        path = _write_task_registry(runtime_dir, registry)
        print(f"created {task_id} in {path}")
    else:
        print(json.dumps(task, ensure_ascii=False, indent=2))
        print("Add --write to update the registry.")
    return 0


def _generated_task_id(title: str, lane: str) -> str:
    date = iso_now()[:10].replace("-", "")
    clock = iso_now()[11:16].replace(":", "")
    slug = _safe_name(title or lane or "codex-os").upper()
    return f"AM-{date}-{clock}-{slug[:28]}"


def run_context(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    data = _build_context_data(root, args, runtime_dir)
    if args.write:
        _write_text(runtime_dir / "context.md", _render_context(data))
        write_json(runtime_dir / "context.json", data)
        print(f"wrote {runtime_dir / 'context.md'}")
        print(f"wrote {runtime_dir / 'context.json'}")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_context(data))
    return 0


def _build_context_data(root: Path, args: Namespace, runtime_dir: Path) -> dict[str, Any]:
    changed_paths, git_error = read_git_status_paths(root)
    return {
        "generated_at": iso_now(),
        "workspace": str(root),
        "task_id": getattr(args, "task_id", None),
        "task": _load_task_if_present(runtime_dir, getattr(args, "task_id", None)),
        "context_files": [{"path": path, "exists": (root / path).exists()} for path in CONTEXT_FILES],
        "changed_paths": changed_paths,
        "git_status_error": git_error,
        "registry_audit": registry_audit(root, runtime_dir),
        "validation_recommendation": build_validation_recommendation(root, changed_paths, include_changed=False),
        "guardrails": [
            "Do not write Codex internal SQLite.",
            "Do not auto-archive threads; produce recommendations only.",
            "Do not write workflow/versions/<version>/execution/** from Codex OS.",
            "Do not treat .codex/runtime/codex-os/** as product source of truth.",
        ],
    }


def _render_context(data: dict[str, Any]) -> str:
    lines = ["Codex OS context", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- workspace: {data['workspace']}")
    lines.append(f"- task_id: {data.get('task_id') or '(none)'}")
    lines.append(f"- registry_audit: {data['registry_audit']['result']}")
    if data.get("task"):
        lines.append("")
        lines.append("Task")
        lines.append("")
        lines.extend(f"- {key}: {value}" for key, value in data["task"].items() if value)
    lines.append("")
    lines.append("Context Files")
    lines.append("")
    for item in data["context_files"]:
        lines.append(f"- {'OK' if item['exists'] else 'MISSING'}: `{item['path']}`")
    lines.append("")
    lines.append("Changed Paths")
    lines.append("")
    lines.extend(f"- `{path}`" for path in data["changed_paths"][:80]) if data["changed_paths"] else lines.append("- none")
    lines.append("")
    lines.append("Recommended Validation")
    lines.append("")
    for item in data["validation_recommendation"]["commands"]:
        lines.append(f"- `{item['command']}` - {item['reason']}")
    lines.append("")
    lines.append("Guardrails")
    lines.append("")
    lines.extend(f"- {item}" for item in data["guardrails"])
    return "\n".join(lines).rstrip() + "\n"


def run_resume(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    registry = require_registry(runtime_dir)
    task = find_task(registry, args.task_id) if args.task_id else _next_registry_task(registry.get("tasks", []), args.lane)
    if task is None:
        raise ToolError("no matching task to resume", code=1)
    data = {
        "generated_at": iso_now(),
        "task": task,
        "registry_audit": registry_audit(root, runtime_dir),
        "warnings": lifecycle_warnings(task),
        "manual_confirmations": _manual_confirmations(task),
        "recommended_commands": _recommended_commands(task),
        "next_commands": [
            f"./dev codex-os preflight --task-id {task['task_id']} --strict",
            f"./dev codex-os task start --task-id {task['task_id']} --write",
            "./dev codex-os recommend-validation",
        ],
    }
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_resume(data))
    return 0


def _manual_confirmations(task: dict[str, Any]) -> list[str]:
    if _task_needs_confirmation(task) and task.get("confirmation_status") != "Granted":
        return ["High or Mission-Critical task: confirm impact, risk, validation, and rollback before writes."]
    return []


def _render_resume(data: dict[str, Any]) -> str:
    lines = ["Codex OS resume", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- registry_audit: {data['registry_audit']['result']}")
    lines.append("")
    lines.append(render_task_detail(data["task"]).rstrip())
    if data["warnings"]:
        lines.append("")
        lines.append("Warnings")
        lines.append("")
        lines.extend(f"- {warning}" for warning in data["warnings"])
    if data["manual_confirmations"]:
        lines.append("")
        lines.append("Manual Confirmations")
        lines.append("")
        lines.extend(f"- {item}" for item in data["manual_confirmations"])
    lines.append("")
    lines.append("Recommended Validation")
    lines.append("")
    lines.extend(f"- `{command}`" for command in data["recommended_commands"])
    lines.append("")
    lines.append("Next Commands")
    lines.append("")
    lines.extend(f"- `{command}`" for command in data["next_commands"])
    return "\n".join(lines).rstrip() + "\n"


def run_recommend_validation(root: Path, args: Namespace) -> int:
    data = build_validation_recommendation(root, args.path or [], include_changed=args.changed or not args.path)
    runtime_dir = _runtime_dir_from_args(root, args)
    if args.write:
        write_json(runtime_dir / "recommend-validation.json", data)
        print(f"wrote {runtime_dir / 'recommend-validation.json'}")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_validation_recommendation(data))
    return 0


def build_validation_recommendation(root: Path, paths: list[str], *, include_changed: bool) -> dict[str, Any]:
    inputs = list(paths)
    git_error = ""
    if include_changed:
        changed, git_error = read_git_status_paths(root)
        inputs.extend(changed)
    unique_paths = sorted(dict.fromkeys(path for path in inputs if path))
    commands: list[dict[str, str]] = []
    warnings: list[str] = []

    def add(command: str, reason: str) -> None:
        if command not in [item["command"] for item in commands]:
            commands.append({"command": command, "reason": reason})

    if not unique_paths:
        add("./dev codex-os doctor", "Codex OS structure smoke check when no changed paths are available.")
        add("./dev check codex-os", "Codex OS command and unit-test gate.")
    for path in unique_paths:
        _append_validation_for_path(path, add)
        lowered = path.lower()
        if any(hint in lowered for hint in HIGH_RISK_TEXT_HINTS) or any(path.startswith(hint) for hint in HIGH_RISK_PATH_HINTS):
            warnings.append(f"High-risk review may be required for `{path}`.")
    if unique_paths:
        add("./dev check diff", "Whitespace and conflict-marker check for the current diff.")
    if git_error:
        warnings.append(f"git status unavailable: {git_error}")
    return {
        "generated_at": iso_now(),
        "input_paths": unique_paths,
        "commands": commands,
        "warnings": sorted(dict.fromkeys(warnings)),
        "execution_policy": "recommendation only; commands are not executed automatically",
    }


def _append_validation_for_path(path: str, add: Callable[[str, str], None]) -> None:
    if path == "dev" or path == "task-loop" or path.startswith("scripts/dev_tools/") or path.startswith("scripts/task_loop/"):
        add("PYTHONDONTWRITEBYTECODE=1 python3 -m compileall -q scripts/dev_tools scripts/task_loop", "Python developer-tool syntax gate.")
        add("PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.dev_tools.test_codex_os", "Codex OS regression tests.")
        add("./dev check codex-os", "Codex OS integrated health check.")
    if path.startswith(".codex/skills-src/") or path.startswith(".agents/skills/"):
        add("./dev check skills", "Repo-local skill structure and discovery check.")
        add("./dev check quality", "Skill and quality smoke coverage.")
        add("./dev check wording", "Long-lived wording audit for Codex materials.")
    if path.startswith(".codex/references/") or path.startswith(".codex/templates/") or path == ".codex/README.md":
        add("./dev check codex-os", "Codex OS docs/templates and command smoke check.")
        add("./dev check quality", "Codex reference navigation quality smoke.")
        add("./dev check wording", "Long-lived Codex wording audit.")
    if path.startswith("workflow/versions/") and "/execution/" in path:
        add("./dev check prompts", "Live execution prompt doctor.")
    elif path.startswith("workflow/"):
        add("./dev workflow doctor", "Versioned workflow structure and gate check.")
    if path.startswith("core/"):
        add("cd core && cargo fmt --all -- --check", "Rust formatting gate.")
        add("cd core && cargo clippy --all-targets --all-features -- -D warnings", "Rust lint gate.")
        add("cd core && cargo test --workspace", "Rust workspace tests.")
    if path.startswith("apps/macos/"):
        add("xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO", "macOS build gate.")
        add("./dev test macos", "macOS XCTest gate.")
    if path.startswith(".github/") or path in {"CODE_REVIEW.md", "SECURITY.md", "CONTRIBUTING.md"} or path.startswith("docs/development/"):
        add("./dev check governance", "Governance, review, security, dependency, and CI gate.")
        add("./dev check quality", "Quality smoke gate.")
        add("./dev check wording", "Long-lived governance wording audit.")
    if path == ".gitleaks.toml" or path.startswith("scripts/check-secrets"):
        add("./dev check secrets", "Local secret scan gate.")
    if path.startswith("docs/") and not path.startswith("docs/development/"):
        add("./dev check wording", "Long-lived docs wording audit.")


def _render_validation_recommendation(data: dict[str, Any]) -> str:
    lines = ["Codex OS validation recommendation", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- execution_policy: {data['execution_policy']}")
    lines.append("")
    lines.append("Input Paths")
    lines.append("")
    lines.extend(f"- `{path}`" for path in data["input_paths"]) if data["input_paths"] else lines.append("- none")
    lines.append("")
    lines.append("Recommended Commands")
    lines.append("")
    for item in data["commands"]:
        lines.append(f"- `{item['command']}` - {item['reason']}")
    if data["warnings"]:
        lines.append("")
        lines.append("Warnings")
        lines.append("")
        lines.extend(f"- {warning}" for warning in data["warnings"])
    return "\n".join(lines).rstrip() + "\n"


def run_archive_review(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    data = _archive_review_data(snapshot, args.limit)
    if args.write:
        write_json(runtime_dir / "archive-review.json", data)
        _write_text(runtime_dir / "archive-review.md", _render_archive_review(data))
        print(f"wrote {runtime_dir / 'archive-review.md'}")
        print(f"wrote {runtime_dir / 'archive-review.json'}")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_archive_review(data))
    return 0


def _archive_review_data(snapshot: dict[str, Any], limit: int) -> dict[str, Any]:
    candidates = [item for item in snapshot["threads"] if item.bucket == "Archive Candidate"]
    risk = [item for item in snapshot["threads"] if item.bucket == "Risk Review"]
    return {
        "generated_at": iso_now(),
        "project_filter": snapshot["project_filter"],
        "policy": "recommendations only; no archive action is performed",
        "bucket_counts": snapshot["bucket_counts"],
        "archive_candidates": [thread_to_json(item) for item in candidates[:limit]],
        "risk_review": [thread_to_json(item) for item in risk[:limit]],
    }


def _render_archive_review(data: dict[str, Any]) -> str:
    lines = ["Codex OS archive review", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- project_filter: {data['project_filter'] or '(all projects)'}")
    lines.append(f"- policy: {data['policy']}")
    lines.append("")
    lines.append("Bucket Counts")
    lines.append("")
    for key, value in data["bucket_counts"].items():
        lines.append(f"- {key}: {value}")
    lines.append("")
    lines.append("Archive Candidates")
    lines.append("")
    lines.extend(
        f"- {item['updated_at']} | {item['age_days']}d | {item['reason']} | {item['title']}"
        for item in data["archive_candidates"]
    ) if data["archive_candidates"] else lines.append("- none")
    lines.append("")
    lines.append("Risk Review")
    lines.append("")
    lines.extend(
        f"- {item['updated_at']} | {item['age_days']}d | {item['reason']} | {item['title']}"
        for item in data["risk_review"]
    ) if data["risk_review"] else lines.append("- none")
    return "\n".join(lines).rstrip() + "\n"


def run_title_suggestions(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    rows = []
    for item in snapshot["threads"]:
        if item.thread.archived or item.bucket not in {"Archive Candidate", "Risk Review", "Cold", "Warm"}:
            continue
        rows.append(_title_suggestion(item))
        if len(rows) >= args.limit:
            break
    data = {"generated_at": iso_now(), "policy": "suggestions only; no thread title is changed", "suggestions": rows}
    if args.write:
        write_json(runtime_dir / "title-suggestions.json", data)
        print(f"wrote {runtime_dir / 'title-suggestions.json'}")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_title_suggestions(data))
    return 0


def _title_suggestion(item: Any) -> dict[str, str]:
    project = Path(item.thread.cwd).name or "Codex"
    original = item.thread.display_title
    if item.bucket == "Archive Candidate":
        title = f"{project} / archive review / {item.reason}"
    elif item.bucket == "Risk Review":
        title = f"{project} / risk review / {original[:48]}"
    else:
        title = f"{project} / resume review / {original[:48]}"
    return {
        "thread_id": item.thread.id,
        "current_title": original,
        "suggested_title": title,
        "bucket": item.bucket,
        "reason": item.reason,
    }


def _render_title_suggestions(data: dict[str, Any]) -> str:
    lines = ["Codex OS title suggestions", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- policy: {data['policy']}")
    lines.append("")
    for item in data["suggestions"]:
        lines.append(f"- `{item['thread_id']}`")
        lines.append(f"  current: {item['current_title']}")
        lines.append(f"  suggested: {item['suggested_title']}")
    if not data["suggestions"]:
        lines.append("- none")
    return "\n".join(lines).rstrip() + "\n"


def run_weekly(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    audit = registry_audit(root, runtime_dir)
    data = {
        "generated_at": iso_now(),
        "thread_summary": {
            "total_threads": snapshot["total_threads"],
            "unarchived_threads": snapshot["unarchived_threads"],
            "bucket_counts": snapshot["bucket_counts"],
        },
        "task_counts": _task_counts(load_registry(runtime_dir)),
        "registry_audit": audit,
        "recommended_actions": _weekly_actions(snapshot, audit),
    }
    if args.write:
        _write_text(runtime_dir / "weekly.md", _render_weekly(data))
        write_json(runtime_dir / "weekly.json", data)
        print(f"wrote {runtime_dir / 'weekly.md'}")
        print(f"wrote {runtime_dir / 'weekly.json'}")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_weekly(data))
    return 0


def _task_counts(registry: dict[str, Any] | None) -> dict[str, int]:
    counts: dict[str, int] = {}
    if not registry:
        return counts
    for task in registry.get("tasks", []):
        status = str(task.get("status", ""))
        counts[status] = counts.get(status, 0) + 1
    return counts


def _weekly_actions(snapshot: dict[str, Any], audit: dict[str, Any]) -> list[str]:
    actions = ["Run `./dev codex-os dashboard --write` after major task batches."]
    if snapshot["bucket_counts"].get("Risk Review", 0):
        actions.append("Review Risk Review threads manually before any cleanup.")
    if snapshot["bucket_counts"].get("Archive Candidate", 0):
        actions.append("Run `./dev codex-os archive-review --write`; archive only after manual confirmation.")
    if audit["result"] != "OK":
        actions.append("Run `./dev codex-os registry status --strict` and repair lifecycle issues.")
    return actions


def _render_weekly(data: dict[str, Any]) -> str:
    lines = ["Codex OS weekly review", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append("")
    lines.append("Threads")
    lines.append("")
    for key, value in data["thread_summary"]["bucket_counts"].items():
        lines.append(f"- {key}: {value}")
    lines.append("")
    lines.append("Tasks")
    lines.append("")
    if data["task_counts"]:
        for key, value in sorted(data["task_counts"].items()):
            lines.append(f"- {key}: {value}")
    else:
        lines.append("- none")
    lines.append("")
    lines.append("Registry")
    lines.append("")
    lines.append(f"- result: {data['registry_audit']['result']}")
    lines.append(f"- issues: {len(data['registry_audit']['issues'])}")
    lines.append("")
    lines.append("Recommended Actions")
    lines.append("")
    lines.extend(f"- {item}" for item in data["recommended_actions"])
    return "\n".join(lines).rstrip() + "\n"


def run_diagnose(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    data = _diagnose_data(root, args, runtime_dir)
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_diagnose(data))
    return 1 if args.strict and data["result"] == "FAIL" else 0


def _diagnose_data(root: Path, args: Namespace, runtime_dir: Path) -> dict[str, Any]:
    audit = registry_audit(root, runtime_dir)
    task = _load_task_if_present(runtime_dir, args.task_id)
    task_warnings = lifecycle_warnings(task) if task else []
    result = "FAIL" if audit["result"] == "FAIL" else "WARN" if audit["result"] == "WARN" or task_warnings else "OK"
    return {
        "generated_at": iso_now(),
        "result": result,
        "task": task,
        "task_warnings": task_warnings,
        "manual_confirmations": _manual_confirmations(task or {}),
        "registry_audit": audit,
        "validation_recommendation": build_validation_recommendation(root, args.path or [], include_changed=args.changed),
    }


def _render_diagnose(data: dict[str, Any]) -> str:
    lines = ["Codex OS diagnose", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- result: {data['result']}")
    if data.get("task"):
        lines.append("")
        lines.append(render_task_detail(data["task"]).rstrip())
    lines.append("")
    lines.append("Registry Issues")
    lines.append("")
    if data["registry_audit"]["issues"]:
        for issue in data["registry_audit"]["issues"]:
            task = f" `{issue['task_id']}`" if issue.get("task_id") else ""
            lines.append(f"- {issue['severity']}:{task} {issue['message']}")
    else:
        lines.append("- none")
    if data["task_warnings"]:
        lines.append("")
        lines.append("Task Warnings")
        lines.append("")
        lines.extend(f"- {warning}" for warning in data["task_warnings"])
    if data["manual_confirmations"]:
        lines.append("")
        lines.append("Manual Confirmations")
        lines.append("")
        lines.extend(f"- {item}" for item in data["manual_confirmations"])
    lines.append("")
    lines.append("Validation")
    lines.append("")
    for item in data["validation_recommendation"]["commands"]:
        lines.append(f"- `{item['command']}` - {item['reason']}")
    return "\n".join(lines).rstrip() + "\n"


def run_health_score(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    data = _health_score(snapshot, registry_audit(root, runtime_dir))
    if args.write:
        write_json(runtime_dir / "health-score.json", data)
        print(f"wrote {runtime_dir / 'health-score.json'}")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_health_score(data))
    return 0


def _health_score(snapshot: dict[str, Any], audit: dict[str, Any]) -> dict[str, Any]:
    deductions: list[dict[str, Any]] = []

    def subtract(points: int, reason: str) -> None:
        if points > 0:
            deductions.append({"points": points, "reason": reason})

    subtract(min(20, snapshot["bucket_counts"].get("Archive Candidate", 0)), "archive candidates need review")
    subtract(min(25, snapshot["bucket_counts"].get("Risk Review", 0) * 5), "risk-review threads need manual triage")
    subtract(min(25, len(audit["issues"]) * 5), "registry lifecycle issues")
    if audit["result"] == "FAIL":
        subtract(15, "registry audit has failing issues")
    score = max(0, 100 - sum(item["points"] for item in deductions))
    status = "OK" if score >= 85 else "WARN" if score >= 60 else "FAIL"
    return {"generated_at": iso_now(), "score": score, "status": status, "deductions": deductions}


def _render_health_score(data: dict[str, Any]) -> str:
    lines = ["Codex OS health score", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- score: {data['score']}")
    lines.append(f"- status: {data['status']}")
    lines.append("")
    lines.append("Deductions")
    lines.append("")
    if data["deductions"]:
        for item in data["deductions"]:
            lines.append(f"- -{item['points']}: {item['reason']}")
    else:
        lines.append("- none")
    return "\n".join(lines).rstrip() + "\n"


def run_runbook(root: Path, args: Namespace) -> int:
    text = _codex_os_runbook()
    if args.write:
        path = _runtime_dir_from_args(root, args) / "runbook.md"
        _write_text(path, text)
        print(f"wrote {path}")
    print(text)
    return 0


def _codex_os_runbook() -> str:
    return """# Codex OS Runbook

## Start

1. `./dev codex-os status`
2. `./dev codex-os context`
3. `./dev codex-os resume` or `./dev codex-os new --lane <lane> --title "<title>" --write`
4. `./dev codex-os preflight --task-id <task-id> --strict`

## Work

- Quick: execute, run the smallest sufficient validation, write closeout.
- Change: use read-only subagents for code/docs/tests/risk, then let the main agent write.
- Mission-Critical: explain impact, risk, validation, and rollback; wait for explicit confirmation before writes.

Use `./dev codex-os subagent-plan --task-id <task-id>` to generate a structured read-only delegation plan.

## Validate

1. `./dev codex-os recommend-validation`
2. Run selected commands explicitly.
3. Record fresh results with `./dev codex-os evidence --task-id <task-id> --write`.

## Finish

1. `./dev codex-os closeout --task-id <task-id> --write`
2. `./dev codex-os finish --task-id <task-id> --status Done --validation "<fresh result>" --evidence-file <path> --closeout-file <path> --write`
3. `./dev codex-os archive-review --write`

## Guardrails

- Do not write Codex internal SQLite.
- Do not auto-archive threads.
- Do not create a second runner, queue, progress, promotion, or checkpoint system.
- Do not treat subagent output as validation evidence until the main agent verifies it.
"""


def run_lifecycle(root: Path, args: Namespace) -> int:
    registry = require_registry(_runtime_dir_from_args(root, args))
    task = find_task(registry, args.task_id)
    if task is None:
        raise ToolError(f"task not found: {args.task_id}", code=1)
    data = _lifecycle_data(task)
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(_render_lifecycle(data))
    return 0


def _lifecycle_data(task: dict[str, Any]) -> dict[str, Any]:
    status = task.get("status")
    missing: list[str] = []
    if status == "Done" and not task.get("validation"):
        missing.append("validation")
    if status == "Done" and not (task.get("evidence_file") or task.get("closeout_file") or task.get("evidence_note") or task.get("closeout_note")):
        missing.append("evidence_or_closeout")
    if status == "Blocked" and not (task.get("next_action") or task.get("handoff_file")):
        missing.append("next_action_or_handoff")
    if _task_needs_confirmation(task) and task.get("confirmation_status") != "Granted":
        missing.append("manual_confirmation")
    return {
        "generated_at": iso_now(),
        "task_id": task.get("task_id"),
        "status": status,
        "lane": task.get("lane"),
        "missing": missing,
        "allowed_next_commands": _lifecycle_commands(task),
        "warnings": lifecycle_warnings(task),
    }


def _lifecycle_commands(task: dict[str, Any]) -> list[str]:
    task_id = task.get("task_id")
    status = task.get("status")
    if status in {"Backlog", "Ready", "Waiting Confirmation"}:
        return [f"./dev codex-os preflight --task-id {task_id} --strict", f"./dev codex-os task start --task-id {task_id} --write"]
    if status == "Running":
        return [f"./dev codex-os task verify --task-id {task_id} --validation '<command>: <result>' --write"]
    if status == "Verifying":
        return [f"./dev codex-os evidence --task-id {task_id} --write", f"./dev codex-os finish --task-id {task_id} --status Done --validation '<fresh result>' --evidence-note '<summary>' --write"]
    if status == "Blocked":
        return [f"./dev codex-os handoff --task-id {task_id} --write", f"./dev codex-os resume --task-id {task_id}"]
    return [f"./dev codex-os task show --task-id {task_id}"]


def _render_lifecycle(data: dict[str, Any]) -> str:
    lines = ["Codex OS lifecycle", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- task_id: {data['task_id']}")
    lines.append(f"- lane: {data.get('lane') or '(unset)'}")
    lines.append(f"- status: {data['status']}")
    lines.append("")
    lines.append("Missing")
    lines.append("")
    lines.extend(f"- {item}" for item in data["missing"]) if data["missing"] else lines.append("- none")
    lines.append("")
    lines.append("Allowed Next Commands")
    lines.append("")
    lines.extend(f"- `{command}`" for command in data["allowed_next_commands"])
    return "\n".join(lines).rstrip() + "\n"


def run_start_flow(root: Path, args: Namespace) -> int:
    from .codex_os_subagents import build_subagent_plan

    runtime_dir = _runtime_dir_from_args(root, args)
    registry = _load_or_default_registry(args, runtime_dir)
    task = _resolve_start_flow_task(root, args, runtime_dir, registry)
    task_id = str(task.get("task_id", ""))
    context_args = _namespace_for_flow(
        args,
        task_id=task_id,
        path=getattr(args, "path", []) or [],
        changed=getattr(args, "changed", False),
    )
    context_data = _build_context_data(root, context_args, runtime_dir)
    preflight = _flow_preflight(root, args, runtime_dir, task)
    validation = build_validation_recommendation(
        root,
        getattr(args, "path", []) or [],
        include_changed=getattr(args, "changed", False) or not getattr(args, "path", []),
    )
    registered_task_id = task_id if find_task(registry, task_id) is not None else None
    subagent_args = _namespace_for_flow(
        args,
        task_id=registered_task_id,
        lane=task.get("lane"),
        risk_level=task.get("risk_level"),
        path=getattr(args, "path", []) or [],
        changed=getattr(args, "changed", False),
    )
    subagent_plan = build_subagent_plan(root, subagent_args)
    lifecycle = _lifecycle_data(task)
    result = _flow_result(preflight["checks"])
    action = "preview"
    registry_path_value = ""
    if args.write and result != "FAIL":
        if find_task(registry, task_id) is None:
            registry.setdefault("tasks", []).append(task)
            action = "created_and_started"
        else:
            action = "started"
        updates = {
            "status": "Running",
            "validation": "; ".join(item["command"] for item in validation["commands"]),
            "validation_status": "Recommended",
            "automation_scope": "registry-write",
        }
        apply_task_updates(task, updates)
        registry_path_value = str(_write_task_registry(runtime_dir, registry))
        lifecycle = _lifecycle_data(task)
    elif args.write and result == "FAIL":
        action = "blocked_by_preflight"
    data = {
        "generated_at": iso_now(),
        "flow": "start-flow",
        "result": result,
        "write": args.write,
        "action": action,
        "registry_path": registry_path_value,
        "task": task,
        "context": context_data,
        "preflight": preflight,
        "subagent_plan": subagent_plan,
        "validation_recommendation": validation,
        "lifecycle": lifecycle,
        "guardrails": _flow_guardrails(),
        "next_commands": _start_flow_next_commands(task_id, result),
    }
    if args.write:
        write_json(runtime_dir / "start-flow.json", data)
        _write_text(runtime_dir / "start-flow.md", _render_start_flow(data))
    _emit_flow(data, args.json, _render_start_flow)
    return 1 if args.strict and result == "FAIL" else 0


def _load_or_default_registry(args: Namespace, runtime_dir: Path) -> dict[str, Any]:
    registry = load_registry(runtime_dir)
    if registry is not None:
        return registry
    if getattr(args, "title", None):
        return default_registry()
    raise ToolError("task registry is missing; pass --title to preview a new task or run registry init", code=1)


def _resolve_start_flow_task(
    root: Path,
    args: Namespace,
    runtime_dir: Path,
    registry: dict[str, Any],
) -> dict[str, Any]:
    if getattr(args, "task_id", None):
        task = find_task(registry, args.task_id)
        if task is not None:
            return task
        if not getattr(args, "title", None):
            raise ToolError(f"task not found: {args.task_id}", code=1)
    if not getattr(args, "title", None):
        task = _next_registry_task(registry.get("tasks", []), getattr(args, "lane", None))
        if task is None:
            raise ToolError("no matching task; pass --task-id or --title", code=1)
        return task
    task_id = getattr(args, "task_id", None) or _generated_task_id(args.title, args.lane or "Change")
    if find_task(registry, task_id):
        raise ToolError(f"task already exists: {task_id}", code=1)
    validation = build_validation_recommendation(
        root,
        getattr(args, "path", []) or [],
        include_changed=getattr(args, "changed", False) or not getattr(args, "path", []),
    )
    return {
        "task_id": task_id,
        "project": getattr(args, "project_name", None) or "AreaMatrix",
        "title": args.title,
        "lane": args.lane or "Change",
        "status": "Ready",
        "owner_thread": getattr(args, "owner_thread", None) or "",
        "handoff_file": getattr(args, "handoff_file", None) or "",
        "next_action": getattr(args, "next_action", None) or f"Start Codex OS task: {args.title}",
        "validation": "; ".join(item["command"] for item in validation["commands"]),
        "archive_recommendation": "keep",
        "risk_level": getattr(args, "risk_level", None) or _infer_task_risk(args.lane or "Change", getattr(args, "path", []) or []),
        "confirmation_status": getattr(args, "confirmation_status", None) or "Not Required",
        "validation_status": "Recommended",
        "automation_scope": "registry-write",
        "created_at": iso_now(),
        "updated_at": iso_now(),
    }


def _infer_task_risk(lane: str, paths: list[str]) -> str:
    if lane == "Mission-Critical":
        return "Mission-Critical"
    if any(path.startswith(hint) for path in paths for hint in HIGH_RISK_PATH_HINTS):
        return "High"
    return "Medium" if lane in {"Change", "Review", "Ops"} else "Low"


def _flow_preflight(root: Path, args: Namespace, runtime_dir: Path, task: dict[str, Any]) -> dict[str, Any]:
    registry = load_registry(runtime_dir)
    checks: list[dict[str, str]] = []
    manual_confirmations = _manual_confirmations(task)
    checks.append(_flow_check("task registry", "OK" if registry is not None else "WARN", "available" if registry is not None else "missing; new task preview"))
    checks.append(_flow_check("task", "OK", f"{task.get('task_id')} ({task.get('status')})"))
    if task.get("handoff_file"):
        status = "OK" if _relative_path_exists(root, str(task.get("handoff_file"))) else "WARN"
        checks.append(_flow_check("handoff file", status, str(task.get("handoff_file"))))
    else:
        checks.append(_flow_check("handoff file", "WARN", "not set"))
    checks.append(_flow_check("validation", "OK" if task.get("validation") else "WARN", task.get("validation") or "will be recommended"))
    git_paths, git_error = read_git_status_paths(root)
    checks.append(_flow_check("git worktree", "WARN" if git_paths or git_error else "OK", git_error or f"{len(git_paths)} changed path(s)"))
    if _task_needs_confirmation(task) and task.get("confirmation_status") != "Granted":
        checks.append(_flow_check("manual confirmation", "FAIL", "high-risk task requires explicit confirmation"))
    return {
        "result": _flow_result(checks),
        "strict": getattr(args, "strict", False),
        "checks": checks,
        "manual_confirmations": manual_confirmations,
    }


def _flow_check(name: str, status: str, detail: str = "") -> dict[str, str]:
    return {"name": name, "status": status, "detail": detail}


def _flow_result(checks: list[dict[str, str]]) -> str:
    if any(check["status"] == "FAIL" for check in checks):
        return "FAIL"
    if any(check["status"] == "WARN" for check in checks):
        return "WARN"
    return "PASS"


def _namespace_for_flow(args: Namespace, **overrides: Any) -> Namespace:
    values = dict(vars(args))
    values.update(overrides)
    return Namespace(**values)


def _flow_guardrails() -> list[str]:
    return [
        "Codex OS writes only local operating-layer runtime or registry state.",
        "No Codex thread is archived or renamed automatically.",
        "No Codex internal SQLite writes are performed.",
        "No workflow/versions/<version>/execution/** live state is written.",
        "Subagent output is advisory and never replaces fresh main-agent validation.",
    ]


def _start_flow_next_commands(task_id: str, result: str) -> list[str]:
    if result == "FAIL":
        return [f"./dev codex-os repair-plan --task-id {task_id} --changed"]
    return [
        f"./dev codex-os run-validation --task-id {task_id} --changed --execute --write",
        f"./dev codex-os close-flow --task-id {task_id} --status Done --validation '<fresh PASS/OK result>' --write",
    ]


def _emit_flow(data: dict[str, Any], as_json: bool, renderer: Callable[[dict[str, Any]], str]) -> None:
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(renderer(data))


def _render_start_flow(data: dict[str, Any]) -> str:
    lines = _flow_header("Codex OS start flow", data)
    task = data["task"]
    lines.append("")
    lines.append("Task")
    lines.append("")
    for key in ("task_id", "title", "lane", "status", "risk_level", "confirmation_status", "validation_status"):
        if task.get(key):
            lines.append(f"- {key}: {task[key]}")
    lines.append("")
    lines.append("Preflight")
    lines.append("")
    for check in data["preflight"]["checks"]:
        detail = f" - {check['detail']}" if check.get("detail") else ""
        lines.append(f"- {check['status']}: {check['name']}{detail}")
    _append_named_list(lines, "Manual Confirmations", data["preflight"].get("manual_confirmations", []))
    lines.append("")
    lines.append("Subagent Plan")
    lines.append("")
    lines.append(f"- recommended: {data['subagent_plan']['subagents_recommended']}")
    for role in data["subagent_plan"]["roles"]:
        lines.append(f"- {role['role']} ({role['mode']})")
    lines.append("")
    lines.append("Recommended Validation")
    lines.append("")
    for item in data["validation_recommendation"]["commands"]:
        lines.append(f"- `{item['command']}` - {item['reason']}")
    _append_named_list(lines, "Next Commands", data["next_commands"], code=True)
    return "\n".join(lines).rstrip() + "\n"


def run_validation_flow(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    task = _load_task_if_present(runtime_dir, getattr(args, "task_id", None))
    recommendation = build_validation_recommendation(
        root,
        getattr(args, "path", []) or [],
        include_changed=getattr(args, "changed", False) or not getattr(args, "path", []),
    )
    selected_commands = _selected_validation_commands(task, recommendation)
    execution_policy = _validation_execution_policy(args)
    results: list[dict[str, Any]] = []
    if args.execute:
        for command in selected_commands:
            result = _execute_validation_command(root, command, getattr(args, "timeout", 600))
            results.append(result)
            if result["result"] == "BLOCKED":
                break
    else:
        results = [_dry_validation_result(command) for command in selected_commands]
    validation_result = _aggregate_validation_results(results, executed=args.execute)
    report = {
        "generated_at": iso_now(),
        "flow": "run-validation",
        "task_id": getattr(args, "task_id", None),
        "execute": args.execute,
        "write": args.write,
        "execution_policy": execution_policy,
        "recommendation": recommendation,
        "selected_commands": selected_commands,
        "results": results,
        "result": validation_result,
        "validation_summary": _validation_summary(results),
        "guardrails": _flow_guardrails(),
        "next_commands": _validation_next_commands(getattr(args, "task_id", None), validation_result),
    }
    if args.write:
        report_path = runtime_dir / "validation" / f"{_safe_name(getattr(args, 'task_id', None))}-{_timestamp_slug()}.json"
        report["report_path"] = str(report_path)
        write_json(report_path, report)
        _write_text(report_path.with_suffix(".md"), _render_validation_flow(report))
        _update_validation_task(runtime_dir, getattr(args, "task_id", None), report, report_path)
    _emit_flow(report, args.json, _render_validation_flow)
    return 1 if validation_result in {"FAIL", "BLOCKED"} else 0


def _selected_validation_commands(task: dict[str, Any] | None, recommendation: dict[str, Any]) -> list[str]:
    commands: list[str] = []
    if task and task.get("validation"):
        commands.extend(_validation_commands(str(task.get("validation"))))
    commands.extend(item["command"] for item in recommendation["commands"])
    return list(dict.fromkeys(command for command in commands if command))


def _validation_execution_policy(args: Namespace) -> str:
    if args.execute:
        return "execute selected allowlisted validation commands and record fresh results"
    return "dry-run preview only; commands are not executed without --execute"


def _dry_validation_result(command: str) -> dict[str, Any]:
    return {
        "command": command,
        "result": "SKIPPED",
        "exit_code": None,
        "duration_seconds": 0.0,
        "stdout_tail": "",
        "stderr_tail": "",
        "note": "dry-run preview; pass --execute to run",
    }


def _execute_validation_command(root: Path, command: str, timeout_seconds: int) -> dict[str, Any]:
    started = time.monotonic()
    allowed, reason = _is_allowed_validation_command(command)
    if not allowed:
        return {
            "command": command,
            "result": "BLOCKED",
            "exit_code": None,
            "duration_seconds": 0.0,
            "stdout_tail": "",
            "stderr_tail": "",
            "note": reason,
        }
    try:
        proc = subprocess.run(
            _command_argv(command),
            cwd=root,
            env=_command_env(command),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_seconds,
            check=False,
        )
    except FileNotFoundError as exc:
        duration = round(time.monotonic() - started, 3)
        return {
            "command": command,
            "result": "BLOCKED",
            "exit_code": None,
            "duration_seconds": duration,
            "stdout_tail": "",
            "stderr_tail": str(exc),
            "note": "validation executable not found",
        }
    except subprocess.TimeoutExpired as exc:
        duration = round(time.monotonic() - started, 3)
        return {
            "command": command,
            "result": "BLOCKED",
            "exit_code": None,
            "duration_seconds": duration,
            "stdout_tail": _tail(exc.stdout or ""),
            "stderr_tail": _tail(exc.stderr or ""),
            "note": f"timed out after {timeout_seconds}s",
        }
    duration = round(time.monotonic() - started, 3)
    return {
        "command": command,
        "result": "PASS" if proc.returncode == 0 else "FAIL",
        "exit_code": proc.returncode,
        "duration_seconds": duration,
        "stdout_tail": _tail(proc.stdout),
        "stderr_tail": _tail(proc.stderr),
        "note": "",
    }


def _is_allowed_validation_command(command: str) -> tuple[bool, str]:
    blocked_chars = (";", "\n", "||", "|", ">", "<", "`", "$(", "${")
    if any(token in command for token in blocked_chars):
        return False, "blocked shell metacharacter in validation command"
    if "&&" in command and not (command.startswith("cd core && cargo ") and command.count("&&") == 1):
        return False, "blocked shell command chain in validation command"
    allowed_prefixes = (
        "PYTHONDONTWRITEBYTECODE=1 python3 -m compileall ",
        "PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile ",
        "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest ",
        "python3 -m compileall ",
        "python3 -m py_compile ",
        "python3 -m unittest ",
        "cd core && cargo ",
        "xcodebuild -project apps/macos/AreaMatrix.xcodeproj ",
    )
    if command.startswith("./dev "):
        return _is_allowed_dev_validation_command(command)
    if not command.startswith(allowed_prefixes):
        return False, "command is outside the Codex OS validation allowlist"
    return True, ""


def _is_allowed_dev_validation_command(command: str) -> tuple[bool, str]:
    argv = shlex.split(command)
    allowed = False
    if len(argv) >= 3 and argv[:2] == ["./dev", "check"]:
        allowed = True
    elif argv == ["./dev", "test", "macos"] or (len(argv) > 3 and argv[:3] == ["./dev", "test", "macos"]):
        allowed = True
    elif argv == ["./dev", "workflow", "doctor"]:
        allowed = True
    elif len(argv) >= 5 and argv[:3] == ["./dev", "workflow", "discuss"] and argv[-1] == "doctor":
        allowed = True
    return (True, "") if allowed else (False, "only read-only ./dev validation commands are allowed")


def _command_env(command: str) -> dict[str, str]:
    env = dict(os.environ)
    if command.startswith("PYTHONDONTWRITEBYTECODE=1 "):
        env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def _command_argv(command: str) -> list[str]:
    text = command
    if text.startswith("PYTHONDONTWRITEBYTECODE=1 "):
        text = text[len("PYTHONDONTWRITEBYTECODE=1 ") :]
    if text.startswith("cd core && "):
        return ["bash", "-lc", text]
    return shlex.split(text)


def _tail(text: str, *, limit: int = 4000) -> str:
    return text[-limit:] if len(text) > limit else text


def _aggregate_validation_results(results: list[dict[str, Any]], *, executed: bool) -> str:
    if not executed:
        return "NOT-READY"
    if any(item["result"] == "BLOCKED" for item in results):
        return "BLOCKED"
    if any(item["result"] == "FAIL" for item in results):
        return "FAIL"
    return "PASS"


def _validation_summary(results: list[dict[str, Any]]) -> str:
    parts = [f"{item['command']}: {item['result']}" for item in results]
    return "; ".join(parts)


def _validation_next_commands(task_id: str | None, result: str) -> list[str]:
    if not task_id:
        return ["./dev codex-os repair-plan --changed"]
    if result == "PASS":
        return [f"./dev codex-os close-flow --task-id {task_id} --status Done --validation '<fresh result>' --write"]
    return [f"./dev codex-os repair-plan --task-id {task_id} --changed"]


def _update_validation_task(runtime_dir: Path, task_id: str | None, report: dict[str, Any], report_path: Path) -> None:
    if not task_id:
        return
    status = {
        "PASS": "Pass",
        "FAIL": "Fail",
        "BLOCKED": "Blocked",
        "NOT-READY": "Not-Ready",
    }[report["result"]]
    updates = {
        "validation": report["validation_summary"],
        "validation_status": status,
        "automation_scope": "validation-run" if report["execute"] else "observe-only",
        "next_action": "; ".join(report["next_commands"]),
        "validation_report_file": relative_to_root(runtime_dir.parent.parent.parent, report_path),
    }
    update_task_reference(runtime_dir, task_id, updates)


def _render_validation_flow(data: dict[str, Any]) -> str:
    lines = _flow_header("Codex OS run validation", data)
    lines.append(f"- execution_policy: {data['execution_policy']}")
    if data.get("report_path"):
        lines.append(f"- report_path: {data['report_path']}")
    lines.append("")
    lines.append("Selected Commands")
    lines.append("")
    lines.extend(f"- `{command}`" for command in data["selected_commands"]) if data["selected_commands"] else lines.append("- none")
    lines.append("")
    lines.append("Results")
    lines.append("")
    for item in data["results"]:
        lines.append(f"- {item['result']}: `{item['command']}` ({item['exit_code']}) {item.get('note', '')}".rstrip())
    _append_named_list(lines, "Warnings", data["recommendation"].get("warnings", []))
    _append_named_list(lines, "Next Commands", data["next_commands"], code=True)
    return "\n".join(lines).rstrip() + "\n"


def run_repair_plan_flow(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    diagnose_args = _namespace_for_flow(args, changed=getattr(args, "changed", False), path=getattr(args, "path", []) or [])
    diagnosis = _diagnose_data(root, diagnose_args, runtime_dir)
    validation_report = _load_validation_report(root, runtime_dir, getattr(args, "validation_report", None))
    steps = _repair_steps(diagnosis, validation_report)
    data = {
        "generated_at": iso_now(),
        "flow": "repair-plan",
        "task_id": getattr(args, "task_id", None),
        "result": "READY" if steps else "NO-ACTION",
        "policy": "read-only repair planning; no files are modified",
        "diagnosis": diagnosis,
        "validation_report": validation_report,
        "steps": steps,
        "guardrails": _flow_guardrails(),
    }
    if args.write:
        write_json(runtime_dir / "repair-plan.json", data)
        _write_text(runtime_dir / "repair-plan.md", _render_repair_plan_flow(data))
    _emit_flow(data, args.json, _render_repair_plan_flow)
    return 0


def _load_validation_report(root: Path, runtime_dir: Path, explicit: str | None) -> dict[str, Any] | None:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_absolute():
            path = root / path
        if not path.is_file():
            raise ToolError(f"validation report not found: {path}", code=1)
        return json.loads(path.read_text(encoding="utf-8"))
    reports = sorted((runtime_dir / "validation").glob("*.json"), key=lambda item: item.stat().st_mtime, reverse=True)
    if not reports:
        return None
    return json.loads(reports[0].read_text(encoding="utf-8"))


def _repair_steps(diagnosis: dict[str, Any], validation_report: dict[str, Any] | None) -> list[dict[str, str]]:
    steps: list[dict[str, str]] = []
    for item in diagnosis["registry_audit"]["issues"]:
        message = item["message"]
        if "missing granted confirmation" in message:
            steps.append(_repair_step("manual-confirmation", item.get("severity", "FAIL"), "Record explicit impact, risk, validation, and rollback confirmation before writes."))
        elif "does not exist" in message:
            steps.append(_repair_step("missing-reference", item.get("severity", "WARN"), f"Regenerate or correct the referenced file: {message}"))
        elif "no evidence" in message or "no closeout" in message:
            steps.append(_repair_step("missing-evidence", item.get("severity", "WARN"), "Run close-flow with fresh validation and write evidence/closeout references."))
        else:
            steps.append(_repair_step("registry", item.get("severity", "WARN"), message))
    for warning in diagnosis.get("task_warnings", []):
        steps.append(_repair_step("task-lifecycle", "WARN", warning))
    for item in diagnosis.get("manual_confirmations", []):
        steps.append(_repair_step("manual-confirmation", "FAIL", item))
    if validation_report:
        for result in validation_report.get("results", []):
            if result.get("result") in {"FAIL", "BLOCKED"}:
                steps.append(_repair_step("validation", result["result"], f"Inspect `{result['command']}`: {result.get('note') or 'non-zero validation result'}"))
    if not steps and diagnosis["result"] != "OK":
        steps.append(_repair_step("diagnose", diagnosis["result"], "Review diagnose output and rerun start-flow after correction."))
    return steps


def _repair_step(category: str, severity: str, action: str) -> dict[str, str]:
    return {"category": category, "severity": severity, "action": action}


def _render_repair_plan_flow(data: dict[str, Any]) -> str:
    lines = _flow_header("Codex OS repair plan", data)
    lines.append(f"- policy: {data['policy']}")
    lines.append("")
    lines.append("Diagnosis")
    lines.append("")
    lines.append(f"- result: {data['diagnosis']['result']}")
    lines.append(f"- registry_audit: {data['diagnosis']['registry_audit']['result']}")
    lines.append("")
    lines.append("Repair Steps")
    lines.append("")
    if data["steps"]:
        for index, step in enumerate(data["steps"], start=1):
            lines.append(f"{index}. {step['severity']} / {step['category']}: {step['action']}")
    else:
        lines.append("- none")
    return "\n".join(lines).rstrip() + "\n"


def run_close_flow(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    registry = require_registry(runtime_dir)
    task = find_task(registry, args.task_id)
    if task is None:
        raise ToolError(f"task not found: {args.task_id}", code=1)
    validation_summary = args.validation or task.get("validation")
    evidence_path = args.evidence_file or task.get("evidence_file")
    closeout_path = args.closeout_file or task.get("closeout_file")
    created_files: dict[str, str] = {}
    preview_task = dict(task)
    _validate_close_flow_gate(task, args, validation_summary)
    if args.write and args.status == "Done":
        evidence_path = evidence_path or _write_flow_template(root, runtime_dir, "evidence", args.task_id)
        closeout_path = closeout_path or _write_flow_template(root, runtime_dir, "closeout", args.task_id)
        created_files = {"evidence_file": evidence_path, "closeout_file": closeout_path}
    closeout_args = _namespace_for_flow(
        args,
        evidence_file=evidence_path,
        closeout_file=closeout_path,
        validation=validation_summary,
    )
    _validate_close_flow(root, task, closeout_args)
    updates = _close_flow_updates(closeout_args, validation_summary, evidence_path, closeout_path)
    preview_task.update({key: value for key, value in updates.items() if value is not None})
    preview_task["updated_at"] = iso_now()
    result = "UPDATED" if args.write else "PREVIEW"
    registry_path_value = ""
    if args.write:
        apply_task_updates(task, updates)
        registry_path_value = str(_write_task_registry(runtime_dir, registry))
    data = {
        "generated_at": iso_now(),
        "flow": "close-flow",
        "task_id": args.task_id,
        "status": args.status,
        "write": args.write,
        "result": result,
        "registry_path": registry_path_value,
        "created_files": created_files,
        "task": preview_task,
        "warnings": _close_flow_warnings(args),
        "guardrails": _flow_guardrails(),
        "next_commands": _close_flow_next_commands(args.task_id, args.status),
    }
    if args.write:
        write_json(runtime_dir / "close-flow.json", data)
        _write_text(runtime_dir / "close-flow.md", _render_close_flow(data))
    _emit_flow(data, args.json, _render_close_flow)
    return 0


def _validate_close_flow_gate(task: dict[str, Any], args: Namespace, validation: str | None) -> None:
    if args.status == "Done" and not args.validation:
        raise ToolError("close-flow --status Done requires explicit fresh --validation", code=1)
    if args.status == "Done" and not _looks_like_fresh_pass_validation(args.validation):
        raise ToolError("close-flow --status Done requires a fresh PASS/OK validation summary, not dry-run or recommendation output", code=1)
    if args.status == "Blocked" and not (args.next_action or task.get("next_action") or args.handoff_file or task.get("handoff_file")):
        raise ToolError("close-flow --status Blocked requires --next-action or handoff file", code=1)


def _looks_like_fresh_pass_validation(value: str | None) -> bool:
    if not value:
        return False
    upper = value.upper()
    blocked_markers = ("SKIPPED", "NOT-READY", "NOT READY", "RECOMMENDED", "DRY-RUN", "DRY RUN", "FAIL", "BLOCKED")
    if any(marker in upper for marker in blocked_markers):
        return False
    return "PASS" in upper or "OK" in upper


def _write_flow_template(root: Path, runtime_dir: Path, key: str, task_id: str) -> str:
    template = root / ".codex/templates" / f"codex-{key}-template.md"
    text = template.read_text(encoding="utf-8") if template.is_file() else f"Task ID: <task-id>\n"
    text = text.replace("<task-id>", task_id)
    path = runtime_dir / key / f"{_safe_name(task_id)}-{_timestamp_slug()}.md"
    _write_text(path, text)
    return relative_to_root(root, path)


def _validate_close_flow(root: Path, task: dict[str, Any], args: Namespace) -> None:
    validation = args.validation or task.get("validation")
    evidence = args.evidence_file or args.closeout_file or args.evidence_note or args.closeout_note
    evidence = evidence or task.get("evidence_file") or task.get("closeout_file") or task.get("evidence_note") or task.get("closeout_note")
    if args.status == "Done" and not validation:
        raise ToolError("close-flow --status Done requires --validation or existing validation", code=1)
    if args.status == "Done" and not evidence:
        raise ToolError("close-flow --status Done requires evidence or closeout reference", code=1)
    if args.status == "Blocked" and not (args.next_action or task.get("next_action") or args.handoff_file or task.get("handoff_file")):
        raise ToolError("close-flow --status Blocked requires --next-action or handoff file", code=1)
    for key in ("evidence_file", "closeout_file", "handoff_file"):
        value = getattr(args, key, None)
        if value and not _relative_path_exists(root, value):
            raise ToolError(f"{key.replace('_', '-')} does not exist: {value}", code=1)


def _close_flow_updates(args: Namespace, validation: str | None, evidence_file: str | None, closeout_file: str | None) -> dict[str, Any]:
    validation_status = args.validation_status
    if validation_status is None:
        validation_status = "Pass" if args.status == "Done" else "Blocked" if args.status == "Blocked" else None
    return {
        "status": args.status,
        "validation": validation,
        "validation_status": validation_status,
        "handoff_file": args.handoff_file,
        "evidence_file": evidence_file,
        "closeout_file": closeout_file,
        "evidence_note": args.evidence_note,
        "closeout_note": args.closeout_note,
        "next_action": args.next_action,
        "archive_recommendation": args.archive_recommendation,
        "automation_scope": "registry-write" if args.write else "observe-only",
        "finished_at": iso_now(),
    }


def _close_flow_warnings(args: Namespace) -> list[str]:
    warnings: list[str] = []
    if args.archive_recommendation == "archive":
        warnings.append("Archive recommendation is advisory; no Codex thread is archived.")
    if args.status == "Done" and args.validation_status in {"Skipped", "Blocked", "Not-Ready", "Fail"}:
        warnings.append("Done status paired with non-pass validation status; review before relying on this registry entry.")
    return warnings


def _close_flow_next_commands(task_id: str, status: str) -> list[str]:
    if status == "Done":
        return ["./dev codex-os ops-flow --write"]
    if status == "Blocked":
        return [f"./dev codex-os repair-plan --task-id {task_id}", f"./dev codex-os resume --task-id {task_id}"]
    return [f"./dev codex-os lifecycle --task-id {task_id}"]


def _render_close_flow(data: dict[str, Any]) -> str:
    lines = _flow_header("Codex OS close flow", data)
    if data.get("registry_path"):
        lines.append(f"- registry: {data['registry_path']}")
    lines.append("")
    lines.append("Task")
    lines.append("")
    lines.append(render_task_detail(data["task"]).rstrip())
    if data["created_files"]:
        lines.append("")
        lines.append("Created Files")
        lines.append("")
        for key, value in data["created_files"].items():
            lines.append(f"- {key}: `{value}`")
    _append_named_list(lines, "Warnings", data["warnings"])
    _append_named_list(lines, "Next Commands", data["next_commands"], code=True)
    return "\n".join(lines).rstrip() + "\n"


def run_ops_flow(root: Path, args: Namespace) -> int:
    runtime_dir = _runtime_dir_from_args(root, args)
    snapshot = build_snapshot(_state_db_from_args(args), project=args.project)
    audit = registry_audit(root, runtime_dir)
    archive = _archive_review_data(snapshot, args.limit)
    titles = _title_suggestions_data(snapshot, args.limit)
    weekly = {
        "generated_at": iso_now(),
        "thread_summary": {
            "total_threads": snapshot["total_threads"],
            "unarchived_threads": snapshot["unarchived_threads"],
            "bucket_counts": snapshot["bucket_counts"],
        },
        "task_counts": _task_counts(load_registry(runtime_dir)),
        "registry_audit": audit,
        "recommended_actions": _weekly_actions(snapshot, audit),
    }
    health = _health_score(snapshot, audit)
    data = {
        "generated_at": iso_now(),
        "flow": "ops-flow",
        "result": health["status"] if audit["result"] != "FAIL" else "FAIL",
        "write": args.write,
        "policy": "advisory operations only; no archive, title, workflow, or SQLite mutation is performed",
        "archive_review": archive,
        "title_suggestions": titles,
        "weekly": weekly,
        "health_score": health,
        "registry_audit": audit,
        "guardrails": _flow_guardrails(),
    }
    if args.write:
        write_json(runtime_dir / "ops-flow.json", data)
        _write_text(runtime_dir / "ops-flow.md", _render_ops_flow(data))
    _emit_flow(data, args.json, _render_ops_flow)
    return 1 if args.strict and data["result"] == "FAIL" else 0


def _title_suggestions_data(snapshot: dict[str, Any], limit: int) -> dict[str, Any]:
    rows = []
    for item in snapshot["threads"]:
        if item.thread.archived or item.bucket not in {"Archive Candidate", "Risk Review", "Cold", "Warm"}:
            continue
        rows.append(_title_suggestion(item))
        if len(rows) >= limit:
            break
    return {"generated_at": iso_now(), "policy": "suggestions only; no thread title is changed", "suggestions": rows}


def _render_ops_flow(data: dict[str, Any]) -> str:
    lines = _flow_header("Codex OS ops flow", data)
    lines.append(f"- policy: {data['policy']}")
    lines.append("")
    lines.append("Health")
    lines.append("")
    lines.append(f"- score: {data['health_score']['score']}")
    lines.append(f"- status: {data['health_score']['status']}")
    lines.append(f"- registry_audit: {data['registry_audit']['result']}")
    lines.append("")
    lines.append("Threads")
    lines.append("")
    for key, value in data["weekly"]["thread_summary"]["bucket_counts"].items():
        lines.append(f"- {key}: {value}")
    lines.append("")
    lines.append("Advisory Counts")
    lines.append("")
    lines.append(f"- archive_candidates: {len(data['archive_review']['archive_candidates'])}")
    lines.append(f"- risk_review: {len(data['archive_review']['risk_review'])}")
    lines.append(f"- title_suggestions: {len(data['title_suggestions']['suggestions'])}")
    _append_named_list(lines, "Recommended Actions", data["weekly"]["recommended_actions"])
    return "\n".join(lines).rstrip() + "\n"


def _flow_header(title: str, data: dict[str, Any]) -> list[str]:
    return [
        title,
        "",
        f"- generated_at: {data['generated_at']}",
        f"- flow: {data['flow']}",
        f"- task_id: {data.get('task_id') or '(none)'}",
        f"- result: {data['result']}",
        f"- write: {data.get('write', False)}",
    ]


def _append_named_list(lines: list[str], title: str, items: list[str], *, code: bool = False) -> None:
    if not items:
        return
    lines.append("")
    lines.append(title)
    lines.append("")
    for item in items:
        text = f"`{item}`" if code else item
        lines.append(f"- {text}")
