use std::{fs, path::Path};

use area_matrix_core::{
    get_platform_capabilities, init_repo, load_config, update_config, CoreError, CoreResult,
    ErrorKind, OverviewOutput, PlatformCapabilities, PlatformCapabilityStatus, PlatformId,
    RepoConfig, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-99-c4-20-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-20-repository-settings-cross-platform.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const REPOSITORY_SETTINGS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-08-repository-settings.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const DB_RS: &str = include_str!("../src/db/mod.rs");
const CONTRACT_TEST: &str = include_str!("repository_settings_cross_platform_contract_api.rs");
const IMPLEMENTATION_TEST: &str =
    include_str!("repository_settings_cross_platform_implementation.rs");
const FAILURE_TEST: &str = include_str!("repository_settings_cross_platform_failure_recovery.rs");

#[derive(Debug, Eq, PartialEq)]
struct SettingsValidationSnapshot {
    config_rows: Vec<(String, String)>,
    user_readme: String,
    user_overview: String,
    user_classifier: String,
    table_counts: [i64; 3],
    staging_entries: usize,
}

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
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    fs::write(repo.path().join("AREAMATRIX.md"), "user overview\n").expect("write user AREAMATRIX");
    repo
}

fn db_connection(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn config_rows(repo: &Path) -> Vec<(String, String)> {
    let connection = db_connection(repo);
    let mut statement = connection
        .prepare("SELECT key, value FROM repo_config ORDER BY key")
        .expect("prepare repo_config query");
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .expect("query repo_config rows");

    rows.map(|row| row.expect("read repo_config row")).collect()
}

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    db_connection(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("read table count")
}

fn staging_entries(repo: &Path) -> usize {
    fs::read_dir(repo.join(".areamatrix/staging")).map_or(0, Iterator::count)
}

fn snapshot(repo: &Path) -> SettingsValidationSnapshot {
    SettingsValidationSnapshot {
        config_rows: config_rows(repo),
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        user_overview: fs::read_to_string(repo.join("AREAMATRIX.md"))
            .expect("read user AREAMATRIX"),
        user_classifier: fs::read_to_string(repo.join(".areamatrix/classifier.yaml"))
            .expect("read classifier config"),
        table_counts: [
            table_count(repo, "files"),
            table_count(repo, "change_log"),
            table_count(repo, "scan_sessions"),
        ],
        staging_entries: staging_entries(repo),
    }
}

fn ui_ready_config(mut config: RepoConfig) -> RepoConfig {
    config.default_mode = StorageMode::Indexed;
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    config.locale = "en".to_owned();
    config.icloud_warn = false;
    config.enable_extension_rules = false;
    config.enable_keyword_rules = false;
    config.fallback_to_inbox = false;
    config.allow_replace_during_import = true;
    config
}

fn assert_error_kind(error: CoreError, expected: ErrorKind) {
    assert_eq!(error.kind(), expected);
    assert_eq!(error.to_error_mapping().kind, expected);
}

fn assert_unsupported_rows_disable_settings(matrix: &PlatformCapabilities) {
    for (name, status, ui_enabled, reason) in [
        (
            "cloud_placeholder",
            matrix.cloud_placeholder.status,
            matrix.cloud_placeholder.ui_enabled,
            &matrix.cloud_placeholder.reason,
        ),
        (
            "security_bookmark",
            matrix.security_bookmark.status,
            matrix.security_bookmark.ui_enabled,
            &matrix.security_bookmark.reason,
        ),
    ] {
        assert_eq!(status, PlatformCapabilityStatus::NotAvailable, "{name}");
        assert!(!ui_enabled, "{name} must be disabled for Linux settings");
        assert!(
            reason
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()),
            "{name} must explain why the setting is unsupported"
        );
    }
}

#[test]
fn repository_settings_validation_covers_success_and_platform_disabled_rows() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());
    let config = ui_ready_config(load_config(path_string(repo.path())).expect("load config"));

    update_config(path_string(repo.path()), config.clone()).expect("persist repository settings");
    let reloaded = load_config(path_string(repo.path())).expect("reload repository settings");
    let linux =
        get_platform_capabilities(PlatformId::Linux, "4.0.0-linux".to_owned()).expect("matrix");

    assert_eq!(reloaded, config);
    assert_eq!(linux.platform, PlatformId::Linux);
    assert_unsupported_rows_disable_settings(&linux);

    let after = snapshot(repo.path());
    assert_ne!(after.config_rows, before.config_rows);
    assert_eq!(after.user_readme, before.user_readme);
    assert_eq!(after.user_overview, before.user_overview);
    assert_eq!(after.user_classifier, before.user_classifier);
    assert_eq!(after.table_counts, before.table_counts);
    assert_eq!(after.staging_entries, before.staging_entries);
}

#[test]
fn repository_settings_validation_covers_failure_rollback_and_error_kinds() {
    let repo = initialized_repo();
    let before_config = load_config(path_string(repo.path())).expect("load baseline config");
    let before = snapshot(repo.path());

    let mut mismatched = before_config.clone();
    mismatched.repo_path = "/tmp/other-repository".to_owned();
    assert_error_kind(
        update_config(path_string(repo.path()), mismatched).expect_err("mismatch fails"),
        ErrorKind::Config,
    );

    let mut blank_locale = before_config.clone();
    blank_locale.locale = "  ".to_owned();
    assert_error_kind(
        update_config(path_string(repo.path()), blank_locale).expect_err("blank locale fails"),
        ErrorKind::Config,
    );

    assert_error_kind(
        get_platform_capabilities(PlatformId::Unknown, "4.0.0".to_owned())
            .expect_err("unknown platform fails"),
        ErrorKind::Config,
    );
    assert_eq!(
        load_config(path_string(repo.path())),
        Ok(before_config.clone())
    );
    assert_eq!(snapshot(repo.path()), before);

    install_db_failure_trigger(repo.path());
    let error = update_config(
        path_string(repo.path()),
        ui_ready_config(before_config.clone()),
    )
    .expect_err("triggered database failure rolls back");

    assert_error_kind(error, ErrorKind::Db);
    assert_eq!(load_config(path_string(repo.path())), Ok(before_config));
    assert_eq!(snapshot(repo.path()), before);
}

fn install_db_failure_trigger(repo: &Path) {
    db_connection(repo)
        .execute_batch(
            "CREATE TRIGGER block_repository_settings_locale_update
             BEFORE UPDATE OF value ON repo_config
             WHEN NEW.key = 'locale'
             BEGIN
                 SELECT RAISE(FAIL, 'blocked repository settings locale update');
             END;",
        )
        .expect("install db failure trigger");
}

#[test]
fn repository_settings_validation_locks_api_udl_rust_and_test_evidence() {
    fn assert_load(_: fn(String) -> CoreResult<RepoConfig>) {}
    fn assert_update(_: fn(String, RepoConfig) -> CoreResult<()>) {}
    fn assert_capabilities(_: fn(PlatformId, String) -> CoreResult<PlatformCapabilities>) {}

    assert_load(load_config);
    assert_update(update_config);
    assert_capabilities(get_platform_capabilities);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_consumer_scope_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-99: C4-20 validation",
        "为 C4-20 repository-settings-cross-platform 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-99",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-20 repository-settings-cross-platform",
        "- S4-X-08 repository-settings",
        "- `load_config`",
        "- `update_config`",
        "- `get_platform_capabilities`",
        "跨平台资料库设置和能力约束。",
        "更新 repo_config。",
        "原子更新配置。",
        "配置失败回滚旧值。",
        "账号级云同步设置不在当前 Stage 4。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-X-08 | repository-settings | C4-17, C4-20 | cross-platform settings | 不支持项禁用",
        "平台差异必须结构化暴露。",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    assert_udl_surface_alignment();
    assert_core_api_contract_alignment();
    assert_rust_implementation_alignment();
    assert_documented_error_alignment();
}

fn assert_udl_surface_alignment() {
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
        "PlatformCapabilitySupport cloud_placeholder;",
        "PlatformCapabilitySupport security_bookmark;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum OverviewOutput { \"GeneratedOnly\", \"RootAreaMatrixFile\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_core_api_contract_alignment() {
    for fragment in [
        "| `load_config(repo)` | repo | √ | Config / PermissionDenied / Io / Db |",
        "| `update_config(repo, cfg)` | repo | √ | Config / PermissionDenied / Io / Db |",
        "| `get_platform_capabilities(platform, app_version)` | platform | √ | Config |",
        "#### C4-20 repository settings contract",
        "禁用平台不支持的设置",
        "不移动、删除、重命名、覆盖用户文件",
        "账号级云同步",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_implementation_alignment() {
    for fragment in [
        "pub fn load_config(repo_path: String) -> CoreResult<RepoConfig>",
        "pub fn update_config(repo_path: String, new_config: RepoConfig) -> CoreResult<()>",
        "pub fn get_platform_capabilities(",
        "C4-20 repository settings uses the same transactional update surface",
        "does not test, enable, or emulate platform",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "pub(crate) fn load_config_or_default(repo_path: String) -> CoreResult<RepoConfig>",
        "pub(crate) fn update_config(repo_path: String, new_config: RepoConfig)",
        "validate_config_payload(&repo_path, &new_config)?;",
        "ensure_config_storage_writable(&repo)?;",
        "let tx = connection",
        "upsert_config(&tx, &new_config)?;",
        "tx.commit()",
        "fn validate_config_payload(repo_path: &str, config: &RepoConfig)",
    ] {
        assert_contains(DB_RS, fragment);
    }
}

fn assert_documented_error_alignment() {
    for error_name in ["Config", "PermissionDenied", "Io"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

fn assert_consumer_scope_alignment() {
    for fragment in [
        "展示当前 repo 名称、路径、平台位置类型和 Core version。",
        "展示访问状态、watcher 状态、云盘/本地目录状态。",
        "提供 `Platform capabilities` 入口。",
        "明确危险操作不在本页直接执行。",
        "打开页面读取 repo snapshot 和 platform capability snapshot。",
        "本页不提供删除用户文件、云盘 SDK 配置、账号登录或插件入口。",
        "重新连接失败不会丢失当前 repo 记录。",
    ] {
        assert_contains(REPOSITORY_SETTINGS_PAGE, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "repository_settings_contract_reuses_config_and_platform_capability_apis",
        "repository_settings_contract_exposes_page_consumable_state",
        "repository_settings_contract_rejects_invalid_update_without_partial_write",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "repository_settings_implementation_loads_defaults_and_platform_limits_without_metadata_writes",
        "repository_settings_implementation_persists_repo_config_only",
        "repository_settings_implementation_rejects_mismatched_payload_without_partial_write",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "repository_settings_failure_invalid_inputs_return_config_without_mutation",
        "repository_settings_failure_permission_denied_is_structured_and_non_mutating",
        "repository_settings_failure_db_error_rolls_back_partial_config_updates",
        "repository_settings_failure_ai_remote_defaults_do_not_create_secret_state",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
