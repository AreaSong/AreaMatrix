use area_matrix_core::{
    map_core_error, ErrorKind, ErrorMapping, ErrorMappingInput, ErrorRecoverability, ErrorSeverity,
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
    }
}

fn map(
    kind: ErrorKind,
    path: Option<&str>,
    reason: Option<&str>,
    message: Option<&str>,
) -> ErrorMapping {
    map_core_error(input(kind, path, reason, message))
}

#[test]
fn error_mapping_implementation_branches_on_kind_not_payload_text() {
    let permission = map(
        ErrorKind::PermissionDenied,
        Some("/restricted/repo"),
        Some("database is locked"),
        Some("duplicate file already exists"),
    );

    assert_eq!(permission.kind, ErrorKind::PermissionDenied);
    assert_eq!(permission.user_message, "无访问权限");
    assert_eq!(permission.severity, ErrorSeverity::High);
    assert_eq!(
        permission.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(permission.raw_context, "/restricted/repo");

    let invalid = map(
        ErrorKind::InvalidPath,
        Some("../escape.pdf"),
        Some("permission denied"),
        Some("internal error"),
    );

    assert_eq!(invalid.kind, ErrorKind::InvalidPath);
    assert_eq!(invalid.user_message, "路径不合法");
    assert_eq!(invalid.severity, ErrorSeverity::Low);
    assert_eq!(invalid.raw_context, "../escape.pdf");
}

#[test]
fn error_mapping_implementation_uses_payload_for_declared_kind() {
    let cases = [
        (
            map(
                ErrorKind::Io,
                Some("/ignored"),
                Some("ignored reason"),
                Some("disk full"),
            ),
            "disk full",
        ),
        (
            map(
                ErrorKind::Config,
                Some("/ignored"),
                Some("classifier.yaml line 7"),
                Some("ignored message"),
            ),
            "classifier.yaml line 7",
        ),
        (
            map(
                ErrorKind::DuplicateFile,
                Some("finance/existing.pdf"),
                Some("ignored reason"),
                Some("ignored message"),
            ),
            "finance/existing.pdf",
        ),
        (
            map(
                ErrorKind::Internal,
                Some("/ignored"),
                Some("ignored reason"),
                Some("unexpected invariant"),
            ),
            "unexpected invariant",
        ),
    ];

    for (mapping, raw_context) in cases {
        assert_eq!(mapping.raw_context, raw_context);
        assert!(!mapping.user_message.is_empty());
        assert!(!mapping.suggested_action.is_empty());
    }
}

#[test]
fn error_mapping_implementation_high_severity_errors_are_actionable() {
    let cases = [
        (
            map(
                ErrorKind::Db,
                None,
                None,
                Some("database disk image is malformed"),
            ),
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
        ),
        (
            map(ErrorKind::RepoNotInitialized, Some("/repo"), None, None),
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            map(ErrorKind::PermissionDenied, Some("/repo"), None, None),
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            map(ErrorKind::Internal, None, None, Some("panic boundary")),
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
        ),
    ];

    for (mapping, severity, recoverability) in cases {
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
        assert!(!mapping.suggested_action.is_empty());
        assert!(!matches!(
            mapping.recoverability,
            ErrorRecoverability::Retryable
        ));
    }
}

#[test]
fn error_mapping_implementation_db_locked_stays_retryable_without_repair_route() {
    let mapping = map(ErrorKind::Db, None, None, Some("database is locked"));

    assert_eq!(mapping.kind, ErrorKind::Db);
    assert_eq!(mapping.severity, ErrorSeverity::Medium);
    assert_eq!(mapping.recoverability, ErrorRecoverability::Retryable);
    assert_eq!(mapping.user_message, "数据库暂时被占用");
    assert!(mapping.suggested_action.contains("重试"));
}

#[test]
fn error_mapping_implementation_missing_payloads_have_stable_fallbacks() {
    let cases = [
        (ErrorKind::Io, "unspecified message"),
        (ErrorKind::Db, "unspecified message"),
        (ErrorKind::Config, "unspecified reason"),
        (ErrorKind::Classify, "unspecified reason"),
        (ErrorKind::Conflict, "unknown path"),
        (ErrorKind::DuplicateFile, "unknown path"),
        (ErrorKind::FileNotFound, "unknown path"),
        (ErrorKind::RepoNotInitialized, "unknown path"),
        (ErrorKind::InvalidPath, "unknown path"),
        (ErrorKind::ICloudPlaceholder, "unknown path"),
        (ErrorKind::PermissionDenied, "unknown path"),
        (ErrorKind::Internal, "unspecified message"),
    ];

    for (kind, raw_context) in cases {
        let mapping = map_core_error(input(kind, None, None, None));
        assert_eq!(mapping.raw_context, raw_context);
    }
}

#[test]
fn error_mapping_implementation_is_deterministic() {
    let input = input(
        ErrorKind::ICloudPlaceholder,
        Some("iCloud/report.pdf"),
        None,
        Some("ignored message"),
    );

    let first = map_core_error(input.clone());
    let second = map_core_error(input);

    assert_eq!(first, second);
    assert_eq!(first.severity, ErrorSeverity::Medium);
    assert_eq!(first.recoverability, ErrorRecoverability::Retryable);
}
