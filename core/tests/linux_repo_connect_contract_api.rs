use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, validate_repo_path, CoreError, CoreResult, PlatformPathKind, RepoInitMode,
    RepoInitOptions, RepoPathIssue, RepoPathValidation,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-46-c4-10-contract-api.md"
);
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn linux_repo_connect_contract_exports_documented_signatures_and_errors() {
    fn assert_validate(_: fn(String) -> CoreResult<RepoPathValidation>) {}
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}

    assert_validate(validate_repo_path);
    assert_init(init_repo);

    let documented_errors = [
        CoreError::invalid_path("invalid path"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn linux_repo_connect_contract_exposes_page_ready_local_path_state() {
    let validation = RepoPathValidation {
        repo_path: "/home/user/AreaMatrix".to_owned(),
        exists: true,
        is_directory: true,
        is_readable: true,
        is_writable: true,
        is_empty: false,
        is_initialized: false,
        is_inside_area_matrix: false,
        is_icloud_path: false,
        is_onedrive_path: false,
        platform_path_kind: PlatformPathKind::Local,
        is_case_sensitive_path: true,
        has_unfinished_scan_session: false,
        recommended_mode: Some(RepoInitMode::AdoptExisting),
        issues: vec![RepoPathIssue::NonEmptyDirectory],
    };

    assert_eq!(validation.platform_path_kind, PlatformPathKind::Local);
    assert!(validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(validation.issues, vec![RepoPathIssue::NonEmptyDirectory]);
}

#[test]
fn linux_repo_connect_contract_validates_local_paths_without_mutation() {
    let repo = tempfile::tempdir().expect("create Linux repository candidate");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "owned by user\n").expect("write user README");

    let validation = validate_repo_path(path_string(repo.path())).expect("validate Linux path");

    assert!(validation.exists);
    assert!(validation.is_directory);
    assert!(validation.is_readable);
    assert!(validation.is_writable);
    assert_eq!(validation.platform_path_kind, PlatformPathKind::Local);
    assert!(validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(validation.issues, vec![RepoPathIssue::NonEmptyDirectory]);
    assert!(!repo.path().join(".areamatrix").exists());
    assert_eq!(
        fs::read_to_string(&readme).expect("read preserved user README"),
        "owned by user\n"
    );
}

#[test]
fn linux_repo_connect_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-46: C4-10 contract-api",
        "为 C4-10 linux-repo-connect 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "RepoPathValidation validate_repo_path(string repo_path);",
        "void init_repo(string repo_path, RepoInitOptions options);",
        "dictionary RepoPathValidation",
        "boolean is_readable;",
        "boolean is_writable;",
        "PlatformPathKind platform_path_kind;",
        "boolean is_case_sensitive_path;",
        "RepoInitMode? recommended_mode;",
        "sequence<RepoPathIssue> issues;",
        "enum PlatformPathKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"NetworkShare\", \"Unknown\" };",
        "InvalidPath(string path);",
        "PermissionDenied(string path);",
        "Io(string message);",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `validate_repo_path(repoPath: String) throws -> RepoPathValidation`",
        "### `init_repo(repoPath: String, options: RepoInitOptions) throws`",
        "`platformPathKind`",
        "`isCaseSensitivePath`",
        "`recommendedMode`",
        "`issues`",
        "`InvalidPath`：路径为空、不是可接受的文件系统路径、或位于 `.areamatrix/` 内部。",
        "`PermissionDenied`：无法读取目录 metadata、列出目录内容或确认写权限。",
        "`AdoptExisting`：目录可以非空；不移动、不重命名、不删除、不覆盖已有内容",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`InvalidPath { path }`",
        "`PermissionDenied { path }`",
        "`Io { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "C4-10 Linux repository connection contract",
        "Core does not run or recommend sudo/chmod",
        "adjust POSIX permissions",
        "does not configure third-party sync or mount options",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "RepoPathValidation",
        "RepoPathIssue",
        "PlatformPathKind",
        "Local",
        "NetworkShare",
        "Unknown",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
}
