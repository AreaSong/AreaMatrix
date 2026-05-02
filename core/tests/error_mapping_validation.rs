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
            "文件操作失败",
            "disk full",
        ),
        (
            CoreError::db("database is locked"),
            ErrorKind::Db,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
            "数据库错误",
            "database is locked",
        ),
        (
            CoreError::config("classifier.yaml missing default"),
            ErrorKind::Config,
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
            "配置错误",
            "classifier.yaml missing default",
        ),
        (
            CoreError::classify("rule engine unavailable"),
            ErrorKind::Classify,
            ErrorSeverity::Low,
            ErrorRecoverability::RefreshRequired,
            "分类失败",
            "rule engine unavailable",
        ),
        (
            CoreError::conflict("docs/report.pdf"),
            ErrorKind::Conflict,
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
            "路径冲突",
            "docs/report.pdf",
        ),
        (
            CoreError::DuplicateFile {
                existing_path: "finance/report.pdf".to_owned(),
            },
            ErrorKind::DuplicateFile,
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
            "文件已存在",
            "finance/report.pdf",
        ),
        (
            CoreError::file_not_found("docs/missing.pdf"),
            ErrorKind::FileNotFound,
            ErrorSeverity::Low,
            ErrorRecoverability::RefreshRequired,
            "文件不存在",
            "docs/missing.pdf",
        ),
        (
            CoreError::repo_not_initialized("/repo"),
            ErrorKind::RepoNotInitialized,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
            "资料库未初始化",
            "/repo",
        ),
        (
            CoreError::invalid_path("../escape.pdf"),
            ErrorKind::InvalidPath,
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
            "路径不合法",
            "../escape.pdf",
        ),
        (
            CoreError::icloud_placeholder("iCloud/report.pdf"),
            ErrorKind::ICloudPlaceholder,
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
            "iCloud 文件未下载",
            "iCloud/report.pdf",
        ),
        (
            CoreError::permission_denied("/restricted/repo"),
            ErrorKind::PermissionDenied,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
            "无访问权限",
            "/restricted/repo",
        ),
        (
            CoreError::internal("unexpected invariant"),
            ErrorKind::Internal,
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
            "应用内部错误",
            "unexpected invariant",
        ),
    ];

    for (error, kind, severity, recoverability, user_message, raw_context) in cases {
        let mapping = error.to_error_mapping();

        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
        assert_eq!(mapping.user_message, user_message);
        assert_eq!(mapping.raw_context, raw_context);
        assert!(
            !mapping.suggested_action.is_empty(),
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
    assert_eq!(permission.user_message, "无访问权限");
    assert_eq!(permission.severity, ErrorSeverity::High);
    assert_eq!(
        permission.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(permission.raw_context, "/restricted/repo");

    let icloud = map_core_error(input(
        ErrorKind::ICloudPlaceholder,
        Some("iCloud/report.pdf"),
        Some("permission denied"),
        Some("database is locked"),
    ));
    assert_eq!(icloud.kind, ErrorKind::ICloudPlaceholder);
    assert_eq!(icloud.user_message, "iCloud 文件未下载");
    assert_eq!(icloud.severity, ErrorSeverity::Medium);
    assert_eq!(icloud.recoverability, ErrorRecoverability::Retryable);
    assert_eq!(icloud.raw_context, "iCloud/report.pdf");
}

#[test]
fn error_mapping_validation_high_severity_errors_are_not_swallowed() {
    let cases = [
        map_core_error(input(ErrorKind::Db, None, None, Some("database is locked"))),
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
        assert!(!mapping.user_message.is_empty());
        assert!(!mapping.suggested_action.is_empty());
        assert!(!mapping.raw_context.is_empty());
    }
}
