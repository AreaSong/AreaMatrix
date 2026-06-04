use std::path::Path;

use area_matrix_core::{
    get_missing_file_state, relink_missing_file, remove_missing_file_record, CoreError, CoreResult,
    MissingFileReason, MissingFileRecoveryReport, MissingFileRecoveryStatus,
    MissingFileRelinkRequest, MissingFileRemoveRecordRequest, MissingFileState,
};
use pretty_assertions::assert_eq;

#[path = "support/missing_file_recovery_validation.rs"]
mod missing_file_recovery_validation_support;

use missing_file_recovery_validation_support::{
    change_count, initialized_repo, insert_missing_repo_file, latest_change, path_string,
    user_files, validation_snapshot, write_repo_file,
};

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-89-c4-18-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-18-missing-file-recovery.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const MISSING_FILE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-06-missing-file-recovery.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const MISSING_FILE_RECOVERY_RS: &str = include_str!("../src/missing_file_recovery.rs");
const FILESYSTEM_RS: &str = include_str!("../src/missing_file_recovery/filesystem.rs");
const DB_RS: &str = include_str!("../src/db/missing_file_recovery.rs");
const CONTRACT_TEST: &str = include_str!("missing_file_recovery_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("missing_file_recovery_implementation.rs");
const FAILURE_TEST: &str = include_str!("missing_file_recovery_failure_recovery.rs");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn missing_file_recovery_validation_success_paths_are_ui_ready_and_file_safe() {
    let repo = initialized_repo();
    let content = b"restored report";
    let relink_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", content);
    let remove_id = insert_missing_repo_file(repo.path(), "archive/gone.pdf", b"gone");
    write_repo_file(repo.path(), "docs/restored.pdf", content);
    write_repo_file(repo.path(), "docs/keep.txt", b"keep");

    let state =
        get_missing_file_state(path_string(repo.path()), relink_id).expect("load missing state");
    assert_missing_state(state, relink_id);

    let relink_report = relink_missing_file(
        path_string(repo.path()),
        MissingFileRelinkRequest {
            file_id: relink_id,
            new_path: path_string(&repo.path().join("docs/restored.pdf")),
            confirmed: true,
        },
    )
    .expect("relink matching file");
    assert_relink_report(relink_report);

    let remove_report = remove_missing_file_record(
        path_string(repo.path()),
        MissingFileRemoveRecordRequest {
            file_id: remove_id,
            confirmed: true,
        },
    )
    .expect("remove missing record only");
    assert_remove_report(remove_report, remove_id);

    assert_eq!(change_count(repo.path()), 2);
    assert_eq!(
        user_files(repo.path()),
        vec![
            ("docs/keep.txt".to_owned(), b"keep".to_vec()),
            ("docs/restored.pdf".to_owned(), content.to_vec()),
        ]
    );
    assert_latest_change_is_record_only(repo.path());
}

fn assert_missing_state(state: MissingFileState, file_id: i64) {
    assert_eq!(state.file_id, file_id);
    assert_eq!(state.relative_path, "docs/missing.pdf");
    assert_eq!(state.reason, MissingFileReason::PathMissing);
    assert!(state.expected_hash_sha256.is_some());
    assert!(state.can_locate);
    assert!(state.can_try_again);
    assert!(state.can_remove_record);
    assert!(state.remove_record_requires_confirmation);
    assert!(!state.can_run_rescan);
}

fn assert_relink_report(report: MissingFileRecoveryReport) {
    assert_eq!(report.status, MissingFileRecoveryStatus::Relinked);
    assert_eq!(report.previous_path.as_deref(), Some("docs/missing.pdf"));
    assert_eq!(report.current_path.as_deref(), Some("docs/restored.pdf"));
    assert!(report.hash_matched);
    assert!(!report.record_removed);
    assert!(!report.file_deleted);
    assert_eq!(
        report.change_log_action.as_deref(),
        Some("external_modified")
    );
}

fn assert_remove_report(report: MissingFileRecoveryReport, file_id: i64) {
    assert_eq!(report.file_id, file_id);
    assert_eq!(report.status, MissingFileRecoveryStatus::RecordRemoved);
    assert!(report.record_removed);
    assert!(!report.file_deleted);
    assert_eq!(
        report.change_log_action.as_deref(),
        Some("removed_from_index")
    );
}

fn assert_latest_change_is_record_only(repo: &Path) {
    let (action, detail) = latest_change(repo);
    assert_eq!(action, "removed_from_index");
    assert_eq!(detail["kind"], "missing_file_record_removed");
    assert_eq!(detail["file_deleted"], false);
}

#[test]
fn missing_file_recovery_validation_failure_paths_preserve_metadata_and_files() {
    let repo = initialized_repo();
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", b"original");
    write_repo_file(repo.path(), "docs/wrong.pdf", b"different");
    let before = validation_snapshot(repo.path());

    assert!(matches!(
        remove_missing_file_record(
            path_string(repo.path()),
            MissingFileRemoveRecordRequest {
                file_id,
                confirmed: false,
            },
        ),
        Err(CoreError::PermissionDenied { .. })
    ));
    assert!(matches!(
        relink_missing_file(
            path_string(repo.path()),
            MissingFileRelinkRequest {
                file_id,
                new_path: path_string(&repo.path().join("docs/wrong.pdf")),
                confirmed: false,
            },
        ),
        Err(CoreError::PermissionDenied { .. })
    ));

    let mismatch = relink_missing_file(
        path_string(repo.path()),
        MissingFileRelinkRequest {
            file_id,
            new_path: path_string(&repo.path().join("docs/wrong.pdf")),
            confirmed: true,
        },
    )
    .expect("hash mismatch is a safe report");

    assert_eq!(mismatch.status, MissingFileRecoveryStatus::HashMismatch);
    assert!(!mismatch.hash_matched);
    assert!(!mismatch.record_removed);
    assert!(!mismatch.file_deleted);
    assert_eq!(mismatch.change_log_action, None);
    assert_eq!(validation_snapshot(repo.path()), before);
}

#[test]
fn missing_file_recovery_validation_core_api_udl_rust_and_tests_stay_aligned() {
    fn assert_state(_: fn(String, i64) -> CoreResult<MissingFileState>) {}
    fn assert_relink(
        _: fn(String, MissingFileRelinkRequest) -> CoreResult<MissingFileRecoveryReport>,
    ) {
    }
    fn assert_remove(
        _: fn(String, MissingFileRemoveRecordRequest) -> CoreResult<MissingFileRecoveryReport>,
    ) {
    }

    assert_state(get_missing_file_state);
    assert_relink(relink_missing_file);
    assert_remove(remove_missing_file_record);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_consumer_scope_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-89: C4-18 validation",
        "为 C4-18 missing-file-recovery 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-89",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-18 missing-file-recovery",
        "- S4-X-06 missing-file-recovery",
        "计划新增：`get_missing_file_state`、`remove_missing_file_record`、`relink_missing_file`",
        "更新 file path 或移除索引记录。",
        "写 change log。",
        "Relink 只引用用户选择的新路径。",
        "Remove record 不删除文件。",
        "Remove record 必须确认，且不删除用户原文件。",
        "Relink 路径需校验 hash 或明确风险。",
        "自动全盘搜索缺失文件不在当前 Stage 4。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-X-06 | missing-file-recovery | C4-18 | relink/remove record | remove record 不删文件",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    assert_core_api_and_udl_type_alignment();
    assert_core_api_behavior_alignment();
    assert_error_and_rust_surface_alignment();
    assert_implementation_alignment();
}

fn assert_core_api_and_udl_type_alignment() {
    for fragment in [
        "MissingFileState get_missing_file_state(string repo_path, i64 file_id);",
        "MissingFileRecoveryReport relink_missing_file(",
        "string repo_path, MissingFileRelinkRequest request",
        "MissingFileRecoveryReport remove_missing_file_record(",
        "string repo_path, MissingFileRemoveRecordRequest request",
        "dictionary MissingFileState",
        "MissingFileReason reason;",
        "string? expected_hash_sha256;",
        "boolean remove_record_requires_confirmation;",
        "dictionary MissingFileRecoveryReport",
        "MissingFileRecoveryStatus status;",
        "boolean hash_matched;",
        "boolean record_removed;",
        "boolean file_deleted;",
        "enum MissingFileRecoveryStatus",
        "\"HashMismatch\"",
        "\"RecordRemoved\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_core_api_behavior_alignment() {
    for fragment in [
        "### `get_missing_file_state(repoPath, fileId) throws -> MissingFileState`",
        "`get_missing_file_state` 是 C4-18 的缺失文件恢复状态入口",
        "不做全库 rescan",
        "不删除记录",
        "不写 change log",
        "### `relink_missing_file(repoPath, request) throws -> MissingFileRecoveryReport`",
        "hash 不匹配必须保持原记录为 missing",
        "`status = HashMismatch`",
        "不能覆盖、移动或直接关联",
        "### `remove_missing_file_record(repoPath, request) throws -> MissingFileRecoveryReport`",
        "只能移除 AreaMatrix metadata",
        "不能删除、移动、重命名、覆盖、Trash 或下载任何用户文件",
        "`file_deleted = false`",
        "| `get_missing_file_state(repo, file_id)` | recovery | √ | FileNotFound / PermissionDenied / Db |",
        "| `relink_missing_file(repo, request)` | recovery | √ | FileNotFound / PermissionDenied / Db |",
        "| `remove_missing_file_record(repo, request)` | recovery | √ | FileNotFound / PermissionDenied / Db |",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_error_and_rust_surface_alignment() {
    for fragment in [
        "`FileNotFound { path }`",
        "`PermissionDenied { path }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "pub fn get_missing_file_state(repo_path: String, file_id: i64)",
        "pub fn relink_missing_file(",
        "pub fn remove_missing_file_record(",
        "must never overwrite, move, delete, trash, or download user files",
        "record unchanged",
        "hash mismatch",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "MissingFileReason",
        "MissingFileRecoveryReport",
        "MissingFileRecoveryStatus",
        "MissingFileRelinkRequest",
        "MissingFileRemoveRecordRequest",
        "MissingFileState",
    ] {
        assert_contains(LIB_RS, fragment);
    }
}

fn assert_implementation_alignment() {
    for fragment in [
        "pub(crate) fn get_missing_file_state(",
        "pub(crate) fn relink_missing_file(",
        "pub(crate) fn remove_missing_file_record(",
        "validate_confirmation",
        "hash_mismatch_report",
        "file_deleted: false",
        "removed_from_index",
        "external_modified",
    ] {
        assert_contains(MISSING_FILE_RECOVERY_RS, fragment);
    }

    for fragment in [
        "ensure_record_is_missing",
        "inspect_relink_candidate",
        "repo_relative_path",
        "hash_file",
        "selected relink path must be inside repo",
    ] {
        assert_contains(FILESYSTEM_RS, fragment);
    }

    for fragment in [
        "load_missing_file_recovery_entry",
        "relink_missing_file_record",
        "mark_missing_file_record_removed",
        "INSERT INTO change_log",
        "status = 'deleted'",
    ] {
        assert_contains(DB_RS, fragment);
    }
}

fn assert_consumer_scope_alignment() {
    for fragment in [
        "这是 DB 记录存在但文件系统中找不到文件时的恢复页，不自动删除记录，也不修改用户文件。",
        "`Locate File` 结果：hash 匹配才可重新关联；hash 不匹配不得覆盖或直接关联",
        "点击 `Try Again` 触发只读路径检查，不做全库 rescan。",
        "`Remove Record` 必须二次确认，并明确不删除磁盘文件。",
    ] {
        assert_contains(MISSING_FILE_PAGE, fragment);
    }

    for fragment in ["本合同不新增 control map 之外的页面能力。"] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "missing_file_recovery_contract_exports_signatures_inputs_outputs_and_errors",
        "missing_file_recovery_contract_rejects_invalid_or_unconfirmed_requests",
        "missing_file_recovery_docs_api_udl_and_control_map_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "missing_file_recovery_state_reports_missing_row_without_writes",
        "relink_missing_file_updates_metadata_after_hash_match_without_moving_files",
        "relink_missing_file_hash_mismatch_keeps_metadata_and_change_log_unchanged",
        "remove_missing_file_record_soft_deletes_metadata_without_deleting_files",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "missing_file_recovery_failure_empty_state_and_invalid_inputs_are_explicit",
        "missing_file_recovery_failure_unconfirmed_actions_do_not_read_or_mutate_metadata",
        "missing_file_recovery_failure_hash_mismatch_keeps_record_and_candidate_unchanged",
        "missing_file_recovery_failure_relink_db_error_rolls_back_metadata_without_half_products",
        "missing_file_recovery_failure_remove_record_db_error_rolls_back_soft_delete",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
