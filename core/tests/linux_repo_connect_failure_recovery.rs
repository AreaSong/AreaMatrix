use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_latest_scan_session, init_repo, load_config, validate_repo_path, CoreError, ErrorKind,
    ErrorRecoverability, OverviewOutput, RepoInitMode, RepoInitOptions, RepoPathIssue,
    ScanSessionKind, ScanSessionStatus, StorageMode,
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
                fs::read(path).expect("read Linux user file snapshot"),
            )
        })
        .collect()
}

fn assert_error_kind(error: CoreError, expected: ErrorKind) -> CoreError {
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, expected);
    assert!(!mapping.user_message.is_empty());
    assert!(!mapping.suggested_action.is_empty());
    error
}

fn repo_config_values(repo: &Path) -> Vec<(String, String)> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
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

#[test]
fn linux_repo_connect_failure_invalid_inputs_map_errors_without_metadata() {
    let repo = tempfile::tempdir().expect("create Linux failure repo");

    let blank_error = validate_repo_path("   ".to_owned()).expect_err("blank path is invalid");
    let internal_error = init_repo(
        path_string(&repo.path().join(".areamatrix/generated")),
        create_empty_options(),
    )
    .expect_err("metadata-internal Linux path is invalid");
    let file_path = repo.path().join("not-a-directory.txt");
    fs::write(&file_path, b"not a directory").expect("write regular file");
    let file_validation =
        validate_repo_path(path_string(&file_path)).expect("validate regular file path");

    let blank_error = assert_error_kind(blank_error, ErrorKind::InvalidPath);
    assert_error_kind(internal_error, ErrorKind::InvalidPath);
    assert_eq!(
        blank_error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert!(file_validation.exists);
    assert!(!file_validation.is_directory);
    assert_eq!(file_validation.issues, vec![RepoPathIssue::NotDirectory]);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn linux_repo_connect_failure_rejects_unconfirmed_adopt_options_without_user_file_changes() {
    let repo = tempfile::tempdir().expect("create Linux adopt failure repo");
    let user_file = repo.path().join("README.md");
    fs::write(&user_file, b"user readme").expect("write user file");
    let before = snapshot_files(std::slice::from_ref(&user_file));

    let mut invalid_options = adopt_existing_options();
    invalid_options.create_default_categories = true;
    let error = init_repo(path_string(repo.path()), invalid_options)
        .expect_err("invalid adopt options fail");

    assert_error_kind(error, ErrorKind::Config);
    assert_eq!(snapshot_files(std::slice::from_ref(&user_file)), before);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn linux_repo_connect_failure_corrupted_metadata_maps_db_without_repair_side_effects() {
    let repo = tempfile::tempdir().expect("create Linux corrupted DB repo");
    let metadata = repo.path().join(".areamatrix");
    let user_file = repo.path().join("README.md");
    fs::create_dir(&metadata).expect("create metadata directory");
    fs::write(&user_file, b"user readme").expect("write user file");
    fs::write(metadata.join("index.db"), b"not a sqlite database")
        .expect("write corrupted DB marker");
    let before = snapshot_files(std::slice::from_ref(&user_file));

    let validate_error =
        validate_repo_path(path_string(repo.path())).expect_err("corrupted scan DB fails");
    let load_error = load_config(path_string(repo.path())).expect_err("corrupted config DB fails");

    assert_error_kind(validate_error, ErrorKind::Db);
    let load_error = assert_error_kind(load_error, ErrorKind::Db);
    assert_eq!(
        load_error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(snapshot_files(std::slice::from_ref(&user_file)), before);
    assert!(metadata.join("index.db").is_file());
    assert!(!metadata.join("generated/root.md").exists());
}

#[cfg(unix)]
#[test]
fn linux_repo_connect_failure_permission_denied_does_not_suggest_permission_mutation() {
    use std::os::unix::fs::PermissionsExt;

    let repo = tempfile::tempdir().expect("create readonly Linux repo");
    let user_file = repo.path().join("README.md");
    fs::write(&user_file, b"user readme").expect("write user file");
    let before = snapshot_files(std::slice::from_ref(&user_file));

    let original_permissions = fs::metadata(repo.path())
        .expect("read repository permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o555);
    fs::set_permissions(repo.path(), readonly_permissions).expect("make repo readonly");

    let validation = validate_repo_path(path_string(repo.path())).expect("validate readonly repo");
    let result = init_repo(path_string(repo.path()), adopt_existing_options());

    fs::set_permissions(repo.path(), original_permissions).expect("restore repo permissions");

    let error = result.expect_err("readonly Linux adopt should fail");
    let mapping = assert_error_kind(error, ErrorKind::PermissionDenied).to_error_mapping();
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert!(!mapping.suggested_action.contains("chmod"));
    assert!(!mapping.suggested_action.contains("sudo"));
    assert_eq!(validation.recommended_mode, None);
    assert!(validation.issues.contains(&RepoPathIssue::NotWritable));
    assert_eq!(snapshot_files(std::slice::from_ref(&user_file)), before);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[cfg(unix)]
#[test]
fn linux_repo_connect_failure_adopt_scan_records_resumable_session_without_touching_user_files() {
    use std::os::unix::fs::PermissionsExt;

    let repo = tempfile::tempdir().expect("create Linux scan failure repo");
    let visible_file = repo.path().join("README.md");
    let blocked_dir = repo.path().join("blocked");
    fs::create_dir(&blocked_dir).expect("create blocked user directory");
    fs::write(&visible_file, b"user readme").expect("write visible user file");
    fs::write(blocked_dir.join("secret.txt"), b"user secret").expect("write blocked user file");
    let before = snapshot_files(std::slice::from_ref(&visible_file));

    let original_permissions = fs::metadata(&blocked_dir)
        .expect("read blocked permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&blocked_dir, blocked_permissions).expect("block scan directory");

    let result = init_repo(path_string(repo.path()), adopt_existing_options());

    fs::set_permissions(&blocked_dir, original_permissions).expect("restore blocked directory");

    let error = result.expect_err("unreadable user directory should fail adopt scan");
    assert_error_kind(error, ErrorKind::PermissionDenied);
    assert_eq!(snapshot_files(std::slice::from_ref(&visible_file)), before);
    assert!(blocked_dir.join("secret.txt").is_file());
    assert!(repo.path().join(".areamatrix/index.db").is_file());

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read failed Linux adopt scan session")
        .expect("failed Linux adopt scan session should exist");
    assert_eq!(session.kind, ScanSessionKind::Adopt);
    assert_eq!(session.status, ScanSessionStatus::Failed);
    assert_eq!(session.errors.len(), 1);
    assert!(session.errors[0].contains("permission denied"));
}

#[test]
fn linux_repo_connect_failure_keeps_ai_remote_surfaces_disabled_by_default() {
    let repo = tempfile::tempdir().expect("create Linux privacy repo");

    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize Linux repo");

    let config = load_config(path_string(repo.path())).expect("load config");
    let config_values = repo_config_values(repo.path());
    let serialized_config = format!("{config_values:?}");

    assert!(!config.ai_enabled);
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert!(config_values.contains(&("ai_enabled".to_owned(), "false".to_owned())));
    for sensitive_marker in ["api_key", "secret", "token", "sk-"] {
        assert!(!serialized_config.contains(sensitive_marker));
    }
}
