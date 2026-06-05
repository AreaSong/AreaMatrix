use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_platform_capabilities, init_repo, load_config, update_config, CoreError, OverviewOutput,
    PlatformCapabilityStatus, PlatformId, RepoConfig, RepoInitMode, RepoInitOptions, StorageMode,
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

fn db_connection(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn config_key_values(repo: &Path) -> Vec<(String, String)> {
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

fn table_count(repo: &Path, table_name: &str) -> i64 {
    let sql = format!("SELECT COUNT(*) FROM {table_name}");
    db_connection(repo)
        .query_row(&sql, [], |row| row.get(0))
        .expect("read table count")
}

fn file_snapshot(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| (path.clone(), fs::read(path).expect("read file snapshot")))
        .collect()
}

fn repository_settings_config(repo: &Path) -> RepoConfig {
    let mut config = load_config(path_string(repo)).expect("load repository config");
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

#[test]
fn repository_settings_implementation_loads_defaults_and_platform_limits_without_metadata_writes() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let repo_path = path_string(repo.path());

    let config = load_config(repo_path.clone()).expect("load default config");
    let linux =
        get_platform_capabilities(PlatformId::Linux, "4.0.0-linux".to_owned()).expect("matrix");

    assert_eq!(config.repo_path, repo_path);
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert_eq!(config.locale, "zh-Hans");
    assert!(config.icloud_warn);
    assert_eq!(
        linux.cloud_placeholder.status,
        PlatformCapabilityStatus::NotAvailable
    );
    assert!(!linux.cloud_placeholder.ui_enabled);
    assert!(linux.cloud_placeholder.reason.is_some());
    assert_eq!(
        linux.security_bookmark.status,
        PlatformCapabilityStatus::NotAvailable
    );
    assert!(!linux.security_bookmark.ui_enabled);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn repository_settings_implementation_persists_repo_config_only() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    let classifier_path = repo.path().join(".areamatrix/classifier.yaml");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");
    let before_files = file_snapshot(&[
        readme_path.clone(),
        overview_path.clone(),
        classifier_path.clone(),
    ]);
    let before_table_counts = [
        table_count(repo.path(), "files"),
        table_count(repo.path(), "change_log"),
        table_count(repo.path(), "scan_sessions"),
    ];

    let config = repository_settings_config(repo.path());
    update_config(path_string(repo.path()), config.clone()).expect("persist repository settings");

    assert_eq!(load_config(path_string(repo.path())), Ok(config));
    assert_eq!(
        config_key_values(repo.path()),
        vec![
            ("ai_enabled".to_owned(), "false".to_owned()),
            ("allow_replace_during_import".to_owned(), "true".to_owned()),
            ("default_mode".to_owned(), "indexed".to_owned()),
            ("enable_extension_rules".to_owned(), "false".to_owned()),
            ("enable_keyword_rules".to_owned(), "false".to_owned()),
            ("fallback_to_inbox".to_owned(), "false".to_owned()),
            ("icloud_warn".to_owned(), "false".to_owned()),
            ("locale".to_owned(), "en".to_owned()),
            (
                "overview_output".to_owned(),
                "root_areamatrix_file".to_owned(),
            ),
            ("repo_path".to_owned(), path_string(repo.path())),
        ]
    );
    assert_eq!(
        [
            table_count(repo.path(), "files"),
            table_count(repo.path(), "change_log"),
            table_count(repo.path(), "scan_sessions"),
        ],
        before_table_counts
    );
    assert_eq!(
        file_snapshot(&[readme_path, overview_path, classifier_path]),
        before_files
    );
}

#[test]
fn repository_settings_implementation_rejects_mismatched_payload_without_partial_write() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let before_config = load_config(path_string(repo.path())).expect("load repository config");
    let before_rows = config_key_values(repo.path());
    let before_files = file_snapshot(std::slice::from_ref(&readme_path));
    let mut invalid = before_config.clone();
    invalid.repo_path = "/tmp/other-repository".to_owned();
    invalid.default_mode = StorageMode::Indexed;
    invalid.locale = "en".to_owned();

    let result = update_config(path_string(repo.path()), invalid);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(load_config(path_string(repo.path())), Ok(before_config));
    assert_eq!(config_key_values(repo.path()), before_rows);
    assert_eq!(file_snapshot(&[readme_path]), before_files);
}
