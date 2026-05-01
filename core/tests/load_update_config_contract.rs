use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_config, update_config, CoreError, CoreResult, OverviewOutput, RepoConfig,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");

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

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

fn config_rows(repo: &Path) -> Vec<(String, String, i64)> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let mut statement = connection
        .prepare("SELECT key, value, updated_at FROM repo_config ORDER BY key")
        .expect("prepare repo_config query");
    let rows = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .expect("query repo_config rows");

    rows.map(|row| row.expect("read repo_config row")).collect()
}

fn config_key_values(repo: &Path) -> Vec<(String, String)> {
    config_rows(repo)
        .into_iter()
        .map(|(key, value, _)| (key, value))
        .collect()
}

#[test]
fn load_update_config_contract_exports_callable_signatures() {
    fn assert_load(_: fn(String) -> CoreResult<RepoConfig>) {}
    fn assert_update(_: fn(String, RepoConfig) -> CoreResult<()>) {}

    assert_load(load_config);
    assert_update(update_config);
}

#[test]
fn load_update_config_contract_docs_udl_and_control_map_stay_aligned() {
    for fragment in [
        "RepoConfig load_config(string repo_path);",
        "void update_config(string repo_path, RepoConfig new_config);",
        "dictionary RepoConfig",
        "StorageMode default_mode;",
        "OverviewOutput overview_output;",
        "boolean ai_enabled;",
        "string locale;",
        "boolean icloud_warn;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum OverviewOutput { \"GeneratedOnly\", \"RootAreaMatrixFile\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for core_api_fragment in [
        "| `load_config(repo)` | repo | √ | Config / PermissionDenied / Io / Db |",
        "| `update_config(repo, cfg)` | repo | √ | Config / PermissionDenied / Io / Db |",
        "通过 SQLite 事务更新 `repo_config`",
        "该调用不写 tmp 文件、不",
    ] {
        assert_contains(CORE_API, core_api_fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io", "Db"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }

    assert_contains(
        CAPABILITY_SPEC,
        "当前 C1-04 contract-api 只持久化 SQLite `repo_config`",
    );
    assert_contains(CAPABILITY_SPEC, "文件写入必须采用 tmp + rename");

    for control_map_fragment in [
        "| S1-26 | settings-general | C1-04, C1-07 | `load_config`, `update_config`",
        "| S1-27 | settings-repository | C1-04, C1-08, C1-20 | `load_config`, `update_config`",
        "| S1-28 | settings-classifier | C1-04, C1-05 | `load_config`, `predict_category`",
        "| S1-29 | settings-integrations | C1-04 | `load_config`, `update_config`",
        "| S1-30 | settings-advanced | C1-04, C1-16, C1-20 |",
    ] {
        assert_contains(CONTROL_MAP, control_map_fragment);
    }
}

#[test]
fn load_update_config_loads_defaults_when_metadata_is_missing() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    let config = load_config(path_string(repo.path())).expect("load default config");

    assert_eq!(config.repo_path, path_string(repo.path()));
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(!config.ai_enabled);
    assert_eq!(config.locale, "zh-Hans");
    assert!(config.icloud_warn);
}

#[test]
fn load_update_config_rejects_empty_repo_path_as_config_error() {
    let config = RepoConfig {
        repo_path: String::new(),
        default_mode: StorageMode::Copied,
        overview_output: OverviewOutput::GeneratedOnly,
        ai_enabled: false,
        locale: "zh-Hans".to_owned(),
        icloud_warn: true,
    };

    assert_eq!(load_config(String::new()), Err(CoreError::Config));
    assert_eq!(update_config(String::new(), config), Err(CoreError::Config));
}

#[test]
fn load_update_config_update_persists_all_repo_config_fields() {
    let repo = initialized_repo();
    let mut config = load_config(path_string(repo.path())).expect("load initial config");
    config.default_mode = StorageMode::Indexed;
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    config.ai_enabled = true;
    config.locale = "en".to_owned();
    config.icloud_warn = false;

    update_config(path_string(repo.path()), config.clone()).expect("persist config update");

    let reloaded = load_config(path_string(repo.path())).expect("reload updated config");
    assert_eq!(reloaded, config);
    assert_eq!(config_rows(repo.path()).len(), 6);
    assert!(!repo.path().join("README.md").exists());
    assert!(!repo.path().join("AREAMATRIX.md").exists());
}

#[test]
fn load_update_config_update_refreshes_repo_config_updated_at() {
    let repo = initialized_repo();
    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    connection
        .execute("UPDATE repo_config SET updated_at = 1", [])
        .expect("set stale updated_at values");
    drop(connection);

    let mut config = load_config(path_string(repo.path())).expect("load initial config");
    config.locale = "en".to_owned();

    update_config(path_string(repo.path()), config).expect("persist config update");

    for (key, _, updated_at) in config_rows(repo.path()) {
        assert!(updated_at > 1, "{key} should have a fresh updated_at");
    }
}

#[test]
fn load_update_config_update_rejects_mismatched_payload_without_changing_previous_config() {
    let repo = initialized_repo();
    let before = load_config(path_string(repo.path())).expect("load initial config");
    let mut invalid = before.clone();
    invalid.repo_path = "/tmp/other-repo".to_owned();
    invalid.locale = "en".to_owned();

    let result = update_config(path_string(repo.path()), invalid);

    assert_eq!(result, Err(CoreError::Config));
    let after = load_config(path_string(repo.path())).expect("reload config after failed update");
    assert_eq!(after, before);
}

#[test]
fn load_update_config_update_rejects_empty_locale_without_partial_write() {
    let repo = initialized_repo();
    let before = load_config(path_string(repo.path())).expect("load initial config");
    let mut invalid = before.clone();
    invalid.locale = "  ".to_owned();
    invalid.ai_enabled = true;

    let result = update_config(path_string(repo.path()), invalid);

    assert_eq!(result, Err(CoreError::Config));
    let after = load_config(path_string(repo.path())).expect("reload config after failed update");
    assert_eq!(after, before);
}

#[test]
fn load_update_config_update_rolls_back_when_late_repo_config_write_fails() {
    let repo = initialized_repo();
    let before_config = load_config(path_string(repo.path())).expect("load initial config");
    let before_rows = config_rows(repo.path());
    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    connection
        .execute_batch(
            "CREATE TRIGGER fail_locale_update
             BEFORE UPDATE ON repo_config
             WHEN NEW.key = 'locale'
             BEGIN
               SELECT RAISE(ABORT, 'forced locale write failure');
             END;",
        )
        .expect("install failing config trigger");
    drop(connection);

    let mut config = before_config.clone();
    config.default_mode = StorageMode::Indexed;
    config.ai_enabled = true;
    config.locale = "en".to_owned();
    let result = update_config(path_string(repo.path()), config);

    assert_eq!(result, Err(CoreError::Db));
    let after_config = load_config(path_string(repo.path())).expect("reload config after rollback");
    assert_eq!(after_config, before_config);
    assert_eq!(config_rows(repo.path()), before_rows);
}

#[test]
fn load_update_config_update_is_repeatable_without_duplicate_rows() {
    let repo = initialized_repo();
    let mut config = load_config(path_string(repo.path())).expect("load initial config");
    config.default_mode = StorageMode::Indexed;
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    config.ai_enabled = true;
    config.locale = "en".to_owned();
    config.icloud_warn = false;

    update_config(path_string(repo.path()), config.clone()).expect("first update");
    let first_key_values = config_key_values(repo.path());
    update_config(path_string(repo.path()), config.clone()).expect("second update");

    assert_eq!(load_config(path_string(repo.path())), Ok(config));
    assert_eq!(config_key_values(repo.path()), first_key_values);
    assert_eq!(config_rows(repo.path()).len(), 6);
}

#[test]
fn load_update_config_update_preserves_existing_user_visible_files() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");

    let mut config = load_config(path_string(repo.path())).expect("load initial config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    config.locale = "en".to_owned();
    update_config(path_string(repo.path()), config).expect("persist config update");

    assert_eq!(
        fs::read_to_string(&readme_path).expect("read README"),
        "user readme\n"
    );
    assert_eq!(
        fs::read_to_string(&overview_path).expect("read AREAMATRIX"),
        "user overview\n"
    );
}

#[test]
fn load_update_config_update_requires_initialized_metadata_without_creating_it() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let config = RepoConfig {
        repo_path: path_string(repo.path()),
        default_mode: StorageMode::Copied,
        overview_output: OverviewOutput::GeneratedOnly,
        ai_enabled: false,
        locale: "zh-Hans".to_owned(),
        icloud_warn: true,
    };

    let result = update_config(path_string(repo.path()), config);

    assert_eq!(result, Err(CoreError::Config));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[cfg(unix)]
#[test]
fn load_update_config_update_returns_permission_denied_for_unwritable_database() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read database permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o444);
    fs::set_permissions(&db_path, readonly_permissions).expect("make database read-only");

    let mut config = load_config(path_string(repo.path())).expect("load initial config");
    config.locale = "en".to_owned();
    let result = update_config(path_string(repo.path()), config);

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");
    assert_eq!(result, Err(CoreError::PermissionDenied));
}

#[cfg(unix)]
#[test]
fn load_update_config_update_returns_permission_denied_for_unwritable_metadata_dir() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let before = load_config(path_string(repo.path())).expect("load initial config");
    let metadata_dir = repo.path().join(".areamatrix");
    let original_permissions = fs::metadata(&metadata_dir)
        .expect("read metadata permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o555);
    fs::set_permissions(&metadata_dir, readonly_permissions)
        .expect("make metadata directory read-only");

    let mut config = before.clone();
    config.locale = "en".to_owned();
    let result = update_config(path_string(repo.path()), config);

    fs::set_permissions(&metadata_dir, original_permissions).expect("restore metadata permissions");
    assert_eq!(result, Err(CoreError::PermissionDenied));
    assert_eq!(
        load_config(path_string(repo.path())),
        Ok(before),
        "permission failure must not change persisted config"
    );
}
