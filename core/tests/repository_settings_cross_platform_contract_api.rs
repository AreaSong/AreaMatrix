use std::path::Path;

use area_matrix_core::{
    get_platform_capabilities, init_repo, load_config, update_config, CoreError, CoreResult,
    OverviewOutput, PlatformCapabilities, PlatformCapabilityStatus, PlatformId, RepoConfig,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-96-c4-20-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-20-repository-settings-cross-platform.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const REPOSITORY_SETTINGS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-08-repository-settings.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
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
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

#[test]
fn repository_settings_contract_reuses_config_and_platform_capability_apis() {
    fn assert_load(_: fn(String) -> CoreResult<RepoConfig>) {}
    fn assert_update(_: fn(String, RepoConfig) -> CoreResult<()>) {}
    fn assert_capabilities(_: fn(PlatformId, String) -> CoreResult<PlatformCapabilities>) {}

    assert_load(load_config);
    assert_update(update_config);
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
    let mut config = load_config(path_string(repo.path())).expect("load initial repo config");
    config.default_mode = StorageMode::Indexed;
    config.locale = "en".to_owned();
    config.icloud_warn = false;
    config.allow_replace_during_import = false;

    update_config(path_string(repo.path()), config.clone()).expect("persist repository settings");
    let reloaded = load_config(path_string(repo.path())).expect("reload repository settings");
    let capabilities =
        get_platform_capabilities(PlatformId::Linux, "0.1.0".to_owned()).expect("matrix");

    assert_eq!(reloaded, config);
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
    let before = load_config(path_string(repo.path())).expect("load initial config");
    let mut invalid = before.clone();
    invalid.repo_path = "/tmp/other-repo".to_owned();
    invalid.locale = "en".to_owned();

    let result = update_config(path_string(repo.path()), invalid);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    let after = load_config(path_string(repo.path())).expect("reload config");
    assert_eq!(after, before);
}

#[test]
fn repository_settings_contract_preserves_user_visible_files() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    std::fs::write(&readme_path, "user readme\n").expect("write user README");
    std::fs::write(&overview_path, "user overview\n").expect("write user overview");

    let mut config = load_config(path_string(repo.path())).expect("load initial config");
    config.locale = "en".to_owned();
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("persist settings");

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
        "# 4-3/task-96: C4-20 contract-api",
        "为 C4-20 repository-settings-cross-platform 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-20 repository-settings-cross-platform",
        "- S4-X-08 repository-settings",
        "- `load_config`",
        "- `update_config`",
        "- `get_platform_capabilities`",
        "repo config、platform。",
        "跨平台资料库设置和能力约束。",
        "- `Config`",
        "- `PermissionDenied`",
        "- `Io`",
        "平台不支持的设置项禁用或解释。",
        "修改配置不移动用户文件。",
        "配置失败回滚旧值。",
        "账号级云同步设置不在当前 Stage 4。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-X-08 | repository-settings | C4-17, C4-20 | cross-platform settings | 不支持项禁用",
        "平台差异必须结构化暴露。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "PlatformCapabilities get_platform_capabilities(",
        "RepoConfig load_config(string repo_path);",
        "void update_config(string repo_path, RepoConfig new_config);",
        "dictionary RepoConfig",
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
        "| `load_config(repo)` | repo | √ | Config / PermissionDenied / Io / Db |",
        "| `update_config(repo, cfg)` | repo | √ | Config / PermissionDenied / Io / Db |",
        "| `get_platform_capabilities(platform, app_version)` | platform | √ | Config |",
        "#### C4-20 repository settings contract",
        "`load_config` 是 C4-20 `repository-settings-cross-platform` 的 repo config",
        "`update_config` 是 C4-20 `repository-settings-cross-platform` 的 repo config",
        "`S4-X-08 repository-settings`",
        "禁用平台不支持的设置",
        "不接受 control map 之外的页面能力",
        "不移动、删除、重命名、覆盖用户文件",
        "账号级云同步",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

#[test]
fn repository_settings_contract_documents_consumer_scope() {
    for fragment in [
        "展示当前 repo 名称、路径、平台位置类型和 Core version。",
        "展示访问状态、watcher 状态、云盘/本地目录状态。",
        "提供 `Platform capabilities` 入口。",
        "明确危险操作不在本页直接执行。",
        "打开页面读取 repo snapshot 和 platform capability snapshot。",
        "本页不提供删除用户文件、云盘 SDK 配置、账号登录或插件入口。",
    ] {
        assert_contains(REPOSITORY_SETTINGS_PAGE, fragment);
    }

    for fragment in [
        "C4-20 repository settings also reuses this config snapshot",
        "combine it with",
        "get_platform_capabilities",
        "disable unsupported settings",
        "C4-20 repository settings uses the same transactional update surface",
        "persists only the supplied",
        "does not test, enable, or emulate platform",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-20 repository settings reads this repository config snapshot",
        "C4-20 repository settings persists only repo_config",
        "Platform-unsupported",
    ] {
        assert_contains(UDL, fragment);
    }
}
