use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_config, validate_repo_path, CoreError, CoreResult, OverviewOutput, RepoConfig,
    RepoInitMode, RepoInitOptions, RepoPathIssue, RepoPathValidation,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
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
fn mobile_repo_connect_contract_exports_documented_signatures_and_errors() {
    fn assert_validate(_: fn(String) -> CoreResult<RepoPathValidation>) {}
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_load_config(_: fn(String) -> CoreResult<RepoConfig>) {}

    assert_validate(validate_repo_path);
    assert_init(init_repo);
    assert_load_config(load_config);

    let errors = [
        CoreError::permission_denied("permission denied"),
        CoreError::invalid_path("invalid path"),
        CoreError::icloud_placeholder("icloud placeholder"),
    ];
    assert_eq!(errors.len(), 3);
}

#[test]
fn mobile_repo_connect_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "RepoPathValidation validate_repo_path(string repo_path);",
        "void init_repo(string repo_path, RepoInitOptions options);",
        "RepoConfig load_config(string repo_path);",
        "dictionary RepoPathValidation",
        "RepoInitMode? recommended_mode;",
        "sequence<RepoPathIssue> issues;",
        "dictionary RepoInitOptions",
        "RepoInitMode mode;",
        "dictionary RepoConfig",
        "enum RepoInitMode { \"CreateEmpty\", \"AdoptExisting\" };",
        "PermissionDenied(string path);",
        "InvalidPath(string path);",
        "ICloudPlaceholder(string path);",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `validate_repo_path(repoPath: String) throws -> RepoPathValidation`",
        "### `init_repo(repoPath: String, options: RepoInitOptions) throws`",
        "### `load_config(repoPath: String) throws -> RepoConfig`",
        "recommendedMode",
        "`PermissionDenied`：无法读取目录 metadata、列出目录内容或确认写权限。",
        "`ICloudPlaceholder`：候选路径或关键 metadata 仍是未下载的 iCloud 占位符。",
        "不触发 iCloud 占位符下载。",
        "`AdoptExisting`：目录可以非空；不移动、不重命名、不删除、不覆盖已有内容",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`InvalidPath { path }`",
        "`ICloudPlaceholder { path }`",
        "`PermissionDenied { path }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn mobile_repo_connect_consumers_can_route_from_structured_status() {
    let empty_repo = tempfile::tempdir().expect("create empty repository directory");
    let empty_validation =
        validate_repo_path(path_string(empty_repo.path())).expect("validate empty directory");
    assert_eq!(
        empty_validation.recommended_mode,
        Some(RepoInitMode::CreateEmpty)
    );
    assert!(empty_validation.issues.is_empty());

    let non_empty_repo = tempfile::tempdir().expect("create non-empty repository directory");
    fs::write(non_empty_repo.path().join("README.md"), "owned by user\n")
        .expect("write user README");
    let adopt_validation =
        validate_repo_path(path_string(non_empty_repo.path())).expect("validate non-empty path");
    assert_eq!(
        adopt_validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(
        adopt_validation.issues,
        vec![RepoPathIssue::NonEmptyDirectory]
    );
    assert!(!non_empty_repo.path().join(".areamatrix").exists());

    let initialized_repo = tempfile::tempdir().expect("create initialized repository directory");
    init_repo(
        path_string(initialized_repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");

    let initialized_validation = validate_repo_path(path_string(initialized_repo.path()))
        .expect("validate initialized path");
    let config = load_config(path_string(initialized_repo.path())).expect("load mobile config");

    assert!(initialized_validation.is_initialized);
    assert_eq!(initialized_validation.recommended_mode, None);
    assert_eq!(
        initialized_validation.issues,
        vec![RepoPathIssue::AlreadyInitialized]
    );
    assert_eq!(config.repo_path, path_string(initialized_repo.path()));
}

#[test]
fn mobile_repo_connect_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "mobile repository connection contract reuses the same surface",
        "iOS security-scoped URL or",
        "Core receives only the authorized filesystem path",
        "mobile shells call this only after the shared init/adopt",
        "does not refresh platform permissions or create metadata",
    ] {
        assert_contains(API_RS, fragment);
    }
}
