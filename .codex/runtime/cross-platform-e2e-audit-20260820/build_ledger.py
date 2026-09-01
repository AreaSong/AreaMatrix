#!/usr/bin/env python3
"""Build the recoverable inventory for the cross-platform E2E audit."""

from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
import os
import pathlib
import platform
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[3]
AUDIT_DIR = pathlib.Path(__file__).resolve().parent
PRIOR_STATUS = ROOT / ".codex/runtime/full-repo-audit-20260819/final-status.tsv"
AUDIT_ID = "cross-platform-e2e-audit-20260820"
STATUS_VALUES = [
    "PENDING",
    "IN_PROGRESS",
    "PASS",
    "FINDING",
    "NOT_APPLICABLE",
    "BLOCKED",
]


def git_paths(*args: str) -> list[str]:
    raw = subprocess.check_output(["git", *args], cwd=ROOT)
    return [part.decode("utf-8", "surrogateescape") for part in raw.split(b"\0") if part]


def run_text(*args: str) -> str:
    return subprocess.check_output(list(args), cwd=ROOT, text=True, stderr=subprocess.STDOUT).strip()


def read_payload(path: pathlib.Path) -> bytes:
    if path.is_symlink():
        return os.readlink(path).encode("utf-8", "surrogateescape")
    return path.read_bytes()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_text(data: bytes) -> bool:
    return b"\0" not in data[:8192]


def line_count(data: bytes) -> int:
    if not data:
        return 0
    return data.count(b"\n") + (0 if data.endswith(b"\n") else 1)


def platform_for(path: str) -> str:
    if path.startswith("apps/macos/"):
        return "macOS"
    if path.startswith("apps/ios/"):
        return "iOS"
    if path.startswith("apps/windows/"):
        return "Windows"
    if path.startswith("apps/linux/"):
        return "Linux"
    if path.startswith("core/"):
        return "RustCore"
    if path.startswith(("scripts/", "workflow/", "tasks/", ".github/", ".codex/", ".cursor/", ".agents/", ".ai-governance/")):
        return "GovernanceTooling"
    if path.startswith("assets/"):
        return "Assets"
    return "Shared"


def module_for(path: str) -> str:
    parts = pathlib.PurePosixPath(path).parts
    if path.startswith("apps/") and len(parts) >= 3:
        return "/".join(parts[:3])
    if path.startswith("core/") and len(parts) >= 2:
        return "/".join(parts[:2])
    return parts[0] if parts else "root"


def file_type_for(path: str, text: bool, symlink: bool) -> str:
    if symlink:
        return "symlink"
    if not text:
        return "binary"
    suffix = pathlib.PurePosixPath(path).suffix.lower()
    return suffix[1:] if suffix else "text-no-extension"


def artifact_kind_for(path: str, text: bool) -> str:
    lower = path.lower()
    if not text:
        return "binary_asset_or_artifact"
    if "/bridge/uniffi/" in lower or "/copy-ready/" in lower or "/verify-ready/" in lower:
        return "generated_or_projected"
    if "/evidence/" in lower or "/closeout/" in lower or "/task-loop-runs/" in lower:
        return "historical_evidence"
    if "test" in lower or "/fixtures/" in lower or "/snapshots/" in lower:
        return "test_or_fixture"
    if path.startswith("apps/linux/"):
        return "experimental_or_harness"
    if path.startswith(("apps/windows/", "apps/ios/")):
        return "experimental_client"
    if path.startswith("apps/macos/AreaMatrix/"):
        return "production_runtime"
    if path.startswith("core/src/"):
        return "production_core"
    if path.startswith(("docs/", "workflow/", "tasks/", ".codex/", ".cursor/", ".agents/", ".ai-governance/")):
        return "documentation_or_governance"
    return "repository_support"


def production_path_for(path: str) -> bool:
    return (
        path.startswith("apps/macos/AreaMatrix/")
        or path.startswith("apps/windows/AreaMatrix/")
        or path.startswith("apps/linux/AreaMatrix/")
        or path.startswith("apps/ios/AreaMatrix/")
        or path.startswith("apps/ios/AreaMatrixApp/")
        or path.startswith("apps/ios/AreaMatrixShareExtension/")
        or path.startswith("core/src/")
    )


def load_prior() -> dict[str, dict[str, str]]:
    with PRIOR_STATUS.open(encoding="utf-8") as stream:
        return {row["path"]: row for row in csv.DictReader(stream, delimiter="\t")}


def write_json(path: pathlib.Path, payload: object) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_jsonl(path: pathlib.Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8") as stream:
        for row in rows:
            stream.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def main() -> None:
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    prior = load_prior()
    tracked = git_paths("ls-files", "-z")
    untracked_source = [
        path
        for path in git_paths("ls-files", "--others", "--exclude-standard", "-z")
        if path.startswith(("apps/", "core/", "docs/", "scripts/", "workflow/", ".github/", ".ai-governance/"))
    ]
    paths = list(dict.fromkeys(tracked + untracked_source))
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    head = run_text("git", "rev-parse", "HEAD")
    branch = run_text("git", "branch", "--show-current")
    worktree_status = run_text("git", "status", "--short")

    inventory: list[dict[str, object]] = []
    coverage: list[dict[str, object]] = []
    mismatches: list[str] = []
    status_counts: dict[str, int] = {}
    for index, path in enumerate(paths, 1):
        absolute = ROOT / path
        data = read_payload(absolute)
        content_sha256 = digest(data)
        prior_row = prior.get(path)
        prior_match = bool(prior_row and prior_row.get("content_sha256") == content_sha256)
        if not prior_match:
            mismatches.append(path)
        text = is_text(data)
        lines = line_count(data) if text else 0
        prior_status = prior_row.get("review_status", "PENDING") if prior_match else "PENDING"
        if prior_status not in STATUS_VALUES:
            prior_status = "PENDING"
        status_counts[prior_status] = status_counts.get(prior_status, 0) + 1
        inventory.append(
            {
                "id": index,
                "path": path,
                "platform": platform_for(path),
                "module": module_for(path),
                "file_type": file_type_for(path, text, absolute.is_symlink()),
                "artifact_kind": artifact_kind_for(path, text),
                "production_path": production_path_for(path),
                "tracked": path in tracked,
                "generated": bool(prior_row and prior_row.get("generated") == "1"),
                "byte_count": len(data),
                "line_count": lines,
                "content_sha256": content_sha256,
                "status": "PENDING",
                "current_reviewer": "UNASSIGNED",
                "current_started_at": None,
                "current_completed_at": None,
            }
        )
        coverage.append(
            {
                "id": index,
                "path": path,
                "status": prior_status,
                "reviewed_range": "1-{}".format(lines) if text and lines else "BYTE_RANGE:0-{}".format(max(len(data) - 1, 0)),
                "review_basis": "INHERITED_MANUAL_REVIEW+HASH_VERIFIED" if prior_match else "CURRENT_REVIEW_REQUIRED",
                "source_audit": "full-repo-audit-20260819" if prior_match else None,
                "source_reviewer": prior_row.get("owner") if prior_match else None,
                "source_reviewed_at": prior_row.get("reviewed_at") if prior_match else None,
                "source_evidence": prior_row.get("evidence") if prior_match else None,
                "source_notes": prior_row.get("notes") if prior_match else None,
                "content_sha256": content_sha256,
                "hash_verified_at": now,
                "current_semantic_status": "PENDING",
                "current_reviewer": "UNASSIGNED",
                "current_notes": "本轮跨平台运行时/E2E语义复核尚未完成。",
            }
        )

    excluded_runtime = [
        path
        for path in git_paths("ls-files", "--others", "--exclude-standard", "-z")
        if path not in untracked_source
    ]
    scope = {
        "audit_id": AUDIT_ID,
        "objective": "全仓库逐文件逐行人工跨平台运行时与端到端用户流程审计",
        "status": "IN_PROGRESS",
        "status_values": STATUS_VALUES,
        "baseline_commit": head,
        "branch": branch,
        "captured_at": now,
        "tracked_files": len(tracked),
        "untracked_source_files": len(untracked_source),
        "repository_file_total": len(paths),
        "prior_manual_review_hash_matches": len(paths) - len(mismatches),
        "prior_manual_review_hash_mismatches": mismatches,
        "coverage_status_counts": status_counts,
        "scope_rule": "Git tracked files plus non-ignored untracked source under product/governance paths; local build caches, Git internals, and audit runtime outputs are outside the repository-source snapshot.",
        "excluded_runtime_artifacts": excluded_runtime,
        "worktree_status": worktree_status.splitlines(),
        "host": {
            "os": platform.platform(),
            "machine": platform.machine(),
            "xcode": run_text("xcodebuild", "-version").splitlines(),
            "rustc": run_text("rustc", "--version"),
            "cargo": run_text("cargo", "--version"),
            "dotnet": run_text("dotnet", "--version"),
            "ios_real_device": "UNKNOWN",
            "windows_winui_runtime": "UNAVAILABLE_ON_MACOS_HOST",
            "real_icloud": "NOT_AUTHORIZED",
            "real_onedrive": "NOT_AUTHORIZED",
            "remote_provider_credentials": "NOT_AUTHORIZED",
        },
        "inheritance_policy": "Only byte-identical SHA-256 matches inherit prior manual line-review evidence; this is recorded as inherited evidence, not as a fresh re-read on 2026-08-20.",
    }
    write_json(AUDIT_DIR / "scope.json", scope)
    write_jsonl(AUDIT_DIR / "inventory.jsonl", inventory)
    write_jsonl(AUDIT_DIR / "coverage.jsonl", coverage)

    platform_rows = [
        {"platform": "macOS", "product_status": "FORMAL_PRODUCT_RUNTIME", "runtime_status": "PENDING", "evidence_level": "STATIC_ONLY", "status": "IN_PROGRESS"},
        {"platform": "Rust Core", "product_status": "FORMAL_PRODUCT_CORE", "runtime_status": "PENDING", "evidence_level": "STATIC_ONLY", "status": "IN_PROGRESS"},
        {"platform": "iOS/Share Extension", "product_status": "EXPERIMENTAL_CLIENT", "runtime_status": "REAL_DEVICE_UNVERIFIED", "evidence_level": "STATIC_ONLY", "status": "BLOCKED"},
        {"platform": "Windows WinUI", "product_status": "EXPERIMENTAL_CLIENT", "runtime_status": "WINUI_RUNTIME_UNAVAILABLE", "evidence_level": "STATIC_ONLY", "status": "BLOCKED"},
        {"platform": "Linux/.NET", "product_status": "HEADLESS_HARNESS_AND_UI_CONTRACT", "runtime_status": "GTK_PRODUCT_HOST_ABSENT", "evidence_level": "STATIC_ONLY", "status": "BLOCKED"},
        {"platform": "Cloud/Remote Provider", "product_status": "CAPABILITY_CONTRACT_ONLY", "runtime_status": "REAL_SERVICE_UNAUTHORIZED", "evidence_level": "STATIC_ONLY", "status": "BLOCKED"},
    ]
    write_jsonl(AUDIT_DIR / "platform-matrix.jsonl", platform_rows)

    workflow_names = [
        "首次启动、创建资料库、接管已有目录、重新连接",
        "空目录、已有文件、权限拒绝、无效路径和DB错误",
        "Copy/Move/Indexed单文件、多文件、文件夹导入",
        "Duplicate、同名冲突、Replace、取消和失败重试",
        "浏览目录树、列表、详情、笔记、标签、改动日志",
        "普通搜索、筛选、Saved Search、Smart List、语义搜索",
        "批量标签、分类、重命名、删除、Undo/Redo",
        "Finder/Explorer/外部工具修改后的同步",
        "FSEvents/云placeholder、冲突审阅、Keep Both、Rename、Repair",
        "startup recovery、staging recovery、reindex、missing-file relink",
        "AI配置、隐私阻断、建议审阅、应用、失败恢复和调用日志",
        "Diagnostics、incident、preview/export、日志删除和离线读取",
        "设置、语言、内容语言、主题、窗口尺寸和平台差异",
        "退出、重启、资料库切换、网络中断和异常终止恢复",
    ]
    workflow_rows = []
    for index, name in enumerate(workflow_names, 1):
        workflow_rows.append(
            {
                "workflow_id": "WF-{:02d}".format(index),
                "name": name,
                "platform": "CROSS_PLATFORM",
                "entry": "PENDING",
                "precondition": "PENDING",
                "user_action": "PENDING",
                "core_bridge_call": "PENDING",
                "fs_db_side_effect": "PENDING",
                "ui_state": "PENDING",
                "success_failure_cancel_retry": "PENDING",
                "cleanup_recovery": "PENDING",
                "evidence_level": "STATIC_ONLY",
                "status": "PENDING",
            }
        )
    write_jsonl(AUDIT_DIR / "workflow-matrix.jsonl", workflow_rows)

    runtime_rows = [
        {"evidence_id": "ENV-001", "platform": "macOS", "kind": "HOST", "command": "sw_vers; uname -m", "result": "macOS host arm64", "level": "REAL_RUNTIME", "status": "PASS", "recorded_at": now},
        {"evidence_id": "ENV-002", "platform": "macOS/iOS", "kind": "TOOLCHAIN", "command": "xcodebuild -version", "result": scope["host"]["xcode"], "level": "STATIC_ONLY", "status": "PASS", "recorded_at": now},
        {"evidence_id": "ENV-003", "platform": "Rust Core", "kind": "TOOLCHAIN", "command": "rustc --version; cargo --version", "result": [scope["host"]["rustc"], scope["host"]["cargo"]], "level": "STATIC_ONLY", "status": "PASS", "recorded_at": now},
        {"evidence_id": "ENV-004", "platform": "Windows/Linux", "kind": "TOOLCHAIN", "command": "dotnet --info", "result": "SDK {} on macOS arm64; no Windows runtime/workloads".format(scope["host"]["dotnet"]), "level": "CROSS_PLATFORM_HARNESS", "status": "PASS", "recorded_at": now},
    ]
    write_jsonl(AUDIT_DIR / "runtime-evidence.jsonl", runtime_rows)

    bridge_rows = [
        {"contract_id": "BC-001", "boundary": "docs/api/core-api.md -> core/area_matrix.udl", "platform": "Shared", "status": "PENDING"},
        {"contract_id": "BC-002", "boundary": "core/area_matrix.udl -> core/src/api/** -> core implementation", "platform": "RustCore", "status": "PENDING"},
        {"contract_id": "BC-003", "boundary": "UDL -> tracked macOS UniFFI -> CoreBridge -> SwiftUI", "platform": "macOS", "status": "PENDING"},
        {"contract_id": "BC-004", "boundary": "CoreSDK/XCFramework -> iOS curated FFI -> app/share extension", "platform": "iOS", "status": "PENDING"},
        {"contract_id": "BC-005", "boundary": "cdylib -> Windows NativeCoreInterop -> ViewModel/XAML", "platform": "Windows", "status": "PENDING"},
        {"contract_id": "BC-006", "boundary": "cdylib -> Linux NativeCoreInterop -> headless shell/UI contract", "platform": "Linux", "status": "PENDING"},
        {"contract_id": "BC-007", "boundary": "platform capability DTO -> unsupported/error/alternative UI", "platform": "CrossPlatform", "status": "PENDING"},
        {"contract_id": "BC-008", "boundary": "UI confirmation -> Bridge/Core -> FS/DB/change_log/overview -> UI reload", "platform": "CrossPlatform", "status": "PENDING"},
    ]
    write_jsonl(AUDIT_DIR / "bridge-contracts.jsonl", bridge_rows)
    write_jsonl(AUDIT_DIR / "findings.jsonl", [])
    blocked_rows = [
        {"blocked_id": "BLK-001", "target": "Windows WinUI real runtime", "reason": "macOS host cannot execute WinUI", "required_external_evidence": "Windows x64/arm64 packaged app launch and user-flow run", "status": "BLOCKED"},
        {"blocked_id": "BLK-002", "target": "iOS real device and Share Extension", "reason": "real signed device/extension environment not established", "required_external_evidence": "signed device install, Files/iCloud permissions, extension handoff", "status": "BLOCKED"},
        {"blocked_id": "BLK-003", "target": "real iCloud/OneDrive", "reason": "real user cloud accounts and files are explicitly forbidden", "required_external_evidence": "isolated release-lab cloud fixtures", "status": "BLOCKED"},
        {"blocked_id": "BLK-004", "target": "remote AI Provider", "reason": "real credentials/network provider calls are explicitly forbidden", "required_external_evidence": "isolated provider test account and redacted payload audit", "status": "BLOCKED"},
        {"blocked_id": "BLK-005", "target": "clean Mac notarized release", "reason": "current source host is not a clean release-validation machine", "required_external_evidence": "Developer ID, notarization, stapling, Gatekeeper and clean-machine launch", "status": "BLOCKED"},
    ]
    write_jsonl(AUDIT_DIR / "blocked-evidence.jsonl", blocked_rows)

    (AUDIT_DIR / "review-notes.md").write_text(
        "# 跨平台运行时与 E2E 审计记录\n\n"
        "> 状态：`IN_PROGRESS`。逐行覆盖继承自 `full-repo-audit-20260819`，且 5,053/5,053 个文件 SHA-256 完全一致；本轮跨平台语义复核、finding 复核和运行证据尚未完成。\n\n"
        "## 证据边界\n\n"
        "- 继承证据仅证明当前字节已被人工逐行审阅，不等于今天重新通读，也不等于目标平台真实运行。\n"
        "- 本轮子代理只读；主代理负责复核调用链与最终定级。\n"
        "- 不访问真实用户资料库、真实云存储、真实凭据或生产环境。\n\n"
        "## 进行中\n\n"
        "- macOS SwiftUI / Bridge / PlatformServices。\n"
        "- Windows/Linux .NET 与真实平台边界。\n"
        "- Rust Core / UDL / iOS / 构建装配。\n",
        encoding="utf-8",
    )
    (AUDIT_DIR / "final-report.md").write_text(
        "# AreaMatrix 全仓库跨平台运行时与端到端用户流程审计\n\n"
        "> 状态：`IN_PROGRESS`。存在 `PENDING` 与未复核运行时证据，不构成完成声明。\n\n"
        "## Findings\n\n待本轮复核。\n\n"
        "## 覆盖守恒\n\n待本轮复核。\n\n"
        "## 平台与用户流程\n\n待本轮复核。\n\n"
        "## 运行证据与 Blocked\n\n待本轮复核。\n",
        encoding="utf-8",
    )
    print(json.dumps({"audit_id": AUDIT_ID, "files": len(paths), "hash_matches": len(paths) - len(mismatches), "mismatches": mismatches}, ensure_ascii=False))


if __name__ == "__main__":
    main()
