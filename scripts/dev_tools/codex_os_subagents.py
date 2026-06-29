"""Subagent planning helpers for the Codex OS developer surface."""

from __future__ import annotations

from argparse import Namespace
import json
from pathlib import Path
from typing import Any

from .codex_os_automation import read_git_status_paths, _validate_runtime_dir
from .codex_os_registry import find_task, load_registry, write_json
from .codex_os_state import default_runtime_dir, iso_now
from .common import ToolError


HIGH_RISK_PATH_HINTS = (
    "apps/macos/",
    "core/",
    "core/migrations/",
    "docs/api/",
    "workflow/versions/",
)
CODE_PATH_HINTS = ("scripts/", "core/", "apps/", "dev", "task-loop")
GOVERNANCE_PATH_HINTS = (".codex/", ".ai-governance/", ".github/", "docs/", "workflow/", "tasks/")


def run_subagent_plan(root: Path, args: Namespace) -> int:
    data = build_subagent_plan(root, args)
    runtime_dir = _runtime_dir_from_args(root, args)
    if args.write:
        write_json(runtime_dir / "subagent-plan.json", data)
        print(f"wrote {runtime_dir / 'subagent-plan.json'}")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(render_subagent_plan(data))
    return 0


def build_subagent_plan(root: Path, args: Namespace) -> dict[str, Any]:
    runtime_dir = _runtime_dir_from_args(root, args)
    task = _load_task(runtime_dir, getattr(args, "task_id", None))
    lane = getattr(args, "lane", None) or (task or {}).get("lane") or "Change"
    risk_level = getattr(args, "risk_level", None) or (task or {}).get("risk_level") or _infer_risk(lane, args.path or [])
    paths, git_error = _input_paths(root, args)
    high_risk = lane == "Mission-Critical" or risk_level in {"High", "Mission-Critical"} or _has_high_risk_path(paths)
    should_delegate = lane in {"Change", "Mission-Critical", "Explore", "Review", "Ops"} or high_risk
    roles = _roles_for(lane, paths, high_risk) if should_delegate else []
    return {
        "generated_at": iso_now(),
        "policy": "recommendation only; no subagent is spawned and no write permission is granted",
        "task_id": getattr(args, "task_id", None),
        "task_title": (task or {}).get("title", ""),
        "lane": lane,
        "risk_level": risk_level,
        "input_paths": paths,
        "git_status_error": git_error,
        "subagents_recommended": bool(roles),
        "write_owner": "Main Agent",
        "roles": roles,
        "main_agent_checklist": [
            "Spawn subagents only when the user explicitly requested subagents, delegation, or parallel agent work.",
            "Keep read-only exploration separate from writes; the main agent integrates findings and edits files.",
            "For any writing subagent, declare a disjoint allowed write set and forbidden touches before spawning.",
            "Treat subagent output as input, not as PASS, Done, merge-ready, or closeout evidence.",
            "Run fresh validation after final edits before finish or closeout claims.",
        ],
        "forbidden_touches": [
            "Codex internal SQLite",
            "workflow/versions/<version>/execution/** unless explicitly working on live execution",
            ".codex/runtime/codex-os/** as product source of truth",
            "thread archive/title changes without explicit user confirmation",
            "unrelated dirty worktree changes",
        ],
    }


def _runtime_dir_from_args(root: Path, args: Namespace) -> Path:
    runtime_dir = Path(args.runtime_dir) if getattr(args, "runtime_dir", None) else default_runtime_dir(root)
    _validate_runtime_dir(root, runtime_dir)
    return runtime_dir


def _load_task(runtime_dir: Path, task_id: str | None) -> dict[str, Any] | None:
    if not task_id:
        return None
    registry = load_registry(runtime_dir)
    if registry is None:
        raise ToolError("task registry is missing; run `./dev codex-os registry init --write` first", code=1)
    task = find_task(registry, task_id)
    if task is None:
        raise ToolError(f"task not found: {task_id}", code=1)
    return task


def _input_paths(root: Path, args: Namespace) -> tuple[list[str], str]:
    paths = list(getattr(args, "path", None) or [])
    git_error = ""
    include_changed = getattr(args, "changed", False) or (not paths and not getattr(args, "task_id", None))
    if include_changed:
        changed, git_error = read_git_status_paths(root)
        paths.extend(changed)
    return sorted(dict.fromkeys(path for path in paths if path)), git_error


def _infer_risk(lane: str, paths: list[str]) -> str:
    if lane == "Mission-Critical" or _has_high_risk_path(paths):
        return "High"
    return "Medium" if lane in {"Change", "Review", "Ops"} else "Low"


def _has_high_risk_path(paths: list[str]) -> bool:
    return any(any(path.startswith(hint) for hint in HIGH_RISK_PATH_HINTS) for path in paths)


def _roles_for(lane: str, paths: list[str], high_risk: bool) -> list[dict[str, Any]]:
    roles: list[dict[str, Any]] = []
    if lane in {"Change", "Mission-Critical", "Explore", "Review"} or _has_path_hint(paths, CODE_PATH_HINTS):
        roles.append(_role("Code Explorer", "Trace code paths, call graph, implementation gaps, and regression risks.", paths))
    if lane in {"Change", "Mission-Critical", "Review", "Ops"} or _has_path_hint(paths, GOVERNANCE_PATH_HINTS):
        roles.append(_role("Governance Explorer", "Check AGENTS, docs, governance, skill, workflow, and CI source-of-truth alignment.", paths))
    roles.append(_role("Validation Explorer", "Identify the smallest sufficient fresh validation set and any stale or missing evidence.", paths))
    if high_risk or lane in {"Mission-Critical", "Review"}:
        roles.append(_role("Risk Reviewer", "Review high-risk boundaries, confirmation needs, rollback wording, and forbidden touches.", paths))
    return roles


def _has_path_hint(paths: list[str], hints: tuple[str, ...]) -> bool:
    return any(path == hint or path.startswith(hint) for path in paths for hint in hints)


def _role(name: str, mission: str, paths: list[str]) -> dict[str, Any]:
    path_text = ", ".join(paths[:12]) if paths else "current registered task and related files"
    return {
        "role": name,
        "agent_type": "explorer",
        "mode": "read-only",
        "mission": mission,
        "allowed_actions": [
            "Read files",
            "Run read-only search or inspection commands",
            "Report findings with file paths and line evidence",
        ],
        "forbidden_actions": [
            "Modify files",
            "Stage, commit, push, archive, or rename threads",
            "Write runtime state or workflow execution state",
        ],
        "prompt": (
            f"You are the {name} for an AreaMatrix Codex OS task. "
            f"Work read-only. Focus on: {mission} Scope paths: {path_text}. "
            "Return concise findings, evidence, risks, and recommended next actions."
        ),
    }


def render_subagent_plan(data: dict[str, Any]) -> str:
    lines = ["Codex OS subagent plan", ""]
    lines.append(f"- generated_at: {data['generated_at']}")
    lines.append(f"- policy: {data['policy']}")
    lines.append(f"- task_id: {data.get('task_id') or '(none)'}")
    lines.append(f"- lane: {data['lane']}")
    lines.append(f"- risk_level: {data['risk_level']}")
    lines.append(f"- subagents_recommended: {data['subagents_recommended']}")
    lines.append(f"- write_owner: {data['write_owner']}")
    lines.append("")
    lines.append("Input Paths")
    lines.append("")
    lines.extend(f"- `{path}`" for path in data["input_paths"]) if data["input_paths"] else lines.append("- none")
    lines.append("")
    lines.append("Roles")
    lines.append("")
    if data["roles"]:
        for role in data["roles"]:
            lines.append(f"- {role['role']} ({role['mode']}): {role['mission']}")
    else:
        lines.append("- none; keep the work in the main agent unless risk or ambiguity grows")
    lines.append("")
    lines.append("Main Agent Checklist")
    lines.append("")
    lines.extend(f"- {item}" for item in data["main_agent_checklist"])
    return "\n".join(lines).rstrip() + "\n"
