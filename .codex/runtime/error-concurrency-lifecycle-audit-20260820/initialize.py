#!/usr/bin/env python3
"""Freeze the repository input and create the resumable audit ledgers."""

from __future__ import annotations

import hashlib
import json
import mimetypes
import os
import stat
import subprocess
from collections import Counter
from datetime import datetime
from pathlib import Path


AUDIT_ID = "error-concurrency-lifecycle-audit-20260820"
AUDIT_PREFIX = f".codex/runtime/{AUDIT_ID}/"
AUDIT_DIR = Path(__file__).resolve().parent
ROOT = AUDIT_DIR.parents[2]
ALLOWED = ["PENDING", "IN_PROGRESS", "PASS", "FINDING", "NOT_APPLICABLE", "BLOCKED"]
MANIFEST_FIELDS = (
    "audit_id",
    "path",
    "scope_basis",
    "tracked",
    "file_type",
    "size_bytes",
    "sha256",
    "line_count",
    "mime",
    "module",
    "production_path",
    "generated_or_non_text_reason",
    "symlink_target",
)


def git_paths(*args: str) -> list[str]:
    output = subprocess.run(
        ["git", *args], cwd=ROOT, check=True, stdout=subprocess.PIPE
    ).stdout
    return [item.decode("utf-8", "surrogateescape") for item in output.split(b"\0") if item]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_file(path: Path) -> tuple[str, int | None, str | None, str | None]:
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode):
        return "symlink", None, None, os.readlink(path)
    if not stat.S_ISREG(metadata.st_mode):
        return "other", None, None, None
    with path.open("rb") as handle:
        sample = handle.read(1024 * 1024)
    if b"\0" in sample:
        return "binary", None, mimetypes.guess_type(path.name)[0], None
    try:
        sample.decode("utf-8-sig")
    except UnicodeDecodeError:
        return "binary", None, mimetypes.guess_type(path.name)[0], None
    line_count = 0
    last_byte = b""
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            line_count += chunk.count(b"\n")
            if chunk:
                last_byte = chunk[-1:]
    if path.stat().st_size and last_byte != b"\n":
        line_count += 1
    return "text", line_count, mimetypes.guess_type(path.name)[0] or "text/plain", "utf-8"


def module_for(path: str) -> str:
    parts = Path(path).parts
    if not parts:
        return "root"
    if parts[0] == "apps" and len(parts) > 1:
        return "/".join(parts[:2])
    return parts[0]


def production_path(path: str) -> bool:
    source_roots = ("core/", "apps/", "scripts/", "dev", "task-loop")
    return path.startswith(source_roots) or path.startswith(".github/")


def generated_reason(path: str, file_type: str) -> str | None:
    if file_type == "symlink":
        return "符号链接：逐项核对目标，不把链接本身当作独立实现"
    if file_type == "binary":
        return "二进制/资源：记录来源与用途，不存在可逐行阅读的控制流"
    if path.startswith(".codex/runtime/"):
        return "既有审计/运行证据：逐项记录来源，但不进入产品运行路径"
    if "/Bridge/Generated/" in path or "/Bridge/UniFFI/" in path or "Carea_matrixFFI" in path:
        return "生成 FFI/绑定：源事实为 UDL、build.rs 和生成脚本"
    if path.endswith((".lock", "Cargo.lock", "Package.resolved")):
        return "锁文件：解析依赖版本，不含业务控制流"
    if "/copy-ready/" in path or "/verify-ready/" in path:
        return "静态 prompt 产物：源事实为 task/manifest/pipeline"
    return None


def jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def manifest_digest(rows: list[dict[str, object]]) -> str:
    canonical = "\n".join(
        json.dumps(
            {key: row.get(key) for key in MANIFEST_FIELDS},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        for row in sorted(rows, key=lambda item: str(item["path"]))
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def main() -> None:
    tracked = set(git_paths("ls-files", "-z"))
    untracked = set(git_paths("ls-files", "--others", "--exclude-standard", "-z"))
    paths = sorted((tracked | untracked) - {path for path in tracked | untracked if path.startswith(AUDIT_PREFIX)})
    started_at = datetime.now().astimezone().isoformat(timespec="seconds")
    dirty = subprocess.run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.splitlines()

    inventory: list[dict[str, object]] = []
    coverage: list[dict[str, object]] = []
    counts: Counter[str] = Counter()
    line_total = 0
    for relative in paths:
        absolute = ROOT / relative
        file_type, lines, mime, link_target = inspect_file(absolute)
        reason = generated_reason(relative, file_type)
        record: dict[str, object] = {
            "audit_id": AUDIT_ID,
            "path": relative,
            "scope_basis": "git_tracked" if relative in tracked else "git_untracked_nonignored",
            "tracked": relative in tracked,
            "file_type": file_type,
            "size_bytes": absolute.lstat().st_size,
            "sha256": sha256(absolute) if file_type in {"text", "binary"} else None,
            "line_count": lines,
            "mime": mime,
            "module": module_for(relative),
            "production_path": production_path(relative),
            "generated_or_non_text_reason": reason,
            "status": "PENDING",
            "reviewed_ranges": [],
            "reviewer": None,
            "review_started_at": None,
            "review_completed_at": None,
            "entry_points": [],
            "callers": [],
            "callees": [],
            "state_objects": [],
            "notes": "",
        }
        if link_target is not None:
            record["symlink_target"] = link_target
        inventory.append(record)
        coverage.append(
            {
                "audit_id": AUDIT_ID,
                "path": relative,
                "status": "PENDING",
                "reviewer": None,
                "started_at": None,
                "completed_at": None,
                "reviewed_ranges": [],
                "evidence": [],
                "notes": "",
            }
        )
        counts[file_type] += 1
        if lines is not None:
            line_total += lines

    inventory_text = "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in inventory)
    jsonl(AUDIT_DIR / "inventory.jsonl", inventory)
    jsonl(AUDIT_DIR / "coverage.jsonl", coverage)
    for name in (
        "error-contracts.jsonl",
        "concurrency-map.jsonl",
        "cancellation-retry-ledger.jsonl",
        "lifecycle-ledger.jsonl",
        "findings.jsonl",
    ):
        (AUDIT_DIR / name).write_text("", encoding="utf-8")

    scope = {
        "schema_version": 1,
        "audit_id": AUDIT_ID,
        "started_at": started_at,
        "repository_root": str(ROOT),
        "git_commit": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE).stdout.strip(),
        "git_branch": subprocess.run(["git", "branch", "--show-current"], cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE).stdout.strip(),
        "scope_definition": "审计启动时全部 git tracked 文件加全部非忽略 untracked 文件；排除 .git/** 与本审计自身输出",
        "repository_file_total": len(paths),
        "counts": {**dict(counts), "text_line_total": line_total},
        "inventory_manifest_sha256": manifest_digest(inventory),
        "dirty_worktree_at_start": dirty,
        "allowed_statuses": ALLOWED,
        "conservation_rule": "repository_file_total = PASS + FINDING + NOT_APPLICABLE + BLOCKED；PENDING/IN_PROGRESS 必须为 0",
        "excluded": [
            {"pattern": ".git/**", "reason": "Git 内部数据库，不是仓库内容"},
            {"pattern": AUDIT_PREFIX + "**", "reason": "本次台账输出，防止范围自引用"},
            {"pattern": "Git ignored files", "reason": "本机构建缓存/私有运行状态；不属于冻结仓库内容"},
        ],
    }
    (AUDIT_DIR / "scope.json").write_text(json.dumps(scope, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (AUDIT_DIR / "review-notes.md").write_text(
        f"# 全仓错误处理、并发、取消、重试与生命周期审计\n\n"
        f"- 审计 ID：`{AUDIT_ID}`\n- 启动时间：`{started_at}`\n- 冻结文件数：`{len(paths)}`\n"
        f"- 文本文件：`{counts['text']}`，二进制：`{counts['binary']}`，符号链接：`{counts['symlink']}`，其他：`{counts['other']}`\n"
        "- 本轮只读；不修改生产代码、测试、文档、配置、生成绑定或 live queue。\n"
        "- 既有工作树改动保留，详见 `scope.json`。\n\n"
        "## 状态\n\n"
        "台账状态只允许 `PENDING`、`IN_PROGRESS`、`PASS`、`FINDING`、`NOT_APPLICABLE`、`BLOCKED`。\n",
        encoding="utf-8",
    )
    print(json.dumps({"audit_id": AUDIT_ID, "files": len(paths), "counts": counts, "text_lines": line_total}, ensure_ascii=False, default=dict))


if __name__ == "__main__":
    main()
