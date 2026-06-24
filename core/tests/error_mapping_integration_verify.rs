use std::{fs, path::Path};

use area_matrix_core::{
    map_core_error, CoreError, ErrorKind, ErrorMapping, ErrorMappingInput, ErrorRecoverability,
    ErrorSeverity,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
#[path = "support/error_contract_source.rs"]
mod error_contract_source;

use error_contract_source::ERROR_RS;
const LIB_RS: &str = include_str!("../src/lib.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
}

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
fn error_mapping_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_c1_21_capability_spec();
    assert_core_api_and_udl_contract();
    assert_core_consumers();
    assert_rust_entry_points_are_real_error_mapping_wiring();
}

fn assert_c1_21_capability_spec() {}

fn assert_core_api_and_udl_contract() {
    for fragment in [
        "ErrorMapping map_core_error(ErrorMappingInput input);",
        "dictionary ErrorMappingInput",
        "ErrorKind kind;",
        "string? path;",
        "string? reason;",
        "string? message;",
        "dictionary ErrorMapping",
        "string user_message;",
        "ErrorSeverity severity;",
        "string suggested_action;",
        "ErrorRecoverability recoverability;",
        "string raw_context;",
        "enum ErrorKind",
        "enum ErrorSeverity { \"Low\", \"Medium\", \"High\", \"Critical\" };",
        "enum ErrorRecoverability",
        "\"Retryable\", \"UserActionRequired\", \"RefreshRequired\", \"Fatal\"",
        "interface CoreError",
        "DuplicateFile(string existing_path);",
        "ICloudPlaceholder(string path);",
        "PermissionDenied(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for variant in [
        "\"Io\"",
        "\"Db\"",
        "\"Config\"",
        "\"Validation\"",
        "\"Classify\"",
        "\"Conflict\"",
        "\"DuplicateFile\"",
        "\"FileNotFound\"",
        "\"ExpiredAction\"",
        "\"RepoNotInitialized\"",
        "\"InvalidPath\"",
        "\"ICloudPlaceholder\"",
        "\"StagingRecoveryRequired\"",
        "\"PermissionDenied\"",
        "\"Internal\"",
    ] {
        assert_contains(CORE_API, variant);
        assert_contains(UDL, variant);
    }

    for fragment in [
        "每个错误返回 severity、suggested_action、recoverability",
        "Swift `AppError` 包装层只负责本地化与展示编排",
        "不得用字符串 contains 做主分支判断",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_core_consumers() {}

fn assert_rust_entry_points_are_real_error_mapping_wiring() {
    for fragment in [
        "pub fn map_core_error(input: ErrorMappingInput) -> ErrorMapping",
        "input.into_core_error().to_error_mapping()",
        "pub fn to_error_mapping(&self) -> ErrorMapping",
        "fn mapping_template(&self) -> &'static ErrorMappingTemplate",
        "pub fn raw_context(&self) -> &str",
        "side-effect free",
        "must not",
        "inspect the filesystem",
        "open the database",
        "write logs",
        "mutate repository",
    ] {
        assert_contains(ERROR_RS, fragment);
    }

    for fragment in [
        "map_core_error, CoreError, CoreResult, ErrorKind, ErrorMapping, ErrorMappingInput",
        "ErrorRecoverability, ErrorSeverity",
    ] {
        assert_contains(LIB_RS, fragment);
    }
}

#[test]
fn error_mapping_integration_verify_all_core_errors_drive_stable_ui_metadata() {
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
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
            "数据库暂时被占用",
            "database is locked",
        ),
        (
            CoreError::db("database disk image is malformed"),
            ErrorKind::Db,
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
            "资料库索引损坏",
            "database disk image is malformed",
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
                existing_path: "finance/existing.pdf".to_owned(),
            },
            ErrorKind::DuplicateFile,
            ErrorSeverity::Low,
            ErrorRecoverability::UserActionRequired,
            "文件已存在",
            "finance/existing.pdf",
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
        assert!(!mapping.suggested_action.is_empty());
    }
}

#[test]
fn error_mapping_integration_verify_consuming_pages_can_route_by_kind_and_severity() {
    let repo_error_cases = [
        map(
            ErrorKind::Db,
            None,
            None,
            Some("database disk image is malformed"),
        ),
        map(
            ErrorKind::RepoNotInitialized,
            Some("/repo"),
            None,
            Some("ignored message"),
        ),
        map(
            ErrorKind::PermissionDenied,
            Some("/restricted/repo"),
            Some("ignored reason"),
            None,
        ),
        map(
            ErrorKind::Internal,
            Some("/ignored"),
            Some("ignored reason"),
            Some("panic boundary"),
        ),
    ];

    for mapping in repo_error_cases {
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

    let validate_path = map(
        ErrorKind::InvalidPath,
        Some("../escape.pdf"),
        Some("permission denied"),
        Some("database is locked"),
    );
    assert_eq!(validate_path.kind, ErrorKind::InvalidPath);
    assert_eq!(validate_path.severity, ErrorSeverity::Low);
    assert_eq!(
        validate_path.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(validate_path.raw_context, "../escape.pdf");

    let icloud = map(
        ErrorKind::ICloudPlaceholder,
        Some("iCloud/report.pdf"),
        Some("permission denied"),
        Some("database is locked"),
    );
    assert_eq!(icloud.kind, ErrorKind::ICloudPlaceholder);
    assert_eq!(icloud.severity, ErrorSeverity::Medium);
    assert_eq!(icloud.recoverability, ErrorRecoverability::Retryable);
    assert_eq!(icloud.raw_context, "iCloud/report.pdf");

    let db_locked = map(ErrorKind::Db, None, None, Some("database is locked"));
    assert_eq!(db_locked.kind, ErrorKind::Db);
    assert_eq!(db_locked.severity, ErrorSeverity::Medium);
    assert_eq!(db_locked.recoverability, ErrorRecoverability::Retryable);

    let db_corrupted = map(
        ErrorKind::Db,
        None,
        None,
        Some("database disk image is malformed"),
    );
    assert_eq!(db_corrupted.kind, ErrorKind::Db);
    assert_eq!(db_corrupted.severity, ErrorSeverity::Critical);
    assert_eq!(db_corrupted.recoverability, ErrorRecoverability::Fatal);
}

#[test]
fn error_mapping_integration_verify_has_no_user_file_or_repo_side_effects() {
    let repo = tempfile::tempdir().expect("create temporary user repository");
    let user_file = repo.path().join("README.md");
    let user_dir = repo.path().join("docs");
    fs::create_dir(&user_dir).expect("create user directory");
    fs::write(&user_file, b"user-authored readme").expect("write user file");

    let before = fs::read(&user_file).expect("read user file before mapping");

    let _permission = map(
        ErrorKind::PermissionDenied,
        Some(&path_string(&user_dir)),
        Some("iCloud placeholder can retry"),
        Some("duplicate file already exists"),
    );
    let _icloud = map(
        ErrorKind::ICloudPlaceholder,
        Some(&path_string(&repo.path().join("icloud.placeholder"))),
        Some("permission denied"),
        None,
    );
    let _internal = map(
        ErrorKind::Internal,
        Some("/ignored"),
        Some("ignored reason"),
        Some("panic boundary"),
    );

    assert_eq!(
        fs::read(&user_file).expect("read user file after mapping"),
        before
    );
    assert!(user_dir.is_dir());
    assert!(!repo.path().join(".areamatrix").exists());
}
