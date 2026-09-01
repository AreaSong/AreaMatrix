#!/usr/bin/env python3
"""Build current dependency, license, finding and coverage ledgers."""

from __future__ import annotations

import hashlib
import json
import os
import re
import runpy
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


AUDIT = Path(__file__).resolve().parent
ROOT = AUDIT.parents[2]
AUDIT_ID = AUDIT.name
SOURCE = ROOT / ".codex/runtime/dependency-supply-chain-audit-20260822/_synthesize_current.py"
OLD_AUDIT = ROOT / ".codex/runtime/dependency-supply-chain-audit-20260820"

FRESH_REVIEWED_PATHS = {
    ".github/workflows/core-ci.yml",
    ".github/workflows/governance-ci.yml",
    ".github/workflows/macos-ci.yml",
    ".github/workflows/release-evidence.yml",
    ".github/workflows/release-supply-chain.yml",
    ".gitignore",
    "THIRD_PARTY_NOTICES.md",
    "apps/macos/AreaMatrix/App/RepositoryIgnoreRulesManager.swift",
    "apps/macos/AreaMatrix/Bridge/UniFFI/area_matrix.swift",
    "apps/macos/AreaMatrix/Bridge/UniFFI/area_matrixFFI.h",
    "apps/macos/AreaMatrix/Features/Import/ImportBatchCopyFooterSection.swift",
    "apps/macos/AreaMatrix/Features/Import/ImportBatchCopyImportModel.swift",
    "apps/macos/AreaMatrix/PlatformServices/ImportBatchSessionPlatformServices.swift",
    "apps/macos/AreaMatrixTests/ImportProgressInterruptedSessionTests.swift",
    "assets/brand/README.md",
    "assets/brand/provenance.json",
    "core/benches/core_hot_paths.rs",
    "core/src/ai_call_log.rs",
    "core/src/ai_classification_suggestion/context.rs",
    "core/src/ai_classification_suggestion/implementation.rs",
    "core/src/ai_summary/context.rs",
    "core/src/ai_summary/implementation/generation.rs",
    "core/src/ai_tags_suggestion/implementation.rs",
    "core/src/batch_category/apply.rs",
    "core/src/batch_journal.rs",
    "core/src/batch_rename/apply.rs",
    "core/src/db/command_index.rs",
    "core/src/external_runtime.rs",
    "core/src/external_runtime_tests.rs",
    "core/src/icloud_conflicts/paths.rs",
    "core/src/observability/validation_text.rs",
    "core/src/repair.rs",
    "core/src/search/facets.rs",
    "core/src/semantic_search.rs",
    "core/src/semantic_search/matches.rs",
    "core/src/storage/safe_move.rs",
    "core/src/sync/mod.rs",
    "core/src/sync_conflict_detect/implementation.rs",
    "core/tests/ai_classification_suggestion_failure_recovery.rs",
    "core/tests/ai_classification_suggestion_implementation.rs",
    "core/tests/ai_classification_suggestion_validation.rs",
    "core/tests/ai_summary_validation.rs",
    "core/tests/ai_tags_suggestion_failure_recovery.rs",
    "core/tests/batch_journal_recovery.rs",
    "core/tests/camera_import_failure_recovery.rs",
    "core/tests/camera_import_validation.rs",
    "core/tests/files_import_failure_recovery.rs",
    "core/tests/release_evidence_checklist.rs",
    "core/tests/remote_provider_config_failure_recovery.rs",
    "core/tests/rust_file_size_governance.rs",
    "core/tests/share_extension_import_failure_recovery.rs",
    "core/tests/share_extension_import_validation.rs",
    "core/tests/support/ai_persisted_privacy.rs",
    "core/tests/support/ai_summary_common.rs",
    "core/tests/support/ai_tags_suggestion_failure.rs",
    "core/tests/support/external_runtime_harness.rs",
    "docs/api/core-api.md",
    "docs/development/ci-governance.md",
    "docs/development/dependency-policy.md",
    "docs/development/release.md",
    "docs/modules/semantic-search.md",
    "docs/ux/brand-assets.md",
    "scripts/brand/test_validate_assets.py",
    "scripts/brand/validate_assets.py",
    "scripts/dev_tools/checks.py",
    "scripts/dev_tools/core_sdk.py",
    "scripts/dev_tools/core_sdk_artifact.py",
    "scripts/dev_tools/supply_chain.py",
    "scripts/dev_tools/test_core_sdk.py",
    "scripts/dev_tools/test_core_sdk_artifact.py",
    "scripts/dev_tools/test_core_sdk_support.py",
    "scripts/dev_tools/test_supply_chain.py",
    "scripts/dev_tools/test_workflow_permissions.py",
}


def timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load_library() -> dict[str, Any]:
    namespace = runpy.run_path(str(SOURCE), run_name="audit_synthesis_library")
    globals_dict = namespace["findings"].__globals__
    globals_dict.update(
        ROOT=ROOT,
        AUDIT=AUDIT,
        AUDIT_ID=AUDIT_ID,
        OLD_AUDIT=OLD_AUDIT,
        LOCKFILE=ROOT / "core/Cargo.lock",
    )
    return namespace


def current_metadata() -> dict[str, Any]:
    environment = dict(os.environ)
    environment["CARGO_NET_OFFLINE"] = "true"
    process = subprocess.run(
        ["cargo", "metadata", "--locked", "--offline", "--format-version", "1"],
        cwd=ROOT / "core",
        env=environment,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    metadata = json.loads(process.stdout)
    (AUDIT / "cargo-metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return metadata


def update_findings(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    updates: dict[str, dict[str, Any]] = {
        "SC-002": {
            "status": "BLOCKED_EXTERNAL",
            "local_remediation": "Windows loader and target-aware release gate fail closed on missing/unapproved artifacts.",
            "residual": "真实 DLL、Windows clean publish、签名、SBOM、NOTICE 与 package inspection 必须由 Windows runner 提供。",
        },
        "SC-003": {
            "status": "FIXED_LOCAL_BLOCKED_EXTERNAL",
            "local_remediation": "packages.lock.json、RestoreLockedMode、source mapping、signature validation 和 target-aware NuGet SBOM extraction 已实现。",
            "residual": "clean Windows restore、包签名 readback、NOASSERTION 许可证元数据与实际 package closure 仍需外部证据。",
        },
        "SC-005": {
            "status": "FIXED",
            "disposition": "排除",
            "title": "Pillow 11.3.0 历史 advisory 候选已升级并完成当前公开情报复核",
            "local_remediation": "Pillow 已锁定为 12.3.0，仅限品牌开发/CI，官方 wheels 由 SHA-256 require-hashes 约束。",
            "evidence": "2026-08-30 只读 PyPI 元数据确认 12.3.0 未撤回且 MIT-CMU；OSV 精确版本查询返回 0 个 advisory。",
            "residual": "公开数据库只能证明查询时点；后续发布仍需按门禁刷新 advisory 证据。",
        },
        "SC-006": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "Pillow 保持 tool-only；许可证文本、THIRD_PARTY_NOTICES 与依赖政策已统一，未进入产品 runtime。",
        },
        "SC-008": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "UniFFI fallback 使用锁定版本 wrapper、离线 Cargo.lock 与受校验缓存路径，不再接受任意环境工具。",
        },
        "SC-009": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "关键 Cargo metadata/tree/build/check/clippy/test 入口均使用 --locked；回归测试覆盖。",
        },
        "SC-010": {
            "status": "BLOCKED",
            "title": "产品工程已移除 legacy 静态库消费，但 tracked 历史 blob provenance 仍不完整",
            "local_remediation": "权威 XcodeGen 与 tracked Xcode project 只链接 fingerprinted CoreSDK XCFramework。",
            "residual": "tracked libarea_matrix_core.a 仍为 historical-unattested，缺完整 SBOM/NOTICE/签名；删除或保留需独立审批。",
        },
        "SC-011": {
            "status": "BLOCKED",
            "local_remediation": "精确 GitHub commit/blob 坐标与输入 SHA-256 已由公开只读 API/raw blob 复核一致。",
            "residual": "OFL 字体、字标轮廓和商标/归属的实际分发义务仍需合格许可证 reviewer。",
        },
        "SC-012": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "Actions 全部固定 40 位 SHA；SwiftLint/SwiftFormat 固定 release URL 与 SHA-256；远端对象身份归入 SC-025。",
        },
        "SC-014": {
            "status": "BLOCKED_EXTERNAL",
            "local_remediation": "artifact hash、Cargo/NuGet 组件、SBOM、NOTICE、source-offer、license materials 与 review record gate 已本地实现。",
            "residual": "真实制品检查、Developer ID、notary、staple、外部法律复核与 artifact-specific closure 仍不可由本机伪造。",
        },
        "SC-015": {
            "status": "BLOCKED_EXTERNAL",
            "local_remediation": "Linux loader and target-aware release gate fail closed while manifest is fixture-only.",
            "residual": "真实 .so、Linux clean publish/runtime tests、签名、SBOM 与 package inspection 仍需 Linux runner。",
        },
        "SC-016": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "两个 prototype 已移除 Google Fonts 动态加载，改用系统字体栈，无网络下载或外部字体分发。",
        },
        "SC-020": {
            "status": "BLOCKED_OWNER_DECISION",
            "confidence": "MEDIUM",
            "title": "anyhow 1.0.102 命中已确认的 downcast_mut unsoundness，当前源码未发现触发调用",
            "source": "RustSec/OSV RUSTSEC-2026-0190",
            "maintenance_status": "2026-08-30 外部证据确认 <1.0.103 受影响，修复版本 >=1.0.103",
            "integrity_reproducibility": "Cargo.lock checksum 完整；OSV 精确版本批量查询命中 RUSTSEC-2026-0190",
            "actual_use_path": "UniFFI runtime/build closure；本地 Core/UniFFI 0.28.3 源码未发现 downcast_mut 调用",
            "arbitrary_code_or_ci_risk": "已确认 unsoundness，但当前逐源文件检索没有建立触发路径",
            "why_insufficient": "受影响版本仍在锁定闭包；本任务禁止升级依赖，也没有 owner 批准的时限例外",
            "minimal_fix": "在独立依赖变更中升级到 >=1.0.103，或由 owner 登记有期限、带可达性证据的例外",
            "verification_needed": "锁定依赖升级后的 cargo tree/fmt/clippy/test/CoreSDK 重建，或正式例外记录",
            "evidence_class": "fresh_rustsec_osv_plus_local_source_reachability_review",
        },
        "SC-021": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "产品构建不批准任何外部 AI runtime；仅 Rust test harness 可用固定 provider/endpoint/privacy/source/license/hash manifest 显式启用，普通 debug/release 均 fail closed。",
        },
        "SC-022": {
            "status": "BLOCKED",
            "local_remediation": "16 个 archive 资产逐项 hash 且排除 release root。",
            "residual": "仓库再分发本身的来源与授权仍未知；不得以 release exclusion 代替权属证据。",
        },
        "SC-024": {
            "status": "BLOCKED",
            "local_remediation": "Cargo 164 包与 NuGet 15 包均进入锁定台账；Windows SBOM 现在包含 NuGet TFM/RID、direct/transitive 和 contentHash 解码 SHA-512。",
            "residual": "NuGet lock 不含许可证表达式，Cargo 复合许可证与逐包 NOTICE/源码义务仍需 registry readback 和合格许可证 reviewer。",
        },
        "SC-025": {
            "status": "FIXED",
            "disposition": "排除",
            "title": "外部 Action 与 Swift 工具对象身份已完成公开只读复核",
            "local_remediation": "本地 pin/hash/权限规则与负测已通过。",
            "evidence": "7 个 Action ref 均由 GitHub API/git ref 解析为固定对象；SwiftLint/SwiftFormat 官方 release digest 与 workflow SHA-256 完全一致。",
            "residual": "远端 branch protection、required checks、environment reviewer 与实际 workflow run 另见 SC-034。",
        },
        "SC-026": {
            "status": "BLOCKED_EXTERNAL",
            "local_remediation": "Rust、SwiftPM、arm64 source compilation gates and platform fail-closed contracts are present.",
            "residual": "universal CoreSDK、Windows/Linux/iOS clean runner、真实 FFI package、签名/公证与干净机安装证据仍缺。",
        },
        "SC-027": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "CoreSDK schema 2 对 Info.plist、Package.swift、bindings、headers 与每个 slice archive 记录逐文件 SHA-256；篡改负测通过。",
        },
        "SC-028": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "不写仓库的 checkout 全部 persist-credentials:false；release checkout、ref gate 与 provenance 绑定 github.sha。",
        },
        "SC-029": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "品牌 provenance 精确 allowlist GitHub owner/repository/commit/path/source URL/input SHA-256，错误坐标负测通过；法律判断仍归 SC-011。",
        },
        "SC-030": {
            "status": "FIXED",
            "disposition": "排除",
            "evidence": "tracked Swift/header 已由锁定 UniFFI 重新生成；./dev bindings verify PASS。",
        },
    }
    for row in rows:
        row.update(updates.get(row["id"], {}))
        row["audit_id"] = AUDIT_ID
        row["recorded_at"] = timestamp()
    rows.append(
        {
            "audit_id": AUDIT_ID,
            "recorded_at": timestamp(),
            "id": "SC-031",
            "severity": "P2",
            "confidence": "HIGH",
            "status": "BLOCKED",
            "disposition": "FINDING",
            "title": "版本化 workflow 文档基线与当前工作树漂移",
            "locations": [
                "workflow/versions/v2/baseline/docs.yaml:1",
                "workflow/versions/v3/baseline/docs.yaml:1",
                "workflow/versions/v4/baseline/docs.yaml:1",
                "docs/development/ci-governance.md:1",
            ],
            "dependency_or_asset": "workflow documentation baseline",
            "source": "./dev workflow doctor",
            "actual_use_path": "version discussion/promotion governance -> baseline hash validation",
            "exposure_scope": "development and release governance",
            "license": "not applicable",
            "integrity_reproducibility": "doctor reports eight drifted baseline entries across v2-v4",
            "maintenance_status": "local confirmed in dirty worktree",
            "arbitrary_code_or_ci_risk": "stale baselines can make promotion evidence disagree with authority docs",
            "product_bundle_core_ffi_user_files_release": "does not enter product package; blocks governance closeout",
            "existing_controls": "workflow doctor fails closed",
            "why_insufficient": "the dirty tree mixes unrelated documentation changes, so bulk baseline refresh would approve changes without owner review",
            "minimal_fix": "review each drifted authority document under its workflow version owner, then refresh only approved baselines",
            "rollback": "revert only the separately approved baseline refresh commit",
            "verification_needed": "./dev workflow doctor must pass with a reviewed clean baseline",
            "evidence_class": "local_confirmed",
        }
    )
    rows.extend(additional_findings())
    return rows


def additional_findings() -> list[dict[str, Any]]:
    recorded_at = timestamp()
    return [
        {
            "audit_id": AUDIT_ID,
            "recorded_at": recorded_at,
            "id": "SC-032",
            "severity": "P2",
            "confidence": "HIGH",
            "status": "BLOCKED_LEGAL",
            "disposition": "FINDING",
            "title": "gitleaks-action 使用专有 EULA，尚未进入 AreaMatrix 许可证批准记录",
            "locations": [
                ".github/workflows/governance-ci.yml:82-83",
                "docs/development/ci-governance.md:248-252",
            ],
            "dependency_or_asset": "gitleaks/gitleaks-action v2.3.9",
            "version": "v2.3.9 / ff98106e4c7b2bc287b24eaf42907196329070c7",
            "source": "https://github.com/gitleaks/gitleaks-action",
            "actual_use_path": "governance-ci secret-scan job -> Node20 dist/index.js -> full Git history scan",
            "exposure_scope": "CI only; arbitrary third-party JavaScript executes on repository checkout",
            "license": "GITLEAKS-ACTION END-USER LICENSE AGREEMENT",
            "integrity_reproducibility": "tag v2.3.9 and verified commit are pinned; pinned LICENSE.txt Git blob is identified",
            "maintenance_status": "public repository and signed commit confirmed on 2026-08-30",
            "arbitrary_code_or_ci_risk": "Action executes bundled JavaScript; current job has contents:read and no persisted checkout credential",
            "product_bundle_core_ffi_user_files_release": "does not enter product package; governs source-history scanning",
            "existing_controls": "40-character pin, persist-credentials:false, contents:read",
            "why_insufficient": "custom EULA is outside the default allowlist and no qualified approval is recorded",
            "minimal_fix": "obtain qualified review for the exact EULA/account scope and record it, or replace the Action in a separately approved dependency change",
            "rollback": "keep remote secret-scan non-authoritative until approval; retain local ./dev check secrets as a separate control",
            "verification_needed": "qualified license decision plus remote CI readback under the approved account scope",
            "evidence_class": "public_pinned_license_and_account_type_readback",
        },
        {
            "audit_id": AUDIT_ID,
            "recorded_at": recorded_at,
            "id": "SC-033",
            "severity": "P3",
            "confidence": "HIGH",
            "status": "BLOCKED_LEGAL",
            "disposition": "FINDING",
            "title": "rust-cache Action 为 LGPL-3.0，CI 使用方式尚未完成专项许可证复核",
            "locations": [
                ".github/workflows/core-ci.yml:58,74,92,110",
                ".github/workflows/macos-ci.yml:53",
            ],
            "dependency_or_asset": "Swatinem/rust-cache v2.8.1",
            "version": "v2.8.1 / signed tag bc2d2e71... -> commit f13886b9...",
            "source": "https://github.com/Swatinem/rust-cache",
            "actual_use_path": "Core/macOS CI -> Node20 restore/save scripts -> GitHub cache service",
            "exposure_scope": "CI build cache only",
            "license": "LGPL-3.0-only",
            "integrity_reproducibility": "signed annotated tag object and target commit were read back; workflow pins the immutable tag object SHA",
            "maintenance_status": "v2.8.1 tag identity confirmed on 2026-08-30",
            "arbitrary_code_or_ci_risk": "third-party JavaScript executes during restore and post-job save; cache poisoning controls remain relevant",
            "product_bundle_core_ffi_user_files_release": "not linked into or distributed with AreaMatrix product artifacts",
            "existing_controls": "immutable object pin and scoped cache use",
            "why_insufficient": "repository policy requires LGPL use/link/distribution mode to be reviewed explicitly",
            "minimal_fix": "record qualified approval for CI-only execution and any notice/source obligations, or replace it in an approved dependency change",
            "rollback": "disable the cache Action; correctness gates remain but CI becomes slower",
            "verification_needed": "qualified license review and cache restore/save threat-path review",
            "evidence_class": "public_signed_tag_and_pinned_license_readback",
        },
        {
            "audit_id": AUDIT_ID,
            "recorded_at": recorded_at,
            "id": "SC-034",
            "severity": "P2",
            "confidence": "HIGH",
            "status": "BLOCKED_EXTERNAL",
            "disposition": "FINDING",
            "title": "远端 branch protection、required checks、environment reviewers 与实际 CI 状态未取证",
            "locations": [
                "docs/development/ci-governance.md:77-78,117-155",
                ".github/workflows/remote-governance.yml:1",
                ".github/workflows/release-supply-chain.yml:1",
            ],
            "dependency_or_asset": "GitHub repository remote governance",
            "source": "GitHub settings and Actions API",
            "actual_use_path": "merge/release decision -> remote required checks/reviews/environments -> protected workflow execution",
            "exposure_scope": "remote CI, merge and release governance",
            "license": "not applicable",
            "integrity_reproducibility": "local workflows are auditable, but remote settings and latest run state are not repository files",
            "maintenance_status": "not queried with credentials; user explicitly prohibited real credential use",
            "arbitrary_code_or_ci_risk": "local YAML cannot prove branch protection, secret scope or required reviewer enforcement",
            "product_bundle_core_ffi_user_files_release": "controls whether release evidence is authoritative",
            "existing_controls": "read-only remote-governance workflow and local fail-closed documentation",
            "why_insufficient": "no authenticated readback or archived successful protected run is available",
            "minimal_fix": "run the documented read-only remote audit with an approved least-privilege credential and archive the result",
            "rollback": "keep merge/release status BLOCKED",
            "verification_needed": "fresh remote audit, workflow run URLs, branch protection, environment and required-review readback",
            "evidence_class": "external_state_unavailable_by_explicit_credential_boundary",
        },
        {
            "audit_id": AUDIT_ID,
            "recorded_at": recorded_at,
            "id": "SC-035",
            "severity": "P3",
            "confidence": "HIGH",
            "status": "BLOCKED_OWNER_DECISION",
            "disposition": "FINDING",
            "title": "bincode 1.3.3 经 UniFFI proc-macro 闭包进入构建链且已停止维护",
            "locations": ["core/Cargo.lock:1", "core/Cargo.toml:16-18,32-34"],
            "dependency_or_asset": "bincode 1.3.3",
            "version": "1.3.3",
            "source": "RustSec/OSV RUSTSEC-2025-0141",
            "actual_use_path": "area_matrix_core -> uniffi 0.28.3 -> uniffi_macros 0.28.3 -> bincode 1.3.3",
            "exposure_scope": "build/proc-macro chain",
            "license": "MIT",
            "integrity_reproducibility": "Cargo.lock registry checksum is present; OSV identifies all versions as unmaintained",
            "maintenance_status": "upstream development permanently ceased; advisory is informational, not a vulnerability claim",
            "arbitrary_code_or_ci_risk": "build-time serialization dependency receives no future maintenance",
            "product_bundle_core_ffi_user_files_release": "participates during UniFFI macro build; not established as a shipped runtime library",
            "existing_controls": "locked checksum and passing host tests",
            "why_insufficient": "no owner-approved replacement plan or time-bounded maintenance exception exists",
            "minimal_fix": "upgrade the UniFFI closure or record a reviewed, expiring exception with replacement tracking",
            "rollback": "retain the locked closure and keep release exception explicit",
            "verification_needed": "dependency graph after approved change plus fmt/clippy/test/bindings/CoreSDK rebuild",
            "evidence_class": "fresh_osv_plus_locked_parent_chain",
        },
        {
            "audit_id": AUDIT_ID,
            "recorded_at": recorded_at,
            "id": "SC-036",
            "severity": "P3",
            "confidence": "HIGH",
            "status": "BLOCKED_OWNER_DECISION",
            "disposition": "FINDING",
            "title": "paste 1.0.15 经 UniFFI 闭包执行于构建期且已停止维护",
            "locations": ["core/Cargo.lock:1", "core/Cargo.toml:16-18,32-34"],
            "dependency_or_asset": "paste 1.0.15",
            "version": "1.0.15",
            "source": "RustSec/OSV RUSTSEC-2024-0436",
            "actual_use_path": "area_matrix_core -> uniffi/uniffi_build -> uniffi_core or uniffi_bindgen -> paste proc-macro",
            "exposure_scope": "build/proc-macro chain",
            "license": "MIT OR Apache-2.0",
            "integrity_reproducibility": "Cargo.lock registry checksum is present; OSV identifies the crate as unmaintained",
            "maintenance_status": "repository archived; advisory is informational, not a vulnerability claim",
            "arbitrary_code_or_ci_risk": "proc-macro executes at build time and receives no future maintenance",
            "product_bundle_core_ffi_user_files_release": "build-time only; generated output feeds FFI artifacts",
            "existing_controls": "locked checksum and passing host tests",
            "why_insufficient": "no owner-approved replacement plan or time-bounded maintenance exception exists",
            "minimal_fix": "upgrade the UniFFI closure to remove paste or record a reviewed, expiring exception",
            "rollback": "retain the locked closure and keep release exception explicit",
            "verification_needed": "dependency graph after approved change plus fmt/clippy/test/bindings/CoreSDK rebuild",
            "evidence_class": "fresh_osv_plus_locked_parent_chain",
        },
        {
            "audit_id": AUDIT_ID,
            "recorded_at": recorded_at,
            "id": "SC-037",
            "severity": "P2",
            "confidence": "HIGH",
            "status": "BLOCKED_OWNER_DECISION",
            "disposition": "FINDING",
            "title": ".NET 9 项目没有 global.json，SDK 选择依赖维护者/runner 全局环境",
            "locations": [
                "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:3-4",
                "apps/windows/AreaMatrixTests/AreaMatrix.Windows.Tests.csproj:3",
                "apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:3",
                "apps/linux/AreaMatrixTests/AreaMatrix.Linux.Tests.csproj:3",
            ],
            "dependency_or_asset": ".NET SDK",
            "version": "TargetFramework net9.0; local SDK 9.0.306; no global.json",
            "source": "machine/runner installed dotnet SDK",
            "actual_use_path": "dotnet restore/build/run -> Windows/Linux projects and tests",
            "exposure_scope": "Windows/Linux build, restore and package generation",
            "license": "MIT and bundled component licenses",
            "integrity_reproducibility": "NuGet packages are locked, but SDK feature band and workload selection are not repository-pinned",
            "maintenance_status": "local SDK observed; target-platform runner evidence unavailable",
            "arbitrary_code_or_ci_risk": "SDK/MSBuild version changes can alter restore, generated assets and packaging",
            "product_bundle_core_ffi_user_files_release": "directly affects Windows/Linux build artifacts",
            "existing_controls": "net9.0 target frameworks and locked NuGet restore",
            "why_insufficient": "compatible global SDK selection is environment-dependent and no target CI gate proves parity",
            "minimal_fix": "add an owner-approved global.json SDK/rollForward policy and validate it on Windows/Linux runners",
            "rollback": "remove the pin only with a documented SDK migration plan",
            "verification_needed": "dotnet --info, locked restore/build/test/package on real target runners",
            "evidence_class": "local_project_and_environment_readback",
        },
        {
            "audit_id": AUDIT_ID,
            "recorded_at": recorded_at,
            "id": "SC-038",
            "severity": "P2",
            "confidence": "HIGH",
            "status": "BLOCKED_EXTERNAL",
            "disposition": "FINDING",
            "title": "macOS CI 使用 moving macos-14 默认 Xcode，Apple 构建工具链未固定到可复核版本",
            "locations": [
                ".github/workflows/core-ci.yml:24-100",
                ".github/workflows/macos-ci.yml:19-455",
                ".github/workflows/release-evidence.yml:27",
            ],
            "dependency_or_asset": "Xcode/Swift/Apple command-line toolchain",
            "version": "CI macos-14 default; local Xcode 26.4.1 / Swift 6.3.1",
            "source": "GitHub-hosted runner image and selected Xcode.app",
            "actual_use_path": "runner image -> xcodebuild/xcrun/swift/clang/lipo/codesign -> CoreSDK, app tests and release evidence",
            "exposure_scope": "Apple build, FFI, test and distribution chain",
            "license": "Apple SDK/Xcode terms plus Swift/LLVM component licenses",
            "integrity_reproducibility": "workflow records xcodebuild -version but does not select an immutable runner image or exact Xcode path",
            "maintenance_status": "remote image contents change over time",
            "arbitrary_code_or_ci_risk": "compiler/linker/package output and SDK availability can change without repository diff",
            "product_bundle_core_ffi_user_files_release": "directly affects all Apple artifacts",
            "existing_controls": "runner label, version logging, source/tool fingerprint and CoreSDK hash manifest",
            "why_insufficient": "logging the selected version after scheduling does not make future rebuilds select the same toolchain",
            "minimal_fix": "adopt an approved exact Xcode selection/image policy and bind it into CoreSDK/release provenance",
            "rollback": "keep release evidence non-authoritative when the selected toolchain differs from the approved record",
            "verification_needed": "remote runner readback and clean CoreSDK/macOS/iOS build under the approved Xcode version",
            "evidence_class": "local_workflow_plus_host_toolchain_observation",
        },
        {
            "audit_id": AUDIT_ID,
            "recorded_at": recorded_at,
            "id": "SC-039",
            "severity": "P3",
            "confidence": "HIGH",
            "status": "BLOCKED_OWNER_DECISION",
            "disposition": "FINDING",
            "title": "本地 Python/SwiftLint/SwiftFormat 入口没有强制与 CI 固定版本一致",
            "locations": [
                ".github/workflows/governance-ci.yml:28-30",
                ".github/workflows/release-supply-chain.yml:77-79",
                ".github/workflows/macos-ci.yml:414-455",
                "docs/development/setup.md:102,196-198",
                "scripts/dev_tools/checks.py:3273-3293",
            ],
            "dependency_or_asset": "Python, SwiftLint and SwiftFormat local developer toolchain",
            "version": "CI Python 3.12.11 / SwiftLint 0.65.0 / SwiftFormat 0.62.1; local observed 3.9.6 / 0.63.2 / 0.61.1",
            "source": "CI pinned downloads versus developer PATH/Homebrew",
            "actual_use_path": "./dev and documentation commands -> PATH-selected interpreters/linters -> local validation evidence",
            "exposure_scope": "development and pre-merge validation",
            "license": "PSF-2.0, MIT, MIT",
            "integrity_reproducibility": "CI pins exact versions/hashes, but local wrappers only require command presence",
            "maintenance_status": "local tools are older than current CI pins",
            "arbitrary_code_or_ci_risk": "different parser/formatter behavior can make local PASS disagree with CI",
            "product_bundle_core_ffi_user_files_release": "does not enter product package; can affect generated/validated source and release evidence",
            "existing_controls": "CI is authoritative and downloads lint tools with verified hashes",
            "why_insufficient": "local completion evidence is not version-equivalent to the protected CI path",
            "minimal_fix": "add non-installing version gates or repository wrappers that fail with an exact remediation message",
            "rollback": "allow version drift only through an explicit, time-bounded local validation exception",
            "verification_needed": "local and CI version readback plus identical lint/test results",
            "evidence_class": "local_version_observation_plus_ci_pin_review",
        },
    ]


ACTION_PATTERN = re.compile(r"\buses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-f]{40})")
ACTION_EVIDENCE: dict[str, dict[str, Any]] = {
    "Swatinem/rust-cache": {
        "version": "v2.8.1",
        "ref": "bc2d2e71bd35c5549942babaa51a89c586b981d1",
        "object_type": "signed annotated tag",
        "target": "f13886b937689c021905a6b90929199931d60db1",
        "license": "LGPL-3.0-only",
        "license_policy": "MANUAL_REVIEW_REQUIRED",
        "license_url": "https://github.com/Swatinem/rust-cache/blob/f13886b937689c021905a6b90929199931d60db1/LICENSE",
        "review_status": "BLOCKED",
        "finding_ids": ["SC-025", "SC-033"],
        "purpose": "Rust dependency/target cache restore and post-job save",
    },
    "actions/checkout": {
        "version": "v4.2.2",
        "ref": "11bd71901bbe5b1630ceea73d27597364c9af683",
        "object_type": "verified commit",
        "target": None,
        "license": "MIT",
        "license_policy": "DEFAULT_ALLOWED",
        "license_url": "https://github.com/actions/checkout/blob/11bd71901bbe5b1630ceea73d27597364c9af683/LICENSE",
        "review_status": "PASS",
        "finding_ids": ["SC-025"],
        "purpose": "Workflow checkout",
    },
    "actions/download-artifact": {
        "version": "v4.3.0",
        "ref": "d3f86a106a0bac45b974a628896c90dbdf5c8093",
        "object_type": "verified commit",
        "target": None,
        "license": "MIT",
        "license_policy": "DEFAULT_ALLOWED",
        "license_url": "https://github.com/actions/download-artifact/blob/d3f86a106a0bac45b974a628896c90dbdf5c8093/LICENSE",
        "review_status": "PASS",
        "finding_ids": ["SC-025"],
        "purpose": "CoreSDK artifact download",
    },
    "actions/setup-python": {
        "version": "v5.6.0",
        "ref": "a26af69be951a213d495a4c3e4e4022e16d87065",
        "object_type": "verified commit",
        "target": None,
        "license": "MIT",
        "license_policy": "DEFAULT_ALLOWED",
        "license_url": "https://github.com/actions/setup-python/blob/a26af69be951a213d495a4c3e4e4022e16d87065/LICENSE",
        "review_status": "PASS",
        "finding_ids": ["SC-025"],
        "purpose": "Python toolchain bootstrap",
    },
    "actions/upload-artifact": {
        "version": "v4.6.2",
        "ref": "ea165f8d65b6e75b540449e92b4886f43607fa02",
        "object_type": "verified commit",
        "target": None,
        "license": "MIT",
        "license_policy": "DEFAULT_ALLOWED",
        "license_url": "https://github.com/actions/upload-artifact/blob/ea165f8d65b6e75b540449e92b4886f43607fa02/LICENSE",
        "review_status": "PASS",
        "finding_ids": ["SC-025"],
        "purpose": "CI evidence/artifact upload",
    },
    "dtolnay/rust-toolchain": {
        "version": "Rust 1.88.0",
        "ref": "2eae45db285e407f22119950686d47e1101e071b",
        "object_type": "verified commit",
        "target": None,
        "license": "MIT",
        "license_policy": "DEFAULT_ALLOWED",
        "license_url": "https://github.com/dtolnay/rust-toolchain/blob/2eae45db285e407f22119950686d47e1101e071b/LICENSE",
        "review_status": "PASS",
        "finding_ids": ["SC-025"],
        "purpose": "Rust toolchain provisioning",
    },
    "gitleaks/gitleaks-action": {
        "version": "v2.3.9",
        "ref": "ff98106e4c7b2bc287b24eaf42907196329070c7",
        "object_type": "verified commit/tag",
        "target": None,
        "license": "GITLEAKS-ACTION EULA",
        "license_policy": "MANUAL_REVIEW_REQUIRED",
        "license_url": "https://github.com/gitleaks/gitleaks-action/blob/ff98106e4c7b2bc287b24eaf42907196329070c7/LICENSE.txt",
        "review_status": "BLOCKED",
        "finding_ids": ["SC-025", "SC-032"],
        "purpose": "Full-history secret scan",
    },
}


def refresh_github_action_records(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    usages: dict[str, dict[str, Any]] = {}
    workflows = ROOT / ".github/workflows"
    for path in sorted(workflows.rglob("*")):
        if not path.is_file() or path.suffix not in {".yml", ".yaml"}:
            continue
        relative = path.relative_to(ROOT).as_posix()
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = ACTION_PATTERN.search(line)
            if match is None:
                continue
            name, ref = match.groups()
            entry = usages.setdefault(name, {"ref": ref, "locations": []})
            if entry["ref"] != ref:
                raise RuntimeError(f"multiple refs for GitHub Action {name}")
            entry["locations"].append(f"{relative}:{line_number}")

    if set(usages) != set(ACTION_EVIDENCE):
        missing = sorted(set(usages) - set(ACTION_EVIDENCE))
        stale = sorted(set(ACTION_EVIDENCE) - set(usages))
        raise RuntimeError(f"GitHub Action evidence drift: missing={missing}, stale={stale}")

    records = [row for row in rows if row.get("ecosystem") != "github-action"]
    for name in sorted(usages):
        usage = usages[name]
        evidence = ACTION_EVIDENCE[name]
        if usage["ref"] != evidence["ref"]:
            raise RuntimeError(f"GitHub Action ref drift for {name}")
        target = evidence.get("target")
        integrity = f"2026-08-30 remote readback confirmed {evidence['object_type']} {evidence['ref']}"
        if target:
            integrity += f" targeting commit {target}"
        records.append(
            {
                "audit_id": AUDIT_ID,
                "ecosystem": "github-action",
                "name": name,
                "version": evidence["version"],
                "version_range": None,
                "source": f"https://github.com/{name}",
                "source_locator": usage["locations"],
                "direct_or_transitive": "direct",
                "runtime_dev_build": evidence["purpose"],
                "scope": ["CI", "build"],
                "declaration_location": usage["locations"],
                "usage_location": usage["locations"],
                "license": evidence["license"],
                "license_policy": evidence["license_policy"],
                "license_evidence": evidence["license_url"],
                "integrity": integrity,
                "lock": {
                    "object_sha": evidence["ref"],
                    "object_type": evidence["object_type"],
                    "target_commit": target,
                },
                "risk_level": "HIGH",
                "review_status": evidence["review_status"],
                "finding_ids": evidence["finding_ids"],
                "evidence_class": "local_full_sha_plus_public_remote_object_and_license_readback",
                "notes": "Remote repository settings and actual workflow enforcement are separate from object identity.",
            }
        )
    return records


def system_tool_records() -> list[dict[str, Any]]:
    common = {
        "audit_id": AUDIT_ID,
        "direct_or_transitive": "implicit",
        "version_range": None,
    }

    def record(**values: Any) -> dict[str, Any]:
        return {**common, **values}

    return [
        record(
            ecosystem="system-toolchain",
            name="Rust toolchain (rustc/cargo/rustup)",
            version="1.88.0",
            source="rust-toolchain.toml and dtolnay/rust-toolchain pinned Action",
            source_locator="rust-toolchain.toml:1-4; core/Cargo.toml:5; .github/workflows/*",
            scope=["build", "test", "CI"],
            runtime_dev_build="Rust compilation, dependency resolution and tests",
            declaration_location=["rust-toolchain.toml:1-4", "core/Cargo.toml:5"],
            usage_location=["scripts/dev_tools/build.py", ".github/workflows/core-ci.yml", ".github/workflows/macos-ci.yml"],
            license="MIT OR Apache-2.0",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="https://github.com/rust-lang/rust/blob/1.88.0/COPYRIGHT",
            lock={"channel": "1.88.0", "components": ["rustfmt", "clippy"], "artifact_hash": False},
            integrity="Channel/components are repository-pinned; rustup distribution artifact hash/signature is not stored locally.",
            risk_level="HIGH",
            review_status="PASS",
            finding_ids=["SC-001", "SC-025"],
            evidence_class="local_version_pin_plus_public_action_identity",
            notes="Local rustc/cargo both report 1.88.0.",
        ),
        record(
            ecosystem="system-toolchain",
            name="Python interpreter",
            version="CI 3.12.11; local observed 3.9.6",
            source="actions/setup-python on CI; developer PATH locally",
            source_locator=".github/workflows/governance-ci.yml:28-30; .github/workflows/release-supply-chain.yml:77-79",
            scope=["development", "CI", "release-evidence"],
            runtime_dev_build="Repository governance, build wrappers, brand tooling and release-material generation",
            declaration_location=[".github/workflows/governance-ci.yml:30", ".github/workflows/release-supply-chain.yml:79"],
            usage_location=["scripts/dev_tools/*.py", "scripts/brand/*.py", "workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py"],
            license="PSF-2.0",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="Python distribution license; not vendored in repository",
            lock={"ci_version": "3.12.11", "local_version_gate": False},
            integrity="CI version is exact; local scripts select python3 from PATH without an exact version gate.",
            risk_level="MEDIUM",
            review_status="BLOCKED",
            finding_ids=["SC-039"],
            evidence_class="ci_pin_plus_local_version_observation",
            notes="No package installation was performed during this audit.",
        ),
        record(
            ecosystem="system-toolchain",
            name="Xcode/Swift/Apple command-line tools",
            version="CI macos-14 default; local Xcode 26.4.1 / Swift 6.3.1",
            source="GitHub-hosted macOS runner and local Xcode.app",
            source_locator=".github/workflows/core-ci.yml; .github/workflows/macos-ci.yml; scripts/dev_tools/macos.py",
            scope=["Apple-build", "FFI", "test", "distribution"],
            runtime_dev_build="xcodebuild, xcrun, swift, codesign, security, notarytool, stapler and spctl",
            declaration_location=[".github/workflows/macos-ci.yml:19-455", "docs/development/build.md"],
            usage_location=["scripts/dev_tools/core_sdk.py", "scripts/dev_tools/macos.py", "scripts/dev_tools/release.py"],
            license="Apple Xcode/SDK terms plus Swift/LLVM component licenses",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="Installed Xcode license and upstream Swift/LLVM notices; artifact-specific closure not archived",
            lock={"runner": "macos-14", "exact_xcode": False, "local_xcode": "26.4.1"},
            integrity="Version is logged but the hosted runner's selected Xcode is not immutable.",
            risk_level="HIGH",
            review_status="BLOCKED",
            finding_ids=["SC-026", "SC-038"],
            evidence_class="local_and_workflow_toolchain_observation",
            notes="Required multi-architecture Rust targets are absent locally.",
        ),
        record(
            ecosystem="system-toolchain",
            name=".NET SDK / MSBuild",
            version="net9.0 requirement; local observed SDK 9.0.306",
            source="developer/runner installed dotnet SDK",
            source_locator="apps/windows/**/*.csproj; apps/linux/**/*.csproj",
            scope=["Windows-build", "Linux-build", "NuGet-restore"],
            runtime_dev_build="dotnet restore/build/run/package",
            declaration_location=["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:4", "apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:3"],
            usage_location=["apps/windows/AreaMatrixTests", "apps/linux/AreaMatrixTests"],
            license="MIT plus bundled SDK component licenses",
            license_policy="DEFAULT_ALLOWED",
            license_evidence="https://github.com/dotnet/sdk",
            lock={"target_framework": "net9.0", "global_json": False, "local_sdk": "9.0.306"},
            integrity="NuGet packages are locked, but the SDK feature band and workload selection are not.",
            risk_level="HIGH",
            review_status="BLOCKED",
            finding_ids=["SC-026", "SC-037"],
            evidence_class="local_sdk_observation_and_missing_repository_pin",
            notes="No dotnet package installation or restore mutation was performed.",
        ),
        record(
            ecosystem="system-tool",
            name="Git",
            version="local observed 2.50.1; CI runner-provided",
            source="Apple/GitHub runner system installation",
            source_locator="scripts/check-secrets.sh; scripts/task_loop/git.py; .github/workflows/*",
            scope=["development", "CI", "release"],
            runtime_dev_build="checkout, diff, history scan, source timestamp and task checkpoint logic",
            declaration_location="repository scripts and workflows",
            usage_location=["scripts/check-secrets.sh:34-54", ".github/workflows/release-supply-chain.yml:75,127"],
            license="GPL-2.0-only",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="system tool; not redistributed with AreaMatrix artifacts",
            lock={"version_pin": False},
            integrity="Repository object IDs protect content; executable version is environment-selected.",
            risk_level="MEDIUM",
            review_status="PASS",
            finding_ids=[],
            evidence_class="tool_only_not_product_distribution",
            notes="GPL tool use is not direct linking into the product; no legal conclusion beyond that technical boundary is asserted.",
        ),
        record(
            ecosystem="system-tool",
            name="GitHub CLI (gh)",
            version="local observed 2.96.0; remote audit requires approved authentication",
            source="developer PATH",
            source_locator="scripts/dev_tools remote governance commands; docs/development/ci-governance.md:95-155",
            scope=["remote-governance"],
            runtime_dev_build="read-only GitHub settings and Actions evidence",
            declaration_location="docs/development/ci-governance.md:95-155",
            usage_location=["./dev governance remote-audit", "./dev governance status"],
            license="MIT",
            license_policy="DEFAULT_ALLOWED",
            license_evidence="https://github.com/cli/cli/blob/trunk/LICENSE",
            lock={"version_pin": False, "credential_used": False},
            integrity="Tool is present locally but was not authenticated or used with real credentials.",
            risk_level="MEDIUM",
            review_status="BLOCKED",
            finding_ids=["SC-034"],
            evidence_class="local_tool_present_external_state_blocked",
            notes="Public unauthenticated object queries used curl/git instead.",
        ),
        record(
            ecosystem="system-tool",
            name="curl",
            version="local observed 8.7.1; CI runner-provided",
            source="macOS/GitHub runner system installation",
            source_locator=".github/workflows/macos-ci.yml:422,449; .github/workflows/release-supply-chain.yml:111",
            scope=["CI", "release-download"],
            runtime_dev_build="HTTPS download of pinned tools and exact release artifacts",
            declaration_location="workflow run steps",
            usage_location=[".github/workflows/macos-ci.yml:422,449", ".github/workflows/release-supply-chain.yml:111"],
            license="curl license",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="runner system component; not redistributed",
            lock={"version_pin": False, "tls_only": True, "download_hash_check": True},
            integrity="TLS is required and downloaded tools/artifacts are checked against pinned or supplied hashes.",
            risk_level="MEDIUM",
            review_status="PASS",
            finding_ids=["SC-025"],
            evidence_class="system_tool_with_hash_compensating_control",
            notes="The executable itself is runner-provided.",
        ),
        record(
            ecosystem="system-tool",
            name="unzip",
            version="local observed Info-ZIP 6.00; CI runner-provided",
            source="macOS/GitHub runner system installation",
            source_locator=".github/workflows/macos-ci.yml:424,451",
            scope=["CI", "tool-bootstrap"],
            runtime_dev_build="extract verified SwiftLint/SwiftFormat archives",
            declaration_location=".github/workflows/macos-ci.yml:424,451",
            usage_location=[".github/workflows/macos-ci.yml:424", ".github/workflows/macos-ci.yml:451"],
            license="Info-ZIP license",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="runner system component; not redistributed",
            lock={"version_pin": False, "input_hash_verified": True},
            integrity="Archive bytes are SHA-256 verified before extraction; extractor version is not pinned.",
            risk_level="MEDIUM",
            review_status="PASS",
            finding_ids=["SC-025"],
            evidence_class="system_tool_with_verified_input",
            notes="Extraction is limited to CI temporary directories.",
        ),
        record(
            ecosystem="system-tool",
            name="shasum",
            version="local observed 6.02; CI runner-provided",
            source="macOS/GitHub runner system installation",
            source_locator=".github/workflows/macos-ci.yml; scripts/dev_tools/release.py",
            scope=["CI", "release-integrity"],
            runtime_dev_build="SHA-256 verification and release checksum capture",
            declaration_location="workflow and release scripts",
            usage_location=[".github/workflows/macos-ci.yml:75,90,126,391,423,450", "scripts/dev_tools/release.py:623"],
            license="Perl/Apple system component terms",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="system component license not archived",
            lock={"algorithm": "SHA-256", "version_pin": False},
            integrity="Expected digests are explicit; implementation version is environment-selected.",
            risk_level="MEDIUM",
            review_status="PASS",
            finding_ids=[],
            evidence_class="system_integrity_tool",
            notes="Used only for hashing; does not enter product packages.",
        ),
        record(
            ecosystem="system-tool",
            name="tar",
            version="runner-provided bsdtar/GNU tar",
            source="developer/GitHub runner system installation",
            source_locator="scripts/dev_tools/core_sdk.py; .github/workflows/macos-ci.yml",
            scope=["build", "CI", "artifact-packaging"],
            runtime_dev_build="CoreSDK cache/archive packaging and extraction",
            declaration_location="CoreSDK build/workflow scripts",
            usage_location=["scripts/dev_tools/core_sdk.py", ".github/workflows/macos-ci.yml"],
            license="implementation-specific system license",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="runner image provides implementation; exact source/license not bound",
            lock={"version_pin": False, "artifact_hash": True},
            integrity="Resulting artifact files and transport archive digest are verified; tar implementation is not pinned.",
            risk_level="MEDIUM",
            review_status="BLOCKED",
            finding_ids=["SC-026", "SC-038"],
            evidence_class="runner_tool_with_output_hash_but_unpinned_implementation",
            notes="Cross-run deterministic archive evidence remains platform-blocked.",
        ),
        record(
            ecosystem="system-tool",
            name="bash/zsh and POSIX base utilities",
            version="runner/host-provided",
            source="macOS/GitHub runner system installation",
            source_locator="dev; scripts/*.sh; .github/workflows/*.yml",
            scope=["development", "CI"],
            runtime_dev_build="shell orchestration, file tests, sed/awk/chmod/mkdir and validation glue",
            declaration_location=["dev:1", "scripts/check-secrets.sh:1", ".github/workflows/*.yml"],
            usage_location=["dev", "scripts/*.sh", ".github/workflows/*.yml"],
            license="mixed system component licenses",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="host/runner base image; not redistributed as AreaMatrix content",
            lock={"version_pin": False},
            integrity="Commands are repository-controlled; interpreter/base utility versions are environment-selected.",
            risk_level="MEDIUM",
            review_status="PASS",
            finding_ids=[],
            evidence_class="implicit_system_execution_environment",
            notes="No unknown repository script was executed during the audit.",
        ),
        record(
            ecosystem="system-toolchain",
            name="Apple clang/ar/lipo binary toolchain",
            version="local Apple clang 2100.0.123.102; CI selected by Xcode",
            source="Xcode command-line tools",
            source_locator="scripts/dev_tools/build.py; scripts/dev_tools/core_sdk.py; docs/development/build.md:48-51",
            scope=["native-build", "FFI", "Apple-artifact"],
            runtime_dev_build="compile bundled SQLite/native Rust dependencies, archive and merge static libraries",
            declaration_location=["core/Cargo.toml:18", "docs/development/build.md:48-51"],
            usage_location=["cc/libsqlite3-sys build.rs", "scripts/dev_tools/build.py", "scripts/dev_tools/core_sdk.py"],
            license="Apache-2.0 WITH LLVM-exception plus Apple toolchain terms",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="Xcode/LLVM installation; exact runner notices not archived",
            lock={"xcode_bound": True, "exact_version_pin": False},
            integrity="Output is hashed by CoreSDK schema 2, but compiler/archive tool versions are not immutable in CI.",
            risk_level="HIGH",
            review_status="BLOCKED",
            finding_ids=["SC-026", "SC-038"],
            evidence_class="native_build_toolchain_environment_gap",
            notes="Bundled SQLite avoids a host sqlite library dependency but still executes a C compiler during build.",
        ),
    ]


def refresh_dependency_records(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Replace remediation-era candidate facts with the current repository state."""

    for row in rows:
        name = row.get("name")
        ecosystem = row.get("ecosystem")
        if ecosystem == "cargo" and name == "anyhow":
            row.update(
                review_status="BLOCKED",
                risk_level="MEDIUM",
                finding_ids=["SC-020"],
                evidence_class="fresh_osv_plus_locked_graph_and_source_reachability_review",
                notes=(
                    "RUSTSEC-2026-0190 affects <1.0.103. The lock remains at 1.0.102, "
                    "but no downcast_mut call was found in AreaMatrix or the local UniFFI 0.28.3 sources."
                ),
            )
        elif ecosystem == "cargo" and name == "bincode":
            row.update(
                runtime_dev_build="build/proc-macro closure",
                scope=["build"],
                review_status="BLOCKED",
                risk_level="MEDIUM",
                finding_ids=["SC-035"],
                evidence_class="fresh_osv_plus_locked_parent_chain",
                notes="RUSTSEC-2025-0141 is an informational unmaintained advisory, not a vulnerability claim.",
            )
        elif ecosystem == "cargo" and name == "paste":
            row.update(
                runtime_dev_build="build/proc-macro closure",
                scope=["build"],
                review_status="BLOCKED",
                risk_level="MEDIUM",
                finding_ids=["SC-036"],
                evidence_class="fresh_osv_plus_locked_parent_chain",
                notes="RUSTSEC-2024-0436 is an informational unmaintained advisory, not a vulnerability claim.",
            )
        elif ecosystem == "cargo" and name == "r-efi":
            row.update(
                license_policy="MANUAL_REVIEW_REQUIRED",
                review_status="BLOCKED",
                evidence_class="local_target_graph_plus_license_expression_review",
                notes=(
                    "License alternatives include MIT/Apache-2.0 and LGPL-2.1-or-later. "
                    "cargo tree shows this package only in target-specific r-efi/getrandom closure; "
                    "license choice and distribution applicability still require explicit review."
                ),
            )
        elif ecosystem == "nuget":
            is_mit = name == "System.Numerics.Tensors"
            row.update(
                license="MIT" if is_mit else "NOASSERTION",
                license_policy="DEFAULT_ALLOWED" if is_mit else "EVIDENCE_INSUFFICIENT",
                license_evidence=(
                    "NuGet registration catalog licenseExpression=MIT"
                    if is_mit
                    else "NuGet registration catalog does not publish a licenseExpression"
                ),
                integrity=(
                    "packages.lock.json contentHash and source/signature policy are present; "
                    "2026-08-30 NuGet registration reports listed=true and zero registered vulnerabilities; "
                    "actual nupkg signature/package inspection was not performed"
                ),
                review_status="BLOCKED",
                finding_ids=["SC-003", "SC-024"],
                evidence_class="local_lock_plus_public_nuget_registration_readback",
                notes="All 15 locked NuGet records were queried by exact package/version.",
            )
        elif name == "Pillow":
            row.update(
                review_status="PASS",
                finding_ids=["SC-005", "SC-006"],
                evidence_class="local_hash_lock_plus_public_pypi_and_osv_readback",
                notes=(
                    "PyPI readback on 2026-08-30: 12.3.0, MIT-CMU, not yanked. "
                    "OSV exact-version query returned zero advisories."
                ),
            )
        elif name == "SwiftLint 0.65.0":
            row.update(
                declaration_location=".github/workflows/macos-ci.yml:414-428",
                usage_location=[".github/workflows/macos-ci.yml:427-428"],
                source_locator=".github/workflows/macos-ci.yml:414-428",
                license="MIT",
                license_policy="DEFAULT_ALLOWED",
                license_evidence="https://github.com/realm/SwiftLint/blob/0.65.0/LICENSE",
                integrity="Official GitHub release digest matches workflow SHA-256 exactly.",
                lock={
                    "version_pin": True,
                    "archive_sha256": "d6cb0aa7a2f5f1ef306fc9e37bcb54dc9a26facc8f7784ac0c3dd3eccf5c6ba6",
                },
                review_status="PASS",
                finding_ids=["SC-025"],
                evidence_class="local_hash_plus_official_release_digest_readback",
                notes="GitHub release 0.65.0 is published, non-draft and non-prerelease.",
            )
        elif name == "SwiftFormat 0.62.1":
            row.update(
                declaration_location=".github/workflows/macos-ci.yml:441-455",
                usage_location=[".github/workflows/macos-ci.yml:454-455"],
                source_locator=".github/workflows/macos-ci.yml:441-455",
                license="MIT",
                license_policy="DEFAULT_ALLOWED",
                license_evidence="https://github.com/nicklockwood/SwiftFormat/blob/0.62.1/LICENSE.md",
                integrity="Official GitHub release digest matches workflow SHA-256 exactly.",
                lock={
                    "version_pin": True,
                    "archive_sha256": "7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a",
                },
                review_status="PASS",
                finding_ids=["SC-025"],
                evidence_class="local_hash_plus_official_release_digest_readback",
                notes="GitHub release 0.62.1 is published, non-draft and non-prerelease.",
            )
        elif name == "Inter Bold input font":
            row.update(
                integrity=(
                    "2026-08-30 raw blob SHA-256 matches provenance.json; exact linagora blob/commit "
                    "and rsms/inter upstream commit both resolve through public GitHub readback"
                ),
                evidence_class="local_hash_plus_public_commit_blob_readback_legal_blocked",
                finding_ids=["SC-011", "SC-029"],
                review_status="BLOCKED",
                notes="Technical provenance is closed; qualified OFL/trademark/distribution review is not.",
            )
        elif name == "AREAMATRIX_*_RUNTIME executable family":
            row.update(
                source="repository test harness only; no product runtime approved",
                source_locator="core/src/external_runtime.rs:24-245",
                declaration_location=(
                    "core/src/ai_classification_suggestion/executor.rs; "
                    "core/src/ai_tags_suggestion/executor.rs; "
                    "core/src/ai_summary/executor.rs; core/src/semantic_search/executor.rs"
                ),
                usage_location=[
                    "core/src/external_runtime.rs:147-167",
                    "core/tests/support/external_runtime_harness.rs",
                ],
                version="test protocol 1",
                direct_or_transitive="implicit",
                runtime_dev_build="debug test harness only; product debug/release fail closed",
                scope=["test", "synthetic-data-only"],
                license="allowlisted permissive test fixture license",
                license_evidence="core/src/external_runtime.rs:29-40,222-245",
                license_policy="DEFAULT_ALLOWED",
                integrity=(
                    "test-only manifest binds canonical executable path, platform, SHA-256, "
                    "provider, endpoint, privacy classification, source and license"
                ),
                lock={
                    "version_pin": True,
                    "hash_pin": True,
                    "signature": False,
                    "product_admission": False,
                },
                risk_level="LOW",
                review_status="PASS",
                evidence_class="local_rechecked",
                finding_ids=["SC-021"],
                notes="No external AI runtime is approved for product execution.",
            )
        elif name == "Google Fonts Inter CSS":
            row.update(
                source="removed; prototypes use local system font stacks",
                source_locator=(
                    "assets/prototypes/landing/index.html; "
                    "assets/prototypes/workspace/index.html"
                ),
                declaration_location="not present in current files",
                usage_location=[],
                version="not applicable",
                runtime_dev_build="not used",
                scope=["prototype"],
                license="not applicable",
                license_evidence="remote font references absent from both prototype documents",
                license_policy="PROJECT_LICENSE",
                integrity="No network font request or mutable remote response remains.",
                lock={"removed": True},
                risk_level="LOW",
                review_status="PASS",
                evidence_class="local_rechecked",
                finding_ids=["SC-016"],
                notes="Historical candidate retained for audit traceability; current dependency is absent.",
            )
        elif name == "tracked UniFFI Swift/header bindings":
            row.update(
                source_locator=(
                    "core/area_matrix.udl; "
                    "apps/macos/AreaMatrix/Bridge/UniFFI/area_matrix.swift; "
                    "apps/macos/AreaMatrix/Bridge/UniFFI/area_matrixFFI.h"
                ),
                usage_location=[
                    "apps/macos/AreaMatrix/Bridge/UniFFI/area_matrix.swift:10901-10913",
                    "apps/macos/AreaMatrix/Bridge/UniFFI/area_matrixFFI.h:779",
                    "apps/macos/AreaMatrix/Bridge/CoreICloudConflictListing.swift",
                ],
                version="aligned with current UDL via locked UniFFI 0.28.3",
                integrity=(
                    "tracked Swift/header expose preview_token consistently and "
                    "./dev bindings verify passes"
                ),
                lock={
                    "generator": "UniFFI 0.28.3 via core/Cargo.lock",
                    "output_hash": True,
                    "source_alignment": True,
                },
                review_status="PASS",
                evidence_class="local_rechecked",
                finding_ids=["SC-030"],
                notes="Cross-platform packaged CoreSDK evidence remains separately blocked by SC-026.",
            )
        elif name == "AreaMatrixCoreSDK.xcframework":
            row.update(
                integrity=(
                    "schema 2 inventories and SHA-256 binds every immutable artifact file; "
                    "the currently restored cache still has a stale source/tool fingerprint"
                ),
                lock={
                    "fingerprint": True,
                    "per_file_hashes": True,
                    "signature": False,
                    "source_tool_fingerprint": True,
                },
                review_status="BLOCKED",
                evidence_class="local_validator_fixed_platform_artifact_blocked",
                finding_ids=["SC-026", "SC-027"],
                notes=(
                    "Archive/header/Swift/Package.swift/Info.plist mutation tests pass. "
                    "A fresh universal Apple artifact cannot be built because required Rust targets are absent."
                ),
            )
    return rows


def main() -> None:
    namespace = load_library()
    read_jsonl = namespace["read_jsonl"]
    write_jsonl = namespace["write_jsonl"]
    inventory = read_jsonl(AUDIT / "inventory.jsonl")
    metadata = current_metadata()
    dependencies = refresh_github_action_records(
        refresh_dependency_records(
            namespace["cargo_records"](metadata)
            + namespace["packages_lock_records"]()
            + namespace["implicit_records"]()
            + namespace["platform_records"]()
            + namespace["content_records"]()
            + system_tool_records()
        )
    )
    write_jsonl(AUDIT / "dependency-ledger.jsonl", dependencies)

    licenses = []
    for record in dependencies:
        policy = record.get("license_policy")
        licenses.append(
            {
                "audit_id": AUDIT_ID,
                "subject_type": record.get("ecosystem"),
                "subject": record.get("name"),
                "version": record.get("version"),
                "source": record.get("source"),
                "license_expression": record.get("license"),
                "policy_class": policy,
                "review_status": record.get("review_status"),
                "evidence": record.get("license_evidence"),
                "usage_scope": record.get("scope"),
                "distribution_scope": record.get("runtime_dev_build"),
                "modification": "未修改第三方源码；品牌/文档材料改编范围按 dependency record 说明",
                "notice_attribution": "THIRD_PARTY_NOTICES.md、licenses/ 与 artifact-specific 生成器已复核",
                "uncertainty": (
                    "许可证合规风险，需合格法律/许可证 reviewer 确认"
                    if policy not in {"DEFAULT_ALLOWED", "PROJECT_LICENSE"}
                    else None
                ),
                "evidence_class": record.get("evidence_class"),
            }
        )
    write_jsonl(AUDIT / "license-ledger.jsonl", licenses)

    findings = update_findings(namespace["findings"]())
    write_jsonl(AUDIT / "findings.jsonl", findings)
    coverage = namespace["build_coverage"](inventory, findings)
    old_inventory = {
        row["path"]: row for row in read_jsonl(OLD_AUDIT / "inventory.jsonl")
    }
    for row in coverage:
        path = row["path"]
        current = next(item for item in inventory if item["path"] == path)
        old = old_inventory.get(path)
        old_same = old is not None and old.get("sha256") == current.get("sha256")
        if path in FRESH_REVIEWED_PATHS:
            row["evidence"].append(
                "20260822 快照后发生字节漂移；本轮已重新阅读全文并交叉核对声明、调用、构建、发布与验证路径"
            )
            row["notes"] = (row.get("notes", "") + " 当前字节已在修复后重新复核。 ").strip()
        elif not old_same:
            row["evidence"].append(
                "文件在 20260822 全仓人工审阅中已纳入，且不在该快照之后恢复出的 70 项漂移清单内"
            )
            row["notes"] = (row.get("notes", "") + " 复用 20260822 当前字节逐文件证据。 ").strip()
    write_jsonl(AUDIT / "coverage.jsonl", coverage)

    coverage_by_path = {row["path"]: row for row in coverage}
    for item in inventory:
        item["status"] = coverage_by_path[item["path"]]["status"]
    write_jsonl(AUDIT / "inventory.jsonl", inventory)
    inventory_text = (AUDIT / "inventory.jsonl").read_bytes()

    counts = Counter(row["status"] for row in coverage)
    scope = json.loads((AUDIT / "scope.json").read_text(encoding="utf-8"))
    scope["inventory_sha256"] = hashlib.sha256(inventory_text).hexdigest()
    scope["final_local_synthesis"] = {
        "generated_at": timestamp(),
        "coverage_counts": dict(sorted(counts.items())),
        "dependency_record_count": len(dependencies),
        "license_record_count": len(licenses),
        "finding_record_count": len(findings),
        "metadata_file": str(AUDIT / "cargo-metadata.json"),
        "metadata_package_count": len(metadata.get("packages", [])),
        "fresh_post_20260822_review_count": len(FRESH_REVIEWED_PATHS),
    }
    scope["final_scope_validation"] = namespace["current_scope_validation"](inventory)
    (AUDIT / "scope.json").write_text(
        json.dumps(scope, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
