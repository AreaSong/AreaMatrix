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
fn windows_repo_connect_failure_invalid_inputs_map_errors_without_metadata() {
    let root = tempfile::tempdir().expect("create Windows failure root");
    let repo = root.path().join("C:\\Users\\me\\AreaMatrix");
    fs::create_dir_all(&repo).expect("create Windows-shaped repository path");

    let blank_error = validate_repo_path("   ".to_owned()).expect_err("blank path is invalid");
    let reserved_error = validate_repo_path("C:\\Users\\me\\CON\\AreaMatrix".to_owned())
        .expect_err("reserved Windows device name is invalid");
    let internal_error = init_repo(
        path_string(&repo.join(".AREAMATRIX\\generated")),
        create_empty_options(),
    )
    .expect_err("metadata-internal Windows path is invalid");

    let blank_error = assert_error_kind(blank_error, ErrorKind::InvalidPath);
    let reserved_error = assert_error_kind(reserved_error, ErrorKind::InvalidPath);
    assert_error_kind(internal_error, ErrorKind::InvalidPath);
    assert_eq!(
        blank_error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(
        reserved_error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn windows_repo_connect_failure_onedrive_missing_path_is_read_only_risk_state() {
    let root = tempfile::tempdir().expect("create Windows OneDrive root");
    let missing_repo = root
        .path()
        .join("C:\\Users\\me\\OneDrive - Example Org\\MissingAreaMatrix");

    let validation =
        validate_repo_path(path_string(&missing_repo)).expect("validate missing OneDrive path");

    assert!(!validation.exists);
    assert!(validation.is_onedrive_path);
    assert!(!validation.is_case_sensitive_path);
    assert_eq!(validation.recommended_mode, None);
    assert_eq!(
        validation.issues,
        vec![
            RepoPathIssue::OneDrivePath,
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::MissingPath,
        ]
    );
    assert!(!missing_repo.exists());
}

#[test]
fn windows_repo_connect_failure_rejects_unconfirmed_adopt_options_without_user_file_changes() {
    let root = tempfile::tempdir().expect("create Windows adopt root");
    let repo = root.path().join("C:\\Users\\me\\OneDrive\\AreaMatrix");
    let user_file = repo.join("README.md");
    fs::create_dir_all(&repo).expect("create Windows-shaped repository path");
    fs::write(&user_file, b"user readme").expect("write user file");
    let before = snapshot_files(std::slice::from_ref(&user_file));

    let mut invalid_options = adopt_existing_options();
    invalid_options.create_default_categories = true;
    let error =
        init_repo(path_string(&repo), invalid_options).expect_err("invalid adopt options fail");

    assert_error_kind(error, ErrorKind::Config);
    assert_eq!(snapshot_files(std::slice::from_ref(&user_file)), before);
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn windows_repo_connect_failure_corrupted_metadata_maps_db_without_repair_side_effects() {
    let root = tempfile::tempdir().expect("create Windows corrupted DB root");
    let repo = root.path().join("C:\\Users\\me\\OneDrive\\AreaMatrix");
    let metadata = repo.join(".areamatrix");
    let user_file = repo.join("README.md");
    fs::create_dir_all(&metadata).expect("create metadata directory");
    fs::write(&user_file, b"user readme").expect("write user file");
    fs::write(metadata.join("index.db"), b"not a sqlite database")
        .expect("write corrupted DB marker");
    let before = snapshot_files(std::slice::from_ref(&user_file));

    let validate_error =
        validate_repo_path(path_string(&repo)).expect_err("corrupted scan DB fails");
    let load_error = load_config(path_string(&repo)).expect_err("corrupted config DB fails");

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
fn windows_repo_connect_failure_permission_denied_keeps_user_files_and_blocks_init() {
    use std::os::unix::fs::PermissionsExt;

    let root = tempfile::tempdir().expect("create Windows readonly root");
    let repo = root.path().join("C:\\Users\\me\\OneDrive\\AreaMatrix");
    let user_file = repo.join("README.md");
    fs::create_dir_all(&repo).expect("create Windows-shaped repository path");
    fs::write(&user_file, b"user readme").expect("write user file");
    let before = snapshot_files(std::slice::from_ref(&user_file));

    let original_permissions = fs::metadata(&repo)
        .expect("read repository permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o555);
    fs::set_permissions(&repo, readonly_permissions).expect("make repo readonly");

    let validation = validate_repo_path(path_string(&repo)).expect("validate readonly repo");
    let result = init_repo(path_string(&repo), adopt_existing_options());

    fs::set_permissions(&repo, original_permissions).expect("restore repo permissions");

    let error = result.expect_err("readonly Windows adopt should fail");
    assert_error_kind(error, ErrorKind::PermissionDenied);
    assert_eq!(validation.recommended_mode, None);
    assert!(validation.issues.contains(&RepoPathIssue::NotWritable));
    assert_eq!(snapshot_files(std::slice::from_ref(&user_file)), before);
    assert!(!repo.join(".areamatrix").exists());
}

#[cfg(unix)]
#[test]
fn windows_repo_connect_failure_io_error_is_explicit_and_read_only() {
    use std::os::unix::fs::symlink;

    let root = tempfile::tempdir().expect("create Windows IO failure root");
    let repo = root.path().join("C:\\Users\\me\\AreaMatrix");
    fs::create_dir_all(&repo).expect("create Windows-shaped repository path");
    let loop_path = repo.join("loop");
    symlink(&loop_path, &loop_path).expect("create symlink loop");

    let error = validate_repo_path(path_string(&loop_path)).expect_err("symlink loop is IO");

    assert_error_kind(error, ErrorKind::Io);
    assert!(!repo.join(".areamatrix").exists());
}

#[cfg(unix)]
#[test]
fn windows_repo_connect_failure_adopt_scan_rolls_back_metadata_without_touching_user_files() {
    use std::os::unix::fs::PermissionsExt;

    let root = tempfile::tempdir().expect("create Windows scan failure root");
    let repo = root.path().join("C:\\Users\\me\\OneDrive\\AreaMatrix");
    let visible_file = repo.join("README.md");
    let blocked_dir = repo.join("blocked");
    fs::create_dir_all(&blocked_dir).expect("create blocked user directory");
    fs::write(&visible_file, b"user readme").expect("write visible user file");
    fs::write(blocked_dir.join("secret.txt"), b"user secret").expect("write blocked user file");
    let before = snapshot_files(std::slice::from_ref(&visible_file));

    let original_permissions = fs::metadata(&blocked_dir)
        .expect("read blocked permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&blocked_dir, blocked_permissions).expect("block scan directory");

    let result = init_repo(path_string(&repo), adopt_existing_options());

    fs::set_permissions(&blocked_dir, original_permissions).expect("restore blocked directory");

    let error = result.expect_err("unreadable user directory should fail adopt scan");
    assert_error_kind(error, ErrorKind::PermissionDenied);
    assert_eq!(snapshot_files(std::slice::from_ref(&visible_file)), before);
    assert!(blocked_dir.join("secret.txt").is_file());
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn windows_repo_connect_failure_keeps_remote_ai_disabled_and_credentials_absent_by_default() {
    let root = tempfile::tempdir().expect("create Windows privacy root");
    let repo = root.path().join("C:\\Users\\me\\Documents\\AreaMatrix");
    fs::create_dir_all(&repo).expect("create Windows-shaped empty repo");

    init_repo(path_string(&repo), create_empty_options()).expect("initialize Windows repo");

    let config = load_config(path_string(&repo)).expect("load config");
    let config_values = repo_config_values(&repo);
    let serialized_config = format!("{config_values:?}");

    assert!(!config.ai_enabled);
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert!(config_values.contains(&("ai_enabled".to_owned(), "false".to_owned())));
    for sensitive_marker in ["api_key", "secret", "token", "sk-"] {
        assert!(!serialized_config.contains(sensitive_marker));
    }
    assert!(!repo.join(".areamatrix/ai_call_log").exists());
}
