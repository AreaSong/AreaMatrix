#!/usr/bin/env python3
"""Create the immutable input snapshot and resumable coverage ledger for this audit."""

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


ROOT = Path(__file__).resolve().parents[3]
AUDIT_DIR = Path(__file__).resolve().parent
AUDIT_ID = "dependency-supply-chain-audit-20260820"
AUDIT_PREFIX = f".codex/runtime/{AUDIT_ID}/"
START_COMMIT = "cf3647378d64885e8e6a44a2a5b60d8926668982"
INITIAL_UNTRACKED = {
    "apps/windows/AreaMatrixTests/Architecture/ViewModelSynchronizationContextTests.cs",
}


def git_bytes(*args: str) -> bytes:
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout


def decode_path(raw: bytes) -> str:
    return raw.decode("utf-8", errors="surrogateescape")


def nul_paths(*args: str) -> list[str]:
    output = git_bytes(*args)
    return [decode_path(item) for item in output.split(b"\0") if item]


def status_snapshot() -> tuple[list[dict[str, str]], dict[str, str]]:
    records: list[dict[str, str]] = []
    by_path: dict[str, str] = {}
    items = git_bytes("status", "--porcelain=v1", "-z", "--untracked-files=all").split(b"\0")
    index = 0
    while index < len(items):
        item = items[index]
        index += 1
        if not item:
            continue
        status_code = item[:2].decode("ascii")
        path = decode_path(item[3:])
        record = {"status": status_code, "path": path}
        if status_code[0] in {"R", "C"} and index < len(items):
            original_path = decode_path(items[index])
            index += 1
            record["original_path"] = original_path
        records.append(record)
        by_path[path] = status_code
    return records, by_path


def hash_regular_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def classify_regular_file(path: Path, size: int) -> tuple[str, str | None, int | None, str | None]:
    mime_hint = mimetypes.guess_type(path.name)[0]
    sample_limit = min(size, 1024 * 1024)
    with path.open("rb") as handle:
        sample = handle.read(sample_limit)
    if not sample:
        return "text", mime_hint or "text/plain", 0, "utf-8"
    if b"\0" in sample:
        return "binary", mime_hint, None, None
    try:
        decoded = sample.decode("utf-8-sig")
    except UnicodeDecodeError:
        return "binary", mime_hint, None, None
    disallowed_controls = sum(
        1 for char in decoded if ord(char) < 32 and char not in "\n\r\t\f\b"
    )
    if disallowed_controls > max(2, len(decoded) // 1000):
        return "binary", mime_hint, None, None
    with path.open("rb") as handle:
        newline_count = 0
        last_byte = b""
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            newline_count += chunk.count(b"\n")
            if chunk:
                last_byte = chunk[-1:]
    line_count = newline_count + (1 if size and last_byte != b"\n" else 0)
    return "text", mime_hint or "text/plain", line_count, "utf-8"


def atomic_write_text(path: Path, content: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)


def jsonl(records: list[dict[str, object]]) -> str:
    return "".join(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n" for record in records)


def main() -> None:
    tracked = set(nul_paths("ls-tree", "-r", "--name-only", "-z", START_COMMIT))
    missing_untracked = [path for path in INITIAL_UNTRACKED if not (ROOT / path).exists()]
    if missing_untracked:
        raise SystemExit(f"initial untracked input disappeared: {missing_untracked}")
    untracked = set(INITIAL_UNTRACKED)
    current_untracked = set(nul_paths("ls-files", "--others", "--exclude-standard", "-z"))
    post_start_untracked = sorted(
        path
        for path in current_untracked - untracked
        if not path.startswith(AUDIT_PREFIX)
    )
    paths = sorted(tracked | untracked)
    dirty_records, dirty_by_path = status_snapshot()
    dirty_records = [record for record in dirty_records if record["path"] in set(paths)]
    dirty_by_path = {path: value for path, value in dirty_by_path.items() if path in set(paths)}
    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")

    inventory: list[dict[str, object]] = []
    coverage: list[dict[str, object]] = []
    kinds: Counter[str] = Counter()
    text_lines = 0

    for relative in paths:
        absolute = ROOT / relative
        metadata = absolute.lstat()
        mode = stat.S_IMODE(metadata.st_mode)
        record: dict[str, object] = {
            "audit_id": AUDIT_ID,
            "path": relative,
            "scope_basis": "git_tracked" if relative in tracked else "git_untracked_nonignored",
            "tracked": relative in tracked,
            "git_status": dirty_by_path.get(relative, "  "),
            "mode": format(mode, "04o"),
            "size_bytes": metadata.st_size,
            "status": "PENDING",
            "review_requirement": "line_by_line",
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
            file_type, mime_hint, line_count, encoding = classify_regular_file(absolute, metadata.st_size)
            record.update(
                file_type=file_type,
                sha256=hash_regular_file(absolute),
                line_count=line_count,
                encoding=encoding,
                mime_hint=mime_hint,
            )
            if file_type == "binary":
                record["review_requirement"] = "provenance_generation_packaging"
            elif line_count is not None:
                text_lines += line_count
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

    inventory_content = jsonl(inventory)
    coverage_content = jsonl(coverage)
    atomic_write_text(AUDIT_DIR / "inventory.jsonl", inventory_content)
    atomic_write_text(AUDIT_DIR / "coverage.jsonl", coverage_content)
    inventory_sha256 = hashlib.sha256(inventory_content.encode("utf-8")).hexdigest()

    commit = START_COMMIT
    branch = git_bytes("branch", "--show-current").decode().strip()
    scope = {
        "schema_version": 1,
        "audit_id": AUDIT_ID,
        "generated_at": generated_at,
        "repository_root": str(ROOT),
        "git_commit": commit,
        "git_branch": branch,
        "scope_definition": "当前提交全部 tracked 文件，加审计启动时全部 Git 非忽略 untracked 文件",
        "counts": {
            "repository_file_total": len(paths),
            "tracked": len(tracked),
            "untracked_nonignored": len(untracked),
            "text": kinds["text"],
            "binary": kinds["binary"],
            "symlink": kinds["symlink"],
            "other": kinds["other"],
            "text_line_total": text_lines,
        },
        "inventory_sha256": inventory_sha256,
        "dirty_worktree_at_start": dirty_records,
        "post_start_untracked_excluded": post_start_untracked,
        "excluded_from_repository_file_total": [
            {
                "pattern": ".git/**",
                "basis": "Git 内部数据库，不是仓库提交内容",
            },
            {
                "pattern": ".codex/runtime/dependency-supply-chain-audit-20260820/**",
                "basis": "本次审计自身输出，防止递归改变输入范围",
            },
            {
                "pattern": "Git ignored workspace files",
                "basis": "本机构建、缓存、生成或私有工作状态；仓库内容按 tracked + 非忽略 untracked 冻结",
            },
        ],
        "allowed_statuses": [
            "PENDING",
            "IN_PROGRESS",
            "PASS",
            "FINDING",
            "NOT_APPLICABLE",
            "BLOCKED",
        ],
        "conservation_rule": "repository_file_total = PASS + FINDING + NOT_APPLICABLE + BLOCKED；PENDING/IN_PROGRESS 必须为 0 才可宣称完成",
    }
    atomic_write_text(
        AUDIT_DIR / "scope.json",
        json.dumps(scope, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    )

    for name in ("dependency-ledger.jsonl", "license-ledger.jsonl", "findings.jsonl"):
        atomic_write_text(AUDIT_DIR / name, "")

    notes = f"""# 依赖、许可证与供应链审计记录

## 启动快照

- 审计 ID：`{AUDIT_ID}`
- 冻结时间：`{generated_at}`
- Git commit：`{commit}`
- 分支：`{branch}`
- 范围文件：`{len(paths)}`（tracked `{len(tracked)}`，非忽略 untracked `{len(untracked)}`）
- 分类：文本 `{kinds['text']}`，二进制 `{kinds['binary']}`，符号链接 `{kinds['symlink']}`，其他 `{kinds['other']}`
- 文本总行数：`{text_lines}`
- 工作树在审计启动前已有改动，完整列表见 `scope.json`；审计不覆盖、不撤销这些改动。

## 已读取的权威规则

- 根目录及 `core/`、`apps/macos/`、`workflow/` 的 `AGENTS.md`
- `.agents/skills/areamatrix-enterprise-governance/SKILL.md` 及其治理参考
- `CODE_REVIEW.md`、`SECURITY.md`
- `docs/development/dependency-policy.md`、`docs/development/ci-governance.md`
- `LICENSE`、`COMMERCIAL_LICENSE.md`
- `docs/development/build.md`、`docs/development/release.md`
- 品牌资产 README 与生成说明

## 当前状态

清单已冻结，所有文件初始为 `PENDING`。尚未运行测试、依赖扫描、安装、更新或未知脚本。
"""
    atomic_write_text(AUDIT_DIR / "review-notes.md", notes)
    report = """# AreaMatrix 全仓依赖、许可证与供应链审计

> 状态：IN_PROGRESS。此文件是可恢复的报告骨架；覆盖守恒前不得视为最终审计结论。

## Findings

尚未完成逐文件审阅和主代理复核。

## 覆盖与守恒

待完成。

## 依赖与许可证

待完成。

## 外部证据缺口

待完成。
"""
    atomic_write_text(AUDIT_DIR / "final-report.md", report)


if __name__ == "__main__":
    main()
