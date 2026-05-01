use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_config, update_config, CoreError, OverviewOutput, RepoConfig, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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

fn config_rows(repo: &Path) -> Vec<(String, String, i64)> {
    let connection = db_connection(repo);
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

fn db_connection(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn sqlite_integrity_check(repo: &Path) -> String {
    db_connection(repo)
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .expect("run SQLite integrity_check")
}

fn foreign_key_violations(repo: &Path) -> Vec<String> {
    let connection = db_connection(repo);
    let mut statement = connection
        .prepare("PRAGMA foreign_key_check")
        .expect("prepare foreign_key_check");
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("run foreign_key_check");

    rows.map(|row| row.expect("read foreign_key_check row"))
        .collect()
}

fn file_snapshot(paths: &[&Path]) -> Vec<(String, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path_string(path),
                fs::read(path).expect("read file snapshot bytes"),
            )
        })
        .collect()
}

fn updated_config(repo: &Path) -> RepoConfig {
    RepoConfig {
        repo_path: path_string(repo),
        default_mode: StorageMode::Indexed,
        overview_output: OverviewOutput::RootAreaMatrixFile,
        ai_enabled: true,
        locale: "en".to_owned(),
        icloud_warn: false,
    }
}

#[test]
fn load_update_config_validation_defaults_without_metadata_do_not_create_side_effects() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    let config = load_config(path_string(repo.path())).expect("load default config");

    assert_eq!(config.repo_path, path_string(repo.path()));
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(!config.ai_enabled);
    assert_eq!(config.locale, "zh-Hans");
    assert!(config.icloud_warn);
    assert!(!repo.path().join(".areamatrix").exists());
    assert!(!repo.path().join("README.md").exists());
    assert!(!repo.path().join("AREAMATRIX.md").exists());
}

#[test]
fn load_update_config_validation_success_updates_db_only_and_preserves_files() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    let classifier_path = repo.path().join(".areamatrix/classifier.yaml");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");
    let file_before = file_snapshot(&[&readme_path, &overview_path, &classifier_path]);

    let config = updated_config(repo.path());
    update_config(path_string(repo.path()), config.clone()).expect("persist config update");

    assert_eq!(load_config(path_string(repo.path())), Ok(config));
    assert_eq!(
        file_snapshot(&[&readme_path, &overview_path, &classifier_path]),
        file_before
    );
    assert_eq!(config_rows(repo.path()).len(), 6);
    assert_eq!(sqlite_integrity_check(repo.path()), "ok");
    assert!(foreign_key_violations(repo.path()).is_empty());
}

#[test]
fn load_update_config_validation_rejects_corrupt_persisted_config_value() {
    let repo = initialized_repo();
    db_connection(repo.path())
        .execute(
            "UPDATE repo_config SET value = 'invalid-mode' WHERE key = 'default_mode'",
            [],
        )
        .expect("corrupt default_mode value");

    let result = load_config(path_string(repo.path()));

    assert_eq!(result, Err(CoreError::Config));
    assert_eq!(sqlite_integrity_check(repo.path()), "ok");
}

#[test]
fn load_update_config_validation_failed_update_keeps_previous_rows_readable() {
    let repo = initialized_repo();
    let before_config = load_config(path_string(repo.path())).expect("load initial config");
    let before_rows = config_rows(repo.path());
    db_connection(repo.path())
        .execute_batch(
            "CREATE TRIGGER fail_locale_update
             BEFORE UPDATE ON repo_config
             WHEN NEW.key = 'locale'
             BEGIN
               SELECT RAISE(ABORT, 'forced locale write failure');
             END;",
        )
        .expect("install failing config trigger");

    let result = update_config(path_string(repo.path()), updated_config(repo.path()));

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(load_config(path_string(repo.path())), Ok(before_config));
    assert_eq!(config_rows(repo.path()), before_rows);
    assert_eq!(sqlite_integrity_check(repo.path()), "ok");
    assert!(foreign_key_violations(repo.path()).is_empty());
}
