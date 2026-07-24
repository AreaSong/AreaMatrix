use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_repo_config, update_repo_config, CoreError, CoreResult, OverviewOutput,
    RepoConfigPatch, RepoConfigSnapshot, RepoInitMode, RepoInitOptions, RepositoryLocalePolicy,
    RepositoryLocalePolicyState, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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
        locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
        content_locale: area_matrix_core::ContentLocale::En,
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

fn settings_patch(expected_revision: i64) -> RepoConfigPatch {
    RepoConfigPatch {
        expected_revision,
        default_mode: Some(StorageMode::Indexed),
        overview_output: Some(OverviewOutput::RootAreaMatrixFile),
        ai_enabled: Some(true),
        locale_policy: Some(RepositoryLocalePolicy::En),
        icloud_warn: Some(false),
        enable_extension_rules: Some(false),
        enable_keyword_rules: Some(false),
        fallback_to_inbox: Some(false),
        allow_replace_during_import: Some(true),
    }
}

#[test]
fn load_update_config_contract_exports_callable_signatures() {
    fn assert_load(_: fn(String) -> CoreResult<RepoConfigSnapshot>) {}
    fn assert_update(_: fn(String, RepoConfigPatch) -> CoreResult<RepoConfigSnapshot>) {}

    assert_load(load_repo_config);
    assert_update(update_repo_config);
}

#[test]
fn load_update_config_contract_docs_udl_and_control_map_stay_aligned() {
    for fragment in [
        "RepoConfigSnapshot load_repo_config(string repo_path);",
        "RepoConfigSnapshot update_repo_config(string repo_path, RepoConfigPatch patch);",
        "dictionary RepoConfigSnapshot",
        "dictionary RepoConfigPatch",
        "i64 revision;",
        "i64 expected_revision;",
        "StorageMode default_mode;",
        "OverviewOutput overview_output;",
        "boolean ai_enabled;",
        "RepositoryLocalePolicySnapshot locale_policy;",
        "boolean icloud_warn;",
        "boolean enable_extension_rules;",
        "boolean enable_keyword_rules;",
        "boolean fallback_to_inbox;",
        "boolean allow_replace_during_import;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum OverviewOutput { \"GeneratedOnly\", \"RootAreaMatrixFile\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for core_api_fragment in [
        "| `load_repo_config(repo)` | repo | √ | Config / PermissionDenied / Io / Db |",
        "| `update_repo_config(repo, patch)` | repo | √ | Config / Conflict / PermissionDenied / Io / Db |",
        "通过 SQLite immediate transaction 比较 `expected_revision`",
        "stale revision 返回 `Conflict`",
    ] {
        assert_contains(CORE_API, core_api_fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io", "Db"] {
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

#[test]
fn load_update_config_loads_defaults_when_metadata_is_missing() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    let config = load_repo_config(path_string(repo.path())).expect("load default config");

    assert_eq!(config.repo_path, path_string(repo.path()));
    assert_eq!(config.revision, 0);
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(!config.ai_enabled);
    assert_eq!(config.locale_policy.raw_value, "system");
    assert_eq!(
        config.locale_policy.state,
        RepositoryLocalePolicyState::FollowInterface
    );
    assert!(config.icloud_warn);
    assert!(config.enable_extension_rules);
    assert!(config.enable_keyword_rules);
    assert!(config.fallback_to_inbox);
    assert!(!config.allow_replace_during_import);
}

#[test]
fn initialized_legacy_repo_without_locale_remains_unknown_until_explicit_save() {
    let repo = initialized_repo();
    let db_path = repo.path().join(".areamatrix/index.db");
    let connection = Connection::open(&db_path).expect("open repository database");
    connection
        .execute("DELETE FROM repo_config WHERE key = 'locale'", [])
        .expect("remove legacy locale row");
    drop(connection);

    let unknown = load_repo_config(path_string(repo.path())).expect("load legacy config");
    assert_eq!(unknown.locale_policy.raw_value, "");
    assert_eq!(
        unknown.locale_policy.state,
        RepositoryLocalePolicyState::Unknown
    );

    let blocked = area_matrix_core::prepare_overview_regeneration(
        path_string(repo.path()),
        area_matrix_core::ContentLocale::En,
    );
    assert!(matches!(blocked, Err(CoreError::Config { .. })));

    let saved = update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: unknown.revision,
            locale_policy: Some(RepositoryLocalePolicy::FollowInterface),
            ..RepoConfigPatch::default()
        },
    )
    .expect("save explicit repository locale");
    assert_eq!(saved.locale_policy.raw_value, "system");
    assert_eq!(
        saved.locale_policy.state,
        RepositoryLocalePolicyState::FollowInterface
    );
}

#[test]
fn load_update_config_rejects_empty_repo_path_as_config_error() {
    assert!(matches!(
        load_repo_config(String::new()),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        update_repo_config(String::new(), settings_patch(1)),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn load_update_config_update_persists_all_repo_config_fields() {
    let repo = initialized_repo();
    let initial = load_repo_config(path_string(repo.path())).expect("load initial config");
    let updated = update_repo_config(path_string(repo.path()), settings_patch(initial.revision))
        .expect("persist config update");

    let reloaded = load_repo_config(path_string(repo.path())).expect("reload updated config");
    assert_eq!(reloaded, updated);
    assert_eq!(updated.revision, initial.revision + 1);
    assert_eq!(updated.default_mode, StorageMode::Indexed);
    assert_eq!(updated.overview_output, OverviewOutput::RootAreaMatrixFile);
    assert!(updated.ai_enabled);
    assert_eq!(updated.locale_policy.raw_value, "en");
    assert!(!updated.icloud_warn);
    assert!(!updated.enable_extension_rules);
    assert!(!updated.enable_keyword_rules);
    assert!(!updated.fallback_to_inbox);
    assert!(updated.allow_replace_during_import);
    assert_eq!(config_rows(repo.path()).len(), 10);
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

    let initial = load_repo_config(path_string(repo.path())).expect("load initial config");
    update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: initial.revision,
            locale_policy: Some(RepositoryLocalePolicy::En),
            ..RepoConfigPatch::default()
        },
    )
    .expect("persist config update");

    for (key, _, updated_at) in config_rows(repo.path()) {
        if key == "locale" {
            assert!(updated_at > 1, "locale should have a fresh updated_at");
        } else {
            assert_eq!(updated_at, 1, "{key} should remain untouched");
        }
    }
}

#[test]
fn load_update_config_update_rejects_stale_revision_without_changing_previous_config() {
    let repo = initialized_repo();
    let before = load_repo_config(path_string(repo.path())).expect("load initial config");

    let result = update_repo_config(
        path_string(repo.path()),
        settings_patch(before.revision + 1),
    );

    assert!(
        matches!(result, Err(CoreError::RevisionConflict { .. })),
        "unexpected stale-save result: {result:?}"
    );

    let after =
        load_repo_config(path_string(repo.path())).expect("reload config after failed update");
    assert_eq!(after, before);
}

#[test]
fn load_update_config_empty_patch_is_read_only() {
    let repo = initialized_repo();
    let before = load_repo_config(path_string(repo.path())).expect("load initial config");
    let rows_before = config_rows(repo.path());

    let result = update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: before.revision,
            ..RepoConfigPatch::default()
        },
    )
    .expect("apply empty patch");

    assert_eq!(result, before);
    assert_eq!(config_rows(repo.path()), rows_before);
}

#[test]
fn load_update_config_update_rolls_back_when_late_repo_config_write_fails() {
    let repo = initialized_repo();
    let before_config = load_repo_config(path_string(repo.path())).expect("load initial config");
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

    let result = update_repo_config(
        path_string(repo.path()),
        settings_patch(before_config.revision),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    let after_config =
        load_repo_config(path_string(repo.path())).expect("reload config after rollback");
    assert_eq!(after_config, before_config);
    assert_eq!(config_rows(repo.path()), before_rows);
}

#[test]
fn load_update_config_update_is_repeatable_without_duplicate_rows() {
    let repo = initialized_repo();
    let initial = load_repo_config(path_string(repo.path())).expect("load initial config");
    let first = update_repo_config(path_string(repo.path()), settings_patch(initial.revision))
        .expect("first update");
    let first_key_values = config_key_values(repo.path());
    let second = update_repo_config(path_string(repo.path()), settings_patch(first.revision))
        .expect("second update");

    assert_eq!(
        load_repo_config(path_string(repo.path())),
        Ok(second.clone())
    );
    assert_eq!(second.revision, first.revision + 1);
    assert_eq!(config_key_values(repo.path()), first_key_values);
    assert_eq!(config_rows(repo.path()).len(), 10);
}

#[test]
fn load_update_config_update_preserves_existing_user_visible_files() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");

    let initial = load_repo_config(path_string(repo.path())).expect("load initial config");
    update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: initial.revision,
            overview_output: Some(OverviewOutput::RootAreaMatrixFile),
            locale_policy: Some(RepositoryLocalePolicy::En),
            ..RepoConfigPatch::default()
        },
    )
    .expect("persist config update");

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
    let result = update_repo_config(path_string(repo.path()), settings_patch(1));

    assert!(
        matches!(result, Err(CoreError::RepoNotInitialized { .. })),
        "unexpected uninitialized update result: {result:?}"
    );

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

    let initial = load_repo_config(path_string(repo.path())).expect("load initial config");
    let result = update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: initial.revision,
            locale_policy: Some(RepositoryLocalePolicy::En),
            ..RepoConfigPatch::default()
        },
    );

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");
    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
}

#[cfg(unix)]
#[test]
fn load_update_config_update_returns_permission_denied_for_unwritable_metadata_dir() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let before = load_repo_config(path_string(repo.path())).expect("load initial config");
    let metadata_dir = repo.path().join(".areamatrix");
    let original_permissions = fs::metadata(&metadata_dir)
        .expect("read metadata permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o555);
    fs::set_permissions(&metadata_dir, readonly_permissions)
        .expect("make metadata directory read-only");

    let result = update_repo_config(
        path_string(repo.path()),
        RepoConfigPatch {
            expected_revision: before.revision,
            locale_policy: Some(RepositoryLocalePolicy::En),
            ..RepoConfigPatch::default()
        },
    );

    fs::set_permissions(&metadata_dir, original_permissions).expect("restore metadata permissions");
    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(
        load_repo_config(path_string(repo.path())),
        Ok(before),
        "permission failure must not change persisted config"
    );
}
