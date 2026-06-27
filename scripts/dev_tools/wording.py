"""Long-term source wording audit for AreaMatrix."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from .common import project_root


STRICT_PATHS = (
    "docs",
    "core/src",
    "core/resources",
    "core/benches",
    "core/Cargo.toml",
    "core/area_matrix.udl",
    "README.md",
    "README.zh-CN.md",
)

POLICY_PATHS = (
    "AGENTS.md",
    "core/AGENTS.md",
    ".ai-governance",
    ".codex/skills-src",
)

TEST_PATHS = ("core/tests",)

ARCHIVED_EVIDENCE_TESTS = {
    "core/tests/release_evidence_checklist.rs",
    "core/tests/recovery_scenarios.rs",
}

TEXT_SUFFIXES = {
    "",
    ".c",
    ".h",
    ".json",
    ".md",
    ".py",
    ".rs",
    ".sh",
    ".swift",
    ".toml",
    ".txt",
    ".udl",
    ".yaml",
    ".yml",
}

TERM_RE = re.compile(
    r"\b(?i:stage)[ _-]?[0-9]\b"
    r"|\b(?i:stage)\b"
    r"|\b(?i:phase)[ _-]?[0-9]\b"
    r"|\b(?i:phase)\b"
    r"|\b(?i:mvp)\b"
    r"|(?i:MVP_)"
    r"|\b(?i:v1-mvp)\b"
    r"|\b(?i:local-qa)\b"
    r"|\b(?i:unnotarized)\b"
    r"|\b(?i:prerelease)\b"
    r"|\b(?i:release gate)\b"
    r"|\b(?i:release-gate)\b"
    r"|\b(?i:milestone)\b"
    r"|\b(?i:iteration)\b"
    r"|\b(?i:sprint)\b"
    r"|\b(?i:alpha)\b"
    r"|\b(?i:beta)\b"
    r"|\bC[1-4]-"
    r"|\bc[1-4]-"
    r"|\bS[1-4]-"
    r"|\bs[1-4]-"
    r"|(?i:source)\\?\"\s*:\s*\\?\"[cC][1-4]"
    r"|(?i:area-matrix:[c][1-4]-)"
    r"|本任务"
    r"|对应版本任务"
    r"|任务补齐"
    r"|后续任务"
    r"|页面任务"
    r"|apply 任务"
    r"|任务拆解"
    r"|implementation 任务"
    r"|后续 apply 行为"
    r"|后续清理能力"
    r"|临时\s*mock"
    r"|临时版本"
    r"|临时业务文件"
    r"|临时文件"
    r"|静态占位"
    r"|假数据"
    r"|交付期"
    r"|进入对应阶段"
    r"|核心交付"
    r"|计划交付"
    r"|时间预算"
    r"|第一刀"
    r"|历史任务拆解"
    r"|历史归档"
    r"|能力规格"
    r"|最终验收"
    r"|真实闭环验收"
    r"|阶段",
)


@dataclass(frozen=True)
class WordingHit:
    rel_path: str
    line_no: int
    term: str
    category: str
    reason: str
    line: str


def _relative(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def _iter_files(root: Path, rel_paths: tuple[str, ...]) -> list[Path]:
    files: list[Path] = []
    for rel_path in rel_paths:
        path = root / rel_path
        if path.is_file():
            files.append(path)
            continue
        if not path.is_dir():
            continue
        for child in sorted(path.rglob("*")):
            if child.is_file() and child.suffix in TEXT_SUFFIXES:
                if "core/target" in _relative(root, child):
                    continue
                files.append(child)
    return sorted(set(files))


def _is_policy_path(rel_path: str) -> bool:
    return rel_path == "AGENTS.md" or rel_path == "core/AGENTS.md" or rel_path.startswith(".ai-governance/")


def _is_test_path(rel_path: str) -> bool:
    return rel_path.startswith("core/tests/")


def _is_skill_path(rel_path: str) -> bool:
    return rel_path.startswith(".codex/skills-src/")


def _is_policy_inventory_line(line: str) -> bool:
    inventory_markers = (
        "受控词",
        "不得新引入",
        "不得用",
        "do not introduce",
        "avoid current",
        "execution-period wording",
        "long-term source wording rules",
        "classify remaining hits",
        "do not treat",
        "remaining stage",
    )
    lower_line = line.lower()
    return any(marker.lower() in lower_line for marker in inventory_markers)


def _is_skill_operational_line(line: str) -> bool:
    lower_line = line.lower()
    operation_markers = (
        "workflow/versions/v1-mvp/",
        "workflow/versions/<version>/execution/phase-*",
        "prompt_pipeline.py",
        "./task-loop run --phase",
        "start_from=phase-",
        ".codex/runtime/task-loop/logs/<timestamp>/<phase>/",
        "phase filter",
        "start task or phase",
        "first eligible task in phase order",
        "`--phase`",
        "`phase-",
        "version-local numbering",
        "technical queue complete",
        "prompt task quality",
    )
    return any(marker in lower_line for marker in operation_markers)


def _is_skill_allowed_line(line: str) -> bool:
    return _is_policy_inventory_line(line) or _is_skill_operational_line(line)


def _is_allowed_technical(rel_path: str, term: str, line: str) -> tuple[bool, str]:
    lower_line = line.lower()
    lower_term = term.lower()
    if lower_term == "phase" and "build phase" in lower_line:
        return True, "Xcode Build Phase 技术术语"
    if lower_term == "beta" and ("macos" in lower_line or "apple" in lower_line or "ci beta" in lower_line):
        return True, "Apple/macOS beta 测试语义"
    if term == "阶段" and ("两阶段提交" in line or "两阶段" in line):
        return True, "事务式导入两阶段提交技术语义"
    if term in {"临时业务文件", "临时文件"}:
        return True, "文件安全或系统临时文件技术语义"
    if term == "历史归档" and ("归档" in line and "不代表" in line):
        return True, "中性历史归档导航语义"
    if lower_term in {"alpha", "beta"} and _is_test_path(rel_path):
        return True, "测试 fixture 示例数据"
    return False, ""


def _classify(rel_path: str, line_no: int, term: str, line: str) -> WordingHit:
    if _is_policy_path(rel_path):
        return WordingHit(rel_path, line_no, term, "allowed-policy", "治理或 skill 规则清单需要列出受控词", line)
    if _is_skill_path(rel_path) and _is_skill_allowed_line(line):
        return WordingHit(rel_path, line_no, term, "allowed-policy", "repo-local skill 规则或操作说明需要列出受控词", line)
    if rel_path in ARCHIVED_EVIDENCE_TESTS:
        return WordingHit(rel_path, line_no, term, "allowed-archive-test", "集中历史证据测试，不作为当前命名", line)
    allowed, reason = _is_allowed_technical(rel_path, term, line)
    if allowed:
        return WordingHit(rel_path, line_no, term, "allowed-technical", reason, line)
    if _is_test_path(rel_path):
        return WordingHit(rel_path, line_no, term, "blocked-test", "core/tests 中非集中历史证据命中", line)
    return WordingHit(rel_path, line_no, term, "blocked", "长期源事实不得保留阶段性或执行期口径", line)


def _scan_file(root: Path, path: Path) -> list[WordingHit]:
    rel_path = _relative(root, path)
    hits: list[WordingHit] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        return [WordingHit(rel_path, 0, "", "blocked", f"无法读取文件: {error}", "")]
    for line_no, line in enumerate(text.splitlines(), start=1):
        for match in TERM_RE.finditer(line):
            hits.append(_classify(rel_path, line_no, match.group(0), line.strip()))
    return hits


def audit_wording(root: Path) -> tuple[list[WordingHit], int]:
    files = _iter_files(root, STRICT_PATHS + POLICY_PATHS + TEST_PATHS)
    hits: list[WordingHit] = []
    for path in files:
        hits.extend(_scan_file(root, path))
    return hits, len(files)


def _print_group(label: str, hits: list[WordingHit], *, max_lines: int) -> None:
    if not hits:
        return
    print()
    print(label)
    for hit in hits[:max_lines]:
        print(f"- {hit.rel_path}:{hit.line_no}: `{hit.term}` [{hit.category}] {hit.reason}")
        if hit.line:
            print(f"  {hit.line}")
    if len(hits) > max_lines:
        print(f"- ... {len(hits) - max_lines} more")


def run_wording_audit(root: Path | None = None, args: argparse.Namespace | None = None) -> int:
    root = (root or project_root()).resolve()
    max_lines = getattr(args, "max_lines", 80) if args is not None else 80
    hits, file_count = audit_wording(root)
    blocked = [hit for hit in hits if hit.category.startswith("blocked")]
    allowed = [hit for hit in hits if not hit.category.startswith("blocked")]
    by_category: dict[str, int] = {}
    for hit in hits:
        by_category[hit.category] = by_category.get(hit.category, 0) + 1

    print(f"wording audit: scanned {file_count} file(s)")
    for category in sorted(by_category):
        print(f"- {category}: {by_category[category]}")

    _print_group("Blocked hits", blocked, max_lines=max_lines)
    if getattr(args, "show_allowed", False):
        _print_group("Allowed hits", allowed, max_lines=max_lines)

    if blocked:
        print("wording audit: FAILED", file=sys.stderr)
        return 1
    print("wording audit: PASS")
    return 0
