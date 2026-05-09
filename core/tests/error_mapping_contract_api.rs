use area_matrix_core::{
    map_core_error, CoreError, ErrorKind, ErrorMappingInput, ErrorRecoverability, ErrorSeverity,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const ERROR_RS: &str = include_str!("../src/error.rs");
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
        CoreError::config("configuration error"),
        CoreError::classify("classification error"),
        CoreError::conflict("path conflict"),
        CoreError::DuplicateFile {
            existing_path: "finance/existing.pdf".to_owned(),
        },
        CoreError::file_not_found("missing file"),
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::invalid_path("invalid path"),
        CoreError::icloud_placeholder("icloud placeholder"),
        CoreError::permission_denied("permission denied"),
        CoreError::internal("internal error"),
    ];
    assert_eq!(documented_variants.len(), 12);
}

#[test]
fn error_mapping_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "# C1-21 error-mapping",
        "- S1-03 validate-path",
        "- S1-06 init-failed",
        "- S1-11 main-repo-error",
        "- S1-25 icloud-conflict-min",
        "- S1-32 error-recovery",
        "- 所有 `[Throws=CoreError]` API。",
        "- Swift AppError 包装层。",
        "- `CoreError` variant。",
        "- 原始 path、reason 或 message。",
        "- 可供 UI 展示的错误类型、用户文案、严重程度和建议动作。",
        "- 无。",
        "- `Io`",
        "- `Db`",
        "- `Config`",
        "- `Classify`",
        "- `Conflict`",
        "- `DuplicateFile`",
        "- `FileNotFound`",
        "- `RepoNotInitialized`",
        "- `InvalidPath`",
        "- `ICloudPlaceholder`",
        "- `PermissionDenied`",
        "- `Internal`",
        "- 每个 `CoreError` 都能被 Swift 层映射为用户可理解消息。",
        "- 高严重错误进入 S1-32 或 repo error 状态，不被吞掉。",
        "- 错误映射不依赖字符串 contains 做主分支判断。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-03 | validate-path | C1-01, C1-03, C1-21 |",
        "| S1-06 | init-failed | C1-21 | error mapping only",
        "| S1-11 | main-repo-error | C1-01, C1-19, C1-21 |",
        "| S1-25 | icloud-conflict-min | C1-01, C1-21 |",
        "| S1-32 | error-recovery | C1-16, C1-21 | `recover_on_startup`, error mapping",
        "C1-16..C1-21",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "[Throws=CoreError]",
        "错误映射元数据",
        "每个错误返回 severity、suggested_action、recoverability",
        "避免 UI 解析字符串",
        "ErrorMapping map_core_error(ErrorMappingInput input);",
        "dictionary ErrorMapping",
        "enum ErrorSeverity",
        "enum ErrorRecoverability",
        "interface CoreError",
        "DuplicateFile(string existing_path);",
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
        "Config(string reason);",
        "Classify(string reason);",
        "Conflict(string path);",
        "DuplicateFile(string existing_path);",
        "FileNotFound(string path);",
        "RepoNotInitialized(string path);",
        "InvalidPath(string path);",
        "ICloudPlaceholder(string path);",
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
        "| `Config { reason }` |",
        "| `Classify { reason }` |",
        "| `Conflict { path }` |",
        "| `DuplicateFile { existing_path }` |",
        "| `FileNotFound { path }` |",
        "| `RepoNotInitialized { path }` |",
        "| `InvalidPath { path }` |",
        "| `ICloudPlaceholder { path }` |",
        "| `PermissionDenied { path }` |",
        "| `Internal { message }` |",
        "| low | toast 3s 自动消失 |",
        "| medium | banner 可手动关闭 |",
        "| high | modal alert |",
        "| critical | blocking modal |",
        "Swift 侧 AppError 映射",
        "public func toAppError() -> AppError",
        "不要硬来",
        "用技术术语吓退用户",
        "把 `error.localizedDescription` 直接显示",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "C1-21 treats each variant and payload as the structured input",
        "branch on variants and payloads",
        "localized strings or `Display` output",
        "suggested action, and recoverability",
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
            CoreError::classify("rule engine failed"),
            ErrorKind::Classify,
            ErrorSeverity::Low,
            ErrorRecoverability::RefreshRequired,
            "分类失败",
            "rule engine failed",
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
            CoreError::permission_denied("/repo"),
            ErrorKind::PermissionDenied,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
            "无访问权限",
            "/repo",
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
fn error_mapping_contract_api_exposes_side_effect_free_mapping_function() {
    let mapping = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some("/restricted/repo".to_owned()),
        reason: None,
        message: None,
    });

    assert_eq!(mapping.kind, ErrorKind::PermissionDenied);
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(mapping.user_message, "无访问权限");
    assert_eq!(mapping.raw_context, "/restricted/repo");
    assert_contains(&mapping.suggested_action, "系统设置");
}
