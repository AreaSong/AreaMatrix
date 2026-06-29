"""Automation and operations helpers for the Codex OS developer surface."""

from __future__ import annotations

from argparse import Namespace
from collections import Counter
import json
from pathlib import Path
import subprocess
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
    return Path(args.runtime_dir) if args.runtime_dir else default_runtime_dir(root)


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
        return path if path.is_absolute() else root / path
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
    if validation and str(validation).strip().startswith("./") and ";" not in str(validation) and "\n" not in str(validation):
        commands.append(str(validation))
    elif lane == "Quick":
        commands.append("./dev check codex-os")
    elif lane == "Mission-Critical":
        commands.extend(["./dev check codex-os", "./dev check quality"])
    else:
        commands.extend(["./dev check codex-os", "./dev check quality"])
    return commands


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
        add("PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py", "Python developer-tool syntax gate.")
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
