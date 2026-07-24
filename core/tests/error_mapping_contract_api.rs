use area_matrix_core::{
    map_core_error, CoreError, ErrorKind, ErrorMappingInput, ErrorRecoverability, ErrorSeverity,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/error_contract_source.rs"]
mod error_contract_source;

use error_contract_source::ERROR_RS;
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn error_mapping_contract_api_exposes_structured_core_error_variants() {
    let duplicate = CoreError::DuplicateFile {
        existing_path: "finance/existing.pdf".to_owned(),
    };
    let duplicate_path = match duplicate {
        CoreError::DuplicateFile { existing_path } => existing_path,
        other => panic!("unexpected duplicate error shape: {other:?}"),
    };
    assert_eq!(duplicate_path, "finance/existing.pdf");

    let documented_variants = [
        CoreError::io("io error"),
        CoreError::db("database error"),
        CoreError::db_locked("database locked"),
        CoreError::db_corrupted("database corrupted"),
        CoreError::config("configuration error"),
        CoreError::validation("validation error"),
        CoreError::classify("classification error"),
        CoreError::conflict("path conflict"),
        CoreError::revision_conflict("repo_config", 4, 5),
        CoreError::DuplicateFile {
            existing_path: "finance/existing.pdf".to_owned(),
        },
        CoreError::file_not_found("missing file"),
        CoreError::expired_action("redo:batch-tags:42"),
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::invalid_path("invalid path"),
        CoreError::icloud_placeholder("icloud placeholder"),
        CoreError::staging_recovery_required("staging needs recovery"),
        CoreError::permission_denied("permission denied"),
        CoreError::internal("internal error"),
    ];
    assert_eq!(documented_variants.len(), 18);
}

#[test]
fn error_mapping_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "[Throws=CoreError]",
        "错误映射元数据",
        "每个错误返回 code、field、arguments、recovery action IDs、severity、recoverability",
        "避免 UI 解析字符串",
        "ErrorMapping map_core_error(ErrorMappingInput input);",
        "dictionary ErrorMapping",
        "dictionary ErrorArgument",
        "enum ErrorSeverity",
        "enum ErrorRecoverability",
        "interface CoreError",
        "DuplicateFile(string existing_path);",
        "StagingRecoveryRequired(string path);",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "[Error]",
        "ErrorMapping map_core_error(ErrorMappingInput input);",
        "dictionary ErrorMappingInput",
        "dictionary ErrorMapping",
        "enum ErrorKind",
        "enum ErrorSeverity",
        "enum ErrorRecoverability",
        "interface CoreError",
        "Io(string message);",
        "Db(string message);",
        "DbLocked(string message);",
        "DbCorrupted(string message);",
        "Config(string reason);",
        "Validation(string reason);",
        "Classify(string reason);",
        "Conflict(string path);",
        "RevisionConflict(string resource, i64 expected_revision, i64 current_revision);",
        "DuplicateFile(string existing_path);",
        "FileNotFound(string path);",
        "ExpiredAction(string action_id);",
        "RepoNotInitialized(string path);",
        "InvalidPath(string path);",
        "ICloudPlaceholder(string path);",
        "StagingRecoveryRequired(string path);",
        "PermissionDenied(string path);",
        "Internal(string message);",
    ] {
        assert_contains(UDL, fragment);
    }
}

#[test]
fn error_mapping_contract_api_documents_severity_actions_and_side_effects() {
    for fragment in [
        "| `Io { message }` |",
        "| `Db { message }` |",
        "| `DbLocked { message }` |",
        "| `DbCorrupted { message }` |",
        "| `Config { reason }` |",
        "| `Validation { reason }` |",
        "| `Classify { reason }` |",
        "| `Conflict { path }` |",
        "| `RevisionConflict { resource, expected_revision, current_revision }` |",
        "| `DuplicateFile { existing_path }` |",
        "| `FileNotFound { path }` |",
        "| `ExpiredAction { action_id }` |",
        "| `RepoNotInitialized { path }` |",
        "| `InvalidPath { path }` |",
        "| `ICloudPlaceholder { path }` |",
        "| `StagingRecoveryRequired { path }` |",
        "| `PermissionDenied { path }` |",
        "| `Internal { message }` |",
        "| low | toast 3s 自动消失 |",
        "| medium | banner 可手动关闭 |",
        "| high | modal alert |",
        "| critical | blocking modal |",
        "Swift 侧映射",
        "CoreErrorMappingSnapshot",
        "AppSemanticError",
        "不要硬来",
        "用技术术语吓退用户",
        "把 `error.localizedDescription` 直接显示",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "error mapping treats each variant and payload as the structured input",
        "branch on variants and payloads",
        "localized strings or `Display` output",
        "recovery action identifiers, severity, and recoverability",
        "side-effect free",
        "must not",
        "inspect the filesystem",
        "open the database",
        "write logs",
        "mutate repository",
    ] {
        assert_contains(ERROR_RS, fragment);
    }
}

#[test]
fn error_mapping_contract_api_maps_each_error_to_stable_ui_metadata() {
    let cases = [
        (
            CoreError::io("disk full"),
            ErrorKind::Io,
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
            "io_error",
            "disk full",
        ),
        (
            CoreError::db_locked("database is locked"),
            ErrorKind::DbLocked,
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
            "database_locked",
            "database is locked",
        ),
        (
            CoreError::db_corrupted("database disk image is malformed"),
            ErrorKind::DbCorrupted,
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
            "database_corrupted",
            "database disk image is malformed",
        ),
        (
            CoreError::config("classifier.yaml missing default"),
            ErrorKind::Config,
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
            "config_error",
            "classifier.yaml missing default",
        ),
        (
            CoreError::classify("rule engine failed"),
            ErrorKind::Classify,
            ErrorSeverity::Low,
            ErrorRecoverability::RefreshRequired,
            "classification_error",
            "rule engine failed",
        ),
        (
            CoreError::conflict("docs/report.pdf"),
            ErrorKind::Conflict,
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
            "conflict",
            "docs/report.pdf",
        ),
        (
            CoreError::DuplicateFile {
                existing_path: "finance/existing.pdf".to_owned(),
            },
            ErrorKind::DuplicateFile,
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
            "duplicate_file",
            "finance/existing.pdf",
        ),
        (
            CoreError::file_not_found("docs/missing.pdf"),
            ErrorKind::FileNotFound,
            ErrorSeverity::Low,
            ErrorRecoverability::RefreshRequired,
            "file_not_found",
            "docs/missing.pdf",
        ),
        (
            CoreError::expired_action("redo:batch-tags:42"),
            ErrorKind::ExpiredAction,
            ErrorSeverity::Low,
            ErrorRecoverability::RefreshRequired,
            "expired_action",
            "redo:batch-tags:42",
        ),
        (
            CoreError::repo_not_initialized("/repo"),
            ErrorKind::RepoNotInitialized,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
            "repository_not_initialized",
            "/repo",
        ),
        (
            CoreError::invalid_path("../escape.pdf"),
            ErrorKind::InvalidPath,
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
            "invalid_path",
            "../escape.pdf",
        ),
        (
            CoreError::icloud_placeholder("iCloud/report.pdf"),
            ErrorKind::ICloudPlaceholder,
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
            "icloud_placeholder_not_downloaded",
            "iCloud/report.pdf",
        ),
        (
            CoreError::staging_recovery_required(".areamatrix/staging"),
            ErrorKind::StagingRecoveryRequired,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
            "staging_recovery_required",
            ".areamatrix/staging",
        ),
        (
            CoreError::permission_denied("/repo"),
            ErrorKind::PermissionDenied,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
            "permission_denied",
            "/repo",
        ),
        (
            CoreError::internal("unexpected invariant"),
            ErrorKind::Internal,
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
            "internal_error",
            "unexpected invariant",
        ),
    ];

    for (error, kind, severity, recoverability, code, raw_context) in cases {
        let mapping = error.to_error_mapping();
        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
        assert_eq!(mapping.code, code);
        assert_eq!(
            mapping.technical_details.as_deref().unwrap_or_default(),
            raw_context
        );
        assert!(!mapping.recovery_action_ids.is_empty());
    }
}

#[test]
fn error_mapping_contract_api_exposes_side_effect_free_mapping_function() {
    let mapping = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some("/restricted/repo".to_owned()),
        reason: None,
        message: None,
        expected_revision: None,
        current_revision: None,
    });

    assert_eq!(mapping.kind, ErrorKind::PermissionDenied);
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(mapping.code, "permission_denied");
    assert_eq!(mapping.field.as_deref(), Some("path"));
    assert_eq!(mapping.arguments[0].name, "path");
    assert_eq!(mapping.arguments[0].value, "/restricted/repo");
    assert_eq!(
        mapping.technical_details.as_deref().unwrap_or_default(),
        "/restricted/repo"
    );
    assert_eq!(
        mapping.recovery_action_ids,
        vec!["choose_folder", "open_system_settings"]
    );
}

#[test]
fn error_mapping_contract_api_keeps_icloud_download_user_initiated() {
    let mapping = CoreError::icloud_placeholder("iCloud/report.pdf").to_error_mapping();

    assert_eq!(
        mapping.recovery_action_ids,
        vec!["download_and_retry", "choose_local_repository"]
    );
    assert_contains(ERROR_CODES, "只有用户点击 `Download & retry`");
    assert_contains(ERROR_CODES, "Core\n  和 watcher 都不触发下载");
}

#[test]
fn error_mapping_contract_api_revision_conflict_is_typed_and_nonlocalized() {
    let mapping = CoreError::revision_conflict("repo_config", 7, 9).to_error_mapping();

    assert_eq!(mapping.kind, ErrorKind::RevisionConflict);
    assert_eq!(mapping.code, "repo_config_revision_conflict");
    assert_eq!(mapping.field.as_deref(), Some("revision"));
    assert_eq!(
        mapping
            .arguments
            .iter()
            .map(|argument| (argument.name.as_str(), argument.value.as_str()))
            .collect::<Vec<_>>(),
        vec![
            ("resource", "repo_config"),
            ("expected_revision", "7"),
            ("current_revision", "9"),
        ]
    );
    assert_eq!(
        mapping.recovery_action_ids,
        vec!["review_changes", "reload_latest"]
    );
    assert_eq!(mapping.technical_details, None);

    let mapping_contract = UDL
        .split("dictionary ErrorMapping {")
        .nth(1)
        .and_then(|suffix| suffix.split("};").next())
        .expect("locate ErrorMapping dictionary");
    for forbidden in ["user_message", "suggested_action", "raw_context"] {
        assert!(
            !mapping_contract.contains(forbidden),
            "ErrorMapping must not expose localized or legacy field `{forbidden}`"
        );
    }
}
