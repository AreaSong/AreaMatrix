use area_matrix_core::{
    detect_sync_conflicts, CoreError, CoreResult, SyncConflict, SyncConflictAffectedFile,
    SyncConflictFileRole, SyncConflictSeverity, SyncConflictStatus, SyncConflictType,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-71-c4-15-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-15-sync-conflict-detect.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const SYNC_CONFLICT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-01-sync-conflict.md");
const SYNC_CONFLICT_ENTRY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-03-sync-conflict-entry.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const SYNC_CONFLICT_RS: &str = include_str!("../src/sync_conflict_detect.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn sync_conflict_detect_contract_exports_signature_inputs_outputs_and_errors() {
    fn assert_detect(_: fn(String) -> CoreResult<Vec<SyncConflict>>) {}
    assert_detect(detect_sync_conflicts);

    let affected = SyncConflictAffectedFile {
        path: "docs/report.pdf".to_owned(),
        file_id: Some(42),
        role: SyncConflictFileRole::Existing,
        size_bytes: Some(4096),
        modified_at: Some(1_777_700_000),
        hash_sha256: Some("abcdef12".to_owned()),
        source_platform: Some("Windows".to_owned()),
    };
    let conflict = SyncConflict {
        conflict_id: "sync-conflict:docs/report.pdf".to_owned(),
        conflict_type: SyncConflictType::SameNameDifferentContent,
        severity: SyncConflictSeverity::High,
        status: SyncConflictStatus::NeedsReview,
        primary_path: "docs/report.pdf".to_owned(),
        affected_files: vec![affected],
        version_count: 2,
        source_provider: Some("OneDrive".to_owned()),
        detected_at: Some(1_777_700_010),
        summary: Some("Same name, different content".to_owned()),
    };

    assert_eq!(
        conflict.conflict_type,
        SyncConflictType::SameNameDifferentContent
    );
    assert_eq!(conflict.severity, SyncConflictSeverity::High);
    assert_eq!(conflict.status, SyncConflictStatus::NeedsReview);
    assert_eq!(
        conflict.affected_files[0].role,
        SyncConflictFileRole::Existing
    );
    assert_eq!(conflict.version_count, 2);

    let documented_errors = [
        CoreError::db("sync conflict metadata unavailable"),
        CoreError::io("sync conflict metadata inspection failed"),
        CoreError::conflict("sync conflict snapshot changed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn sync_conflict_detect_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-71: C4-15 contract-api",
        "为 C4-15 sync-conflict-detect 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-15 sync-conflict-detect",
        "- S4-X-03 sync-conflict-entry",
        "- S4-X-01 sync-conflict",
        "计划新增：`detect_sync_conflicts(repo_path) -> sequence<SyncConflict>`",
        "conflict list、severity、affected files。",
        "写 conflict state metadata。",
        "只读探测；不自动解决。",
        "- `Db`",
        "- `Io`",
        "- `Conflict`",
        "冲突入口数量来自 Core 状态。",
        "不静默选择任一版本。",
        "检测失败不删除文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-X-01 | sync-conflict | C4-15, C4-16, C4-21 | conflict detect/resolve | 不静默删除任一版本",
        "| S4-X-03 | sync-conflict-entry | C4-15 | conflict count/status | 入口不解决冲突",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "sequence<SyncConflict> detect_sync_conflicts(string repo_path);",
        "dictionary SyncConflictAffectedFile",
        "SyncConflictFileRole role;",
        "string? source_platform;",
        "dictionary SyncConflict",
        "SyncConflictType conflict_type;",
        "SyncConflictSeverity severity;",
        "SyncConflictStatus status;",
        "string primary_path;",
        "sequence<SyncConflictAffectedFile> affected_files;",
        "i64 version_count;",
        "enum SyncConflictStatus { \"NeedsReview\", \"Resolved\" };",
        "\"SameNameDifferentContent\"",
        "\"ConcurrentModification\"",
        "\"MetadataMismatch\"",
        "\"MissingVersion\"",
        "enum SyncConflictSeverity { \"Low\", \"Medium\", \"High\" };",
        "\"ConflictCopy\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `detect_sync_conflicts(repo)` | sync/conflict | √ | Db / Io / Conflict |",
        "### `detect_sync_conflicts(repoPath) throws -> [SyncConflict]`",
        "`detect_sync_conflicts` 是 C4-15 的多端同步冲突检测入口",
        "external events 和 metadata snapshots",
        "由 Core 从已持久化 watcher/import/cloud/conflict state 中读取",
        "写入或刷新 conflict state metadata",
        "用于保存检测到的冲突状态、稳定冲突 ID",
        "`status`：当前只声明 `NeedsReview` / `Resolved`",
        "不选择任一版本，不标记 resolved，不写 change log",
        "不触发 `sync_external_changes`、manual rescan",
        "不删除、不移动、不重命名、不覆盖、不 Trash",
        "S4-X-03 可以从列表长度",
        "S4-X-01 可以从 `conflict_id`",
        "这些属于 C4-16 / C4-21。",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`Db { message }`",
        "`Io { message }`",
        "`Conflict { path }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn sync_conflict_detect_documents_consumers_and_scope_boundaries() {
    for fragment in [
        "展示单个冲突或一个冲突组的类型、涉及文件、版本数量、来源平台和检测时间。",
        "默认提供 `Keep both`",
        "不允许无确认覆盖任一版本。",
        "解决失败：冲突保持未解决状态，不删除中间文件。",
        "Conflict detail API：hash、relative path、cloud conflict naming",
    ] {
        assert_contains(SYNC_CONFLICT_PAGE, fragment);
    }

    for fragment in [
        "列出冲突数量、最近检测时间、主要冲突类型。",
        "Core conflict summary / list API。",
        "`Later` 不修改文件、不写入解决日志、不从 `Needs Review` 移除。",
        "屏幕阅读器能读出冲突数量、文件名和 `Review` 操作。",
    ] {
        assert_contains(SYNC_CONFLICT_ENTRY_PAGE, fragment);
    }

    for fragment in [
        "Detects C4-15 sync conflicts without resolving any version.",
        "S4-X-03 sync-conflict-entry",
        "S4-X-01 sync-conflict",
        "write or refresh conflict-state metadata for detected conflicts",
        "must not choose a winning version",
        "CoreError::Db",
        "CoreError::Io",
        "CoreError::Conflict",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-15 sync conflict detection contract types and entry point.",
        "Sync conflict category shown to Stage 4 conflict entry and review pages.",
        "User-facing severity for prioritizing conflict review.",
        "One affected file/version entry inside a sync conflict.",
        "Sync conflict row returned by C4-15 detection.",
        "Detects C4-15 sync conflicts without resolving any version.",
        "safely inspects file",
        "conflict-state metadata writes",
    ] {
        assert_contains(SYNC_CONFLICT_RS, fragment);
    }

    for fragment in [
        "SyncConflict",
        "SyncConflictAffectedFile",
        "SyncConflictFileRole",
        "SyncConflictSeverity",
        "SyncConflictStatus",
        "SyncConflictType",
    ] {
        assert_contains(LIB_RS, fragment);
    }
}
