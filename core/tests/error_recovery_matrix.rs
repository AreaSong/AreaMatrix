use area_matrix_core::{CoreError, ErrorRecoverability, ErrorSeverity};

const MATRIX: &str = include_str!("../../docs/development/error-recovery-matrix.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const ERROR_MESSAGES: &str = include_str!("../../docs/ux/error-messages.md");
const TRANSACTIONAL_IMPORT: &str = include_str!("../../docs/architecture/transactional-import.md");
const TROUBLESHOOTING: &str = include_str!("../../docs/development/troubleshooting.md");
#[path = "support/error_contract_source.rs"]
mod error_contract_source;

use error_contract_source::ERROR_RS;
const IMPORT_RS: &str = include_str!("../src/storage/import.rs");
const SAFE_MOVE_RS: &str = include_str!("../src/storage/safe_move.rs");
const RECOVERY_RS: &str = include_str!("../src/recovery.rs");
const IMPORT_COPY_FAILURE: &str = include_str!("import_copy_file_failure_recovery.rs");
const IMPORT_MOVE_FAILURE: &str = include_str!("import_move_file_failure_recovery.rs");
const IMPORT_INDEX_FAILURE: &str = include_str!("import_index_file_failure_recovery.rs");
const DUPLICATE_FAILURE: &str = include_str!("detect_duplicate_failure_recovery.rs");
const CONFLICT_FAILURE: &str = include_str!("resolve_name_conflict_failure_recovery.rs");
const STARTUP_RECOVERY_VERIFY: &str = include_str!("recover_on_startup_integration_verify.rs");
const MAIN_REPO_SWIFT_TESTS: &str =
    include_str!("../../apps/macos/AreaMatrixTests/MainRepoErrorMappingTests.swift");
const ERROR_RECOVERY_PAGE_SWIFT_TESTS: &str =
    include_str!("../../apps/macos/AreaMatrixTests/ErrorRecoveryPageIntegrationVerifyTests.swift");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
}

#[test]
fn error_recovery_matrix_error_mapping_covers_all_core_domains() {
    for domain in [
        "repo path",
        "permission",
        "DB",
        "validation",
        "IO",
        "expired action",
        "iCloud placeholder",
        "duplicate",
        "conflict",
        "staging recovery",
        "internal",
    ] {
        assert_contains(MATRIX, domain);
    }

    for variant in [
        "`Io`",
        "`Db`",
        "`Config`",
        "`Validation`",
        "`Classify`",
        "`Conflict`",
        "`DuplicateFile`",
        "`FileNotFound`",
        "`ExpiredAction`",
        "`RepoNotInitialized`",
        "`InvalidPath`",
        "`ICloudPlaceholder`",
        "`StagingRecoveryRequired`",
        "`PermissionDenied`",
        "`Internal`",
    ] {
        assert_contains(MATRIX, variant);
    }

    for variant_shape in [
        "`Io { message }`",
        "`Db { message }`",
        "`Config { reason }`",
        "`Validation { reason }`",
        "`Classify { reason }`",
        "`Conflict { path }`",
        "`DuplicateFile { existing_path }`",
        "`FileNotFound { path }`",
        "`ExpiredAction { action_id }`",
        "`RepoNotInitialized { path }`",
        "`InvalidPath { path }`",
        "`ICloudPlaceholder { path }`",
        "`StagingRecoveryRequired { path }`",
        "`PermissionDenied { path }`",
        "`Internal { message }`",
    ] {
        assert_contains(ERROR_CODES, variant_shape);
    }

    for action in [
        "Collect diagnostics",
        "Download & retry",
        "Reconnect folder",
        "Skip / Overwrite / Keep both",
        "打开或重试 startup recovery",
        "Leave flow、Collect diagnostics、Open Issue",
    ] {
        assert_contains(MATRIX, action);
    }
}

#[test]
fn error_recovery_matrix_error_mapping_records_source_docs_and_troubleshooting() {
    for fragment in [
        "CoreError → UI 规范表",
        "DB locked",
        "DB corrupted",
        "ICloudPlaceholder",
        "Validation",
        "ExpiredAction",
        "StagingRecoveryRequired",
        "PermissionDenied",
        "Internal",
    ] {
        assert_contains(ERROR_MESSAGES, fragment);
    }

    for (troubleshooting_fragment, matrix_fragment) in [
        ("## iCloud placeholder", "#icloud-placeholder"),
        ("## 权限被拒", "#权限被拒"),
        ("## SQLite busy 或损坏", "#sqlite-busy-或损坏"),
        ("## Staging recovery", "staging recovery"),
        ("## Diagnostics", "diagnostics"),
    ] {
        assert_contains(TROUBLESHOOTING, troubleshooting_fragment);
        assert_contains(MATRIX, matrix_fragment);
    }

    for fragment in [
        "## 核心不变量",
        "失败导入不得留下最终目录半成品",
        "## 失败状态",
        "overview 或 replacement 保护失败时执行专用 DB rollback",
    ] {
        assert_contains(TRANSACTIONAL_IMPORT, fragment);
    }
}

#[test]
fn error_recovery_matrix_error_mapping_records_db_subsemantic_closure() {
    let locked = CoreError::db_locked("database is locked").to_error_mapping();
    let corrupted = CoreError::db_corrupted("database disk image is malformed").to_error_mapping();

    assert_eq!(locked.severity, ErrorSeverity::Medium);
    assert_eq!(locked.recoverability, ErrorRecoverability::Retryable);
    assert_eq!(corrupted.severity, ErrorSeverity::Critical);
    assert_eq!(corrupted.recoverability, ErrorRecoverability::Fatal);
    assert_contains(MATRIX, "P1-ER-001 已关闭");
    assert_contains(MATRIX, "locked retryable 与 corrupt fatal 已可区分");
    assert_contains(ERROR_RS, "const DB_LOCKED_MAPPING");
    assert_contains(ERROR_RS, "const DB_CORRUPTED_MAPPING");
    assert_contains(ERROR_RS, "Self::DbLocked");
    assert_contains(ERROR_RS, "Self::DbCorrupted");
    assert_contains(
        MAIN_REPO_SWIFT_TESTS,
        "testRetryableDbErrorUsesInlineRetryCopyInsteadOfRepairCopy",
    );
    assert_contains(
        ERROR_RECOVERY_PAGE_SWIFT_TESTS,
        "testStartupRecoveryPageIntegrationRoutesFatalDbMappingToRepairWithoutRunningRepair",
    );
}

#[test]
fn error_recovery_matrix_error_mapping_tracks_transactional_import_evidence() {
    for fragment in [
        "StagingFileGuard",
        "DbStagingRowGuard",
        "FinalFileGuard",
        "ReplacementDbRollback",
        "finish_overview_regeneration",
    ] {
        assert_contains(IMPORT_RS, fragment);
        assert_contains(MATRIX, fragment);
    }

    for fragment in [
        "restore_staged_source_or_keep_recoverable",
        "move_recoverable_file",
        "copy_to_new_destination",
    ] {
        assert_contains(SAFE_MOVE_RS, fragment);
    }

    for fragment in [
        "db::list_staging_file_rows(&repo)?",
        "clean_orphan_staging_files",
        "restore_moved_staging_file",
        "remove_staging_file",
    ] {
        assert_contains(RECOVERY_RS, fragment);
    }
}

#[test]
fn error_recovery_matrix_error_mapping_links_failure_recovery_tests() {
    let evidence = [
        (
            IMPORT_COPY_FAILURE,
            "import_copy_file_failure_recovery_rolls_back_final_file_when_db_promotion_fails",
        ),
        (
            IMPORT_MOVE_FAILURE,
            "import_move_file_failure_recovery_db_staging_insert_restores_source",
        ),
        (
            IMPORT_MOVE_FAILURE,
            "import_move_file_failure_recovery_failed_attempt_can_be_retried",
        ),
        (
            IMPORT_INDEX_FAILURE,
            "import_index_file_failure_recovery_failed_attempt_can_be_retried",
        ),
        (
            DUPLICATE_FAILURE,
            "detect_duplicate_failure_recovery_moved_ask_restores_source_without_final_side_effects",
        ),
        (
            DUPLICATE_FAILURE,
            "detect_duplicate_failure_recovery_overwrite_db_failure_can_be_retried",
        ),
        (
            CONFLICT_FAILURE,
            "resolve_name_conflict_failure_recovery_import_db_failure_removes_numbered_final",
        ),
        (
            STARTUP_RECOVERY_VERIFY,
            "recover_on_startup_integration_verify_real_report_drives_consumers_without_user_file_loss",
        ),
    ];

    for (source, function_name) in evidence {
        assert_contains(source, function_name);
        assert_contains(MATRIX, function_name);
    }
}
