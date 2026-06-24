use area_matrix_core::{
    get_missing_file_state, relink_missing_file, remove_missing_file_record, CoreError, CoreResult,
    MissingFileReason, MissingFileRecoveryReport, MissingFileRecoveryStatus,
    MissingFileRelinkRequest, MissingFileRemoveRecordRequest, MissingFileState,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../workflow/versions/v1-mvp/execution/phase-4/4-3-stage4-multiplatform/task-86-c4-18-contract-api.md"
);
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const MISSING_FILE_RECOVERY_RS: &str = include_str!("../src/missing_file_recovery.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn missing_file_recovery_contract_exports_signatures_inputs_outputs_and_errors() {
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

    let state = MissingFileState {
        file_id: 418,
        relative_path: "docs/reports/report.pdf".to_owned(),
        last_known_path: Some("/Volumes/Drive/docs/reports/report.pdf".to_owned()),
        last_seen_at: Some(1_777_800_000),
        reason: MissingFileReason::ExternalVolumeDisconnected,
        expected_hash_sha256: Some("hash".to_owned()),
        can_locate: true,
        can_try_again: true,
        can_remove_record: true,
        remove_record_requires_confirmation: true,
        can_run_rescan: true,
        rescan_disabled_reason: None,
    };
    assert_eq!(state.reason, MissingFileReason::ExternalVolumeDisconnected);
    assert!(state.remove_record_requires_confirmation);

    let relink_request = MissingFileRelinkRequest {
        file_id: state.file_id,
        new_path: "/Users/me/report.pdf".to_owned(),
        confirmed: true,
    };
    assert_eq!(relink_request.file_id, state.file_id);

    let remove_request = MissingFileRemoveRecordRequest {
        file_id: state.file_id,
        confirmed: true,
    };
    assert!(remove_request.confirmed);

    let report = MissingFileRecoveryReport {
        file_id: state.file_id,
        status: MissingFileRecoveryStatus::RecordRemoved,
        previous_path: Some(state.relative_path.clone()),
        current_path: None,
        hash_matched: false,
        record_removed: true,
        file_deleted: false,
        change_log_action: Some("missing_file_record_removed".to_owned()),
        message: Some("Record removed; user file was not deleted.".to_owned()),
    };
    assert_eq!(report.status, MissingFileRecoveryStatus::RecordRemoved);
    assert!(report.record_removed);
    assert!(!report.file_deleted);

    let documented_errors = [
        CoreError::file_not_found("missing file record"),
        CoreError::permission_denied("remove record confirmation is required"),
        CoreError::db("missing file recovery metadata unavailable"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn missing_file_recovery_contract_rejects_invalid_or_unconfirmed_requests() {
    assert!(matches!(
        get_missing_file_state("/tmp/repo".to_owned(), 0),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        remove_missing_file_record(
            "/tmp/repo".to_owned(),
            MissingFileRemoveRecordRequest {
                file_id: 42,
                confirmed: false,
            },
        ),
        Err(CoreError::PermissionDenied { .. })
    ));
    assert!(matches!(
        relink_missing_file(
            "/tmp/repo".to_owned(),
            MissingFileRelinkRequest {
                file_id: 42,
                new_path: String::new(),
                confirmed: true,
            },
        ),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        relink_missing_file(
            "/tmp/repo".to_owned(),
            MissingFileRelinkRequest {
                file_id: 42,
                new_path: "/tmp/report.pdf".to_owned(),
                confirmed: false,
            },
        ),
        Err(CoreError::PermissionDenied { .. })
    ));
    assert!(matches!(
        get_missing_file_state("/tmp/repo".to_owned(), 42),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn missing_file_recovery_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-86: C4-18 contract-api",
        "为 C4-18 missing-file-recovery 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "MissingFileState get_missing_file_state(string repo_path, i64 file_id);",
        "MissingFileRecoveryReport relink_missing_file(",
        "string repo_path, MissingFileRelinkRequest request",
        "MissingFileRecoveryReport remove_missing_file_record(",
        "string repo_path, MissingFileRemoveRecordRequest request",
        "dictionary MissingFileState",
        "string relative_path;",
        "string? last_known_path;",
        "MissingFileReason reason;",
        "string? expected_hash_sha256;",
        "boolean remove_record_requires_confirmation;",
        "boolean can_run_rescan;",
        "dictionary MissingFileRelinkRequest",
        "string new_path;",
        "dictionary MissingFileRemoveRecordRequest",
        "dictionary MissingFileRecoveryReport",
        "MissingFileRecoveryStatus status;",
        "boolean hash_matched;",
        "boolean record_removed;",
        "boolean file_deleted;",
        "enum MissingFileReason",
        "\"PathMissing\"",
        "\"PermissionDenied\"",
        "\"CloudPlaceholder\"",
        "\"ExternalVolumeDisconnected\"",
        "enum MissingFileRecoveryStatus",
        "\"Relinked\"",
        "\"HashMismatch\"",
        "\"RecordRemoved\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `get_missing_file_state(repo, file_id)` | recovery | √ | FileNotFound / PermissionDenied / Db |",
        "| `relink_missing_file(repo, request)` | recovery | √ | FileNotFound / PermissionDenied / Db |",
        "| `remove_missing_file_record(repo, request)` | recovery | √ | FileNotFound / PermissionDenied / Db |",
        "### `get_missing_file_state(repoPath, fileId) throws -> MissingFileState`",
        "missing-file recovery surface",
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
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`FileNotFound { path }`",
        "`PermissionDenied { path }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn missing_file_recovery_documents_consumers_and_file_safety_boundaries() {
    for fragment in [
        "Returns the missing-file recovery state for missing-file recovery surface.",
        "does not scan the whole repository",
        "delete metadata, or mutate user files",
        "Relinks one missing-file record to a user-selected matching path.",
        "must never overwrite, move, delete, trash, or download user files",
        "Removes only the AreaMatrix metadata record for a missing file.",
        "reports `file_deleted = false`",
        "Returns `CoreError::FileNotFound { path }`",
        "Returns `CoreError::PermissionDenied { path }`",
        "Returns `CoreError::Db { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Missing-file recovery contract types and entry points.",
        "Page-ready state for missing-file recovery.",
        "User-selected relink request for missing-file recovery.",
        "Confirmed remove-record request for missing-file recovery.",
        "Whether any user file was deleted by this action. missing-file recovery must keep this false.",
        "Returns page-ready missing-file state.",
        "Removes only the AreaMatrix metadata record for a missing file.",
        "Relinks a missing record to a user-selected matching file.",
    ] {
        assert_contains(MISSING_FILE_RECOVERY_RS, fragment);
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
