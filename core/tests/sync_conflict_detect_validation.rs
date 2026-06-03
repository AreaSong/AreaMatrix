use std::{fs, path::Path};

use area_matrix_core::{
    detect_sync_conflicts, get_fs_event_cursor, record_watcher_health, CoreError, CoreResult,
    SyncConflict, SyncConflictFileRole, SyncConflictSeverity, SyncConflictStatus, SyncConflictType,
};
use pretty_assertions::assert_eq;

#[path = "support/sync_conflict_detect_validation.rs"]
mod sync_conflict_detect_validation_support;

use sync_conflict_detect_validation_support::{
    active_file_count, block_sync_conflict_state_writes, change_log_count, conflict,
    import_repo_file, initialized_repo, insert_previous_conflict_state, path_string,
    repo_config_value, user_files, watcher_signal, write_repo_file,
};

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-74-c4-15-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-15-sync-conflict-detect.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const SYNC_CONFLICT_RS: &str = include_str!("../src/sync_conflict_detect.rs");
const IMPLEMENTATION_RS: &str = include_str!("../src/sync_conflict_detect/implementation.rs");
const DB_SYNC_CONFLICT_RS: &str = include_str!("../src/db/sync_conflicts.rs");
const CONTRACT_TEST: &str = include_str!("sync_conflict_detect_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("sync_conflict_detect_implementation.rs");
const FAILURE_TEST: &str = include_str!("sync_conflict_detect_failure_recovery.rs");

#[derive(Debug, Eq, PartialEq)]
struct ReadOnlySnapshot {
    files: Vec<(String, Vec<u8>)>,
    active_count: i64,
    change_count: i64,
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn sync_conflict_detect_validation_success_path_is_ui_ready_and_read_only() {
    let repo = setup_success_path_fixture();
    let before = read_only_snapshot(repo.path());

    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");

    assert_success_conflicts(&conflicts);
    assert_conflict_state(repo.path(), &conflicts);
    assert_read_only_detection(repo.path(), before);
}

fn setup_success_path_fixture() -> tempfile::TempDir {
    let repo = initialized_repo();
    import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    import_repo_file(repo.path(), "notes", "plan.md", b"tracked plan");
    import_repo_file(repo.path(), "archive", "missing.txt", b"tracked missing");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    record_watcher_health(
        path_string(repo.path()),
        watcher_signal(repo.path(), "notes/plan.md"),
    )
    .expect("record watcher state");
    fs::write(repo.path().join("notes/plan.md"), b"changed externally")
        .expect("modify tracked file externally");
    fs::remove_file(repo.path().join("archive/missing.txt")).expect("remove tracked file");
    repo
}

fn read_only_snapshot(repo: &Path) -> ReadOnlySnapshot {
    ReadOnlySnapshot {
        files: user_files(repo),
        active_count: active_file_count(repo),
        change_count: change_log_count(repo),
    }
}

fn assert_success_conflicts(conflicts: &[SyncConflict]) {
    assert_eq!(conflicts.len(), 3);
    assert_same_name_conflict(conflicts);
    assert_concurrent_conflict(conflicts);
    assert_missing_conflict(conflicts);
}

fn assert_same_name_conflict(conflicts: &[SyncConflict]) {
    let same_name = conflict(
        conflicts,
        SyncConflictType::SameNameDifferentContent,
        "docs/report.pdf",
    );
    assert_eq!(same_name.severity, SyncConflictSeverity::High);
    assert_eq!(same_name.status, SyncConflictStatus::NeedsReview);
    assert_eq!(same_name.version_count, 2);
    assert!(same_name
        .affected_files
        .iter()
        .any(|file| file.role == SyncConflictFileRole::ConflictCopy));
}

fn assert_concurrent_conflict(conflicts: &[SyncConflict]) {
    let concurrent = conflict(
        conflicts,
        SyncConflictType::ConcurrentModification,
        "notes/plan.md",
    );
    assert_eq!(concurrent.source_provider.as_deref(), Some("Inotify"));
    assert!(concurrent
        .affected_files
        .iter()
        .any(|file| file.role == SyncConflictFileRole::Incoming));
}

fn assert_missing_conflict(conflicts: &[SyncConflict]) {
    let missing = conflict(
        conflicts,
        SyncConflictType::MissingVersion,
        "archive/missing.txt",
    );
    assert_eq!(missing.severity, SyncConflictSeverity::High);
    assert_eq!(
        missing.affected_files[0].role,
        SyncConflictFileRole::Missing
    );
}

fn assert_conflict_state(repo: &Path, conflicts: &[SyncConflict]) {
    let state =
        repo_config_value(repo, "sync_conflict_state").expect("stored conflict state metadata");
    let stored: Vec<SyncConflict> =
        serde_json::from_str(&state).expect("stored conflict state parses");
    assert_eq!(stored.len(), conflicts.len());
    assert!(stored
        .iter()
        .all(|conflict| conflict.status == SyncConflictStatus::NeedsReview));
}

fn assert_read_only_detection(repo: &Path, before: ReadOnlySnapshot) {
    assert_eq!(read_only_snapshot(repo), before);
    assert_eq!(
        get_fs_event_cursor(path_string(repo)).expect("read fs event cursor"),
        None
    );
}

#[test]
fn sync_conflict_detect_validation_db_failure_keeps_files_metadata_and_prior_state() {
    let repo = initialized_repo();
    import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let previous_state = r#"[{"conflict_id":"sentinel","status":"NeedsReview"}]"#;
    insert_previous_conflict_state(repo.path(), previous_state);
    block_sync_conflict_state_writes(repo.path());
    let before_files = user_files(repo.path());
    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());

    let result = detect_sync_conflicts(path_string(repo.path()));

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        repo_config_value(repo.path(), "sync_conflict_state").as_deref(),
        Some(previous_state)
    );
    assert_eq!(user_files(repo.path()), before_files);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
}

#[test]
fn sync_conflict_detect_validation_unstable_copy_id_returns_conflict_without_state_write() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/report conflicted copy.pdf", b"ambiguous");
    let before_files = user_files(repo.path());

    let result = detect_sync_conflicts(path_string(repo.path()));

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(repo_config_value(repo.path(), "sync_conflict_state"), None);
    assert_eq!(user_files(repo.path()), before_files);
    assert_eq!(active_file_count(repo.path()), 0);
    assert_eq!(change_log_count(repo.path()), 0);
}

#[test]
fn sync_conflict_detect_validation_core_api_udl_rust_and_tests_stay_aligned() {
    fn assert_detect(_: fn(String) -> CoreResult<Vec<SyncConflict>>) {}
    assert_detect(detect_sync_conflicts);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_consumer_scope_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-74: C4-15 validation",
        "为 C4-15 sync-conflict-detect 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-74",
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
        "Rust 单元测试",
        "集成测试目录",
        "Sync 模块",
        "`core/tests/`",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    assert_core_api_and_udl_type_alignment();
    assert_core_api_behavior_alignment();
    assert_error_and_rust_surface_alignment();
    assert_detector_implementation_alignment();
}

fn assert_core_api_and_udl_type_alignment() {
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
}

fn assert_core_api_behavior_alignment() {
    for fragment in [
        "### `detect_sync_conflicts(repoPath) throws -> [SyncConflict]`",
        "`detect_sync_conflicts` 是 C4-15 的多端同步冲突检测入口",
        "由 Core 从已持久化 watcher/import/cloud/conflict state 中读取",
        "写入或刷新 conflict state metadata",
        "不选择任一版本，不标记 resolved，不写 change log",
        "不触发 `sync_external_changes`、manual rescan",
        "不删除、不移动、不重命名、不覆盖、不 Trash",
        "| `detect_sync_conflicts(repo)` | sync/conflict | √ | Db / Io / Conflict |",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_error_and_rust_surface_alignment() {
    for fragment in [
        "`Db { message }`",
        "`Io { message }`",
        "`Conflict { path }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "pub fn detect_sync_conflicts(repo_path: String) -> CoreResult<Vec<SyncConflict>>",
        "must not choose a winning version",
        "move/delete/rename/overwrite user files",
    ] {
        assert_contains(API_RS, fragment);
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

    for fragment in [
        "pub struct SyncConflict",
        "pub(crate) fn detect_sync_conflicts(repo_path: String)",
        "never mutates user files",
        "CoreError::Db",
        "CoreError::Io",
        "CoreError::Conflict",
    ] {
        assert_contains(SYNC_CONFLICT_RS, fragment);
    }
}

fn assert_detector_implementation_alignment() {
    for fragment in [
        "missing_version_conflicts",
        "metadata_mismatch_conflicts",
        "same_name_conflicts",
        "concurrent_modification_conflicts",
        "persist_conflict_state",
        "normalize_metadata_error",
    ] {
        assert_contains(IMPLEMENTATION_RS, fragment);
    }

    for fragment in [
        "list_active_sync_conflict_files",
        "replace_sync_conflict_state",
        "sync_conflict_state",
        "ensure_config_storage_writable",
    ] {
        assert_contains(DB_SYNC_CONFLICT_RS, fragment);
    }
}

fn assert_consumer_scope_alignment() {
    for fragment in [
        "S4-X-03 可以从列表长度",
        "status = NeedsReview",
        "detected_at",
        "conflict_type",
        "primary_path",
        "S4-X-01 可以从 `conflict_id`",
        "affected_files",
        "version_count",
        "这些属于 C4-16 / C4-21。",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "sync_conflict_detect_contract_exports_signature_inputs_outputs_and_errors",
        "sync_conflict_detect_docs_api_udl_and_control_map_stay_aligned",
        "sync_conflict_detect_documents_consumers_and_scope_boundaries",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "sync_conflict_detect_implementation_empty_repo_returns_empty_state",
        "sync_conflict_detect_implementation_lists_same_name_different_content_read_only",
        "sync_conflict_detect_implementation_records_concurrent_modification_from_watcher_state",
        "sync_conflict_detect_implementation_reports_missing_version_without_deleting_metadata",
        "sync_conflict_detect_implementation_maps_uninitialized_repo_to_db_error",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "sync_conflict_detect_failure_edge_maps_invalid_input_to_documented_io",
        "sync_conflict_detect_failure_edge_keeps_prior_state_when_db_write_fails",
        "sync_conflict_detect_failure_edge_ambiguous_copy_returns_conflict_without_state",
        "sync_conflict_detect_failure_edge_permission_error_is_io_and_retryable",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
