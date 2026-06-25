use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_config, validate_repo_path, CoreError, CoreResult, PlatformPathKind,
    RepoConfig, RepoInitMode, RepoInitOptions, RepoPathIssue, RepoPathValidation,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
#[path = "support/domain_contract_source.rs"]
mod domain_contract_source;

use domain_contract_source::DOMAIN_RS;
const REPO_PATH_RS: &str = include_str!("../src/repo_path.rs");
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
fn windows_repo_connect_contract_exports_existing_repo_signatures_and_errors() {
    fn assert_validate(_: fn(String) -> CoreResult<RepoPathValidation>) {}
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_load_config(_: fn(String) -> CoreResult<RepoConfig>) {}

    assert_validate(validate_repo_path);
    assert_init(init_repo);
    assert_load_config(load_config);

    let documented_errors = [
        CoreError::invalid_path("invalid path"),
        CoreError::permission_denied("permission denied"),
        CoreError::config("configuration error"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn windows_repo_connect_contract_exposes_page_ready_path_state() {
    let validation = RepoPathValidation {
        repo_path: "C:\\Users\\me\\OneDrive\\AreaMatrix".to_owned(),
        exists: true,
        is_directory: true,
        is_readable: true,
        is_writable: true,
        is_empty: false,
        is_initialized: false,
        is_inside_area_matrix: false,
        is_icloud_path: false,
        is_onedrive_path: true,
        platform_path_kind: PlatformPathKind::OneDrive,
        is_case_sensitive_path: false,
        has_unfinished_scan_session: false,
        recommended_mode: Some(RepoInitMode::AdoptExisting),
        issues: vec![
            RepoPathIssue::OneDrivePath,
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::NonEmptyDirectory,
        ],
    };

    assert_eq!(validation.platform_path_kind, PlatformPathKind::OneDrive);
    assert!(validation.is_onedrive_path);
    assert!(!validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert!(validation.issues.contains(&RepoPathIssue::OneDrivePath));
    assert!(validation
        .issues
        .contains(&RepoPathIssue::WindowsCaseInsensitive));
}

#[test]
fn windows_repo_connect_contract_detects_windows_shape_without_mutation() {
    let root = tempfile::tempdir().expect("create Windows-shaped root");
    let repo = root.path().join("C:\\Users\\me\\OneDrive\\AreaMatrix");
    fs::create_dir_all(&repo).expect("create Windows-shaped repository path");
    fs::write(repo.join("README.md"), "owned by user\n").expect("write user file");

    let validation = validate_repo_path(path_string(&repo)).expect("validate Windows path");

    assert!(validation.exists);
    assert!(validation.is_directory);
    assert!(validation.is_onedrive_path);
    assert_eq!(validation.platform_path_kind, PlatformPathKind::OneDrive);
    assert!(!validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(
        validation.issues,
        vec![
            RepoPathIssue::OneDrivePath,
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::NonEmptyDirectory,
        ]
    );
    assert!(!repo.join(".areamatrix").exists());
    assert_eq!(
        fs::read_to_string(repo.join("README.md")).expect("read preserved user file"),
        "owned by user\n"
    );
}

#[test]
fn windows_repo_connect_contract_rejects_reserved_names() {
    let result = validate_repo_path("C:\\Users\\me\\CON\\AreaMatrix".to_owned());

    assert!(matches!(result, Err(CoreError::InvalidPath { .. })));
}

#[test]
fn windows_repo_connect_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "RepoPathValidation validate_repo_path(string repo_path);",
        "void init_repo(string repo_path, RepoInitOptions options);",
        "RepoConfig load_config(string repo_path);",
        "dictionary RepoPathValidation",
        "boolean is_onedrive_path;",
        "PlatformPathKind platform_path_kind;",
        "boolean is_case_sensitive_path;",
        "sequence<RepoPathIssue> issues;",
        "enum PlatformPathKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"NetworkShare\", \"Unknown\" };",
        "\"OneDrivePath\"",
        "\"WindowsReservedName\"",
        "\"WindowsCaseInsensitive\"",
        "InvalidPath(string path);",
        "PermissionDenied(string path);",
        "Config(string reason);",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "dictionary RepoPathValidation",
        "boolean is_onedrive_path;",
        "PlatformPathKind platform_path_kind;",
        "boolean is_case_sensitive_path;",
        "enum PlatformPathKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"NetworkShare\", \"Unknown\" };",
        "\"OneDrivePath\"",
        "\"WindowsReservedName\"",
        "\"WindowsCaseInsensitive\"",
        "`isOnedrivePath`",
        "`platformPathKind`",
        "`isCaseSensitivePath`",
        "不调用 OneDrive SDK，不读取 OneDrive 客户端同步状态，不修改 OneDrive 同步设置。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "is_onedrive_path",
        "platform_path_kind",
        "is_case_sensitive_path",
        "OneDrivePath",
        "WindowsReservedName",
        "WindowsCaseInsensitive",
        "PlatformPathKind",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for fragment in [
        "has_windows_drive_prefix",
        "is_windows_reserved_name",
        "PlatformPathKind::OneDrive",
        "WindowsCaseInsensitive",
        "CoreError::invalid_path",
    ] {
        assert_contains(REPO_PATH_RS, fragment);
    }
}

#[test]
fn windows_repo_connect_documents_consumer_state_without_adjacent_capabilities() {
    for fragment in [
        "Returns `CoreError::InvalidPath { path }`",
        "`CoreError::PermissionDenied { path }`",
        "`CoreError::Config { reason }`",
        "must never create,",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "`InvalidPath { path }`",
        "`PermissionDenied { path }`",
        "`Config { reason }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for forbidden in [
        "Windows shell extension",
        "OneDrive SDK",
        "change OneDrive settings",
    ] {
        assert!(
            !REPO_PATH_RS.contains(forbidden),
            "Windows repository connection repo path contract must not implement adjacent capability `{forbidden}`"
        );
    }

    assert_contains(
        CORE_API,
        "### `validate_repo_path(repoPath: String) throws -> RepoPathValidation`",
    );
}
