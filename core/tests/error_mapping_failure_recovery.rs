use std::{fs, path::Path};

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

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

#[test]
fn error_mapping_failure_recovery_permission_denied_never_becomes_retryable() {
    let mapping = map(
        ErrorKind::PermissionDenied,
        Some("/restricted/repo"),
        Some("icloud placeholder can retry"),
        Some("temporary busy duplicate file"),
    );

    assert_eq!(mapping.kind, ErrorKind::PermissionDenied);
    assert_eq!(mapping.user_message, "无访问权限");
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(mapping.raw_context, "/restricted/repo");
    assert!(mapping.suggested_action.contains("系统设置"));
    assert!(!matches!(
        mapping.recoverability,
        ErrorRecoverability::Retryable
    ));
}

#[test]
fn error_mapping_failure_recovery_retry_policy_stays_structured_by_kind() {
    let cases = [
        (
            map(
                ErrorKind::ICloudPlaceholder,
                Some("iCloud/report.pdf"),
                Some("permission denied"),
                Some("database is locked"),
            ),
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
        ),
        (
            map(
                ErrorKind::DuplicateFile,
                Some("finance/report.pdf"),
                Some("icloud placeholder"),
                Some("busy"),
            ),
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            map(
                ErrorKind::Internal,
                Some("/ignored"),
                Some("duplicate"),
                Some("panic boundary"),
            ),
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
        ),
    ];

    for (mapping, severity, recoverability) in cases {
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
        assert!(!mapping.user_message.is_empty());
        assert!(!mapping.suggested_action.is_empty());
    }
}

#[test]
fn error_mapping_failure_recovery_repeated_mapping_is_idempotent() {
    let input = input(
        ErrorKind::Db,
        Some("/ignored"),
        Some("ignored reason"),
        Some("schema damaged"),
    );

    let first = map_core_error(input.clone());
    let second = map_core_error(input);

    assert_eq!(first, second);
    assert_eq!(first.kind, ErrorKind::Db);
    assert_eq!(first.severity, ErrorSeverity::High);
    assert_eq!(
        first.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(first.raw_context, "schema damaged");
}

#[test]
fn error_mapping_failure_recovery_has_no_user_file_side_effects() {
    let repo = tempfile::tempdir().expect("create temporary user repository");
    let user_file = repo.path().join("README.md");
    let user_dir = repo.path().join("docs");
    fs::create_dir(&user_dir).expect("create user directory");
    fs::write(&user_file, b"user-authored readme").expect("write user file");

    let _invalid = map(
        ErrorKind::InvalidPath,
        Some(&path_string(&user_file)),
        None,
        Some("ignored"),
    );
    let _permission = map(
        ErrorKind::PermissionDenied,
        Some(&path_string(&user_dir)),
        Some("ignored"),
        None,
    );
    let _icloud = map(
        ErrorKind::ICloudPlaceholder,
        Some(&path_string(&repo.path().join("icloud.placeholder"))),
        None,
        None,
    );

    assert_eq!(
        fs::read(&user_file).expect("read user file after mapping"),
        b"user-authored readme"
    );
    assert!(user_dir.is_dir());
    assert!(!repo.path().join(".areamatrix").exists());
}
