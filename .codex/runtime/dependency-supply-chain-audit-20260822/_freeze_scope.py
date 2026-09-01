#!/usr/bin/env python3
"""Freeze a reproducible, resumable repository scope for the supply-chain audit."""

from __future__ import annotations

import hashlib
import json
import mimetypes
import os
import stat
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AUDIT = Path(__file__).resolve().parent
AUDIT_ID = "dependency-supply-chain-audit-20260822"
RUNTIME_PREFIX = ".codex/runtime/"
ALLOWED = ["PENDING", "IN_PROGRESS", "PASS", "FINDING", "NOT_APPLICABLE", "BLOCKED"]


def git_bytes(*args: str) -> bytes:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, stdout=subprocess.PIPE
    ).stdout


def paths_from_git(*args: str) -> list[str]:
    return [
        raw.decode("utf-8", errors="surrogateescape")
        for raw in git_bytes(*args).split(b"\0")
        if raw
    ]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def classify(path: Path, size: int) -> tuple[str, str | None, int | None, str | None]:
    with path.open("rb") as stream:
        sample = stream.read(min(size, 1024 * 1024))
    mime = mimetypes.guess_type(path.name)[0]
    if not sample:
        return "text", mime or "text/plain", 0, "utf-8"
    if b"\0" in sample:
        return "binary", mime, None, None
    try:
        decoded = sample.decode("utf-8-sig")
    except UnicodeDecodeError:
        return "binary", mime, None, None
    controls = sum(
        1 for char in decoded if ord(char) < 32 and char not in "\n\r\t\f\b"
    )
    if controls > max(2, len(decoded) // 1000):
        return "binary", mime, None, None
    lines = 0
    last = b""
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            lines += chunk.count(b"\n")
            if chunk:
                last = chunk[-1:]
    if size and last != b"\n":
        lines += 1
    return "text", mime or "text/plain", lines, "utf-8"


def write(path: Path, value: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(value, encoding="utf-8")
    os.replace(temporary, path)


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    write(path, "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows))


def status_snapshot() -> list[dict[str, str]]:
    result = subprocess.run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    rows = []
    for line in result.stdout.splitlines():
        if len(line) >= 3:
            rows.append({"status": line[:2], "path": line[3:]})
    return rows


def main() -> None:
    tracked = set(paths_from_git("ls-files", "-z"))
    all_untracked = set(paths_from_git("ls-files", "--others", "--exclude-standard", "-z"))
    excluded_runtime = sorted(path for path in all_untracked if path.startswith(RUNTIME_PREFIX))
    untracked = all_untracked - set(excluded_runtime)
    paths = sorted(tracked | untracked)
    generated = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    dirty = status_snapshot()
    dirty_by_path = {row["path"]: row["status"] for row in dirty}
    inventory: list[dict[str, object]] = []
    coverage: list[dict[str, object]] = []
    kinds: Counter[str] = Counter()
    text_lines = 0
    for relative in paths:
        absolute = ROOT / relative
        metadata = absolute.lstat()
        record: dict[str, object] = {
            "audit_id": AUDIT_ID,
            "path": relative,
            "scope_basis": "git_tracked" if relative in tracked else "git_untracked_nonignored",
            "tracked": relative in tracked,
            "git_status_at_freeze": dirty_by_path.get(relative, "  "),
            "mode": format(stat.S_IMODE(metadata.st_mode), "04o"),
            "size_bytes": metadata.st_size,
            "status": "PENDING",
        }
        if stat.S_ISLNK(metadata.st_mode):
            target = os.readlink(absolute)
            record.update(
                file_type="symlink",
                symlink_target=target,
                sha256=hashlib.sha256(os.fsencode(target)).hexdigest(),
                line_count=None,
                encoding=None,
                mime_hint=None,
                review_requirement="provenance_and_target",
            )
        elif stat.S_ISREG(metadata.st_mode):
            file_type, mime, lines, encoding = classify(absolute, metadata.st_size)
            record.update(
                file_type=file_type,
                sha256=sha256_file(absolute),
                line_count=lines,
                encoding=encoding,
                mime_hint=mime,
                review_requirement=(
                    "provenance_generation_packaging" if file_type == "binary" else "line_by_line"
                ),
            )
            if file_type == "text" and lines is not None:
                text_lines += lines
        else:
            record.update(
                file_type="other",
                sha256=None,
                line_count=None,
                encoding=None,
                mime_hint=None,
                review_requirement="provenance_and_type",
            )
        kinds[str(record["file_type"])] += 1
        inventory.append(record)
        coverage.append(
            {
                "audit_id": AUDIT_ID,
                "path": relative,
                "status": "PENDING",
                "reviewer": None,
                "started_at": None,
                "completed_at": None,
                "evidence": [],
                "notes": "",
            }
        )
    inventory_jsonl = "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in inventory)
    write(AUDIT / "inventory.jsonl", inventory_jsonl)
    write_jsonl(AUDIT / "coverage.jsonl", coverage)
    for name in ("dependency-ledger.jsonl", "license-ledger.jsonl", "findings.jsonl"):
        write(AUDIT / name, "")
    scope = {
        "schema_version": 2,
        "audit_id": AUDIT_ID,
        "generated_at": generated,
        "repository_root": str(ROOT),
        "git_commit": git_bytes("rev-parse", "HEAD").decode().strip(),
        "git_branch": git_bytes("branch", "--show-current").decode().strip(),
        "scope_definition": "全部 tracked 文件（包括 tracked .codex/runtime/**）+ 冻结时全部非忽略 untracked 文件；仅未跟踪的 .codex/runtime/** 运行时/审计输出为避免递归而排除",
        "counts": {
            "repository_file_total": len(paths),
            "tracked": len(tracked),
            "untracked_nonignored": len(untracked),
            "excluded_runtime_untracked": len(excluded_runtime),
            "text": kinds["text"],
            "binary": kinds["binary"],
            "symlink": kinds["symlink"],
            "other": kinds["other"],
            "text_line_total": text_lines,
        },
        "inventory_sha256": hashlib.sha256(inventory_jsonl.encode()).hexdigest(),
        "dirty_worktree_at_freeze": dirty,
        "excluded_paths": [
            {
                "pattern": ".git/**",
                "basis": "Git 内部数据库，不是仓库提交内容",
            },
            {
                "pattern": "untracked .codex/runtime/**",
                "count": len(excluded_runtime),
                "paths": excluded_runtime,
                "basis": "未跟踪的审计/运行时生成证据；避免当前审计递归纳入自身输出。所有 tracked .codex/runtime/** 文件仍逐项纳入范围",
            },
            {
                "pattern": "Git ignored workspace files",
                "basis": "构建缓存、私有环境和生成目录，未作为仓库提交内容冻结",
            },
        ],
        "allowed_statuses": ALLOWED,
        "conservation_rule": "repository_file_total = PASS + FINDING + NOT_APPLICABLE + BLOCKED；PENDING/IN_PROGRESS 必须为 0 才可宣称完成",
    }
    write(AUDIT / "scope.json", json.dumps(scope, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    write(
        AUDIT / "review-notes.md",
        f"""# 依赖、许可证与供应链审计记录\n\n## 冻结快照\n\n- 审计 ID：`{AUDIT_ID}`\n- 冻结时间：`{generated}`\n- Git commit：`{scope['git_commit']}`\n- 分支：`{scope['git_branch']}`\n- 纳入文件：`{len(paths)}`（tracked `{len(tracked)}`，非忽略 untracked `{len(untracked)}`）\n- 排除未跟踪的 `.codex/runtime/**` 生成证据：`{len(excluded_runtime)}`，完整路径见 `scope.json`；tracked runtime 文件仍在清单中\n- 分类：文本 `{kinds['text']}`，二进制 `{kinds['binary']}`，符号链接 `{kinds['symlink']}`，其他 `{kinds['other']}`\n- 文本总行数：`{text_lines}`\n\n工作树在冻结时已有大量改动；`scope.json` 保存完整状态，审计不覆盖、不撤销这些改动。所有覆盖记录初始为 `PENDING`，后续必须由主代理或指定只读代理写入逐文件证据。\n""",
    )
    write(
        AUDIT / "final-report.md",
        """# AreaMatrix 全仓依赖、许可证与供应链审计\n\n> 状态：IN_PROGRESS。覆盖守恒和逐文件复核完成前，不得视为最终审计结论。\n\n## Findings\n\n待主代理复核。\n\n## 覆盖与守恒\n\n待完成。\n\n## 依赖与许可证\n\n待完成。\n\n## 外部证据缺口\n\n待完成。\n""",
    )


if __name__ == "__main__":
    main()
