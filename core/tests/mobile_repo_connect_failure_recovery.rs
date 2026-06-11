use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, load_config, validate_repo_path, CoreError, ErrorKind, ErrorRecoverability,
    OverviewOutput, RepoInitMode, RepoInitOptions, RepoPathIssue, StorageMode,
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

fn adopt_existing_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::AdoptExisting,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn snapshot_files(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path.clone(),
                fs::read(path).expect("read user file snapshot"),
            )
        })
        .collect()
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn repo_config_values(repo: &Path) -> Vec<(String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT key, value FROM repo_config ORDER BY key")
        .expect("prepare repo_config query");
    statement
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .expect("query repo_config rows")
        .map(|row| row.expect("read repo_config row"))
        .collect()
}

fn assert_error_kind(error: CoreError, expected: ErrorKind) -> CoreError {
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, expected);
    assert!(!mapping.user_message.is_empty());
    assert!(!mapping.suggested_action.is_empty());
    error
}

#[test]
fn mobile_repo_connect_failure_empty_states_are_read_only_until_confirmed() {
    let repo = tempfile::tempdir().expect("create empty mobile repository directory");
    let missing_path = repo.path().join("missing");

    let empty_validation =
        validate_repo_path(path_string(repo.path())).expect("validate empty mobile path");
    let missing_validation =
        validate_repo_path(path_string(&missing_path)).expect("validate missing mobile path");
    let default_config =
        load_config(path_string(repo.path())).expect("load default config before init");

    assert_eq!(
        empty_validation.recommended_mode,
        Some(RepoInitMode::CreateEmpty)
    );
    assert_eq!(empty_validation.issues, Vec::<RepoPathIssue>::new());
    assert_eq!(missing_validation.issues, vec![RepoPathIssue::MissingPath]);
    assert_eq!(missing_validation.recommended_mode, None);
    assert_eq!(default_config.repo_path, path_string(repo.path()));
    assert_eq!(default_config.default_mode, StorageMode::Copied);
    assert!(!default_config.ai_enabled);
    assert!(!repo.path().join(".areamatrix").exists());
    assert!(!missing_path.exists());
}

#[test]
fn mobile_repo_connect_failure_invalid_inputs_do_not_create_metadata() {
    let repo = tempfile::tempdir().expect("create mobile repository directory");
    let internal_path = repo.path().join(".areamatrix").join("staging");
    let placeholder_path = repo.path().join("Document.pdf.icloud");

    let empty_error = validate_repo_path(String::new()).expect_err("empty path is invalid");
    let internal_error = init_repo(path_string(&internal_path), create_empty_options())
        .expect_err("reject internals");
    let placeholder_error =
        validate_repo_path(path_string(&placeholder_path)).expect_err("reject placeholder");

    assert_error_kind(empty_error, ErrorKind::InvalidPath);
    assert_error_kind(internal_error, ErrorKind::InvalidPath);
    let placeholder_error = assert_error_kind(placeholder_error, ErrorKind::ICloudPlaceholder);
    assert_eq!(
        placeholder_error.to_error_mapping().recoverability,
        ErrorRecoverability::Retryable
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn mobile_repo_connect_failure_rejects_unconfirmed_modes_without_touching_user_files() {
    let repo = tempfile::tempdir().expect("create non-empty mobile repository directory");
    let readme = repo.path().join("README.md");
    let notes = repo.path().join("notes.txt");
    fs::write(&readme, b"user readme").expect("write user README");
    fs::write(&notes, b"user notes").expect("write user notes");
    let before = snapshot_files(&[readme.clone(), notes.clone()]);

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate non-empty mobile path");
    let create_result = init_repo(path_string(repo.path()), create_empty_options());
    let mut invalid_adopt = adopt_existing_options();
    invalid_adopt.create_default_categories = true;
    let invalid_adopt_result = init_repo(path_string(repo.path()), invalid_adopt);

    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert!(matches!(create_result, Err(CoreError::Config { .. })));
    assert!(matches!(
        invalid_adopt_result,
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot_files(&[readme, notes]), before);
    assert!(!repo.path().join(".areamatrix").exists());
    assert!(!repo.path().join("README.md").is_dir());
}

#[cfg(unix)]
#[test]
fn mobile_repo_connect_failure_permission_denied_keeps_retryable_user_state() {
    use std::os::unix::fs::PermissionsExt;

    let repo = tempfile::tempdir().expect("create readonly mobile repository directory");
    let user_file = repo.path().join("README.md");
    fs::write(&user_file, b"mobile user content").expect("write user file");
    let before = snapshot_files(std::slice::from_ref(&user_file));

    let original_permissions = fs::metadata(repo.path())
        .expect("read repository permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o555);
    fs::set_permissions(repo.path(), readonly_permissions).expect("make repo readonly");

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate readonly mobile path");
    let result = init_repo(path_string(repo.path()), adopt_existing_options());

    fs::set_permissions(repo.path(), original_permissions).expect("restore repo permissions");

    let error = result.expect_err("readonly adopt should fail");
    assert_error_kind(error, ErrorKind::PermissionDenied);
    assert_eq!(validation.recommended_mode, None);
    assert!(validation.issues.contains(&RepoPathIssue::NotWritable));
    assert_eq!(snapshot_files(std::slice::from_ref(&user_file)), before);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[cfg(unix)]
#[test]
fn mobile_repo_connect_failure_maps_io_errors_without_side_effects() {
    use std::os::unix::fs::symlink;

    let repo = tempfile::tempdir().expect("create mobile repository directory");
    let loop_path = repo.path().join("loop");
    symlink(&loop_path, &loop_path).expect("create symlink loop");

    let error = validate_repo_path(path_string(&loop_path)).expect_err("symlink loop is IO");

    assert_error_kind(error, ErrorKind::Io);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn mobile_repo_connect_failure_maps_db_errors_without_metadata_repair_side_effects() {
    let repo = tempfile::tempdir().expect("create mobile repository directory");
    let user_file = repo.path().join("README.md");
    let metadata_dir = repo.path().join(".areamatrix");
    fs::write(&user_file, b"user file").expect("write user file");
    fs::create_dir(&metadata_dir).expect("create metadata directory");
    fs::write(metadata_dir.join("index.db"), b"not a sqlite database")
        .expect("write corrupted database");
    let before = snapshot_files(std::slice::from_ref(&user_file));

    let validation_error =
        validate_repo_path(path_string(repo.path())).expect_err("corrupted scan DB fails");
    let load_error = load_config(path_string(repo.path())).expect_err("corrupted config DB fails");

    assert_error_kind(validation_error, ErrorKind::Db);
    let load_error = assert_error_kind(load_error, ErrorKind::Db);
    assert_eq!(
        load_error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(snapshot_files(std::slice::from_ref(&user_file)), before);
    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert!(!repo.path().join(".areamatrix/generated/root.md").exists());
}

#[test]
fn mobile_repo_connect_failure_load_config_io_error_is_read_only() {
    let repo = tempfile::tempdir().expect("create mobile repository directory");
    let metadata_path = repo.path().join(".areamatrix");
    fs::write(&metadata_path, b"not a metadata directory").expect("write metadata file");

    let error = load_config(path_string(repo.path())).expect_err("metadata file blocks DB path");

    assert_error_kind(error, ErrorKind::Io);
    assert_eq!(
        fs::read(&metadata_path).expect("read metadata file after failed load"),
        b"not a metadata directory"
    );
    assert!(!repo.path().join(".areamatrix.init-retry").exists());
}

#[test]
fn mobile_repo_connect_failure_keeps_ai_and_remote_calls_disabled_by_default() {
    let repo = tempfile::tempdir().expect("create mobile repository directory");

    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize mobile repo");

    let config = load_config(path_string(repo.path())).expect("load mobile repo config");
    let config_values = repo_config_values(repo.path());
    let serialized_config = format!("{config_values:?}");

    assert!(!config.ai_enabled);
    assert!(config_values.contains(&("ai_enabled".to_owned(), "false".to_owned())));
    for sensitive_marker in ["api_key", "secret", "token", "sk-"] {
        assert!(!serialized_config.contains(sensitive_marker));
    }
    assert!(!repo.path().join(".areamatrix/ai_call_log").exists());
}
