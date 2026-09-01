#!/usr/bin/env python3
"""Freeze the repository scope and initialize the docs/API/bridge audit ledger."""

from __future__ import annotations

import hashlib
import json
import mimetypes
import os
import stat
import subprocess
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AUDIT_DIR = Path(__file__).resolve().parent
AUDIT_ID = "docs-api-bridge-drift-audit-20260820"
AUDIT_PREFIX = f".codex/runtime/{AUDIT_ID}/"
VALID_STATUSES = [
    "PENDING",
    "IN_PROGRESS",
    "PASS",
    "FINDING",
    "NOT_APPLICABLE",
    "BLOCKED",
]


def git_paths(*args: str) -> list[str]:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [item.decode("utf-8", "surrogateescape") for item in result.stdout.split(b"\0") if item]


def git_text(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return result.stdout


def sha256(path: Path) -> str:
    if path.is_symlink():
        return hashlib.sha256(os.fsencode(os.readlink(path))).hexdigest()
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def classify(path: Path) -> tuple[str, str | None, int | None, str | None, str]:
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode):
        return "symlink", None, None, None, os.readlink(path)
    if not stat.S_ISREG(metadata.st_mode):
        return "other", None, None, None, ""

    mime = mimetypes.guess_type(path.name)[0]
    size = metadata.st_size
    with path.open("rb") as handle:
        sample = handle.read(min(size, 1024 * 1024))
    if b"\0" in sample:
        return "binary", mime, None, None, ""
    try:
        sample.decode("utf-8-sig")
    except UnicodeDecodeError:
        return "binary", mime, None, None, ""

    newline_count = 0
    last = b""
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            newline_count += chunk.count(b"\n")
            if chunk:
                last = chunk[-1:]
    line_count = newline_count + (1 if size and last != b"\n" else 0)
    return "text", mime or "text/plain", line_count, "utf-8", ""


def dirty_paths() -> dict[str, str]:
    raw = git_text("status", "--porcelain=v1", "-z", "--untracked-files=all").encode()
    records = raw.split(b"\0")
    result: dict[str, str] = {}
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue
        status = record[:2].decode("ascii", "replace")
        path = record[3:].decode("utf-8", "surrogateescape")
        result[path] = status
        if status[0] in {"R", "C"} and index < len(records):
            index += 1
    return result


def main() -> None:
    tracked = set(git_paths("ls-files", "-z"))
    untracked = {
        path
        for path in git_paths("ls-files", "--others", "--exclude-standard", "-z")
        if not path.startswith(AUDIT_PREFIX)
    }
    paths = sorted(tracked | untracked)
    dirty = dirty_paths()
    timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
    inventory: list[dict[str, object]] = []
    coverage: list[dict[str, object]] = []
    counts = {"tracked": len(tracked), "untracked_nonignored": len(untracked)}
    type_counts: dict[str, int] = {}
    text_lines = 0

    for relative in paths:
        absolute = ROOT / relative
        file_type, mime, line_count, encoding, link_target = classify(absolute)
        type_counts[file_type] = type_counts.get(file_type, 0) + 1
        if line_count is not None:
            text_lines += line_count
        record: dict[str, object] = {
            "audit_id": AUDIT_ID,
            "path": relative,
            "scope_basis": "git_tracked" if relative in tracked else "git_untracked_nonignored",
            "tracked": relative in tracked,
            "git_status_at_start": dirty.get(relative, "  "),
            "file_type": file_type,
            "mime_hint": mime,
            "line_count": line_count,
            "encoding": encoding,
            "size_bytes": absolute.lstat().st_size,
            "sha256": sha256(absolute) if file_type != "other" else None,
            "symlink_target": link_target or None,
            "source_fact_layer": None,
            "role": None,
            "generated_source": None,
            "generator": None,
            "generator_command": None,
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
        }
        inventory.append(record)
        coverage.append(
            {
                "audit_id": AUDIT_ID,
                "path": relative,
                "status": "PENDING",
                "reviewer": None,
                "reviewer_role": None,
                "started_at": None,
                "completed_at": None,
                "reviewed_line_ranges": [],
                "evidence": [],
                "notes": "",
            }
        )

    inventory_text = "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in inventory)
    coverage_text = "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in coverage)
    (AUDIT_DIR / "inventory.jsonl").write_text(inventory_text, encoding="utf-8")
    (AUDIT_DIR / "coverage.jsonl").write_text(coverage_text, encoding="utf-8")

    scope = {
        "schema_version": 1,
        "audit_id": AUDIT_ID,
        "frozen_at": timestamp,
        "repository_root": str(ROOT),
        "snapshot_commit": git_text("rev-parse", "HEAD").strip(),
        "branch": git_text("branch", "--show-current").strip(),
        "scope_definition": "全部 Git tracked 文件 + 冻结时全部 Git 非忽略 untracked 文件",
        "excluded_patterns": [
            {"pattern": ".git/**", "reason": "Git 内部数据库，不是仓库内容"},
            {"pattern": "Git-ignored files", "reason": "本地构建产物、缓存、运行状态或凭据，不属于可审计源文件"},
            {"pattern": f"{AUDIT_PREFIX}**", "reason": "当前审计台账，避免自引用导致范围移动"},
        ],
        "allowed_statuses": VALID_STATUSES,
        "counts": {
            **counts,
            "repository_file_total": len(paths),
            "text": type_counts.get("text", 0),
            "binary": type_counts.get("binary", 0),
            "symlink": type_counts.get("symlink", 0),
            "other": type_counts.get("other", 0),
            "text_line_total": text_lines,
        },
        "dirty_paths_at_start": sorted(path for path in dirty if path in set(paths)),
        "conservation_formula": "repository_file_total = PASS + FINDING + NOT_APPLICABLE + BLOCKED; PENDING/IN_PROGRESS must be zero at closeout",
        "manual_review_rule": "文本逐行阅读；二进制/生成物/锁文件逐项记录来源、生成器、校验和与不逐行原因",
    }
    (AUDIT_DIR / "scope.json").write_text(json.dumps(scope, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(scope["counts"], ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
