use area_matrix_core::{
    map_core_error, CoreError, ErrorKind, ErrorMappingInput, ErrorRecoverability, ErrorSeverity,
};
use pretty_assertions::assert_eq;

fn input(
    kind: ErrorKind,
    path: Option<&str>,
    reason: Option<&str>,
    message: Option<&str>,
) -> ErrorMappingInput {
    ErrorMappingInput {
        kind,
        path: path.map(str::to_owned),
        reason: reason.map(str::to_owned),
        message: message.map(str::to_owned),
        expected_revision: None,
        current_revision: None,
    }
}

#[test]
fn error_mapping_validation_maps_every_core_error_to_ui_metadata() {
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
            CoreError::classify("rule engine unavailable"),
            ErrorKind::Classify,
            ErrorSeverity::Low,
            ErrorRecoverability::RefreshRequired,
            "classification_error",
            "rule engine unavailable",
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
                existing_path: "finance/report.pdf".to_owned(),
            },
            ErrorKind::DuplicateFile,
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
            "duplicate_file",
            "finance/report.pdf",
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
            CoreError::permission_denied("/restricted/repo"),
            ErrorKind::PermissionDenied,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
            "permission_denied",
            "/restricted/repo",
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
        assert!(
            !mapping.recovery_action_ids.is_empty(),
            "mapped errors need a user-actionable next step"
        );
    }
}

#[test]
fn error_mapping_validation_ffi_input_matches_core_error_mapping() {
    let cases = [
        (
            CoreError::io("disk full"),
            input(ErrorKind::Io, None, None, Some("disk full")),
        ),
        (
            CoreError::db("database is locked"),
            input(ErrorKind::Db, None, None, Some("database is locked")),
        ),
        (
            CoreError::db("database disk image is malformed"),
            input(
                ErrorKind::Db,
                None,
                None,
                Some("database disk image is malformed"),
            ),
        ),
        (
            CoreError::config("bad config"),
            input(ErrorKind::Config, None, Some("bad config"), None),
        ),
        (
            CoreError::classify("bad classifier"),
            input(ErrorKind::Classify, None, Some("bad classifier"), None),
        ),
        (
            CoreError::conflict("docs/report.pdf"),
            input(ErrorKind::Conflict, Some("docs/report.pdf"), None, None),
        ),
        (
            CoreError::DuplicateFile {
                existing_path: "finance/report.pdf".to_owned(),
            },
            input(
                ErrorKind::DuplicateFile,
                Some("finance/report.pdf"),
                None,
                None,
            ),
        ),
        (
            CoreError::file_not_found("docs/missing.pdf"),
            input(
                ErrorKind::FileNotFound,
                Some("docs/missing.pdf"),
                None,
                None,
            ),
        ),
        (
            CoreError::repo_not_initialized("/repo"),
            input(ErrorKind::RepoNotInitialized, Some("/repo"), None, None),
        ),
        (
            CoreError::invalid_path("../escape.pdf"),
            input(ErrorKind::InvalidPath, Some("../escape.pdf"), None, None),
        ),
        (
            CoreError::icloud_placeholder("iCloud/report.pdf"),
            input(
                ErrorKind::ICloudPlaceholder,
                Some("iCloud/report.pdf"),
                None,
                None,
            ),
        ),
        (
            CoreError::permission_denied("/restricted/repo"),
            input(
                ErrorKind::PermissionDenied,
                Some("/restricted/repo"),
                None,
                None,
            ),
        ),
        (
            CoreError::internal("unexpected invariant"),
            input(
                ErrorKind::Internal,
                None,
                None,
                Some("unexpected invariant"),
            ),
        ),
    ];

    for (error, ffi_input) in cases {
        assert_eq!(map_core_error(ffi_input), error.to_error_mapping());
    }
}

#[test]
fn error_mapping_validation_uses_kind_not_misleading_payload_text() {
    let permission = map_core_error(input(
        ErrorKind::PermissionDenied,
        Some("/restricted/repo"),
        Some("iCloud placeholder can retry"),
        Some("duplicate file already exists"),
    ));
    assert_eq!(permission.kind, ErrorKind::PermissionDenied);
    assert_eq!(permission.code, "permission_denied");
    assert_eq!(permission.severity, ErrorSeverity::High);
    assert_eq!(
        permission.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(
        permission.technical_details.as_deref().unwrap_or_default(),
        "/restricted/repo"
    );

    let icloud = map_core_error(input(
        ErrorKind::ICloudPlaceholder,
        Some("iCloud/report.pdf"),
        Some("permission denied"),
        Some("database is locked"),
    ));
    assert_eq!(icloud.kind, ErrorKind::ICloudPlaceholder);
    assert_eq!(icloud.code, "icloud_placeholder_not_downloaded");
    assert_eq!(icloud.severity, ErrorSeverity::Medium);
    assert_eq!(icloud.recoverability, ErrorRecoverability::Retryable);
    assert_eq!(
        icloud.technical_details.as_deref().unwrap_or_default(),
        "iCloud/report.pdf"
    );
}

#[test]
fn error_mapping_validation_high_severity_errors_are_not_swallowed() {
    let cases = [
        map_core_error(input(
            ErrorKind::Db,
            None,
            None,
            Some("database disk image is malformed"),
        )),
        map_core_error(input(
            ErrorKind::RepoNotInitialized,
            Some("/repo"),
            None,
            None,
        )),
        map_core_error(input(
            ErrorKind::PermissionDenied,
            Some("/restricted/repo"),
            None,
            None,
        )),
        map_core_error(input(
            ErrorKind::Internal,
            None,
            None,
            Some("panic boundary"),
        )),
    ];

    for mapping in cases {
        assert!(matches!(
            mapping.severity,
            ErrorSeverity::High | ErrorSeverity::Critical
        ));
        assert!(matches!(
            mapping.recoverability,
            ErrorRecoverability::UserActionRequired | ErrorRecoverability::Fatal
        ));
        assert!(!mapping.code.is_empty());
        assert!(!mapping.recovery_action_ids.is_empty());
        assert!(!mapping
            .technical_details
            .as_deref()
            .unwrap_or_default()
            .is_empty());
    }
}

#[test]
fn error_mapping_validation_db_locked_and_corrupted_have_distinct_recovery_paths() {
    let locked = CoreError::db_locked("SQLITE_BUSY: database is locked").to_error_mapping();
    assert_eq!(locked.kind, ErrorKind::DbLocked);
    assert_eq!(locked.code, "database_locked");
    assert_eq!(locked.severity, ErrorSeverity::Medium);
    assert_eq!(locked.recoverability, ErrorRecoverability::Retryable);
    assert_eq!(
        locked.recovery_action_ids,
        vec!["retry", "collect_diagnostics"]
    );

    let corrupted = CoreError::db_corrupted("database disk image is malformed").to_error_mapping();
    assert_eq!(corrupted.kind, ErrorKind::DbCorrupted);
    assert_eq!(corrupted.code, "database_corrupted");
    assert_eq!(corrupted.severity, ErrorSeverity::Critical);
    assert_eq!(corrupted.recoverability, ErrorRecoverability::Fatal);
    assert_eq!(
        corrupted.recovery_action_ids,
        vec!["open_recovery", "collect_diagnostics"]
    );
}

#[test]
fn error_mapping_validation_descriptor_preserves_typed_payloads() {
    let locked = map_core_error(ErrorMappingInput {
        kind: ErrorKind::DbLocked,
        path: None,
        reason: None,
        message: Some("SQLITE_BUSY".to_owned()),
        expected_revision: None,
        current_revision: None,
    });
    assert_eq!(locked.code, "database_locked");

    let revision = map_core_error(ErrorMappingInput {
        kind: ErrorKind::RevisionConflict,
        path: Some("repo_config".to_owned()),
        reason: None,
        message: None,
        expected_revision: Some(7),
        current_revision: Some(9),
    });
    assert_eq!(revision.code, "repo_config_revision_conflict");
    assert_eq!(revision.arguments[1].value, "7");
    assert_eq!(revision.arguments[2].value, "9");
}

#[test]
fn error_mapping_validation_generic_db_message_is_never_reclassified() {
    let mapping = map_core_error(input(
        ErrorKind::Db,
        None,
        None,
        Some("database is locked after database disk image is malformed"),
    ));

    assert_eq!(mapping.kind, ErrorKind::Db);
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(mapping.code, "database_error");
}
