use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    detect_cloud_storage_state, CloudPermissionState, CloudPlaceholderState,
    CloudStorageProviderKind, CloudStorageRiskLevel, CoreError, ErrorKind, ErrorRecoverability,
    ErrorSeverity,
};
use pretty_assertions::assert_eq;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn file_snapshot(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
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
    assert_eq!(error.kind(), expected);
    assert_eq!(error.to_error_mapping().kind, expected);
    error
}

fn assert_no_cloud_probe_side_effects(repo: &Path, before: &[(PathBuf, Vec<u8>)]) {
    assert_eq!(file_snapshot(&before_paths(before)), before);
    assert!(!repo.join(".areamatrix").exists());
    assert!(!repo.join("AREAMATRIX.md").exists());
}

fn before_paths(before: &[(PathBuf, Vec<u8>)]) -> Vec<PathBuf> {
    before.iter().map(|(path, _bytes)| path.clone()).collect()
}

fn assert_no_secret_material(value: &str) {
    for fragment in [
        "sk-secret",
        "api_key",
        "token=",
        "Bearer ",
        "secure-storage:",
        "keychain:",
    ] {
        assert!(
            !value.contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
}

#[test]
fn cloud_permission_state_failure_empty_repo_state_is_read_only() {
    let repo = tempfile::tempdir().expect("create empty repository directory");

    let state =
        detect_cloud_storage_state(path_string(repo.path())).expect("detect empty repo state");

    assert_eq!(state.repo_path, path_string(repo.path()));
    assert_eq!(state.provider_kind, CloudStorageProviderKind::Local);
    assert_eq!(state.risk, CloudStorageRiskLevel::NoRisk);
    assert_eq!(
        state.placeholder_state,
        CloudPlaceholderState::NotPlaceholder
    );
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert!(state.risk_reasons.is_empty());
    assert!(!state.can_retry);
    assert!(!state.requires_reconnect);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn cloud_permission_state_failure_invalid_inputs_are_explicit_and_side_effect_free() {
    let repo = tempfile::tempdir().expect("create repository directory");
    let user_file = repo.path().join("README.md");
    fs::write(&user_file, b"user authored readme").expect("write user README");
    let before = file_snapshot(std::slice::from_ref(&user_file));

    let empty = detect_cloud_storage_state(String::new()).expect_err("empty path is invalid");
    let internal = detect_cloud_storage_state(path_string(&repo.path().join(".areamatrix")))
        .expect_err("metadata-internal path is invalid");

    assert!(matches!(
        assert_error_kind(empty, ErrorKind::InvalidPath),
        CoreError::InvalidPath { path } if path.contains("required")
    ));
    assert!(matches!(
        assert_error_kind(internal, ErrorKind::InvalidPath),
        CoreError::InvalidPath { path } if path.contains("repository root")
    ));
    assert_no_cloud_probe_side_effects(repo.path(), &before);
}

#[test]
fn cloud_permission_state_failure_placeholder_maps_to_retryable_error_without_downloads() {
    let repo = tempfile::tempdir().expect("create repository directory");
    let user_file = repo.path().join("notes.txt");
    fs::write(&user_file, b"user notes").expect("write user file");
    let before = file_snapshot(std::slice::from_ref(&user_file));
    let placeholder_path = repo.path().join("AreaMatrix.icloud");

    let error = detect_cloud_storage_state(path_string(&placeholder_path))
        .expect_err("placeholder repo path must fail explicitly");
    let error = assert_error_kind(error, ErrorKind::ICloudPlaceholder);
    let mapping = error.to_error_mapping();

    assert!(matches!(
        error,
        CoreError::ICloudPlaceholder { path } if path == path_string(&placeholder_path)
    ));
    assert_eq!(mapping.severity, ErrorSeverity::Medium);
    assert_eq!(mapping.recoverability, ErrorRecoverability::Retryable);
    assert_no_cloud_probe_side_effects(repo.path(), &before);
    assert!(!placeholder_path.exists());
}

#[test]
fn cloud_permission_state_failure_io_error_is_not_silently_downgraded() {
    let repo = tempfile::tempdir().expect("create repository directory");
    let user_file = repo.path().join("README.md");
    let not_directory = repo.path().join("not-a-directory.txt");
    fs::write(&user_file, b"user readme").expect("write user file");
    fs::write(&not_directory, b"not a repository").expect("write file path");
    let before = file_snapshot(&[user_file.clone(), not_directory.clone()]);

    let error = detect_cloud_storage_state(path_string(&not_directory))
        .expect_err("file path is an IO failure for cloud state detection");
    let error = assert_error_kind(error, ErrorKind::Io);

    assert!(matches!(error, CoreError::Io { message } if message.contains("not a directory")));
    assert_no_cloud_probe_side_effects(repo.path(), &before);
}

#[cfg(unix)]
#[test]
fn cloud_permission_state_failure_permission_denied_requires_reconnect_without_mutation() {
    use std::os::unix::fs::PermissionsExt;

    let repo = tempfile::tempdir().expect("create repository directory");
    let user_file = repo.path().join("README.md");
    fs::write(&user_file, b"permission protected readme").expect("write user file");
    let before = file_snapshot(std::slice::from_ref(&user_file));
    let original_permissions = fs::metadata(repo.path())
        .expect("read repo permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(repo.path(), blocked_permissions).expect("remove repository permissions");

    let result = detect_cloud_storage_state(path_string(repo.path()));

    fs::set_permissions(repo.path(), original_permissions).expect("restore repository permissions");
    let error = result.expect_err("blocked directory listing must fail");
    let error = assert_error_kind(error, ErrorKind::PermissionDenied);
    let mapping = error.to_error_mapping();

    assert!(matches!(
        error,
        CoreError::PermissionDenied { path } if path == path_string(repo.path())
    ));
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_no_cloud_probe_side_effects(repo.path(), &before);
}

#[test]
fn cloud_permission_state_failure_corrupted_db_is_not_read_or_repaired_by_probe() {
    let repo = tempfile::tempdir().expect("create repository directory");
    let user_file = repo.path().join("README.md");
    let metadata_dir = repo.path().join(".areamatrix");
    let db_path = metadata_dir.join("index.db");
    fs::write(&user_file, b"user readme").expect("write user file");
    fs::create_dir(&metadata_dir).expect("create metadata directory");
    fs::write(&db_path, b"not a sqlite database").expect("write corrupted metadata");
    let before_user = fs::read(&user_file).expect("read user file before probe");
    let before_db = fs::read(&db_path).expect("read corrupted db before probe");

    let state = detect_cloud_storage_state(path_string(repo.path()))
        .expect("cloud state probe must not open repository DB");

    assert_eq!(state.provider_kind, CloudStorageProviderKind::Local);
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert_eq!(
        fs::read(&user_file).expect("read user file after probe"),
        before_user
    );
    assert_eq!(
        fs::read(&db_path).expect("read corrupted db after probe"),
        before_db
    );
    assert!(!metadata_dir.join("generated").exists());
    assert!(!metadata_dir.join("staging").exists());
}

#[test]
fn cloud_permission_state_failure_cloud_provider_messages_do_not_expose_secret_material() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = root
        .path()
        .join("Users")
        .join("me")
        .join("OneDrive")
        .join("AreaMatrix");
    fs::create_dir_all(&repo).expect("create OneDrive-shaped repo path");
    fs::write(repo.join("secret.txt"), b"api_key=sk-secret").expect("write user file");

    let state = detect_cloud_storage_state(path_string(&repo))
        .expect("detect OneDrive state without reading user file content");

    assert_eq!(state.provider_kind, CloudStorageProviderKind::OneDrive);
    assert_eq!(state.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert_no_secret_material(&state.status_summary);
    for reason in &state.risk_reasons {
        assert_no_secret_material(reason);
    }
    assert_eq!(
        fs::read(repo.join("secret.txt")).expect("read user file after probe"),
        b"api_key=sk-secret"
    );
}
