#!/usr/bin/env python3
"""Merge scope deltas, apply explicit review decisions, and verify audit closure."""

from __future__ import annotations

import fnmatch
import importlib.util
import json
import os
import stat
import subprocess
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


def load_local_module(name: str, filename: str) -> Any:
    path = Path(__file__).resolve().parent / filename
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load audit helper: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


build_ledger = load_local_module("audit_build_ledger", "build-ledger.py")
enrich_inventory = load_local_module("audit_enrich_inventory", "enrich-inventory.py")

AUDIT_ID = build_ledger.AUDIT_ID
AUDIT_PREFIX = build_ledger.AUDIT_PREFIX
ROOT = build_ledger.ROOT
classify = build_ledger.classify
sha256 = build_ledger.sha256
classify_role = enrich_inventory.classify


AUDIT_DIR = Path(__file__).resolve().parent
INVENTORY_PATH = AUDIT_DIR / "inventory.jsonl"
COVERAGE_PATH = AUDIT_DIR / "coverage.jsonl"
SCOPE_PATH = AUDIT_DIR / "scope.json"
DECISIONS_PATH = AUDIT_DIR / "review-decisions.jsonl"
VALID_STATUSES = {
    "PENDING",
    "IN_PROGRESS",
    "PASS",
    "FINDING",
    "NOT_APPLICABLE",
    "BLOCKED",
}


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def git_paths(*args: str) -> list[str]:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [item.decode("utf-8", "surrogateescape") for item in result.stdout.split(b"\0") if item]


def current_paths() -> tuple[set[str], set[str], list[str]]:
    tracked = set(git_paths("ls-files", "-z"))
    untracked = {
        path
        for path in git_paths("ls-files", "--others", "--exclude-standard", "-z")
        if not path.startswith(AUDIT_PREFIX)
    }
    return tracked, untracked, sorted(tracked | untracked)


def inventory_record(path: str, tracked: bool, frozen_at: str) -> dict[str, Any]:
    absolute = ROOT / path
    file_type, mime, line_count, encoding, link_target = classify(absolute)
    record: dict[str, Any] = {
        "audit_id": AUDIT_ID,
        "path": path,
        "scope_basis": "git_tracked" if tracked else "git_untracked_nonignored_scope_delta",
        "tracked": tracked,
        "git_status_at_start": "??" if not tracked else "  ",
        "file_type": file_type,
        "mime_hint": mime,
        "line_count": line_count,
        "encoding": encoding,
        "size_bytes": absolute.lstat().st_size,
        "sha256": sha256(absolute) if file_type != "other" else None,
        "symlink_target": link_target or None,
        "generator_version": None,
        "input_fingerprint": None,
        "review_requirement": (
            "line_by_line"
            if file_type == "text"
            else "provenance_generation_packaging"
            if file_type == "binary"
            else "provenance_and_target"
            if file_type == "symlink"
            else "provenance_and_type"
        ),
        "scope_delta": "added_after_freeze",
        "scope_delta_detected_at": frozen_at,
    }
    record.update(classify_role(path, file_type))
    return record


def refresh_scope(
    inventory: list[dict[str, Any]],
    coverage: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    tracked, untracked, paths = current_paths()
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    inventory_by_path = {row["path"]: row for row in inventory}
    coverage_by_path = {row["path"]: row for row in coverage}
    current = set(paths)
    added: list[str] = []
    removed: list[str] = []
    changed: list[str] = []

    for path in paths:
        row = inventory_by_path.get(path)
        if row is None:
            row = inventory_record(path, path in tracked, now)
            inventory_by_path[path] = row
            coverage_by_path[path] = {
                "audit_id": AUDIT_ID,
                "path": path,
                "status": "PENDING",
                "auditor": None,
                "auditor_role": None,
                "reviewer": None,
                "reviewer_role": None,
                "started_at": None,
                "completed_at": None,
                "reviewed_sha256": None,
                "reviewed_line_ranges": [],
                "evidence": [],
                "notes": "冻结后新增，必须纳入审阅或明确 BLOCKED。",
            }
            added.append(path)
            continue
        absolute = ROOT / path
        current_type, current_mime, current_lines, current_encoding, current_link = classify(absolute)
        current_hash = sha256(absolute) if current_type != "other" else None
        row.update(
            current_file_type=current_type,
            current_mime_hint=current_mime,
            current_line_count=current_lines,
            current_encoding=current_encoding,
            current_size_bytes=absolute.lstat().st_size,
            current_sha256=current_hash,
            current_symlink_target=current_link or None,
        )
        if row.get("sha256") != current_hash:
            row["scope_delta"] = "content_changed_after_freeze"
            row["scope_delta_detected_at"] = now
            changed.append(path)

    for path, row in inventory_by_path.items():
        if path in current:
            continue
        row["scope_delta"] = "removed_after_freeze"
        row["scope_delta_detected_at"] = now
        decision = coverage_by_path[path]
        decision.update(
            status="BLOCKED",
            auditor="root",
            auditor_role="scope_owner",
            reviewer="root",
            reviewer_role="scope_owner",
            started_at=now,
            completed_at=now,
            reviewed_sha256=None,
            reviewed_line_ranges=[],
            evidence=["冻结文件在收口前消失，无法复核当前内容。"],
            notes="removed_after_freeze",
        )
        removed.append(path)

    inventory_rows = [inventory_by_path[path] for path in sorted(inventory_by_path)]
    coverage_rows = [coverage_by_path[path] for path in sorted(coverage_by_path)]
    delta = {
        "checked_at": now,
        "current_tracked": len(tracked),
        "current_untracked_nonignored": len(untracked),
        "current_repository_file_total": len(paths),
        "added_after_freeze": added,
        "removed_after_freeze": removed,
        "content_changed_after_freeze": changed,
    }
    return inventory_rows, coverage_rows, delta


def matches(decision: dict[str, Any], path: str) -> bool:
    exact = decision.get("path")
    pattern = decision.get("pattern")
    if bool(exact) == bool(pattern):
        raise ValueError("each review decision needs exactly one of path or pattern")
    return path == exact if exact else fnmatch.fnmatchcase(path, pattern)


def apply_decisions(
    inventory: list[dict[str, Any]],
    coverage: list[dict[str, Any]],
    decisions: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    inventory_by_path = {row["path"]: row for row in inventory}
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    for decision in decisions:
        status = decision["status"]
        if status not in VALID_STATUSES:
            raise ValueError(f"invalid review status: {status}")
        selected = [row for row in coverage if matches(decision, row["path"])]
        if not selected and not decision.get("allow_empty", False):
            raise ValueError(f"review decision matched no files: {decision}")
        for row in selected:
            inventory_row = inventory_by_path[row["path"]]
            line_count = inventory_row.get("current_line_count", inventory_row.get("line_count"))
            ranges = decision.get("reviewed_line_ranges")
            if ranges == "full":
                ranges = [[1, line_count]] if line_count else []
            row.update(
                status=status,
                auditor=decision.get("auditor"),
                auditor_role=decision.get("auditor_role"),
                reviewer=decision.get("reviewer"),
                reviewer_role=decision.get("reviewer_role"),
                started_at=decision.get("started_at", now),
                completed_at=decision.get("completed_at", now),
                reviewed_sha256=(
                    inventory_row.get("current_sha256", inventory_row.get("sha256"))
                    if decision.get("reviewed_sha256", "current") == "current"
                    else decision.get("reviewed_sha256")
                ),
                reviewed_line_ranges=ranges or [],
                evidence=decision.get("evidence", []),
                notes=decision.get("notes", ""),
            )
    return coverage


def validate(inventory: list[dict[str, Any]], coverage: list[dict[str, Any]]) -> dict[str, Any]:
    inventory_by_path = {row["path"]: row for row in inventory}
    errors: list[str] = []
    statuses = Counter(row["status"] for row in coverage)
    for row in coverage:
        path = row["path"]
        item = inventory_by_path[path]
        status = row["status"]
        if status not in VALID_STATUSES:
            errors.append(f"{path}: invalid status {status}")
            continue
        current_type = item.get("current_file_type", item["file_type"])
        current_hash = item.get("current_sha256", item.get("sha256"))
        line_count = item.get("current_line_count", item.get("line_count"))
        if status in {"PASS", "FINDING", "NOT_APPLICABLE", "BLOCKED"}:
            if not row.get("auditor") or not row.get("reviewer"):
                errors.append(f"{path}: terminal status lacks auditor or reviewer")
            if not row.get("started_at") or not row.get("completed_at"):
                errors.append(f"{path}: terminal status lacks review timestamps")
            if status != "BLOCKED" and row.get("reviewed_sha256") != current_hash:
                errors.append(f"{path}: review hash does not match current content")
        if current_type == "text" and status in {"PASS", "FINDING"}:
            if line_count and row.get("reviewed_line_ranges") != [[1, line_count]]:
                errors.append(f"{path}: text review does not cover exact full range 1-{line_count}")
        if status == "NOT_APPLICABLE":
            if not row.get("evidence") or not row.get("notes"):
                errors.append(f"{path}: NOT_APPLICABLE lacks per-file evidence or rationale")
            if not current_hash:
                errors.append(f"{path}: NOT_APPLICABLE lacks a current per-file hash")
            if current_type == "text" and item.get("role") not in {
                "deterministic_rendered_prompt",
                "tracked_generated_binding",
                "tracked_generated_binding_subset",
                "historical_source_doc",
                "evidence_or_closeout",
                "prior_audit_or_runtime_artifact",
                "lockfile",
            }:
                errors.append(f"{path}: text role {item.get('role')} is not eligible for NOT_APPLICABLE")
        if status == "BLOCKED" and (not row.get("evidence") or not row.get("notes")):
            errors.append(f"{path}: BLOCKED lacks evidence or rationale")
        if current_type == "symlink" and status == "NOT_APPLICABLE":
            target = ROOT / path
            if not target.exists():
                errors.append(f"{path}: symlink target is missing")
    total = len(coverage)
    classified = sum(statuses[name] for name in ("PASS", "FINDING", "NOT_APPLICABLE", "BLOCKED"))
    if total != classified + statuses["PENDING"] + statuses["IN_PROGRESS"]:
        errors.append("coverage status accounting does not conserve total")
    return {
        "repository_file_total": total,
        "status_counts": dict(sorted(statuses.items())),
        "classified_total": classified,
        "pending_or_in_progress": statuses["PENDING"] + statuses["IN_PROGRESS"],
        "conservation_holds": total == sum(statuses.values()),
        "closure_ready": not errors and not statuses["PENDING"] and not statuses["IN_PROGRESS"],
        "errors": errors,
    }


def main() -> int:
    inventory = read_jsonl(INVENTORY_PATH)
    coverage = read_jsonl(COVERAGE_PATH)
    inventory, coverage, delta = refresh_scope(inventory, coverage)
    coverage = apply_decisions(inventory, coverage, read_jsonl(DECISIONS_PATH))
    result = validate(inventory, coverage)
    write_jsonl(INVENTORY_PATH, inventory)
    write_jsonl(COVERAGE_PATH, coverage)
    scope = json.loads(SCOPE_PATH.read_text(encoding="utf-8"))
    scope["scope_delta"] = delta
    scope["closeout"] = result
    SCOPE_PATH.write_text(json.dumps(scope, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["closure_ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
