#!/usr/bin/env python3
"""Close the frozen audit ledgers without changing product files."""

from __future__ import annotations

import hashlib
import json
import os
import stat
import subprocess
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


AUDIT_ID = "error-concurrency-lifecycle-audit-20260820"
AUDIT_DIR = Path(__file__).resolve().parent
ROOT = AUDIT_DIR.parents[2]
ALLOWED_STATUSES = {
    "PENDING",
    "IN_PROGRESS",
    "PASS",
    "FINDING",
    "NOT_APPLICABLE",
    "BLOCKED",
}


FULL_PASS = {
    ".ai-governance/project/areamatrix-rules.md",
    ".codex/references/completion-evidence-checklist.md",
    ".codex/references/debugging-failure-attribution-runbook.md",
    ".codex/references/ui-evidence-tool-templates.md",
    ".codex/skills-src/areamatrix-enterprise-governance/SKILL.md",
    ".codex/skills-src/areamatrix-enterprise-governance/references/governance-map.md",
    ".codex/skills-src/areamatrix-enterprise-governance/references/review-security-ci.md",
    ".codex/skills-src/areamatrix-file-safety/SKILL.md",
    ".codex/skills-src/areamatrix-file-safety/references/acceptance-checklist.md",
    ".codex/skills-src/areamatrix-file-safety/references/risk-scenarios.md",
    ".codex/skills-src/areamatrix-macos-ui/SKILL.md",
    ".codex/skills-src/areamatrix-macos-ui/references/page-l10n-checklist.md",
    ".codex/skills-src/areamatrix-validation-driver/SKILL.md",
    ".codex/skills-src/areamatrix-validation-driver/references/report-format.md",
    ".codex/skills-src/areamatrix-validation-driver/references/validation-matrix.md",
    ".github/workflows/core-ci.yml",
    ".github/workflows/governance-ci.yml",
    ".github/workflows/release-evidence.yml",
    ".github/workflows/remote-governance.yml",
    "AGENTS.md",
    "CODE_REVIEW.md",
    "SECURITY.md",
    "apps/ios/AreaMatrix/App/AreaMatrixIOSApp.swift",
    "apps/ios/AreaMatrix/Features/Onboarding/RepositoryAccessService.swift",
    "apps/linux/AreaMatrix/AreaMatrix.Linux.csproj",
    "apps/linux/AreaMatrix/Features/Help/PlatformDifferencesView.cs",
    "apps/macos/AGENTS.md",
    "apps/macos/AreaMatrix/App/ObservabilityRuntimeAssembly.swift",
    "apps/macos/AreaMatrix/Bridge/CoreNoteReadingWriting.swift",
    "apps/macos/AreaMatrix/Features/SyncConflicts/SyncConflictReviewModel.swift",
    "apps/macos/AreaMatrix/PlatformServices/RepositoryWriteCoordinator.swift",
    "apps/windows/AreaMatrix/App.xaml.cs",
    "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj",
    "apps/windows/AreaMatrix/Features/Import/WindowsImportViewModel.Results.cs",
    "apps/windows/AreaMatrix/Features/Library/WindowsMainWindowViewModel.Snapshot.cs",
    "apps/windows/AreaMatrix/Features/Library/WindowsWatcherDiagnostics.cs",
    "apps/windows/AreaMatrix/Features/Recovery/MissingFileRecoveryViewModel.cs",
    "core/AGENTS.md",
    "core/Cargo.toml",
    "core/build.rs",
    "core/resources/classifier.yaml",
    "core/src/db/connection.rs",
    "core/src/db/staging_recovery.rs",
    "core/src/error/core_error.rs",
    "core/src/error/mapping.rs",
    "core/src/error/templates.rs",
    "core/src/error/types.rs",
    "core/src/lib.rs",
    "core/src/observability/callback.rs",
    "core/src/observability/runtime.rs",
    "core/src/repo_scan/session.rs",
    "core/src/storage/replacement_trash.rs",
    "core/src/storage/safe_move.rs",
    "core/tests/init_empty_repo_implementation.rs",
    "core/tests/recovery_scenarios.rs",
    "docs/api/error-codes.md",
    "docs/architecture/concurrency.md",
    "docs/architecture/ffi-design.md",
    "docs/architecture/fs-watcher.md",
    "docs/architecture/source-of-truth.md",
    "docs/architecture/transactional-import.md",
    "docs/development/ci-governance.md",
    "docs/development/dependency-policy.md",
    "docs/development/error-recovery-matrix.md",
    "docs/development/recovery.md",
    "docs/development/testing.md",
    "docs/development/troubleshooting.md",
    "docs/ux/error-messages.md",
    "workflow/AGENTS.md",
}


FULL_FINDING: dict[str, list[str]] = {
    "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailModel.swift": [
        "IOS-DETAIL-STALE-001"
    ],
    "apps/linux/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs": [
        "DOTNET-CANCELLATION-001"
    ],
    "apps/macos/AreaMatrix/Features/Settings/RepositoryOverviewRegenerationModel.swift": [
        "MACOS-OVERVIEW-STALE-001"
    ],
    "apps/windows/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs": [
        "DOTNET-CANCELLATION-001"
    ],
    "core/src/batch_category/fs_move.rs": ["RUST-BATCH-FSDB-001"],
    "core/src/batch_rename/apply.rs": ["RUST-BATCH-FSDB-001"],
    "core/src/overview/atomic_write.rs": ["RUST-OVERVIEW-ATOMIC-001"],
    "core/src/repo_init.rs": [
        "RUST-INIT-CLEANUP-001",
        "RUST-INIT-ROLLBACK-001",
    ],
}


PARTIAL_RANGES: dict[str, list[tuple[int, int]]] = {
    ".github/workflows/macos-ci.yml": [(1, 213)],
    "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreBridge.swift": [(111, 190)],
    "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreFFI.swift": [(90, 106)],
    "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailView.swift": [(1, 145)],
    "apps/ios/AreaMatrix/Features/Library/MobileLibraryCoreBridge.swift": [(135, 173)],
    "apps/ios/AreaMatrix/Features/Library/MobileLibraryCoreFFI.swift": [(82, 96)],
    "apps/ios/AreaMatrix/Features/Library/MobileLibraryView.swift": [(1, 105), (420, 445)],
    "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryModel.swift": [
        (1, 232),
        (396, 400),
    ],
    "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryView.swift": [
        (1, 190),
        (245, 325),
    ],
    "apps/ios/AreaMatrix/Features/Onboarding/MobileRepositoryCoreFFI.swift": [(235, 300)],
    "apps/macos/AreaMatrix/Bridge/CoreBridge.swift": [(1, 220)],
    "apps/macos/AreaMatrix/Bridge/CoreFileDeleting.swift": [(1, 220)],
    "apps/macos/AreaMatrix/Bridge/CoreFileRenaming.swift": [(1, 220)],
    "apps/macos/AreaMatrix/Bridge/CoreOverviewRegenerating.swift": [(121, 240)],
    "apps/macos/AreaMatrix/Bridge/CoreSyncConflictResolving.swift": [(1, 220)],
    "apps/macos/AreaMatrix/Features/Import/ImportFolderPreviewModel.swift": [(200, 330)],
    "apps/macos/AreaMatrix/Features/Import/ImportSingleFilePreviewModel.swift": [(100, 230)],
    "apps/macos/AreaMatrix/Features/MainList/MainFileListExternalSyncActions.swift": [(1, 190)],
    "apps/macos/AreaMatrix/Features/MainList/MainFileListModel.swift": [(1, 260)],
    "apps/macos/AreaMatrix/Features/Onboarding/OnboardingInitializationProgress.swift": [
        (100, 340)
    ],
    "apps/macos/AreaMatrix/PlatformServices/MainExternalCreatedFileWatcher.swift": [(1, 380)],
    "apps/macos/AreaMatrix/PlatformServices/Observability/CoreObservabilitySinkAdapter.swift": [
        (1, 88)
    ],
    "apps/macos/AreaMatrix/PlatformServices/Observability/ObservabilityHub.swift": [(1, 359)],
    "apps/macos/AreaMatrix/Features/Settings/LanguageSettingsPane.swift": [
        (81, 87),
        (334, 340),
    ],
    "apps/windows/AreaMatrix/Features/Import/WindowsImportViewModel.cs": [
        (120, 270),
        (340, 470),
    ],
    "apps/windows/AreaMatrix/Features/Library/WatcherStatusViewModel.cs": [
        (1, 180),
        (361, 470),
    ],
    "apps/windows/AreaMatrix/MainWindow.xaml.cs": [(1, 180), (450, 530)],
    "core/area_matrix.udl": [(1, 260)],
    "core/benches/core_hot_paths.rs": [(1, 220)],
    "core/resources/observability_catalog.json": [(1, 80)],
    "core/src/db/move_to_category.rs": [(75, 125)],
    "core/src/db/rename.rs": [(120, 175)],
    "core/src/batch_category/apply.rs": [(1, 340)],
    "core/src/note.rs": [(150, 270)],
    "core/src/observability/queue.rs": [(1, 176)],
    "core/src/overview/mod.rs": [(35, 240), (470, 525)],
    "core/src/overview/regeneration/execution.rs": [(1, 390)],
    "core/src/recovery.rs": [(150, 400)],
    "core/src/repair.rs": [(1, 700)],
    "core/src/storage/import.rs": [(1, 280)],
    "docs/api/uniffi-recipes.md": [(24, 90), (360, 420)],
    "docs/modules/overview-gen.md": [(35, 100)],
    "scripts/dev_tools/core_sdk.py": [(36, 520)],
    "scripts/dev_tools/macos.py": [(1, 250)],
    "scripts/dev_tools/macos_release_probe.py": [(70, 200)],
    "scripts/dev_tools/remote_governance.py": [(1, 90)],
    "scripts/task_loop/runner.py": [(1240, 1500), (1680, 1760)],
}


PARTIAL_FINDINGS: dict[str, list[str]] = {
    "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreBridge.swift": [
        "IOS-ERROR-MAPPING-001",
        "IOS-DETAIL-STALE-001",
    ],
    "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreFFI.swift": [
        "IOS-ERROR-MAPPING-001"
    ],
    "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailView.swift": [
        "IOS-DETAIL-STALE-001"
    ],
    "apps/ios/AreaMatrix/Features/Library/MobileLibraryCoreBridge.swift": [
        "IOS-ERROR-MAPPING-001"
    ],
    "apps/ios/AreaMatrix/Features/Library/MobileLibraryCoreFFI.swift": [
        "IOS-ERROR-MAPPING-001"
    ],
    "apps/ios/AreaMatrix/Features/Library/MobileLibraryView.swift": [
        "IOS-ERROR-MAPPING-001"
    ],
    "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryModel.swift": [
        "IOS-CONNECT-STALE-001",
        "IOS-ERROR-MAPPING-001",
    ],
    "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryView.swift": [
        "IOS-CONNECT-STALE-001"
    ],
    "apps/ios/AreaMatrix/Features/Onboarding/MobileRepositoryCoreFFI.swift": [
        "IOS-ERROR-MAPPING-001"
    ],
    "apps/macos/AreaMatrix/Features/Settings/LanguageSettingsPane.swift": [
        "MACOS-OVERVIEW-STALE-001"
    ],
    "core/src/batch_category/apply.rs": ["RUST-BATCH-FSDB-001"],
    "core/src/db/move_to_category.rs": ["RUST-BATCH-FSDB-001"],
    "core/src/db/rename.rs": ["RUST-BATCH-FSDB-001"],
    "core/src/overview/mod.rs": [
        "RUST-OVERVIEW-ATOMIC-001",
        "RUST-OVERVIEW-CAS-001",
    ],
}


SYMBOLS: dict[str, dict[str, list[str]]] = {
    "core/src/repo_init.rs": {
        "entry_points": ["init_repo", "initialize_metadata_for_repair"],
        "callers": ["Core repository API / UniFFI init entry"],
        "callees": [
            "preflight_create_empty",
            "preflight_adopt_existing",
            "cleanup_recoverable_init_dirs",
            "commit_metadata_staging",
            "InitRollback::rollback",
        ],
        "state_objects": ["InitRollback", ".areamatrix.init-*", ".areamatrix/", "AREAMATRIX.md"],
    },
    "core/src/overview/atomic_write.rs": {
        "entry_points": ["write_plans_with_rollback"],
        "callers": ["overview::regenerate_external_sync_overviews"],
        "callees": ["FileSnapshot::capture", "write_atomic_replace", "FileSnapshot::restore"],
        "state_objects": ["WritePlan", "FileSnapshot", "SnapshotState"],
    },
    "core/src/batch_rename/apply.rs": {
        "entry_points": ["apply_batch_rename_plan"],
        "callers": ["batch_rename"],
        "callees": ["with_batch_rename_transaction", "move_checked_file", "batch_update_rename_repo_owned_in_tx"],
        "state_objects": ["RenameRollbackGuard", "AppliedFsRename", "SQLite transaction"],
    },
    "core/src/batch_category/apply.rs": {
        "entry_points": ["apply_batch_category_plan"],
        "callers": ["batch_move_to_category"],
        "callees": ["with_batch_category_transaction", "move_recoverable_file", "batch_update_category_repo_owned_in_tx"],
        "state_objects": ["MoveRollbackGuard", "AppliedFsMove", "SQLite transaction"],
    },
    "core/src/batch_category/fs_move.rs": {
        "entry_points": ["move_checked_file", "move_recoverable_file"],
        "callers": ["batch_category::apply"],
        "callees": ["hard_link", "copy_to_new_destination", "remove_file"],
        "state_objects": ["CategoryDirectoryGuard", "MoveRollbackGuard", "AppliedFsMove"],
    },
    "core/src/db/connection.rs": {
        "entry_points": ["open_repo_connection", "open_repo_read_connection"],
        "callers": ["Core DB helpers"],
        "callees": ["rusqlite::Connection::open", "configure_connection"],
        "state_objects": ["SQLite connection", "WAL", "busy_timeout"],
    },
    "core/src/error/core_error.rs": {
        "entry_points": ["CoreError", "CoreError::to_error_mapping"],
        "callers": ["Core API error producers", "map_core_error"],
        "callees": ["mapping_template_for_kind"],
        "state_objects": ["ErrorKind", "ErrorMapping"],
    },
    "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailModel.swift": {
        "entry_points": ["reloadMetadata", "reloadChangeLog", "reloadNote"],
        "callers": ["MobileFileDetailView toolbar/.task/retry/segment tasks"],
        "callees": ["MobileFileDetailCoreBridge"],
        "state_objects": ["metadataState", "changeLogState", "noteState", "selectedSegment"],
    },
    "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryModel.swift": {
        "entry_points": ["connectSelectedURL", "reconnect", "retryICloudPermissionCheck", "handleOpenURL"],
        "callers": ["ConnectRepositoryView", "ConnectRepositoryEntryView.onOpenURL"],
        "callees": ["RepositoryAccessServicing", "MobileRepositoryCoreBridge"],
        "state_objects": ["checkState", "route", "error", "latestValidation", "latestCloudState"],
    },
    "apps/macos/AreaMatrix/Features/Settings/RepositoryOverviewRegenerationModel.swift": {
        "entry_points": ["load", "prepare", "commit", "cancel", "recoverSafely"],
        "callers": ["LanguageSettingsPane", "RepositoryOverviewRegenerationSection"],
        "callees": ["CoreOverviewRegenerating", "OverviewRegenerationCoordinator"],
        "state_objects": ["phase", "languageStatus", "concreteContentLocale", "sharedOperation"],
    },
    "apps/macos/AreaMatrix/PlatformServices/RepositoryWriteCoordinator.swift": {
        "entry_points": ["withWriteAccess"],
        "callers": ["import/recovery/repair/external-sync feature models"],
        "callees": ["acquire", "release"],
        "state_objects": ["activeRepositoryKeys", "waiters"],
    },
    "apps/windows/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs": {
        "entry_points": ["LoadCapabilitiesAsync", "InspectContractAsync"],
        "callers": ["PlatformDifferencesView"],
        "callees": ["IPlatformDifferencesCoreBridge"],
        "state_objects": ["Status", "Report", "Capabilities", "ErrorMessage"],
    },
    "apps/linux/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs": {
        "entry_points": ["LoadCapabilitiesAsync", "InspectContractAsync"],
        "callers": ["PlatformDifferencesView"],
        "callees": ["IPlatformDifferencesCoreBridge"],
        "state_objects": ["Status", "Report", "Capabilities", "ErrorMessage"],
    },
}


FINDINGS: list[dict[str, Any]] = [
    {
        "id": "RUST-INIT-CLEANUP-001",
        "severity": "P0",
        "confidence": "high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "初始化预检会删除仅凭名称和目录形状推断为残留的用户目录",
        "category": ["filesystem", "recovery", "ownership", "lifecycle"],
        "locations": [
            {"path": "core/src/repo_init.rs", "lines": "198-218", "symbol": "preflight_create_empty"},
            {"path": "core/src/repo_init.rs", "lines": "230-250", "symbol": "preflight_adopt_existing"},
            {"path": "core/src/repo_init.rs", "lines": "253-330", "symbol": "cleanup_recoverable_init_dirs"},
        ],
        "entry": "init_repo(CreateEmpty|AdoptExisting)",
        "call_chain": [
            "init_repo",
            "preflight_create_empty/preflight_adopt_existing",
            "cleanup_recoverable_init_dirs",
            "is_recoverable_init_dir",
            "fs::remove_dir_all",
        ],
        "failure_or_interleaving": "资料库根中只要存在以 .areamatrix.init- 开头且内容满足宽松形状检查的目录（空目录也满足），预检就递归删除；没有 operation UUID、creator marker、journal identity 或内容 hash 证明该目录属于 AreaMatrix。",
        "happens_before_gap": "目录所有权证明与删除之间不存在可信身份关系；名称/形状检查不能建立 ownership happens-before。",
        "impact": "可递归删除用户创建或同步进来的目录及其内容，直接违反接管已有目录不得删除用户文件的不变量。",
        "invariants": ["接管已有目录不得删除用户文件", "恢复只能清理可证明由本次/既有 AreaMatrix 操作拥有的 residue"],
        "minimum_fix": "创建 init staging 时写入不可伪造/可核验的 operation marker 与 manifest；恢复仅接受已知 UUID/journal 且逐项校验的路径，未知或无 marker 的目录 fail closed 并报告。",
        "rollback": "修复只收紧清理条件；若新条件产生兼容性问题，可保留目录并提示人工恢复，不能回退到形状推断删除。",
        "validation": ["临时目录中放置同名前缀空目录/内部形状用户目录，断言预检保留", "已签名真实 residue 可幂等清理", "symlink/未知条目 fail closed"],
        "confirmation_boundary": "静态代码已确认；无需真实用户资料库。",
    },
    {
        "id": "RUST-INIT-ROLLBACK-001",
        "severity": "P0",
        "confidence": "medium-high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "CreateEmpty 在 metadata commit 后失败会无条件删除并发写入的 metadata 和根文件",
        "category": ["filesystem", "rollback", "concurrency", "ownership"],
        "locations": [
            {"path": "core/src/repo_init.rs", "lines": "97-149", "symbol": "init_create_empty_repo/init_create_empty_inner"},
            {"path": "core/src/repo_init.rs", "lines": "188-195", "symbol": "commit_metadata_staging"},
            {"path": "core/src/repo_init.rs", "lines": "407-462", "symbol": "InitRollback::rollback"},
        ],
        "entry": "init_repo(CreateEmpty)",
        "call_chain": ["commit_metadata_staging", "create_default_category_dirs/write_root_areamatrix_file/record_initialized_overview_provenance", "InitRollback::rollback", "remove_file/remove_dir_all"],
        "failure_or_interleaving": "线程 A rename 安装 .areamatrix 后继续执行分类/概览/provenance；线程 B 或同步进程写入 .areamatrix 或编辑刚创建的 AREAMATRIX.md；A 后续失败后不校验 inode、hash、目录新增项或 operation id 就删除。",
        "happens_before_gap": "metadata commit 后没有封闭 ownership 或 compare-and-swap；rollback 假定其仍独占刚提交路径。",
        "impact": "并发写入的 metadata、用户对根 AREAMATRIX.md 的编辑或其他新内容可能被删除。清理错误还被忽略，调用方无法区分安全回滚和残留。",
        "invariants": ["补偿不得删除无法证明属于本次操作的内容", "根 managed block 外用户内容必须保留"],
        "minimum_fix": "commit 后使用持久 operation manifest/identity；rollback 逐项校验 inode/hash/内容清单，发现未知变化立即停止并返回 recoverable state；记录清理失败。",
        "rollback": "保留 metadata 并转入 startup recovery 比递归删除更安全；回退时不得恢复无条件删除。",
        "validation": ["commit 后注入 provenance 失败并并发新增 metadata 文件", "commit 后编辑根文件再触发失败", "断言未知变化被保留并报告"],
        "confirmation_boundary": "静态删除路径已确认；交错复现需要故障注入。",
    },
    {
        "id": "RUST-OVERVIEW-ATOMIC-001",
        "severity": "P0",
        "confidence": "high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "概览原子写使用固定临时名并跟随 symlink，回滚也存在 symlink TOCTOU",
        "category": ["filesystem", "symlink", "atomic-write", "rollback", "concurrency"],
        "locations": [
            {"path": "core/src/overview/mod.rs", "lines": "494-506", "symbol": "write_atomic_replace"},
            {"path": "core/src/overview/atomic_write.rs", "lines": "19-31", "symbol": "write_plans_with_rollback"},
            {"path": "core/src/overview/atomic_write.rs", "lines": "45-69", "symbol": "FileSnapshot::capture/restore"},
        ],
        "entry": "任一 incremental/full overview 写入",
        "call_chain": ["write_plans_with_rollback", "write_atomic_replace", "fs::write(<target>.md.tmp)", "fs::rename"],
        "failure_or_interleaving": "攻击者或同步进程预先把固定 <target>.md.tmp 建成 symlink，fs::write 会跟随并截断链接目标；并发 writer 也共享同一 tmp。后续 plan 失败时，snapshot 与 restore 之间若目标被换成 symlink，fs::write(path, bytes) 再次跟随链接。",
        "happens_before_gap": "临时文件没有 create_new/唯一 operation id，snapshot identity 也未在 restore 前复核。",
        "impact": "可覆盖资料库外当前用户有权限写入的文件；并发 writer 可互删 tmp、产生失败或让最终内容/provenance 与 operation 不一致。",
        "invariants": ["自动生成不得覆盖用户文件", "回滚不得越过资料库/operation ownership"],
        "minimum_fix": "在受控目录使用 UUID 临时文件 + OpenOptions::create_new + O_NOFOLLOW/等价安全打开；sync 后原子替换；restore 前复核 regular-file identity 与预期 hash，拒绝 symlink/特殊文件。",
        "rollback": "若平台不支持安全替换，fail closed 并保留 journal，不使用 fs::write 回滚。",
        "validation": ["预置 tmp symlink 指向外部 sentinel，断言 sentinel 不变", "snapshot 后换 symlink 的故障注入", "两 writer barrier 交错测试"],
        "confirmation_boundary": "symlink sink 静态确认；跨平台行为需 macOS/Linux/Windows fixture 验证。",
    },
    {
        "id": "RUST-OVERVIEW-CAS-001",
        "severity": "P0",
        "confidence": "high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "增量概览的 provenance 检查与最终替换之间无 CAS，可覆盖根文件并发用户编辑",
        "category": ["filesystem", "concurrency", "toctou", "user-content"],
        "locations": [
            {"path": "core/src/overview/mod.rs", "lines": "70-135", "symbol": "regenerate_external_sync_overviews"},
            {"path": "core/src/overview/mod.rs", "lines": "158-179", "symbol": "ensure_incremental_targets_trusted"},
            {"path": "core/src/overview/mod.rs", "lines": "494-506", "symbol": "write_atomic_replace"},
        ],
        "entry": "regenerate_for_node / external sync overview refresh",
        "call_chain": ["读取 DB/目标并构建完整 WritePlan", "ensure_incremental_targets_trusted", "write_plans_with_rollback", "rename 覆盖目标", "record_provenance"],
        "failure_or_interleaving": "A 验证旧 hash 与 managed block 后暂停；B 修改 AREAMATRIX.md managed block 外用户正文；A 用基于旧内容生成的整文件临时副本 rename 覆盖 B。两个 Core writer 也可同时通过旧 provenance。",
        "happens_before_gap": "preflight hash 与 rename 之间没有 per-repo/target lock、版本号或最终 hash CAS。",
        "impact": "根 AREAMATRIX.md managed block 外用户内容丢失；生成文件与 provenance 也可能漂移。",
        "invariants": ["根 AREAMATRIX.md 只替换合法 managed block", "managed block 外用户内容保持不变"],
        "minimum_fix": "最终替换前重新读取并比较目标 identity/hash；对根文件基于最新内容重新合并 managed block；按 repo/target 串行化并持久化 operation identity。",
        "rollback": "CAS 冲突时保留用户当前文件并返回 Conflict，不回写旧 snapshot。",
        "validation": ["在 provenance check 后编辑根文件并 barrier 继续", "并发两次不同 locale/node 更新", "断言冲突且用户文本不变"],
        "confirmation_boundary": "静态 TOCTOU 已确认；确定性交错测试尚未运行。",
    },
    {
        "id": "RUST-BATCH-FSDB-001",
        "severity": "P1",
        "confidence": "high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "批量 rename/category 在 SQLite transaction 内先移动文件，硬崩溃后无持久恢复",
        "category": ["filesystem", "database", "transaction", "crash-recovery", "lifecycle"],
        "locations": [
            {"path": "core/src/batch_rename/apply.rs", "lines": "12-33", "symbol": "apply_batch_rename_plan"},
            {"path": "core/src/batch_rename/apply.rs", "lines": "168-215", "symbol": "try_apply_change"},
            {"path": "core/src/batch_rename/apply.rs", "lines": "293-350", "symbol": "AppliedFsRename/RenameRollbackGuard"},
            {"path": "core/src/batch_category/apply.rs", "lines": "18-39", "symbol": "apply_batch_category_plan"},
            {"path": "core/src/batch_category/apply.rs", "lines": "239-289", "symbol": "try_apply_change"},
            {"path": "core/src/batch_category/fs_move.rs", "lines": "52-111", "symbol": "AppliedFsMove/MoveRollbackGuard"},
            {"path": "core/src/db/rename.rs", "lines": "130-141", "symbol": "with_batch_rename_transaction"},
            {"path": "core/src/db/move_to_category.rs", "lines": "85-96", "symbol": "with_batch_category_transaction"},
        ],
        "entry": "batch_rename / batch_move_to_category",
        "call_chain": ["打开 SQLite transaction", "closure 内移动文件/sidecar", "更新 row/change log/undo", "commit transaction", "disarm RAII guards"],
        "failure_or_interleaving": "文件移动后、DB commit 前进程崩溃/SIGKILL/断电；Drop 不执行。正常 commit/closure 错误时 Drop 的 rollback 错误也被忽略。startup recovery 没有对应 batch journal。",
        "happens_before_gap": "FS mutation 的持久证据没有先于 mutation 落盘；DB commit 也不能原子覆盖 FS。",
        "impact": "DB 仍指向旧路径而文件已移动，可能长期列表缺失、后续 sync/retry 误处理或重复操作；transaction 生命周期跨越了无法与 SQLite 原子提交的 FS mutation。",
        "invariants": ["成功操作 FS/DB 同时可见", "失败/退出不得留下不可判定的不一致"],
        "minimum_fix": "FS 变更前持久化 operation journal；使用短事务 reservation/CAS，执行 FS，再用短事务 promote；startup recovery roll-forward/rollback；持久记录 rollback failure。",
        "rollback": "新流程失败时保留 journal 和文件，不尝试无证据删除；可用 feature flag 回退到只读预览但不能回退到无 journal 写。",
        "validation": ["在每个 FS move 后强制终止子进程", "重启执行 startup recovery", "注入 rollback IO failure", "检查 DB integrity/path/change log/sidecar"],
        "confirmation_boundary": "事务/FS 顺序静态确认；硬崩溃恢复需子进程故障注入。",
    },
    {
        "id": "IOS-ERROR-MAPPING-001",
        "severity": "P1",
        "confidence": "high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "iOS 多条链路绕过结构化 ErrorMapping，直接显示 Core/SQLite 技术文本",
        "category": ["ffi", "error-propagation", "privacy", "recovery", "ui-contract"],
        "locations": [
            {"path": "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreFFI.swift", "lines": "90-106", "symbol": "MobileFileDetailCoreSDKMapping.error"},
            {"path": "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreBridge.swift", "lines": "111-137", "symbol": "MobileFileDetailError.message/map"},
            {"path": "apps/ios/AreaMatrix/Features/Library/MobileLibraryCoreFFI.swift", "lines": "82-96", "symbol": "MobileLibraryCoreSDKMapping.error"},
            {"path": "apps/ios/AreaMatrix/Features/Library/MobileLibraryCoreBridge.swift", "lines": "135-173", "symbol": "MobileLibraryQueryError"},
            {"path": "apps/ios/AreaMatrix/Features/Onboarding/MobileRepositoryCoreFFI.swift", "lines": "270-287", "symbol": "mapError"},
            {"path": "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryModel.swift", "lines": "396-400", "symbol": "connectionError"},
            {"path": "apps/ios/AreaMatrix/Features/Library/MobileLibraryView.swift", "lines": "82-93,433-438", "symbol": "LibraryListViewModel.reload/errorSection"},
        ],
        "entry": "iOS connect/list/detail Core calls",
        "call_chain": ["AreaMatrixCoreSDK.CoreError", "feature-local switch or default String(describing:)", "feature error String", "SwiftUI Label/Text"],
        "error_propagation": "Db/DbLocked/DbCorrupted 被合并为带原始 message 的 .database；其他未列举 variants 变成 String(describing: coreError) 或 localizedDescription。UI 直接显示该字符串，未调用 map_core_error，也没有 code/severity/recoverability/recovery_action_ids。",
        "retry_semantics": "DbLocked 的 Retryable 与 DbCorrupted 的 Fatal/Repair 被抹平；页面只显示通用 Retry/文本，无法按稳定合同选择动作。",
        "impact": "损坏 DB 可能无法进入阻断 repair，locked/corrupt 恢复动作混淆；绝对路径、SQLite 文本或内部错误可能直接暴露给用户。",
        "invariants": ["不得解析/显示 localizedDescription 决定业务恢复", "typed DB 子语义必须保持到 UI", "技术详情只能在受控诊断面显示"],
        "minimum_fix": "统一复用 CoreErrorMappingSnapshot/AppSemanticError；feature state 保存稳定 descriptor，View 通过 AppLocalizer 解析；技术详情单独受控展示，按 recovery_action_ids 提供真实动作。",
        "rollback": "保留旧 feature enum 作为适配层时也必须承载 mapping snapshot，不能回退到 raw String。",
        "validation": ["18 个 CoreError variant 的 iOS mapping table test", "DbLocked 显示 Retry，DbCorrupted 路由 Repair", "路径/用户名不出现在普通 UI", "en/zh-Hans 同一 retained state"],
        "confirmation_boundary": "所列三条 UI 链静态确认；其余 iOS consumer 尚未逐文件审完。",
    },
    {
        "id": "IOS-DETAIL-STALE-001",
        "severity": "P2",
        "confidence": "high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "iOS 详情重复刷新无 generation，旧请求可覆盖新状态",
        "category": ["swift-concurrency", "cancellation", "ui-state", "lifecycle"],
        "locations": [
            {"path": "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailModel.swift", "lines": "95-147", "symbol": "reloadMetadata/reloadChangeLog/reloadNote"},
            {"path": "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailView.swift", "lines": "37-50,75-82,110-123", "symbol": "toolbar/.task/retry callbacks"},
            {"path": "apps/ios/AreaMatrix/Features/Detail/MobileFileDetailCoreBridge.swift", "lines": "141-161", "symbol": "LiveMobileRepositoryCoreBridge"},
        ],
        "entry": "刷新按钮、Retry、segment 切换和 view .task",
        "call_chain": ["独立 Task", "@MainActor model reload", "await Task.detached FFI", "无 identity 检查写 Published state"],
        "failure_or_interleaving": "A 先发起但慢，B 后发起且先完成写入新结果，A 随后完成并覆盖。刷新按钮在 loading 时未禁用。",
        "cancellation_semantics": "View task 取消不会中断 detached 同步 FFI；返回后 model 未检查 Task.isCancelled/generation，仍写成功或失败。",
        "impact": "详情、日志或笔记显示旧数据/旧错误；页面销毁或快速交互后的晚到结果可污染仍被持有的 model。",
        "invariants": ["异步 UI completion 必须拒绝过期结果", "取消后不得把旧结果呈现为当前结果"],
        "minimum_fix": "三类请求分别保存 Task 或递增 generation；新请求替换旧请求，completion 前同时检查 generation、fileID/segment 与 cancellation。",
        "rollback": "generation 仅影响呈现提交；底层不可取消调用仍可安全完成，不需要强杀 Rust。",
        "validation": ["可控 continuation 让第二次请求先完成", "取消 view task 后释放结果", "断言旧 completion 不写 state"],
        "confirmation_boundary": "静态交错已确认；iOS XCTest 未运行。",
    },
    {
        "id": "IOS-CONNECT-STALE-001",
        "severity": "P2",
        "confidence": "medium-high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "iOS 资料库连接与外部 URL 入口共享状态但没有请求身份校验",
        "category": ["swift-concurrency", "routing", "security-scope", "lifecycle"],
        "locations": [
            {"path": "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryModel.swift", "lines": "47-99,105-179,137-232", "symbol": "connect/reconnect/handleOpenURL"},
            {"path": "apps/ios/AreaMatrix/App/AreaMatrixIOSApp.swift", "lines": "48-50", "symbol": "onOpenURL"},
            {"path": "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryView.swift", "lines": "145-160,263-307", "symbol": "recent/picker/retry callbacks"},
        ],
        "entry": "folder picker/reconnect/retry 与 app onOpenURL share-import",
        "call_chain": ["独立 Task", "beginChecking", "security-scoped access", "validate/cloud/config/bookmark awaits", "写 route/error/latestValidation/latestCloudState"],
        "failure_or_interleaving": "正常按钮在 isChecking 时禁用，但系统 onOpenURL 可在现有连接流程等待期间启动另一条任务；两条任务没有 UUID、URL 匹配或 Task identity，旧 completion 可覆盖新 route。",
        "cancellation_semantics": "没有保存连接 Task；路由 dismiss/picker 取消只改状态，不会取消或拒绝在途 completion。security scope 自身通过 defer 正确释放。",
        "impact": "打开错误资料库/确认页、把旧错误覆盖新连接、或让 share-import takeover 与手工选择互相覆盖。",
        "invariants": ["资料库切换后的旧任务不得覆盖新 route", "security-scope 生命周期必须与对应请求绑定"],
        "minimum_fix": "连接 operation 使用 generation/UUID 和规范化 URL；每个 await 后 guard 当前 identity；新操作取消旧 Swift task并在 completion 丢弃旧结果。",
        "rollback": "取消只阻止呈现提交，defer 继续释放 security scope；不强制中断同步 Core。",
        "validation": ["onOpenURL 与 picker 两条受控 continuation 反序完成", "dismiss 后晚到 completion", "断言 scope stop 各执行一次且 route 属于最新请求"],
        "confirmation_boundary": "可达入口和无 identity 静态确认；真实 iOS lifecycle 仍需验证。",
    },
    {
        "id": "MACOS-OVERVIEW-STALE-001",
        "severity": "P2",
        "confidence": "high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "macOS overview language status load 无 generation，快速语言变化会旧结果回写",
        "category": ["swift-concurrency", "ui-state", "localization", "lifecycle"],
        "locations": [
            {"path": "apps/macos/AreaMatrix/Features/Settings/RepositoryOverviewRegenerationModel.swift", "lines": "101-113", "symbol": "load(contentLocale:)"},
            {"path": "apps/macos/AreaMatrix/Features/Settings/LanguageSettingsPane.swift", "lines": "81-87,334-340", "symbol": "task/onChange/refreshOverviewStatus"},
        ],
        "entry": "LanguageSettingsPane .task 与 interface-language onChange",
        "call_chain": ["独立 Task", "model.load(locale)", "await overviewLanguageStatus", "无 locale/generation guard 写 languageStatus/phase"],
        "failure_or_interleaving": "locale A 请求先开始后变慢；locale B 请求完成并写新状态；A 返回后覆盖 B。load 也没有检查当前 phase，可能干扰另一 operation 的呈现。",
        "cancellation_semantics": "SwiftUI task 取消或语言再次变化不会拒绝旧 completion；同步 FFI 的 detached 语义不保证即时取消。",
        "impact": "设置页显示错误目标语言/同步状态，可能诱导用户对错误 locale 进入 regeneration preflight。",
        "invariants": ["保留状态应随当前界面/内容 locale 投影", "旧异步结果不得覆盖当前设置"],
        "minimum_fix": "load 使用 generation/Task identity，completion 校验 locale 和 phase；新 load 取消旧 Swift task。",
        "rollback": "只丢弃旧 completion，不取消已经开始的 Core 读取。",
        "validation": ["A/B locale 受控反序 completion", "页面消失/语言切换取消", "断言 prepare 使用当前 concrete locale"],
        "confirmation_boundary": "静态交错已确认；macOS XCTest/UI 未运行。",
    },
    {
        "id": "DOTNET-CANCELLATION-001",
        "severity": "P3",
        "confidence": "high",
        "status": "FINDING",
        "confirmation_state": "STATIC_CONFIRMED",
        "title": "Windows/Linux PlatformDifferences 把 OperationCanceledException 映射为普通失败",
        "category": ["dotnet", "cancellation", "error-propagation", "ui-state"],
        "locations": [
            {"path": "apps/windows/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs", "lines": "179-226", "symbol": "LoadCapabilitiesAsync/InspectContractAsync"},
            {"path": "apps/linux/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs", "lines": "182-231", "symbol": "LoadCapabilitiesAsync/InspectContractAsync"},
        ],
        "entry": "PlatformDifferences load/check APIs",
        "call_chain": ["caller token", "bridge async call", "OperationCanceledException", "catch(Exception)", "Failed/error UI state"],
        "error_propagation": "两个平台的 catch(Exception) 未排除 OperationCanceledException；finally 清 busy 后，上层无法再识别取消。",
        "cancellation_semantics": "取消被转换为 UnknownSnapshot/Failed，并提示 Retry，而不是保持/恢复 idle 或向上传播。Windows 当前 View 使用默认 token，Linux wrapper 公开 token，因此当前影响以 Linux/API consumer 更直接。",
        "impact": "页面关闭、目标切换或上层取消可显示虚假失败并覆盖后续有效状态。",
        "invariants": ["取消不是失败", "上层必须能区分用户取消和可重试错误"],
        "minimum_fix": "catch OperationCanceledException 后重新抛出或恢复中性状态；普通 catch 使用 when filter。",
        "rollback": "无持久副作用；恢复旧行为仅影响呈现，不应自动重试。",
        "validation": ["预取消 token", "等待中取消 token", "断言 OCE 传播且无失败文案"],
        "confirmation_boundary": "静态 catch 路径已确认；平台 UI runtime 未运行。",
    },
]


ERROR_CONTRACTS = [
    ("Io", "message", "io_error", "medium", "Retryable", ["retry", "collect_diagnostics"]),
    ("Db", "message", "database_error", "high", "UserActionRequired", ["collect_diagnostics", "open_recovery"]),
    ("DbLocked", "message", "database_locked", "medium", "Retryable", ["retry", "collect_diagnostics"]),
    ("DbCorrupted", "message", "database_corrupted", "critical", "Fatal", ["open_recovery", "collect_diagnostics"]),
    ("Config", "reason", "config_error", "medium", "UserActionRequired", ["open_settings", "review_configuration"]),
    ("Validation", "reason", "validation_error", "low", "UserActionRequired", ["fix_input"]),
    ("Classify", "reason", "classification_error", "low", "RefreshRequired", ["open_classifier", "refresh"]),
    ("Conflict", "path", "conflict", "medium", "UserActionRequired", ["review_conflict", "reload_latest"]),
    ("RevisionConflict", "resource/revisions", "revision_conflict", "medium", "UserActionRequired", ["review_changes", "reload_latest"]),
    ("DuplicateFile", "existing_path", "duplicate_file", "low", "UserActionRequired", ["skip", "keep_both", "review_replace"]),
    ("FileNotFound", "path", "file_not_found", "low", "RefreshRequired", ["refresh", "locate_file"]),
    ("ExpiredAction", "action_id", "expired_action", "low", "RefreshRequired", ["refresh_history"]),
    ("RepoNotInitialized", "path", "repository_not_initialized", "high", "UserActionRequired", ["initialize_repository", "choose_repository"]),
    ("InvalidPath", "path", "invalid_path", "low", "UserActionRequired", ["change_path"]),
    ("ICloudPlaceholder", "path", "icloud_placeholder_not_downloaded", "medium", "Retryable", ["download_and_retry", "choose_local_repository"]),
    ("StagingRecoveryRequired", "path", "staging_recovery_required", "high", "UserActionRequired", ["open_recovery"]),
    ("PermissionDenied", "path", "permission_denied", "high", "UserActionRequired", ["choose_folder", "open_system_settings"]),
    ("Internal", "message", "internal_error", "critical", "Fatal", ["collect_diagnostics", "leave_flow", "open_issue"]),
]


CONCURRENCY_ROWS = [
    {
        "id": "CONCURRENCY-SWIFT-FFI",
        "status": "BLOCKED",
        "participants": ["SwiftUI/MainActor", "CoreBridge actor instance", "Task.detached", "sync UniFFI", "Rust Core"],
        "coordination": ["actor instance isolation", "Core transaction/guard/token"],
        "shared_state": ["repository files", "SQLite", "UI state"],
        "evidence": ["docs/architecture/concurrency.md:27-76"],
        "notes": "架构合同已读；全部 Bridge 调用方未逐文件闭环。Task.detached 本身是规定模式，不单独构成 finding。",
    },
    {
        "id": "CONCURRENCY-REPO-WRITE-COORDINATOR",
        "status": "PASS",
        "participants": ["feature tasks per repository"],
        "coordination": ["RepositoryWriteCoordinator actor", "normalized repo key", "cancelable waiter queue"],
        "shared_state": ["per-repo write access"],
        "evidence": ["apps/macos/AreaMatrix/PlatformServices/RepositoryWriteCoordinator.swift:1-78"],
        "notes": "所读实现未见 double-resume、漏 release 或 waiter cancellation 缺陷；全调用面仍由 coverage 的 BLOCKED 文件限制。",
    },
    {
        "id": "CONCURRENCY-SQLITE",
        "status": "PASS",
        "participants": ["Core DB readers", "single SQLite writer"],
        "coordination": ["WAL", "foreign_keys", "busy_timeout=5000", "transactions"],
        "shared_state": ["index.db", "WAL/SHM"],
        "evidence": ["core/src/db/connection.rs:1-147", "docs/architecture/concurrency.md:106-129"],
        "notes": "连接配置范围 PASS；不能外推为所有 FS/DB 跨资源操作安全。",
    },
    {
        "id": "CONCURRENCY-INIT",
        "status": "FINDING",
        "participants": ["repo init", "user/sync/second process"],
        "coordination": ["none after metadata rename"],
        "shared_state": [".areamatrix.init-*", ".areamatrix/", "AREAMATRIX.md"],
        "evidence": ["RUST-INIT-CLEANUP-001", "RUST-INIT-ROLLBACK-001"],
        "notes": "cleanup/rollback ownership 与并发写入存在 P0 缺口。",
    },
    {
        "id": "CONCURRENCY-OVERVIEW-INCREMENTAL",
        "status": "FINDING",
        "participants": ["overview writer A", "overview writer/user edit B"],
        "coordination": ["preflight provenance only; no final CAS/target lock"],
        "shared_state": ["generated markdown", "AREAMATRIX.md", "fixed .md.tmp", "provenance rows"],
        "evidence": ["RUST-OVERVIEW-ATOMIC-001", "RUST-OVERVIEW-CAS-001"],
        "notes": "固定 tmp、symlink 与最终 CAS 均缺失。",
    },
    {
        "id": "CONCURRENCY-BATCH-FSDB",
        "status": "FINDING",
        "participants": ["batch rename/category", "SQLite writer", "filesystem"],
        "coordination": ["SQLite transaction", "in-process RAII only"],
        "shared_state": ["user files/sidecars", "files rows", "change log", "undo"],
        "evidence": ["RUST-BATCH-FSDB-001"],
        "notes": "缺 crash-durable journal。",
    },
    {
        "id": "CONCURRENCY-FSEVENTS",
        "status": "PASS",
        "participants": ["FSEvents callback", "flush task", "ordered window drain", "Core sync", "cursor ack"],
        "coordination": ["generation", "cancelable flush", "queue head", "RepositoryWriteCoordinator"],
        "shared_state": ["pending events", "cursor watermark", "in-flight refs"],
        "evidence": ["apps/macos/AreaMatrix/PlatformServices/MainExternalCreatedFileWatcher.swift:1-380", "apps/macos/AreaMatrix/Features/MainList/MainFileListExternalSyncActions.swift:1-190"],
        "notes": "已读范围未见 cursor 越过失败队首；文件整体仍可能因未读尾段在 coverage 中 BLOCKED。",
    },
    {
        "id": "CONCURRENCY-IOS-DETAIL",
        "status": "FINDING",
        "participants": ["toolbar/retry/segment tasks", "MainActor model", "detached FFI"],
        "coordination": ["none per request"],
        "shared_state": ["metadataState", "changeLogState", "noteState"],
        "evidence": ["IOS-DETAIL-STALE-001"],
        "notes": "旧 completion 可覆盖新状态。",
    },
    {
        "id": "CONCURRENCY-IOS-CONNECT",
        "status": "FINDING",
        "participants": ["picker/reconnect task", "onOpenURL task", "MainActor model"],
        "coordination": ["UI busy disable only; no operation identity"],
        "shared_state": ["route", "checkState", "validation", "cloud state"],
        "evidence": ["IOS-CONNECT-STALE-001"],
        "notes": "系统 URL 入口可绕过普通按钮 busy 串行。",
    },
    {
        "id": "CONCURRENCY-MACOS-OVERVIEW-UI",
        "status": "FINDING",
        "participants": ["language change tasks", "MainActor overview model", "Core read"],
        "coordination": ["shared operation coordinator for staged writes; no load generation"],
        "shared_state": ["languageStatus", "phase", "concreteContentLocale"],
        "evidence": ["MACOS-OVERVIEW-STALE-001"],
        "notes": "prepare 在 await 前置 busy，重复 prepare 候选已排除；load 仍存在竞态。",
    },
    {
        "id": "CONCURRENCY-LINUX-UI",
        "status": "BLOCKED",
        "participants": [".NET async continuations", "future/current Linux UI host"],
        "coordination": ["ConfigureAwait(false); no reviewed dispatcher"],
        "shared_state": ["INotifyPropertyChanged models"],
        "evidence": ["apps/linux/AreaMatrix/Features/Help/PlatformDifferencesViewModel.cs:176-231", "apps/linux/AreaMatrix/Features/System/LinuxWatcherStatusViewModel.cs:241-303"],
        "notes": "当前 csproj/view wrapper 未建立 GTK binding/PropertyChanged subscriber，不能证明 cross-thread UI sink；需真实 Linux UI runtime。",
    },
    {
        "id": "CONCURRENCY-OBSERVABILITY",
        "status": "PASS",
        "participants": ["Core delivery worker", "callback worker", "Swift ingress", "ObservabilityHub"],
        "coordination": ["bounded queues", "timeout", "catch_unwind", "ordered stop"],
        "shared_state": ["events", "drop counters", "health", "rolling store"],
        "evidence": ["core/src/observability/callback.rs:1-100", "core/src/observability/runtime.rs:1-498", "apps/macos/AreaMatrix/App/ObservabilityRuntimeAssembly.swift:1-449"],
        "notes": "所读文件 PASS；Hub/adapter 尚有未读范围，端到端结论仍受 coverage BLOCKED 限制。",
    },
]


CANCELLATION_ROWS = [
    {
        "id": "CANCEL-SYNC-FFI",
        "status": "BLOCKED",
        "operation": "Swift Task -> synchronous Rust FFI",
        "cancel_point": "调用前后或相邻小调用之间",
        "bottom_work_after_cancel": "已开始的同步 Rust 调用继续到返回",
        "cleanup": "依赖 Core 单次调用事务/guard/session",
        "late_write_risk": "调用方必须用 generation/state token 拒绝旧 UI completion",
        "retry": "按 report/session/token；不得假定 Task.cancel 已撤销副作用",
        "evidence": ["docs/architecture/concurrency.md:59-76,166-172", "docs/api/uniffi-recipes.md:366-382"],
        "notes": "合同明确，全部调用方未逐项闭环。",
    },
    {
        "id": "CANCEL-IOS-DETAIL",
        "status": "FINDING",
        "operation": "iOS detail reload",
        "cancel_point": "View task cancellation / newer reload",
        "bottom_work_after_cancel": "detached read continues",
        "cleanup": "无资源写；Task 不持久保存",
        "late_write_risk": "会写旧 metadata/log/note state",
        "retry": "按钮可重复启动；无 request identity",
        "evidence": ["IOS-DETAIL-STALE-001"],
    },
    {
        "id": "CANCEL-IOS-CONNECT",
        "status": "FINDING",
        "operation": "repository connect/open URL",
        "cancel_point": "picker dismiss/route dismiss/new URL",
        "bottom_work_after_cancel": "access/validation/config awaits continue",
        "cleanup": "security scope defer stop PASS",
        "late_write_risk": "旧 route/error 覆盖新请求",
        "retry": "retry/picker/onOpenURL 无统一 operation id",
        "evidence": ["IOS-CONNECT-STALE-001"],
    },
    {
        "id": "CANCEL-MACOS-OVERVIEW-LOAD",
        "status": "FINDING",
        "operation": "overview language status load",
        "cancel_point": "language change/view task cancellation",
        "bottom_work_after_cancel": "Core read may continue",
        "cleanup": "无持久写",
        "late_write_risk": "旧 locale 状态覆盖当前 locale",
        "retry": "每次 onChange 新 Task；无 generation",
        "evidence": ["MACOS-OVERVIEW-STALE-001"],
    },
    {
        "id": "CANCEL-DOTNET-PLATFORM-DIFF",
        "status": "FINDING",
        "operation": "platform capability/contract check",
        "cancel_point": "CancellationToken",
        "bottom_work_after_cancel": "bridge 决定；OCE 返回后被 catch",
        "cleanup": "finally 清 busy",
        "late_write_risk": "写 Failed/UnknownSnapshot",
        "retry": "错误文案建议 Retry，但取消不应归类为错误",
        "evidence": ["DOTNET-CANCELLATION-001"],
    },
    {
        "id": "CANCEL-OVERVIEW-REGENERATION",
        "status": "PASS",
        "operation": "explicit full overview regeneration",
        "cancel_point": "commit 前；committing 后不可取消",
        "bottom_work_after_cancel": "journal/state machine 收敛",
        "cleanup": "staging/backup/journal whitelist + recovery",
        "late_write_risk": "operation id/session status 校验",
        "retry": "resume/rollback by operation id",
        "evidence": ["core/src/overview/regeneration/execution.rs:1-390", "apps/macos/AreaMatrix/Features/Settings/RepositoryOverviewRegenerationModel.swift:135-205"],
        "notes": "已读范围 PASS；底层共享 atomic writer 仍受 RUST-OVERVIEW-ATOMIC-001 影响。",
    },
    {
        "id": "CANCEL-FSEVENTS-FLUSH",
        "status": "PASS",
        "operation": "FSEvents debounce/drain",
        "cancel_point": "新 generation/stop/restart",
        "bottom_work_after_cancel": "generation guard 拒绝旧 flush",
        "cleanup": "stop 释放 stream/context/task",
        "late_write_risk": "队首窗口与 cursor 由 model 串行",
        "retry": "失败保留队首，从同窗口重放",
        "evidence": ["apps/macos/AreaMatrix/PlatformServices/MainExternalCreatedFileWatcher.swift:1-380", "docs/architecture/fs-watcher.md"],
    },
    {
        "id": "RETRY-ERROR-CONTRACT",
        "status": "FINDING",
        "operation": "Core error -> UI retry/recovery",
        "cancel_point": "not applicable",
        "bottom_work_after_cancel": "not applicable",
        "cleanup": "由具体 operation 决定",
        "late_write_risk": "iOS feature-local raw String 丢失状态",
        "retry": "DbLocked retry / DbCorrupted repair / Internal no-auto-retry；iOS reviewed surfaces 未保持",
        "evidence": ["IOS-ERROR-MAPPING-001", "docs/api/error-codes.md:86-95"],
    },
    {
        "id": "CANCEL-BATCH-IMPORT",
        "status": "BLOCKED",
        "operation": "batch import stop-after-current-file",
        "cancel_point": "单文件 Core 调用之间",
        "bottom_work_after_cancel": "当前同步 import 完成",
        "cleanup": "Core staging guards/session",
        "late_write_risk": "不得启动下一项",
        "retry": "session/report/idempotency required",
        "evidence": ["docs/architecture/concurrency.md:142-151"],
        "notes": "合同已读，但全部实现/调用方未逐文件完成，不能判 PASS。",
    },
]


LIFECYCLE_ROWS = [
    {
        "id": "LIFECYCLE-INIT-ROLLBACK",
        "status": "FINDING",
        "resource": "InitRollback + init staging/committed metadata",
        "creator": "init_create_empty_repo/init_adopt_existing_repo",
        "owner": "stack-local InitRollback",
        "release": "mark_complete or rollback",
        "exception_exit": "manual rollback; errors ignored",
        "evidence": ["RUST-INIT-CLEANUP-001", "RUST-INIT-ROLLBACK-001"],
    },
    {
        "id": "LIFECYCLE-OVERVIEW-WRITE",
        "status": "FINDING",
        "resource": "tmp files, snapshots, target markdown",
        "creator": "write_plans_with_rollback/write_atomic_replace",
        "owner": "call stack only; fixed tmp has no operation owner",
        "release": "rename or best-effort remove",
        "exception_exit": "snapshot restore best effort; errors ignored",
        "evidence": ["RUST-OVERVIEW-ATOMIC-001", "RUST-OVERVIEW-CAS-001"],
    },
    {
        "id": "LIFECYCLE-BATCH-GUARDS",
        "status": "FINDING",
        "resource": "moved files/sidecars/category dirs + SQLite tx",
        "creator": "batch apply closure",
        "owner": "AppliedFsRename/AppliedFsMove until commit",
        "release": "disarm after tx commit",
        "exception_exit": "Drop rollback only in-process; rollback result ignored",
        "evidence": ["RUST-BATCH-FSDB-001"],
    },
    {
        "id": "LIFECYCLE-REPO-WRITE-WAITER",
        "status": "PASS",
        "resource": "per-repo write permit/continuation",
        "creator": "RepositoryWriteCoordinator.acquire",
        "owner": "withWriteAccess task",
        "release": "success/error release; cancellation removes waiter",
        "exception_exit": "defer-equivalent do/catch release",
        "evidence": ["apps/macos/AreaMatrix/PlatformServices/RepositoryWriteCoordinator.swift:1-78"],
    },
    {
        "id": "LIFECYCLE-FSEVENTS",
        "status": "PASS",
        "resource": "FSEventStream/callback context/flush Task/generation",
        "creator": "MainExternalCreatedFileWatcher.start",
        "owner": "watcher instance",
        "release": "stop invalidates generation, cancels task, stops/releases stream/context",
        "exception_exit": "start failure tears down; late callback generation rejected",
        "evidence": ["apps/macos/AreaMatrix/PlatformServices/MainExternalCreatedFileWatcher.swift:32-311"],
        "notes": "文件尾段未逐行完成，coverage 仍 BLOCKED。",
    },
    {
        "id": "LIFECYCLE-OBSERVABILITY",
        "status": "PASS",
        "resource": "bounded ingress/delivery/callback workers and runtime leases",
        "creator": "Core observability runtime / ObservabilityRuntimeAssembly",
        "owner": "runtime assembly + worker state",
        "release": "stop ingress -> flush/drain -> close; timeout degrades health",
        "exception_exit": "callback panic caught; writer failure recorded",
        "evidence": ["core/src/observability/callback.rs:1-100", "core/src/observability/runtime.rs:1-498", "apps/macos/AreaMatrix/App/ObservabilityRuntimeAssembly.swift:1-449"],
    },
    {
        "id": "LIFECYCLE-WINDOWS-WATCHER",
        "status": "PASS",
        "resource": "FileSystemWatcher and event subscriptions",
        "creator": "WindowsWatcherDiagnostics",
        "owner": "MainWindow",
        "release": "MainWindow_Closed -> Dispose -> StopWatcher/unsubscribe",
        "exception_exit": "watcher error stops watcher",
        "evidence": ["apps/windows/AreaMatrix/Features/Library/WindowsWatcherDiagnostics.cs:1-375", "apps/windows/AreaMatrix/MainWindow.xaml.cs:480-517"],
    },
    {
        "id": "LIFECYCLE-IOS-SECURITY-SCOPE",
        "status": "PASS",
        "resource": "security-scoped URL access",
        "creator": "RepositoryAccessService.beginAccessing",
        "owner": "ConnectRepositoryModel request",
        "release": "defer scopedAccess.stop()",
        "exception_exit": "defer executes on success/error",
        "evidence": ["apps/ios/AreaMatrix/Features/Onboarding/RepositoryAccessService.swift:75-85", "apps/ios/AreaMatrix/Features/Onboarding/ConnectRepositoryModel.swift:145-150"],
        "notes": "资源释放 PASS；请求 identity 竞态另见 IOS-CONNECT-STALE-001。",
    },
    {
        "id": "LIFECYCLE-IOS-DETAIL-TASKS",
        "status": "FINDING",
        "resource": "untracked Swift Tasks and detached FFI reads",
        "creator": "View toolbar/.task/retry callbacks",
        "owner": "Swift runtime/View; model does not retain task handle",
        "release": "no explicit replacement/deinit cancellation",
        "exception_exit": "error mapped and written without request identity",
        "evidence": ["IOS-DETAIL-STALE-001"],
    },
    {
        "id": "LIFECYCLE-UNREVIEWED",
        "status": "BLOCKED",
        "resource": "remaining Task/Timer/observer/Combine/AsyncStream/thread/FD/SQLite statement/file handle objects",
        "creator": "unreviewed files",
        "owner": "unknown",
        "release": "unknown",
        "exception_exit": "unknown",
        "evidence": ["coverage.jsonl status=BLOCKED"],
        "notes": "不能从抽查 PASS 外推到全仓生命周期。",
    },
]


EXCLUDED_CANDIDATES = [
    ("Task.detached 普遍不可取消", "排除为独立 finding", "docs/architecture/concurrency.md:59-76 明确规定同步 FFI 通过 detached 执行且只能在调用之间取消；只登记有具体过期回写/协调缺口的链路。"),
    ("RepositoryOverviewRegenerationModel.prepare 可重复通过 guard", "排除", "prepare 在首个 await 前同步将 phase=.loading；第二个 MainActor 调用看到 phase.isBusy=true。仅 load 缺 generation。"),
    ("resumeInterruptedInitialization 绕过写协调器", "不登记（可达性 BLOCKED）", "resume_scan_session 确实写 DB；已检查引用未发现 production 调用方，只有测试直接调用。但全仓调用图未逐行闭环，因此不把该检索结果升级为确定性排除。"),
    ("Linux ConfigureAwait(false) 后更新绑定属性", "需外部验证/BLOCKED", "当前 Linux csproj/view wrapper 未建立 GTK dispatcher 或 PropertyChanged UI subscriber；可见风险但尚无具体 UI sink，不能作为静态确认缺陷。"),
    ("remote-governance expression 注入", "排除为安全 finding", "workflow_dispatch 未声明 branch input，实际值来自管理员控制的 default_branch；虽然 Git ref 可含 shell metacharacters，未建立低权限输入到高权限 shell 的边界。仍建议用 env/printf 硬化。"),
    ("CI 未设置 timeout-minutes", "排除为明确缺陷", "GitHub 有平台默认上限且主要 workflow 有 concurrency cancellation；属于可靠性硬化，当前无项目合同或已证实 hung path。"),
    ("Windows watcher 关闭泄漏", "排除", "MainWindow_Closed 反订阅并 Dispose；WindowsWatcherDiagnostics.StopWatcher 解绑事件并释放 watcher。"),
    ("task-loop timeout 留下子进程", "排除（已读范围）", "Popen 使用新 session，idle/total timeout 进入 terminate_child，TERM 后升级 KILL 并清 current child/log state。"),
]


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as error:
                raise RuntimeError(f"{path}:{number}: invalid JSON: {error}") from error
    return rows


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


FROZEN_INVENTORY_FIELDS = (
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


def inventory_manifest_digest(inventory: list[dict[str, Any]]) -> str:
    """Hash only freeze-time fields so final status annotations do not alter the manifest."""
    canonical = "\n".join(
        json.dumps(
            {key: row.get(key) for key in FROZEN_INVENTORY_FIELDS},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        for row in sorted(inventory, key=lambda item: item["path"])
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def validate_frozen_inventory(scope: dict[str, Any], inventory: list[dict[str, Any]]) -> str:
    if len(inventory) != scope["repository_file_total"]:
        raise RuntimeError("inventory count does not match frozen scope before classification")
    paths = [row.get("path") for row in inventory]
    if any(not isinstance(path, str) or not path for path in paths):
        raise RuntimeError("inventory contains an empty or non-string path")
    if len(set(paths)) != len(paths):
        raise RuntimeError("inventory contains duplicate paths before classification")
    required = (set(FROZEN_INVENTORY_FIELDS) - {"symlink_target"}) | {"status", "reviewed_ranges"}
    if any(not required.issubset(row) for row in inventory):
        raise RuntimeError("inventory row is missing freeze/status fields")
    if any(row.get("audit_id") != AUDIT_ID or row.get("status") not in ALLOWED_STATUSES for row in inventory):
        raise RuntimeError("inventory row has invalid audit_id/status")
    counts = Counter(row.get("file_type") for row in inventory)
    expected_counts = scope.get("counts", {})
    for file_type in ("text", "binary", "symlink", "other"):
        if counts[file_type] != expected_counts.get(file_type, 0):
            raise RuntimeError(
                f"inventory {file_type} count {counts[file_type]} does not match scope "
                f"{expected_counts.get(file_type, 0)}"
            )
    line_total = sum(row.get("line_count") or 0 for row in inventory)
    if line_total != expected_counts.get("text_line_total", 0):
        raise RuntimeError("inventory text line total does not match frozen scope")
    digest = inventory_manifest_digest(inventory)
    expected_digest = scope.get("inventory_manifest_sha256")
    if expected_digest is not None and expected_digest != digest:
        raise RuntimeError("inventory freeze manifest digest changed")
    return digest


def validate_override_tables(inventory: list[dict[str, Any]]) -> None:
    paths = {row["path"] for row in inventory}
    groups = {
        "FULL_PASS": set(FULL_PASS),
        "FULL_FINDING": set(FULL_FINDING),
        "PARTIAL_RANGES": set(PARTIAL_RANGES),
    }
    names = list(groups)
    for index, left_name in enumerate(names):
        for right_name in names[index + 1 :]:
            overlap = groups[left_name] & groups[right_name]
            if overlap:
                raise RuntimeError(f"coverage override overlap {left_name}/{right_name}: {sorted(overlap)}")
    all_overrides = set().union(*groups.values())
    missing = sorted(all_overrides - paths)
    if missing:
        raise RuntimeError(f"coverage overrides not in frozen inventory: {missing}")
    finding_ids = {finding["id"] for finding in FINDINGS}
    for table_name, table in (("FULL_FINDING", FULL_FINDING), ("PARTIAL_FINDINGS", PARTIAL_FINDINGS)):
        for path, ids in table.items():
            if path not in paths:
                raise RuntimeError(f"{table_name} path not in frozen inventory: {path}")
            if path not in PARTIAL_RANGES and table_name == "PARTIAL_FINDINGS":
                raise RuntimeError(f"{table_name} path has no partial ranges: {path}")
            unknown = set(ids) - finding_ids
            if unknown:
                raise RuntimeError(f"{table_name} references unknown findings: {sorted(unknown)}")
            for finding_id in ids:
                if not any(
                    location["path"] == path
                    for finding in FINDINGS
                    if finding["id"] == finding_id
                    for location in finding["locations"]
                ):
                    raise RuntimeError(f"{table_name} has no location evidence for {finding_id} at {path}")
    rows_by_path = {row["path"]: row for row in inventory}
    for path in FULL_PASS | set(FULL_FINDING):
        row = rows_by_path[path]
        if row.get("file_type") != "text" or not isinstance(row.get("line_count"), int) or row["line_count"] < 1:
            raise RuntimeError(f"full-read override is not a non-empty text file: {path}")
    for path, ranges in PARTIAL_RANGES.items():
        row = rows_by_path[path]
        line_count = row.get("line_count")
        if row.get("file_type") != "text" or not isinstance(line_count, int) or line_count < 1:
            raise RuntimeError(f"partial-read override is not a text file: {path}")
        if any(start < 1 or end < start or end > line_count for start, end in ranges):
            raise RuntimeError(f"partial range exceeds line bounds: {path}")


def merge_ranges(ranges: list[tuple[int, int]], line_count: int | None) -> list[dict[str, int]]:
    if line_count is None:
        return []
    normalized = sorted((max(1, start), min(line_count, end)) for start, end in ranges if start <= end)
    merged: list[list[int]] = []
    for start, end in normalized:
        if start > line_count or end < 1:
            continue
        if merged and start <= merged[-1][1] + 1:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return [{"start": start, "end": end} for start, end in merged]


def reviewed_line_count(ranges: list[dict[str, int]]) -> int:
    return sum(item["end"] - item["start"] + 1 for item in ranges)


def reviewer_for(path: str) -> str:
    if path.startswith("core/"):
        return "rust_core_audit + root"
    if path.startswith(("apps/macos/", "apps/ios/")):
        return "swift_apple_audit + root"
    if path.startswith(("apps/windows/", "apps/linux/", "scripts/", ".github/")):
        return "cross_platform_workflow_audit + root"
    return "root"


def source_chain_for_not_applicable(row: dict[str, Any]) -> tuple[str, list[str]]:
    path = row["path"]
    file_type = row["file_type"]
    if file_type == "symlink":
        target = row.get("symlink_target") or "unknown"
        return (
            f"符号链接本体无独立控制流；目标为 {target}，语义审阅归入目标文件。",
            [f"lstat/readlink:{path}->{target}", f"target:{target}"],
        )
    if file_type == "binary":
        if path.endswith("libarea_matrix_core.a"):
            return (
                "UniFFI/Cargo 生成的静态库；源链为 core/area_matrix.udl + core/src/** + core/build.rs/Cargo，二进制不逐行反汇编。",
                ["core/area_matrix.udl", "core/build.rs", "core/Cargo.toml"],
            )
        if "/bin/" in path or "/obj/" in path or path.endswith((".dll", ".pdb")):
            return (
                "MSBuild/.NET 构建输出；由对应 csproj 与 C# 源重建，不含可独立人工逐行审阅的源控制流。",
                ["associated .csproj", "dotnet build/test output"],
            )
        if "__pycache__" in path or path.endswith(".pyc"):
            return (
                "CPython 导入缓存；由同模块 .py 源自动生成。",
                ["adjacent Python source", "CPython bytecode cache"],
            )
        if path.endswith((".dmg", ".pkg")) or "/evidence/artifacts/" in path:
            return (
                "历史构建/发布证据制品；由 release/build pipeline 生成，不是源代码控制流。",
                ["scripts/dev_tools/release.py", ".github/workflows/release-evidence.yml"],
            )
        if path.startswith("assets/brand/archive/"):
            return (
                "历史品牌视觉归档；二进制像素/PDF 资产无错误处理或并发控制流，来源为归档设计产物。",
                ["assets/brand/archive/", "historical visual source"],
            )
        if path.startswith("assets/brand/final/"):
            return (
                "最终品牌视觉源资产；由应用资源/文档消费，无可逐行执行控制流。生成工具链不在本次仓库审计中声明。",
                ["assets/brand/final/", "apps/* resource consumers"],
            )
        if "/Resources/" in path or path.startswith("apps/"):
            return (
                "应用二进制视觉资源；由 Xcode/MSBuild 资源清单消费，控制流位于相邻项目文件与 View 代码。",
                ["application resource catalog/project", "assets/brand/final/ where applicable"],
            )
        return (
            "二进制/媒体资产无文本行和可逐行控制流；已冻结 path、mime、size 与 SHA-256。来源/生成工具未在该资产中编码。",
            [f"sha256:{row.get('sha256')}", f"mime:{row.get('mime')}", f"size:{row.get('size_bytes')}"],
        )
    reason = row.get("generated_or_non_text_reason") or "非产品源实现"
    if path.startswith(".codex/runtime/"):
        audit_name = path.split("/", 3)[2] if len(path.split("/")) > 2 else "runtime"
        return (
            f"既有 {audit_name} 审计运行证据/辅助脚本；由相邻 scope/inventory/ledger 生成或维护，不进入 AreaMatrix 产品运行路径。",
            [f".codex/runtime/{audit_name}/scope.json", f".codex/runtime/{audit_name}/inventory.jsonl"],
        )
    if "/Bridge/UniFFI/" in path or "/Carea_matrixFFI/" in path:
        return (
            "确定性 UniFFI 生成绑定；源链为 docs/api/core-api.md -> core/area_matrix.udl -> Rust -> uniffi-bindgen -> tracked binding。",
            ["docs/api/core-api.md", "core/area_matrix.udl", "core/build.rs", "scripts/dev_tools/core_sdk.py"],
        )
    if path.endswith("Cargo.lock") or path.endswith("Package.resolved"):
        return (
            "依赖锁定解析产物；来源为对应 manifest 与包解析器，不含业务控制流。",
            ["core/Cargo.toml", "Cargo resolver"],
        )
    if "/copy-ready/" in path or "/verify-ready/" in path:
        return (
            "版本化/任务包生成的静态 prompt 投影；源链为 task/manifest/shared rules/prompt pipeline，不作为产品运行时实现重复审阅。",
            ["workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py", "associated task/manifest", "associated shared prompt rules"],
        )
    return reason, [f"classification:{reason}"]


def current_scope_paths() -> set[str]:
    tracked = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, check=True, stdout=subprocess.PIPE
    ).stdout.split(b"\0")
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout.split(b"\0")
    paths = {
        value.decode("utf-8", "surrogateescape")
        for value in tracked + untracked
        if value
    }
    prefix = f".codex/runtime/{AUDIT_ID}/"
    return {path for path in paths if not path.startswith(prefix)}


def run_git_diff_check() -> dict[str, Any]:
    result = subprocess.run(
        ["git", "diff", "--check", "--", f".codex/runtime/{AUDIT_ID}"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    return {
        "command": f"git diff --check -- .codex/runtime/{AUDIT_ID}",
        "exit_code": result.returncode,
        "status": "PASS" if result.returncode == 0 else "FAIL",
        "output": result.stdout.strip(),
        "limitation": "git diff --check does not inspect untracked files; JSONL/report schema checks cover those artifacts.",
    }


def classify_inventory(
    inventory: list[dict[str, Any]], started_at: str, completed_at: str
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    validate_override_tables(inventory)

    changed: list[str] = []
    missing: list[str] = []
    symlink_drift: list[str] = []
    coverage: list[dict[str, Any]] = []
    status_counts: Counter[str] = Counter()
    reviewed_lines = 0
    reviewed_text_files = 0
    partial_text_files = 0
    na_text_lines = 0
    blocked_unreviewed_lines = 0

    for row in inventory:
        path = row["path"]
        expected_hash = row.get("sha256")
        absolute = ROOT / path
        current_hash = None
        hash_drift = False
        drift_reasons: list[str] = []
        current_symlink_target = None
        try:
            current_metadata = absolute.lstat()
        except FileNotFoundError:
            current_metadata = None
            missing.append(path)
            hash_drift = True
            drift_reasons.append("frozen path missing at close")

        if row.get("file_type") == "symlink":
            if current_metadata is None:
                pass
            elif not stat.S_ISLNK(current_metadata.st_mode):
                hash_drift = True
                symlink_drift.append(path)
                drift_reasons.append("current path is no longer a symlink")
            else:
                current_symlink_target = os.readlink(absolute)
                current_hash = hashlib.sha256(current_symlink_target.encode("utf-8", "surrogateescape")).hexdigest()
                if current_symlink_target != row.get("symlink_target"):
                    hash_drift = True
                    symlink_drift.append(path)
                    drift_reasons.append(
                        f"symlink target changed from {row.get('symlink_target')} to {current_symlink_target}"
                    )
                resolved = (absolute.parent / current_symlink_target).resolve(strict=False)
                try:
                    resolved.relative_to(ROOT.resolve())
                except ValueError:
                    hash_drift = True
                    symlink_drift.append(path)
                    drift_reasons.append("symlink target leaves repository root")
                if not resolved.exists():
                    hash_drift = True
                    symlink_drift.append(path)
                    drift_reasons.append("symlink target is missing")
        elif expected_hash is not None:
            if current_metadata is None:
                pass
            elif not stat.S_ISREG(current_metadata.st_mode):
                hash_drift = True
                drift_reasons.append("current path is no longer a regular file")
            else:
                current_hash = file_sha256(absolute)
                if current_hash != expected_hash:
                    hash_drift = True
                    drift_reasons.append("file SHA-256 changed")
        elif current_metadata is None:
            # Keep the explicit missing marker for non-hashed special entries too.
            pass

        if hash_drift and path not in changed:
            changed.append(path)

        status: str
        ranges: list[dict[str, int]]
        evidence: list[str]
        notes: str
        if path in FULL_FINDING:
            status = "FINDING"
            ranges = merge_ranges([(1, row.get("line_count") or 0)], row.get("line_count"))
            evidence = [f"finding:{finding_id}" for finding_id in FULL_FINDING[path]]
            notes = "全文逐行审阅完成；发现项已由主代理回源复核。"
        elif path in FULL_PASS:
            status = "PASS"
            ranges = merge_ranges([(1, row.get("line_count") or 0)], row.get("line_count"))
            evidence = [f"manual-full-read:{path}"]
            notes = "全文逐行审阅完成；在本次错误/并发/取消/重试/生命周期范围内未确认缺陷。"
        elif path in PARTIAL_RANGES:
            status = "BLOCKED"
            ranges = merge_ranges(PARTIAL_RANGES[path], row.get("line_count"))
            evidence = [
                "manual-partial-read:" + ",".join(f"{item['start']}-{item['end']}" for item in ranges)
            ]
            if path in PARTIAL_FINDINGS:
                evidence.extend(f"finding:{finding_id}" for finding_id in PARTIAL_FINDINGS[path])
                notes = "局部范围确认 finding；其余行未审，文件整体保持 BLOCKED。"
            else:
                notes = "仅列示范围完成人工逐行阅读；其余行未审，文件整体不得标 PASS/FINDING。"
        elif row.get("generated_or_non_text_reason") is not None:
            status = "NOT_APPLICABLE"
            ranges = []
            notes, evidence = source_chain_for_not_applicable(row)
        else:
            status = "BLOCKED"
            ranges = []
            evidence = ["manual-review-not-completed"]
            notes = "冻结范围内文件，但本轮没有完成逐文件逐行人工审阅；禁止由搜索、测试或同目录结论外推。"

        if hash_drift:
            status = "BLOCKED"
            if expected_hash:
                evidence.append(f"frozen-sha256:{expected_hash}")
            if current_hash:
                evidence.append(f"current-sha256:{current_hash}")
            if current_symlink_target is not None:
                evidence.append(f"current-symlink-target:{current_symlink_target}")
            evidence.extend(f"drift:{reason}" for reason in drift_reasons)
            notes += " 冻结后路径/类型/内容发生漂移；当前版本不能与冻结审阅证据混用。"

        status_counts[status] += 1
        line_count = row.get("line_count") or 0
        line_reviewed = reviewed_line_count(ranges)
        reviewed_lines += line_reviewed
        if row.get("file_type") == "text":
            if status in {"PASS", "FINDING"} and line_reviewed == line_count:
                reviewed_text_files += 1
            elif line_reviewed:
                partial_text_files += 1
            if status == "NOT_APPLICABLE":
                na_text_lines += line_count
            if status == "BLOCKED":
                blocked_unreviewed_lines += max(0, line_count - line_reviewed)

        symbol_data = SYMBOLS.get(path, {})
        if status == "NOT_APPLICABLE":
            default_entry = ["NOT_APPLICABLE: 无独立源代码运行入口"]
            default_caller = evidence[:2]
            default_callee: list[str] = []
            default_state = ["frozen path/hash/type metadata"]
        elif status == "BLOCKED" and not ranges:
            default_entry = ["BLOCKED: 未完成逐行审阅，无法可靠枚举"]
            default_caller = ["BLOCKED"]
            default_callee = ["BLOCKED"]
            default_state = ["BLOCKED"]
        elif path.endswith((".md", ".yaml", ".yml", ".json")):
            default_entry = ["文档/配置源事实入口"]
            default_caller = ["AreaMatrix implementation/governance consumers"]
            default_callee = []
            default_state = ["documented contract/configuration"]
        else:
            default_entry = ["已读范围内符号；关键调用见 evidence/专项台账"]
            default_caller = ["详见专项台账"]
            default_callee = ["详见专项台账"]
            default_state = ["详见专项台账"]

        row.update(
            {
                "status": status,
                "reviewed_ranges": ranges,
                "reviewer": reviewer_for(path),
                "verifier": "root",
                "review_started_at": started_at,
                "review_completed_at": completed_at,
                "entry_points": symbol_data.get("entry_points", default_entry),
                "callers": symbol_data.get("callers", default_caller),
                "callees": symbol_data.get("callees", default_callee),
                "state_objects": symbol_data.get("state_objects", default_state),
                "notes": notes,
                "evidence": evidence,
                "current_sha256_at_close": current_hash,
                "current_symlink_target_at_close": current_symlink_target,
                "hash_drift_since_scope_freeze": hash_drift,
            }
        )
        coverage.append(
            {
                "audit_id": AUDIT_ID,
                "path": path,
                "status": status,
                "reviewer": row["reviewer"],
                "verifier": row["verifier"],
                "started_at": started_at,
                "completed_at": completed_at,
                "reviewed_ranges": ranges,
                "reviewed_line_count": line_reviewed,
                "line_count": row.get("line_count"),
                "evidence": evidence,
                "notes": notes,
                "hash_drift_since_scope_freeze": hash_drift,
            }
        )

    current = current_scope_paths()
    frozen = {row["path"] for row in inventory}
    production_drift = sorted(path for path in changed if next(row for row in inventory if row["path"] == path).get("production_path"))
    nonproduction_drift = sorted(set(changed) - set(production_drift))
    added = sorted(current - frozen)
    removed = sorted(frozen - current)
    metrics = {
        "status_counts": dict(sorted(status_counts.items())),
        "human_reviewed_line_total": reviewed_lines,
        "fully_human_reviewed_text_files": reviewed_text_files,
        "partially_human_reviewed_text_files": partial_text_files,
        "not_applicable_text_line_total": na_text_lines,
        "blocked_unreviewed_text_line_total": blocked_unreviewed_lines,
        "hash_drift_count": len(changed),
        "hash_drift_paths": sorted(changed),
        "production_hash_drift_paths": production_drift,
        "nonproduction_hash_drift_paths": nonproduction_drift,
        "symlink_drift_paths": sorted(set(symlink_drift)),
        "missing_frozen_path_count": len(missing),
        "missing_frozen_paths": sorted(missing),
        "post_freeze_added_count": len(added),
        "post_freeze_added_paths": added,
        "post_freeze_removed_count": len(removed),
        "post_freeze_removed_paths": removed,
        "unexpected_post_freeze_added_paths": [path for path in added if not path.startswith(".codex/runtime/")],
    }
    return inventory, coverage, metrics


def build_error_contract_rows() -> list[dict[str, Any]]:
    explicitly_mapped_ios = {
        "FileNotFound",
        "RepoNotInitialized",
        "InvalidPath",
        "ICloudPlaceholder",
        "PermissionDenied",
    }
    rows = []
    for variant, payload, code, severity, recoverability, actions in ERROR_CONTRACTS:
        finding_ids = [] if variant in explicitly_mapped_ios else ["IOS-ERROR-MAPPING-001"]
        rows.append(
            {
                "audit_id": AUDIT_ID,
                "variant": variant,
                "payload": payload,
                "stable_code": code,
                "severity": severity,
                "recoverability": recoverability,
                "recovery_action_ids": actions,
                "core_definition": "core/src/error/core_error.rs:15-75",
                "core_mapping": "core/src/error/templates.rs:11-175; core/src/error/core_error.rs:194-315",
                "ffi_contract": "core/area_matrix.udl (partial review only)",
                "bridge_consumers": [
                    "macOS generated/manual bridge: BLOCKED end-to-end",
                    "iOS reviewed connect/list/detail surfaces: partial mapping",
                    "Windows/Linux consumers: BLOCKED end-to-end",
                ],
                "ui_recovery": actions,
                "diagnostic_entry": "controlled technicalDetails / collect_diagnostics where declared",
                "core_mapping_status": "PASS",
                "end_to_end_status": "BLOCKED",
                "finding_ids": finding_ids,
                "notes": "Core definition/template was fully read. Complete producer -> UDL -> every platform UI/action/diagnostic trace was not completed; no variant is claimed end-to-end PASS.",
            }
        )
    return rows


def markdown_table(headers: list[str], rows: list[list[Any]]) -> str:
    def clean(value: Any) -> str:
        return str(value).replace("|", "\\|").replace("\n", " ")

    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    lines.extend("| " + " | ".join(clean(value) for value in row) + " |" for row in rows)
    return "\n".join(lines)


def render_findings() -> str:
    sections: list[str] = []
    for finding in FINDINGS:
        locations = "; ".join(
            f"`{item['path']}:{item['lines']}` `{item['symbol']}`" for item in finding["locations"]
        )
        sections.append(
            f"### [{finding['severity']}] {finding['id']} - {finding['title']}\n\n"
            f"- 置信度/状态：`{finding['confidence']}` / `{finding['status']}`\n"
            f"- 证据：{locations}\n"
            f"- 入口与链路：`{finding['entry']}` -> " + " -> ".join(f"`{item}`" for item in finding["call_chain"]) + "\n"
            f"- 失败或交错：{finding.get('failure_or_interleaving', finding.get('error_propagation', '见 finding JSONL。'))}\n"
            f"- 实际影响：{finding['impact']}\n"
            f"- 最小修复：{finding['minimum_fix']}\n"
            f"- 回滚原则：{finding['rollback']}\n"
            f"- 建议验证：" + "；".join(finding["validation"]) + "\n"
            f"- 确认边界：{finding['confirmation_boundary']}"
        )
    return "\n\n".join(sections)


def render_report(scope: dict[str, Any], metrics: dict[str, Any]) -> str:
    counts = metrics["status_counts"]
    total = scope["repository_file_total"]
    conservation = sum(counts.get(key, 0) for key in ("PASS", "FINDING", "NOT_APPLICABLE", "BLOCKED"))
    severity_counts = Counter(item["severity"] for item in FINDINGS)
    error_rows = build_error_contract_rows()
    error_table = markdown_table(
        ["Variant", "Code", "Severity", "Recoverability", "Actions", "E2E"],
        [
            [
                row["variant"],
                row["stable_code"],
                row["severity"],
                row["recoverability"],
                ", ".join(row["recovery_action_ids"]),
                row["end_to_end_status"],
            ]
            for row in error_rows
        ],
    )
    concurrency_table = markdown_table(
        ["ID", "状态", "参与者/共享状态", "协调与结论"],
        [
            [
                row["id"],
                row["status"],
                ", ".join(row["participants"] + row["shared_state"]),
                ", ".join(row["coordination"]) + "；" + row["notes"],
            ]
            for row in CONCURRENCY_ROWS
        ],
    )
    cancel_table = markdown_table(
        ["ID", "状态", "取消点", "底层/晚到", "重试"],
        [
            [
                row["id"],
                row["status"],
                row["cancel_point"],
                row["bottom_work_after_cancel"] + "；" + row["late_write_risk"],
                row["retry"],
            ]
            for row in CANCELLATION_ROWS
        ],
    )
    exclusion_table = markdown_table(
        ["候选", "处置", "理由"], [[name, disposition, reason] for name, disposition, reason in EXCLUDED_CANDIDATES]
    )
    drift_paths = "\n".join(f"- `{path}`" for path in metrics["hash_drift_paths"])
    added_paths = "\n".join(f"- `{path}`" for path in metrics["post_freeze_added_paths"])
    production_drift_paths = "\n".join(
        f"- `{path}`" for path in metrics["production_hash_drift_paths"]
    ) or "- 无"
    nonproduction_drift_paths = "\n".join(
        f"- `{path}`" for path in metrics["nonproduction_hash_drift_paths"]
    ) or "- 无"
    missing_paths = "\n".join(
        f"- `{path}`" for path in metrics["missing_frozen_paths"]
    ) or "- 无"
    removed_paths = "\n".join(
        f"- `{path}`" for path in metrics["post_freeze_removed_paths"]
    ) or "- 无"
    unexpected_added_paths = "\n".join(
        f"- `{path}`" for path in metrics["unexpected_post_freeze_added_paths"]
    ) or "- 无"
    return f"""# AreaMatrix 全仓错误、并发、取消、重试与生命周期审计

## 结论

**结果：`BLOCKED / NOT-READY`。** 冻结范围的 {total} 个文件已全部完成状态归类且统计守恒，但只有 {metrics['fully_human_reviewed_text_files']} 个文本文件完成全文人工逐行审阅，另有 {metrics['partially_human_reviewed_text_files']} 个文本文件只完成部分区间；其余未获豁免的文件保持 `BLOCKED`。因此本报告不是“全仓逐行审计通过”，也不是 merge/release approval。

静态审阅确认 {len(FINDINGS)} 条 finding：P0={severity_counts['P0']}、P1={severity_counts['P1']}、P2={severity_counts['P2']}、P3={severity_counts['P3']}。最高风险集中在初始化 cleanup/rollback、overview 原子写/CAS 和用户文件 ownership。

## Findings

{render_findings()}

## 覆盖与守恒

{markdown_table(
    ['指标', '数量/结果'],
    [
        ['冻结文件总数', total],
        ['文本文件 / 文本行', f"{scope['counts']['text']} / {scope['counts']['text_line_total']}"],
        ['PASS', counts.get('PASS', 0)],
        ['FINDING（全文已读文件）', counts.get('FINDING', 0)],
        ['NOT_APPLICABLE', counts.get('NOT_APPLICABLE', 0)],
        ['BLOCKED', counts.get('BLOCKED', 0)],
        ['PENDING / IN_PROGRESS', f"{counts.get('PENDING', 0)} / {counts.get('IN_PROGRESS', 0)}"],
        ['人工已读行（含部分文件区间）', metrics['human_reviewed_line_total']],
        ['有证据豁免的文本行', metrics['not_applicable_text_line_total']],
        ['BLOCKED 未读文本行', metrics['blocked_unreviewed_text_line_total']],
        ['守恒', f"{total} = {counts.get('PASS', 0)} + {counts.get('FINDING', 0)} + {counts.get('NOT_APPLICABLE', 0)} + {counts.get('BLOCKED', 0)} = {conservation}"],
    ],
)}

逐文件路径、类型、行数、是否生产路径、精确已读区间、审阅者/复核者、时间、入口/调用方/被调用方/状态对象、证据和阻断原因见 `inventory.jsonl` 与 `coverage.jsonl`。`NOT_APPLICABLE` 逐项记录 symlink target、生成链或二进制来源/消费边界；没有按目录静默跳过。

### 冻结范围漂移

审计启动后的路径/类型/内容复核发现 {metrics['hash_drift_count']} 个冻结文件发生漂移；任何漂移文件都保持 `BLOCKED`，当前版本不与冻结审阅证据混用。

生产路径漂移：{len(metrics['production_hash_drift_paths'])} 个

{production_drift_paths}

非生产/审计材料漂移：{len(metrics['nonproduction_hash_drift_paths'])} 个

{nonproduction_drift_paths}

冻结路径缺失：{metrics['missing_frozen_path_count']}

{missing_paths}

冻结后移除（路径集合差异）：{metrics['post_freeze_removed_count']}

{removed_paths}

{drift_paths}

另有 {metrics['post_freeze_added_count']} 个文件在冻结后新增；只有 `.codex/runtime/**` 新增材料不纳入本次 {total} 文件分母，其他新增会使收口保持 `BLOCKED`：

{added_paths}

冻结后非审计 runtime 新增：

{unexpected_added_paths}

## CoreError 端到端覆盖

Core 的 18 个 variant、稳定 code、severity、recoverability 与 recovery action 已在 `core/src/error/**` 全文核对；但 UDL、所有 producer 和所有 macOS/iOS/Windows/Linux 消费路径没有全部逐行闭环，所以每一行端到端状态均为 `BLOCKED`，不能把 Core mapping PASS 外推为 UI PASS。详细证据见 `error-contracts.jsonl`。

{error_table}

iOS 已读链路另有 `IOS-ERROR-MAPPING-001`：至少 connect/list/detail 绕过该表，合并 typed DB variant 并显示技术文本。

## 并发图

```text
SwiftUI/MainActor
  -> feature Task / generation / state guard
  -> CoreBridge actor instance
  -> Task.detached (同步 FFI 不可被 Swift 强制中断)
  -> Rust Core transaction / guard / operation token
  -> filesystem + SQLite WAL(single writer, busy_timeout=5s)

并行平台事件:
  FSEvents callback -> debounce/generation -> ordered window queue
                    -> RepositoryWriteCoordinator(per repo)
                    -> Core batch -> overview -> cursor ack

高风险缺口:
  init cleanup/rollback ----无可信 ownership----> remove_dir_all/remove_file
  overview writer ----------无安全 tmp/final CAS--> markdown/provenance
  batch FS move ------------仅 RAII、无 journal----> SQLite commit
```

{concurrency_table}

## 取消、超时、重试与恢复

{cancel_table}

未发现通用自动重试循环；已读合同规定 SQLite 等待上限 5 秒、`ICloudPlaceholder` 只能用户触发 Download & retry、`Internal/PermissionDenied/Conflict/StagingRecoveryRequired` 不得自动重试。由于多数 UI consumer 与长流程文件仍 `BLOCKED`，这些规则不能宣称全仓落实。

## 生命周期结论

- 用户文件：`FAIL`。四条 P0 路径可删除/覆盖用户内容或通过 symlink 写出资料库边界。
- DB/文件一致性：`FAIL`。batch rename/category 的硬崩溃窗口没有持久 journal。
- staging/import：已读普通 guard/恢复范围未见新 finding，但大量实现与测试未全文审阅，结论 `BLOCKED`。
- FSEvents/cursor：已读 watcher、ordered window 和 cursor 合同范围 PASS；文件整体/平台实测仍 `BLOCKED`，未发现 cursor 越过已确认失败窗口。
- iCloud：合同明确 watcher/Core 不隐式下载；所有平台消费链未全审且未使用真实 iCloud，`BLOCKED / 需外部验证`。
- UI/FFI：`FAIL`。iOS error mapping 丢 typed recovery；iOS/macOS 三条旧结果回写；通用 detached 语义本身符合文档。
- 线程/Task：已读 RepositoryWriteCoordinator、observability 和 watcher 关键范围较完整；其余 Task/线程/dispatcher `BLOCKED`。
- Timer/observer/Combine/AsyncStream：部分 observability/Combine owner 已核对，未覆盖全仓，`BLOCKED`。
- SQLite connection/statement/transaction：连接 WAL/foreign key/busy timeout 配置 PASS；跨 FS transaction 的 batch 路径 FAIL；其余 statement 生命周期 `BLOCKED`。
- 文件句柄/临时文件：safe_move 已读范围 PASS；overview tmp/snapshot FAIL；全仓 FD/临时文件结论 `BLOCKED`。

完整 owner/create/release/exception-path 表见 `lifecycle-ledger.jsonl`。

## P0 边界威胁模型

- 资产：资料库内用户文件、根 `AREAMATRIX.md` managed block 外正文、资料库外同一用户可写文件、`.areamatrix/` metadata。
- 信任边界：用户/同步进程可写资料库目录；AreaMatrix cleanup/rollback/overview writer 以应用权限写文件；SQLite 与文件系统不能共享事务。
- 入口：`.areamatrix.init-*` 命名目录、固定 `.md.tmp`、symlink、并发文件编辑、初始化/概览失败注入、进程崩溃。
- 能力：本地用户、同步提供商或同账户进程可以控制文件名、symlink 和时序；没有假设远程未认证攻击者。
- Abuse path：形状伪装目录 -> cleanup 删除；preflight 后并发写 -> rollback 删除；tmp symlink -> 外部文件截断；provenance 后编辑 -> rename 覆盖。
- 已有控制：最终 target provenance、部分 symlink_metadata、RAII guard、full regeneration journal；这些控制未覆盖固定 tmp、最终 CAS、init ownership 和硬崩溃。
- 建议缓解：durable operation identity/journal、create_new + no-follow、最终 CAS、fail-closed recovery、故障注入。
- 残余风险：真实 iCloud/FSEvents、多进程、Windows symlink 权限和断电语义需要外部平台验证。

## 已排除候选

{exclusion_table}

## 验证证据

已运行：

- `python3 .codex/runtime/{AUDIT_ID}/finalize_audit.py`：PASS（退出 0）；内部重新解析所有 JSONL，检查 {total} 条 inventory/coverage 一一对应、路径唯一、状态枚举、`PENDING=IN_PROGRESS=0`、守恒、finding/schema 引用和 18 条 error contract。
- 冻结清单/路径/类型/SHA-256 复核：PASS（缺失 {metrics['missing_frozen_path_count']}，漂移 {metrics['hash_drift_count']}）；漂移项逐项记录并全部保持 `BLOCKED`。
- 当前 scope 差异复核：{'PASS' if not metrics['unexpected_post_freeze_added_paths'] and not metrics['post_freeze_removed_paths'] else 'BLOCKED'}；冻结后新增 {metrics['post_freeze_added_count']} 个，非审计 runtime 新增 {len(metrics['unexpected_post_freeze_added_paths'])} 个，移除 {metrics['post_freeze_removed_count']} 个。
- `{metrics['git_diff_check']['command']}`：`{metrics['git_diff_check']['status']}`（exit {metrics['git_diff_check']['exit_code']}）。限制：{metrics['git_diff_check']['limitation']}

未运行：

- `cargo test --workspace`、Rust 专项测试、`./dev test macos`、xcodebuild、.NET/Linux tests、lint、build、压力/故障注入：按用户门禁，只有全仓逐文件逐行人工审阅完成后才能启动；当前仍有 {counts.get('BLOCKED', 0)} 个 `BLOCKED` 文件，因此本轮不得运行并伪装为完成证据。
- 真实 iCloud、真实 FSEvents、真实 WinUI/Linux runtime、真实用户资料库、长稳/极端并发：安全边界或环境外部验证，未运行。

## 最终门禁

- 人工逐行审计：`BLOCKED`
- 辅助测试：`NOT RUN`（受用户前置门禁约束）
- 真实平台/压力/长稳：`BLOCKED-EXTERNAL`
- Review：`blocked`（存在 P0/P1 findings 和未审文件）
- Security/file safety：`blocked`
- Dependency：`not-applicable`（本轮无依赖变更）
- CI：`blocked`（未运行，且本轮不是 merge approval）
- Git evidence：`not-applicable`（未提交、未推送）
- 总结论：`BLOCKED / NOT-READY`
"""


def validate_outputs(scope: dict[str, Any]) -> dict[str, int]:
    inventory = read_jsonl(AUDIT_DIR / "inventory.jsonl")
    coverage = read_jsonl(AUDIT_DIR / "coverage.jsonl")
    validate_frozen_inventory(scope, inventory)
    if len(inventory) != scope["repository_file_total"]:
        raise RuntimeError("inventory count does not match frozen scope")
    if len(coverage) != len(inventory):
        raise RuntimeError("coverage count does not match inventory")
    inventory_paths = [row["path"] for row in inventory]
    coverage_paths = [row["path"] for row in coverage]
    if len(set(inventory_paths)) != len(inventory_paths):
        raise RuntimeError("duplicate inventory paths")
    if inventory_paths != coverage_paths:
        raise RuntimeError("inventory/coverage paths or order differ")
    inventory_by_path = {row["path"]: row for row in inventory}
    coverage_required = {
        "audit_id",
        "path",
        "status",
        "reviewer",
        "verifier",
        "started_at",
        "completed_at",
        "reviewed_ranges",
        "reviewed_line_count",
        "line_count",
        "evidence",
        "notes",
        "hash_drift_since_scope_freeze",
    }
    finding_ids = {finding["id"] for finding in FINDINGS}
    for row in coverage:
        if not coverage_required.issubset(row) or row["audit_id"] != AUDIT_ID:
            raise RuntimeError(f"coverage row missing required fields: {row.get('path')}")
        inventory_row = inventory_by_path[row["path"]]
        if row["status"] != inventory_row["status"]:
            raise RuntimeError(f"coverage/inventory status mismatch: {row['path']}")
        if row["reviewed_ranges"] != inventory_row.get("reviewed_ranges"):
            raise RuntimeError(f"coverage/inventory reviewed range mismatch: {row['path']}")
        if row["hash_drift_since_scope_freeze"] != inventory_row.get("hash_drift_since_scope_freeze"):
            raise RuntimeError(f"coverage/inventory drift mismatch: {row['path']}")
        if row["line_count"] != inventory_row.get("line_count"):
            raise RuntimeError(f"coverage/inventory line count mismatch: {row['path']}")
        ranges = row["reviewed_ranges"]
        previous_end = 0
        for item in ranges:
            if not isinstance(item, dict) or set(item) != {"start", "end"}:
                raise RuntimeError(f"invalid reviewed range: {row['path']}")
            if item["start"] < 1 or item["end"] < item["start"] or item["start"] <= previous_end:
                raise RuntimeError(f"overlapping/out-of-order reviewed ranges: {row['path']}")
            if row["line_count"] is None or item["end"] > row["line_count"]:
                raise RuntimeError(f"reviewed range exceeds line count: {row['path']}")
            previous_end = item["end"]
        if row["reviewed_line_count"] != reviewed_line_count(ranges):
            raise RuntimeError(f"reviewed line count mismatch: {row['path']}")
        for evidence in row["evidence"]:
            if evidence.startswith("finding:") and evidence.split(":", 1)[1] not in finding_ids:
                raise RuntimeError(f"coverage references unknown finding: {row['path']}")
    counts = Counter(row["status"] for row in coverage)
    unknown = set(counts) - ALLOWED_STATUSES
    if unknown:
        raise RuntimeError(f"unknown statuses: {sorted(unknown)}")
    if counts["PENDING"] or counts["IN_PROGRESS"]:
        raise RuntimeError("pending/in-progress entries remain")
    conservation = sum(counts[key] for key in ("PASS", "FINDING", "NOT_APPLICABLE", "BLOCKED"))
    if conservation != len(inventory):
        raise RuntimeError("coverage conservation failed")
    finding_rows = read_jsonl(AUDIT_DIR / "findings.jsonl")
    finding_row_ids = [row.get("id") for row in finding_rows]
    required_finding_keys = {
        "id",
        "severity",
        "confidence",
        "status",
        "confirmation_state",
        "title",
        "locations",
        "entry",
        "call_chain",
        "impact",
        "minimum_fix",
        "rollback",
        "validation",
        "confirmation_boundary",
    }
    if any(
        not required_finding_keys.issubset(row)
        or row.get("audit_id") != AUDIT_ID
        or row.get("status") != "FINDING"
        or row.get("confirmation_state") != "STATIC_CONFIRMED"
        for row in finding_rows
    ):
        raise RuntimeError("finding row is missing required fields")
    if len(finding_row_ids) != len(set(finding_row_ids)) or set(finding_row_ids) != finding_ids:
        raise RuntimeError("finding IDs are not unique/complete")
    error_rows = read_jsonl(AUDIT_DIR / "error-contracts.jsonl")
    if len(error_rows) != len(ERROR_CONTRACTS) or len({row.get("variant") for row in error_rows}) != len(ERROR_CONTRACTS):
        raise RuntimeError("error contract variant count mismatch")
    if any(row.get("audit_id") != AUDIT_ID for row in error_rows):
        raise RuntimeError("error contract row has wrong audit_id")
    for name in (
        "concurrency-map.jsonl",
        "cancellation-retry-ledger.jsonl",
        "lifecycle-ledger.jsonl",
    ):
        rows = read_jsonl(AUDIT_DIR / name)
        ids = [row.get("id") for row in rows]
        if any(not row.get("id") or row.get("audit_id") != AUDIT_ID for row in rows):
            raise RuntimeError(f"{name}: missing id/audit_id")
        if len(ids) != len(set(ids)):
            raise RuntimeError(f"{name}: duplicate ids")
        for row in rows:
            if row["status"] not in ALLOWED_STATUSES:
                raise RuntimeError(f"{name}: invalid status {row['status']}")
    return dict(sorted(counts.items()))


def main() -> None:
    scope_path = AUDIT_DIR / "scope.json"
    scope = json.loads(scope_path.read_text(encoding="utf-8"))
    started_at = scope["started_at"]
    completed_at = datetime.now().astimezone().isoformat(timespec="seconds")
    inventory = read_jsonl(AUDIT_DIR / "inventory.jsonl")
    manifest_digest = validate_frozen_inventory(scope, inventory)
    inventory, coverage, metrics = classify_inventory(inventory, started_at, completed_at)

    write_jsonl(AUDIT_DIR / "inventory.jsonl", inventory)
    write_jsonl(AUDIT_DIR / "coverage.jsonl", coverage)
    write_jsonl(AUDIT_DIR / "findings.jsonl", [dict(row, audit_id=AUDIT_ID) for row in FINDINGS])
    write_jsonl(AUDIT_DIR / "error-contracts.jsonl", build_error_contract_rows())
    write_jsonl(AUDIT_DIR / "concurrency-map.jsonl", [dict(row, audit_id=AUDIT_ID) for row in CONCURRENCY_ROWS])
    write_jsonl(
        AUDIT_DIR / "cancellation-retry-ledger.jsonl",
        [dict(row, audit_id=AUDIT_ID) for row in CANCELLATION_ROWS],
    )
    write_jsonl(AUDIT_DIR / "lifecycle-ledger.jsonl", [dict(row, audit_id=AUDIT_ID) for row in LIFECYCLE_ROWS])
    metrics["git_diff_check"] = run_git_diff_check()

    scope.update(
        {
            "finalized_at": completed_at,
            "result": "BLOCKED / NOT-READY",
            "status_counts": metrics["status_counts"],
            "coverage_metrics": metrics,
            "finding_counts": dict(sorted(Counter(row["severity"] for row in FINDINGS).items())),
            "finding_total": len(FINDINGS),
            "product_validation": "NOT_RUN_USER_GATE_BLOCKED",
            "inventory_manifest_sha256": manifest_digest,
            "inventory_manifest_recorded_at_close": True,
            "finalization_completed": False,
        }
    )
    scope_path.write_text(json.dumps(scope, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    validate_counts = validate_outputs(scope)
    if validate_counts != metrics["status_counts"]:
        raise RuntimeError("post-write counts differ from computed metrics")

    (AUDIT_DIR / "final-report.md").write_text(render_report(scope, metrics), encoding="utf-8")
    review_notes = f"""# 全仓错误处理、并发、取消、重试与生命周期审计

- 审计 ID：`{AUDIT_ID}`
- 启动时间：`{started_at}`
- 收口时间：`{completed_at}`
- 冻结文件数：`{scope['repository_file_total']}`
- 文本文件/行：`{scope['counts']['text']}` / `{scope['counts']['text_line_total']}`
- 生产代码、测试、文档、配置、bindings、live queue：未修改
- 既有工作树改动：保留，详见 `scope.json`

## 状态

`{json.dumps(metrics['status_counts'], ensure_ascii=False, sort_keys=True)}`

守恒：`{scope['repository_file_total']} = PASS + FINDING + NOT_APPLICABLE + BLOCKED`；`PENDING/IN_PROGRESS = 0`。

## 方法与边界

- 三个只读分区代理分别覆盖 Rust、Apple、Windows/Linux/workflow 线索；主代理回源复核每条候选。
- 检索命中、测试属性和代理自述不计作全文 PASS；部分范围文件整体标 `BLOCKED`。
- 二进制、symlink、确定性生成绑定、锁文件、静态 prompt 和既有审计材料逐项记录来源链后标 `NOT_APPLICABLE`。
- 全仓逐行覆盖未完成，最终结论 `BLOCKED / NOT-READY`。
- 按用户前置门禁未运行产品测试、lint、build 或压力脚本。

## 候选处置

{exclusion_table_for_notes()}

## 台账自检

- finalize_audit.py 内部 JSONL parse/count/path/status/conservation/finding/error-contract 校验：PASS。
- 冻结路径缺失：{metrics['missing_frozen_path_count']}。
- 冻结后哈希漂移：{metrics['hash_drift_count']}，逐项见 `scope.json`。
- 冻结后新增：{metrics['post_freeze_added_count']}；其中其他审计 runtime {metrics['post_freeze_added_count'] - len(metrics['unexpected_post_freeze_added_paths'])}，非 runtime {len(metrics['unexpected_post_freeze_added_paths'])}。
"""
    (AUDIT_DIR / "review-notes.md").write_text(review_notes, encoding="utf-8")
    scope["finalization_completed"] = True
    scope["finalization_output_sha256"] = {
        name: file_sha256(AUDIT_DIR / name)
        for name in (
            "inventory.jsonl",
            "coverage.jsonl",
            "error-contracts.jsonl",
            "concurrency-map.jsonl",
            "cancellation-retry-ledger.jsonl",
            "lifecycle-ledger.jsonl",
            "findings.jsonl",
            "final-report.md",
            "review-notes.md",
        )
    }
    scope_path.write_text(json.dumps(scope, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "audit_id": AUDIT_ID,
                "result": scope["result"],
                "files": scope["repository_file_total"],
                "status_counts": validate_counts,
                "findings": len(FINDINGS),
                "hash_drift": metrics["hash_drift_count"],
                "post_freeze_added": metrics["post_freeze_added_count"],
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )


def exclusion_table_for_notes() -> str:
    return "\n".join(
        f"- `{name}`：{disposition}。{reason}" for name, disposition, reason in EXCLUDED_CANDIDATES
    )


if __name__ == "__main__":
    main()
