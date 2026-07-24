use std::path::Path;

use area_matrix_core::{
    get_platform_capabilities, init_repo, load_repo_config, update_repo_config, CoreError,
    CoreResult, OverviewOutput, PlatformCapabilities, PlatformCapabilityStatus, PlatformId,
    RepoConfigPatch, RepoConfigSnapshot, RepoInitMode, RepoInitOptions, RepositoryLocalePolicy,
    StorageMode,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
        locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
        content_locale: area_matrix_core::ContentLocale::En,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

#[test]
fn repository_settings_contract_reuses_config_and_platform_capability_apis() {
    fn assert_load(_: fn(String) -> CoreResult<RepoConfigSnapshot>) {}
    fn assert_update(_: fn(String, RepoConfigPatch) -> CoreResult<RepoConfigSnapshot>) {}
    fn assert_capabilities(_: fn(PlatformId, String) -> CoreResult<PlatformCapabilities>) {}

    assert_load(load_repo_config);
    assert_update(update_repo_config);
    assert_capabilities(get_platform_capabilities);

    let documented_errors = [
        CoreError::config("invalid repository settings"),
        CoreError::permission_denied("metadata unavailable"),
        CoreError::io("metadata inspection failed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn repository_settings_contract_exposes_page_consumable_state() {
    let repo = initialized_repo();
    let config = load_repo_config(path_string(repo.path())).expect("load initial repo config");
    let updated = update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: config.revision,
            default_mode: Some(StorageMode::Indexed),
            locale_policy: Some(RepositoryLocalePolicy::En),
            icloud_warn: Some(false),
            allow_replace_during_import: Some(false),
            ..RepoConfigPatch::default()
        },
    )
    .expect("persist repository settings");
    let reloaded = load_repo_config(path_string(repo.path())).expect("reload repository settings");
    let capabilities =
        get_platform_capabilities(PlatformId::Linux, "0.1.0".to_owned()).expect("matrix");

    assert_eq!(reloaded, updated);
    assert_eq!(reloaded.revision, config.revision + 1);
    assert_eq!(capabilities.platform, PlatformId::Linux);
    assert_eq!(
        capabilities.cloud_placeholder.status,
        PlatformCapabilityStatus::NotAvailable
    );
    assert!(!capabilities.cloud_placeholder.ui_enabled);
    assert!(capabilities.cloud_placeholder.reason.is_some());
    assert_eq!(
        capabilities.security_bookmark.status,
        PlatformCapabilityStatus::NotAvailable
    );
    assert!(!capabilities.security_bookmark.ui_enabled);
}

#[test]
fn repository_settings_contract_rejects_invalid_update_without_partial_write() {
    let repo = initialized_repo();
    let before = load_repo_config(path_string(repo.path())).expect("load initial config");
    let result = update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: -1,
            locale_policy: Some(RepositoryLocalePolicy::En),
            ..RepoConfigPatch::default()
        },
    );

    assert!(matches!(result, Err(CoreError::Config { .. })));
    let after = load_repo_config(path_string(repo.path())).expect("reload config");
    assert_eq!(after, before);
}

#[test]
fn repository_settings_contract_preserves_user_visible_files() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    std::fs::write(&readme_path, "user readme\n").expect("write user README");
    std::fs::write(&overview_path, "user overview\n").expect("write user overview");

    let config = load_repo_config(path_string(repo.path())).expect("load initial config");
    update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: config.revision,
            locale_policy: Some(RepositoryLocalePolicy::En),
            overview_output: Some(OverviewOutput::RootAreaMatrixFile),
            ..RepoConfigPatch::default()
        },
    )
    .expect("persist settings");

    assert_eq!(
        std::fs::read_to_string(&readme_path).expect("read README"),
        "user readme\n"
    );
    assert_eq!(
        std::fs::read_to_string(&overview_path).expect("read AREAMATRIX"),
        "user overview\n"
    );
}

#[test]
fn repository_settings_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "PlatformCapabilities get_platform_capabilities(",
        "RepoConfigSnapshot load_repo_config(string repo_path);",
        "RepoConfigSnapshot update_repo_config(string repo_path, RepoConfigPatch patch);",
        "dictionary RepoConfigSnapshot",
        "dictionary RepoConfigPatch",
        "StorageMode default_mode;",
        "OverviewOutput overview_output;",
        "boolean icloud_warn;",
        "boolean allow_replace_during_import;",
        "dictionary PlatformCapabilities",
        "PlatformCapabilitySupport watcher;",
        "PlatformCapabilitySupport trash;",
        "PlatformCapabilitySupport cloud_placeholder;",
        "PlatformCapabilitySupport security_bookmark;",
        "enum PlatformId { \"Macos\", \"Ios\", \"Windows\", \"Linux\", \"Unknown\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `load_repo_config(repo)` | repo | √ | Config / PermissionDenied / Io / Db |",
        "| `update_repo_config(repo, patch)` | repo | √ | Config / Conflict / PermissionDenied / Io / Db |",
        "| `get_platform_capabilities(platform, app_version)` | platform | √ | Config |",
        "#### repository settings contract",
        "`load_repo_config` 是 repository settings `repository-settings-cross-platform` 的 repo config",
        "`update_repo_config` 是 repository settings `repository-settings-cross-platform` 的 repo config",
        "`repository settings surface`",
        "禁用平台不支持的设置",
        "不接受 control map 之外的页面能力",
        "不移动、删除、重命名、覆盖用户文件",
        "账号级云同步",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io"] {
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

#[test]
fn repository_settings_contract_documents_consumer_scope() {
    for fragment in [
        "repository settings also reuses this config snapshot",
        "combine it with",
        "get_platform_capabilities",
        "disable unsupported settings",
        "repository settings uses the same transactional update surface",
        "persists only the supplied",
        "does not test, enable, or emulate platform",
    ] {
        assert_contains(API_RS, fragment);
    }

    assert_contains(UDL, "repository settings reads a revisioned snapshot");
    assert_contains(UDL, "repository settings submits dirty fields");
}
