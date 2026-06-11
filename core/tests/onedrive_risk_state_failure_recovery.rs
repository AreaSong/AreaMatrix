use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    acknowledge_onedrive_risk_notice, detect_cloud_storage_state, init_repo,
    CloudStorageProviderKind, CoreError, ErrorKind, ErrorRecoverability, ErrorSeverity,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};

const ACK_KEY: &str = "onedrive_risk_notice_acknowledged";

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_onedrive_repo(root: &Path) -> PathBuf {
    let repo = root
        .join("Users")
        .join("me")
        .join("OneDrive - Example Org")
        .join("AreaMatrix");
    fs::create_dir_all(&repo).expect("create OneDrive-shaped repository path");
    repo
}

fn init_empty_repo(repo: &Path) {
    init_repo(
        path_string(repo),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository metadata");
}

fn repo_db_path(repo: &Path) -> PathBuf {
    repo.join(".areamatrix").join("index.db")
}

fn repo_config_rows(repo: &Path) -> Vec<(String, String)> {
    let connection = Connection::open(repo_db_path(repo)).expect("open repository database");
    let mut statement = connection
        .prepare("SELECT key, value FROM repo_config ORDER BY key")
        .expect("prepare repo_config rows query");
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .expect("query repo_config rows");
    rows.map(|row| row.expect("read repo_config row")).collect()
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    let connection = Connection::open(repo_db_path(repo)).expect("open repository database");
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [key],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .expect("query repo_config value")
}

fn directory_entries(path: &Path) -> Vec<String> {
    if !path.exists() {
        return Vec::new();
    }

    let mut entries = fs::read_dir(path)
        .expect("read directory entries")
        .map(|entry| {
            entry
                .expect("read directory entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect::<Vec<_>>();
    entries.sort();
    entries
}

fn assert_error_kind(error: CoreError, expected: ErrorKind) -> CoreError {
    assert_eq!(error.kind(), expected);
    assert_eq!(error.to_error_mapping().kind, expected);
    error
}

fn assert_user_file_preserved(path: &Path, before: &[u8]) {
    assert_eq!(fs::read(path).expect("read preserved user file"), before);
}

fn assert_no_secret_material(value: &str) {
    for fragment in ["api_key", "sk-secret", "token=", "Bearer "] {
        assert!(
            !value.contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
}

#[test]
fn onedrive_risk_failure_invalid_inputs_and_io_errors_are_explicit() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    let user_file = repo.join("secret.txt");
    let not_directory = repo.join("not-a-directory.txt");
    fs::write(&user_file, b"api_key=sk-secret").expect("write user file");
    fs::write(&not_directory, b"not a repository").expect("write file path");
    let before_user_file = fs::read(&user_file).expect("read user file before failures");
    let before_file_path = fs::read(&not_directory).expect("read file path before failures");

    let empty = detect_cloud_storage_state(String::new()).expect_err("empty path is invalid");
    let metadata_path = detect_cloud_storage_state(path_string(&repo.join(".areamatrix")))
        .expect_err("metadata-internal path is invalid");
    let io_error = detect_cloud_storage_state(path_string(&not_directory))
        .expect_err("file path is not a valid cloud-state repository directory");

    assert!(matches!(
        assert_error_kind(empty, ErrorKind::InvalidPath),
        CoreError::InvalidPath { path } if path.contains("required")
    ));
    assert!(matches!(
        assert_error_kind(metadata_path, ErrorKind::InvalidPath),
        CoreError::InvalidPath { path } if path.contains("repository root")
    ));
    let io_error = assert_error_kind(io_error, ErrorKind::Io);
    assert!(matches!(
        &io_error,
        CoreError::Io { message } if message.contains("not a directory")
    ));
    assert_no_secret_material(io_error.raw_context());
    assert_user_file_preserved(&user_file, &before_user_file);
    assert_user_file_preserved(&not_directory, &before_file_path);
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn onedrive_risk_failure_status_messages_do_not_expose_user_file_secrets() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    let user_file = repo.join("secret.txt");
    fs::write(&user_file, b"api_key=sk-secret").expect("write user file");
    let before_user_file = fs::read(&user_file).expect("read user file before probe");

    let state = detect_cloud_storage_state(path_string(&repo))
        .expect("detect OneDrive state without reading user file content");

    assert_eq!(state.provider_kind, CloudStorageProviderKind::OneDrive);
    assert_no_secret_material(&state.status_summary);
    for reason in &state.risk_reasons {
        assert_no_secret_material(reason);
    }
    assert_user_file_preserved(&user_file, &before_user_file);
    assert!(!repo.join(".areamatrix").exists());
}

#[cfg(unix)]
#[test]
fn onedrive_risk_failure_permission_denied_maps_to_user_action_without_mutation() {
    use std::os::unix::fs::PermissionsExt;

    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    let user_file = repo.join("README.md");
    fs::write(&user_file, b"permission protected readme").expect("write user file");
    let before_user_file = fs::read(&user_file).expect("read user file before permission change");
    let original_permissions = fs::metadata(&repo)
        .expect("read repo permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&repo, blocked_permissions).expect("remove repository permissions");

    let result = detect_cloud_storage_state(path_string(&repo));

    fs::set_permissions(&repo, original_permissions).expect("restore repository permissions");
    let error = assert_error_kind(
        result.expect_err("blocked directory listing must fail"),
        ErrorKind::PermissionDenied,
    );
    let mapping = error.to_error_mapping();

    assert!(matches!(
        error,
        CoreError::PermissionDenied { path } if path == path_string(&repo)
    ));
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_user_file_preserved(&user_file, &before_user_file);
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn onedrive_risk_failure_detect_db_schema_error_is_reported_without_repair() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    init_empty_repo(&repo);
    let user_file = repo.join("README.md");
    fs::write(&user_file, b"user readme").expect("write user file after init");
    Connection::open(repo_db_path(&repo))
        .expect("open repository database")
        .execute("DROP TABLE repo_config", [])
        .expect("drop repo_config table for DB failure test");
    let before_user_file = fs::read(&user_file).expect("read user file before detect");
    let before_db = fs::read(repo_db_path(&repo)).expect("read DB before detect");
    let generated_dir = repo.join(".areamatrix").join("generated");
    let staging_dir = repo.join(".areamatrix").join("staging");
    let before_generated_entries = directory_entries(&generated_dir);
    let before_staging_entries = directory_entries(&staging_dir);

    let error = detect_cloud_storage_state(path_string(&repo))
        .expect_err("missing repo_config table must fail explicitly");
    let error = assert_error_kind(error, ErrorKind::Io);

    assert!(matches!(
        error,
        CoreError::Io { message } if message.contains("repo_config")
            || message.contains("metadata is unavailable")
    ));
    assert_user_file_preserved(&user_file, &before_user_file);
    assert_eq!(
        fs::read(repo_db_path(&repo)).expect("read DB after failed detect"),
        before_db
    );
    assert_eq!(directory_entries(&generated_dir), before_generated_entries);
    assert_eq!(directory_entries(&staging_dir), before_staging_entries);
}

#[test]
fn onedrive_risk_failure_invalid_ack_value_is_not_silently_downgraded() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    init_empty_repo(&repo);
    let user_file = repo.join("notes.txt");
    fs::write(&user_file, b"user notes").expect("write user file after init");
    Connection::open(repo_db_path(&repo))
        .expect("open repository database")
        .execute(
            "INSERT INTO repo_config (key, value, updated_at) VALUES (?1, 'unexpected', 1)",
            [ACK_KEY],
        )
        .expect("insert invalid acknowledgement metadata");
    let before_rows = repo_config_rows(&repo);
    let before_user_file = fs::read(&user_file).expect("read user file before detect");

    let error = detect_cloud_storage_state(path_string(&repo))
        .expect_err("invalid acknowledgement metadata must not be treated as false");
    let error = assert_error_kind(error, ErrorKind::Io);

    assert!(matches!(
        error,
        CoreError::Io { message } if message.contains("metadata is invalid")
    ));
    assert_eq!(repo_config_rows(&repo), before_rows);
    assert_user_file_preserved(&user_file, &before_user_file);
}

#[test]
fn onedrive_risk_failure_acknowledge_write_error_leaves_no_half_metadata() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    init_empty_repo(&repo);
    let user_file = repo.join("README.md");
    fs::write(&user_file, b"user readme").expect("write user file after init");
    Connection::open(repo_db_path(&repo))
        .expect("open repository database")
        .execute(
            "CREATE TRIGGER block_onedrive_ack_insert \
             BEFORE INSERT ON repo_config \
             WHEN NEW.key = 'onedrive_risk_notice_acknowledged' \
             BEGIN \
                 SELECT RAISE(ABORT, 'onedrive acknowledgement write blocked'); \
             END",
            [],
        )
        .expect("install acknowledgement insert failure trigger");
    let before_rows = repo_config_rows(&repo);
    let before_user_file = fs::read(&user_file).expect("read user file before failed ack");
    let staging_dir = repo.join(".areamatrix").join("staging");
    let before_staging_entries = directory_entries(&staging_dir);

    let error = acknowledge_onedrive_risk_notice(path_string(&repo))
        .expect_err("acknowledgement DB write failure must be returned");
    let error = assert_error_kind(error, ErrorKind::Io);

    assert!(matches!(
        error,
        CoreError::Io { message } if message.contains("metadata is unavailable")
            || message.contains("write blocked")
    ));
    assert_eq!(repo_config_rows(&repo), before_rows);
    assert_eq!(repo_config_value(&repo, ACK_KEY), None);
    assert_user_file_preserved(&user_file, &before_user_file);
    assert_eq!(directory_entries(&staging_dir), before_staging_entries);
    assert!(!repo.join("AREAMATRIX.md").exists());
}
