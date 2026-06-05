use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, load_config, map_core_error, update_config, CoreError, ErrorKind, ErrorMappingInput,
    ErrorRecoverability, ErrorSeverity, OverviewOutput, RepoConfig, RepoInitMode, RepoInitOptions,
    StorageMode,
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

fn file_snapshot(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| (path.clone(), fs::read(path).expect("read file snapshot")))
        .collect()
}

fn directory_entry_count(path: &Path) -> usize {
    fs::read_dir(path).map_or(0, Iterator::count)
}

fn assert_no_ai_remote_secret_side_effects(repo: &Path) {
    for path in [
        repo.join(".areamatrix/ai"),
        repo.join(".areamatrix/remote"),
        repo.join(".areamatrix/secrets"),
        repo.join(".areamatrix/ai_call_log"),
        repo.join(".areamatrix/generated/ai_config.json"),
    ] {
        assert!(
            !path.exists(),
            "repository settings must not create {}",
            path.display()
        );
    }

    if repo.join(".areamatrix/index.db").exists() {
        let combined = config_rows(repo)
            .into_iter()
            .map(|(key, value)| format!("{key}={value}"))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(!combined.contains("sk-"));
        assert!(!combined.contains("api_key"));
    }
}

fn new_repo_config(repo_path: String) -> RepoConfig {
    RepoConfig {
        repo_path,
        default_mode: StorageMode::Copied,
        overview_output: OverviewOutput::GeneratedOnly,
        ai_enabled: false,
        locale: "zh-Hans".to_owned(),
        icloud_warn: true,
        enable_extension_rules: true,
        enable_keyword_rules: true,
        fallback_to_inbox: true,
        allow_replace_during_import: false,
    }
}

fn changed_repo_config(mut config: RepoConfig) -> RepoConfig {
    config.default_mode = StorageMode::Indexed;
    config.locale = "en".to_owned();
    config.icloud_warn = false;
    config.allow_replace_during_import = true;
    config
}

fn assert_error_kind(error: CoreError, expected: ErrorKind) {
    assert_eq!(error.kind(), expected);
    assert_eq!(error.to_error_mapping().kind, expected);
}

#[test]
fn repository_settings_failure_empty_state_is_read_only_and_default_off() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");

    let config = load_config(path_string(repo.path())).expect("load default repository config");

    assert_eq!(config.repo_path, path_string(repo.path()));
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(!config.ai_enabled);
    assert!(!config.allow_replace_during_import);
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read user README"),
        "user readme\n"
    );
    assert!(!repo.path().join(".areamatrix").exists());
    assert_no_ai_remote_secret_side_effects(repo.path());
}

#[test]
fn repository_settings_failure_invalid_inputs_return_config_without_mutation() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let before_config = load_config(path_string(repo.path())).expect("load baseline config");
    let before_rows = config_rows(repo.path());
    let before_files = file_snapshot(&[readme_path.clone()]);

    let mut mismatched = before_config.clone();
    mismatched.repo_path = "/tmp/other-repository".to_owned();
    mismatched.locale = "en".to_owned();
    let mismatch_error = update_config(path_string(repo.path()), mismatched)
        .expect_err("mismatched payload must fail");

    let mut blank_locale = before_config.clone();
    blank_locale.locale = "  ".to_owned();
    let blank_error =
        update_config(path_string(repo.path()), blank_locale).expect_err("blank locale must fail");

    let empty_path_error =
        update_config(String::new(), before_config.clone()).expect_err("empty path must fail");

    for error in [mismatch_error, blank_error, empty_path_error] {
        assert_error_kind(error, ErrorKind::Config);
    }
    assert_eq!(load_config(path_string(repo.path())), Ok(before_config));
    assert_eq!(config_rows(repo.path()), before_rows);
    assert_eq!(file_snapshot(&[readme_path]), before_files);
}

#[test]
fn repository_settings_failure_corrupt_persisted_values_do_not_silently_default() {
    let repo = initialized_repo();
    db_connection(repo.path())
        .execute(
            "UPDATE repo_config SET value = 'teleport' WHERE key = 'default_mode'",
            [],
        )
        .expect("corrupt persisted default mode");

    let error = load_config(path_string(repo.path()))
        .expect_err("invalid persisted config must be explicit");

    assert_error_kind(error, ErrorKind::Config);
}

#[cfg(unix)]
#[test]
fn repository_settings_failure_permission_denied_is_structured_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let before_config = load_config(path_string(repo.path())).expect("load baseline config");
    let before_rows = config_rows(repo.path());
    let before_files = file_snapshot(&[readme_path.clone()]);

    let metadata_dir = repo.path().join(".areamatrix");
    let original_permissions = fs::metadata(&metadata_dir)
        .expect("read metadata permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o555);
    fs::set_permissions(&metadata_dir, blocked_permissions).expect("make metadata read-only");
    let result = update_config(
        path_string(repo.path()),
        changed_repo_config(before_config.clone()),
    );
    fs::set_permissions(&metadata_dir, original_permissions).expect("restore metadata permissions");

    let error = result.expect_err("read-only metadata must reject settings update");
    assert_eq!(error.kind(), ErrorKind::PermissionDenied);
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, ErrorKind::PermissionDenied);
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(load_config(path_string(repo.path())), Ok(before_config));
    assert_eq!(config_rows(repo.path()), before_rows);
    assert_eq!(file_snapshot(&[readme_path]), before_files);
}

#[test]
fn repository_settings_failure_io_error_preserves_user_files_and_metadata_shape() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let repo_path = path_string(repo.path());
    let readme_path = repo.path().join("README.md");
    let metadata_path = repo.path().join(".areamatrix");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&metadata_path, "metadata path is not a directory\n")
        .expect("write malformed metadata path");

    let load_error =
        load_config(repo_path.clone()).expect_err("malformed metadata path must fail load");
    let update_error = update_config(repo_path.clone(), new_repo_config(repo_path))
        .expect_err("malformed metadata path must fail update");

    for error in [load_error, update_error] {
        assert_error_kind(error, ErrorKind::Io);
    }
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read user README"),
        "user readme\n"
    );
    assert_eq!(
        fs::read_to_string(&metadata_path).expect("read malformed metadata path"),
        "metadata path is not a directory\n"
    );
    assert!(!repo.path().join(".areamatrix/staging").exists());
    assert!(!repo.path().join(".areamatrix/generated").exists());
}

#[test]
fn repository_settings_failure_db_error_rolls_back_partial_config_updates() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let before_config = load_config(path_string(repo.path())).expect("load baseline config");
    let before_rows = config_rows(repo.path());
    let before_files = file_snapshot(&[readme_path.clone()]);
    let before_table_counts = [
        table_count(repo.path(), "files"),
        table_count(repo.path(), "change_log"),
        table_count(repo.path(), "scan_sessions"),
    ];

    db_connection(repo.path())
        .execute_batch(
            "CREATE TRIGGER block_repository_settings_locale_update
             BEFORE UPDATE OF value ON repo_config
             WHEN NEW.key = 'locale'
             BEGIN
                 SELECT RAISE(FAIL, 'blocked repository settings locale update');
             END;",
        )
        .expect("install db failure trigger");

    let error = update_config(
        path_string(repo.path()),
        changed_repo_config(before_config.clone()),
    )
    .expect_err("triggered DB error must fail settings update");

    assert_eq!(error.kind(), ErrorKind::Db);
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    assert_eq!(load_config(path_string(repo.path())), Ok(before_config));
    assert_eq!(config_rows(repo.path()), before_rows);
    assert_eq!(file_snapshot(&[readme_path]), before_files);
    assert_eq!(
        [
            table_count(repo.path(), "files"),
            table_count(repo.path(), "change_log"),
            table_count(repo.path(), "scan_sessions"),
        ],
        before_table_counts
    );
    assert_eq!(
        directory_entry_count(&repo.path().join(".areamatrix/staging")),
        0
    );
}

#[test]
fn repository_settings_failure_corrupted_db_preserves_user_files_and_maps_fatal() {
    let repo = tempfile::tempdir().expect("create corrupted repository directory");
    let user_file = repo.path().join("docs/client.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create docs dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");
    let metadata_dir = repo.path().join(".areamatrix");
    fs::create_dir(&metadata_dir).expect("create metadata directory");
    fs::create_dir(metadata_dir.join("staging")).expect("create staging directory");
    fs::write(metadata_dir.join("index.db"), b"not a sqlite database")
        .expect("write corrupted database fixture");

    let load_error =
        load_config(path_string(repo.path())).expect_err("corrupted db must fail load");
    let update_error = update_config(
        path_string(repo.path()),
        new_repo_config(path_string(repo.path())),
    )
    .expect_err("corrupted db must fail update");

    for error in [load_error, update_error] {
        assert_eq!(error.kind(), ErrorKind::Db);
        let mapping = error.to_error_mapping();
        assert_eq!(mapping.kind, ErrorKind::Db);
        assert_eq!(mapping.recoverability, ErrorRecoverability::Fatal);
    }
    assert_eq!(
        fs::read(&user_file).expect("read user file"),
        b"user file bytes"
    );
    assert_eq!(
        directory_entry_count(&repo.path().join(".areamatrix/staging")),
        0
    );
}

#[test]
fn repository_settings_failure_error_mapping_covers_documented_kinds() {
    let cases = [
        (
            ErrorMappingInput {
                kind: ErrorKind::Config,
                path: None,
                reason: Some("repository settings payload is invalid".to_owned()),
                message: None,
            },
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::PermissionDenied,
                path: Some("/repo/.areamatrix".to_owned()),
                reason: None,
                message: None,
            },
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Io,
                path: None,
                reason: None,
                message: Some("metadata inspection failed".to_owned()),
            },
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Db,
                path: None,
                reason: None,
                message: Some("SQLITE_BUSY: database is locked".to_owned()),
            },
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Db,
                path: None,
                reason: None,
                message: Some("database disk image is malformed".to_owned()),
            },
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
        ),
    ];

    for (input, severity, recoverability) in cases {
        let mapping = map_core_error(input);
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
        assert!(!mapping.user_message.is_empty());
        assert!(!mapping.suggested_action.is_empty());
    }
}

#[test]
fn repository_settings_failure_ai_remote_defaults_do_not_create_secret_state() {
    let repo = initialized_repo();
    let mut config = load_config(path_string(repo.path())).expect("load baseline config");
    assert!(!config.ai_enabled);
    assert_no_ai_remote_secret_side_effects(repo.path());

    config.ai_enabled = true;
    update_config(path_string(repo.path()), config).expect("persist local AI toggle only");

    assert_no_ai_remote_secret_side_effects(repo.path());
}
