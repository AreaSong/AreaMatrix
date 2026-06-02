use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    detect_cloud_storage_state, CloudPermissionState, CloudPlaceholderState,
    CloudStorageProviderKind, CloudStorageRiskLevel, CoreError,
};
use pretty_assertions::assert_eq;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_nested_repo(root: &Path, components: &[&str]) -> PathBuf {
    let repo = components.iter().fold(root.to_path_buf(), |path, component| {
        path.join(component)
    });
    fs::create_dir_all(&repo).expect("create nested cloud repository path");
    repo
}

fn snapshot(path: &Path) -> Vec<(String, Vec<u8>)> {
    let mut entries = fs::read_dir(path)
        .expect("read repository directory")
        .map(|entry| {
            let entry = entry.expect("read directory entry");
            let name = entry.file_name().to_string_lossy().into_owned();
            let bytes = if entry.path().is_file() {
                fs::read(entry.path()).expect("read file bytes")
            } else {
                Vec::new()
            };
            (name, bytes)
        })
        .collect::<Vec<_>>();
    entries.sort_by(|left, right| left.0.cmp(&right.0));
    entries
}

#[test]
fn cloud_permission_state_implementation_detects_local_repo_read_only() {
    let repo = tempfile::tempdir().expect("create local repository directory");
    fs::write(repo.path().join("README.md"), "user content\n").expect("write user file");
    let before = snapshot(repo.path());

    let state = detect_cloud_storage_state(path_string(repo.path()))
        .expect("detect local cloud storage state");

    assert_eq!(state.repo_path, path_string(repo.path()));
    assert_eq!(state.provider_kind, CloudStorageProviderKind::Local);
    assert_eq!(state.risk, CloudStorageRiskLevel::NoRisk);
    assert_eq!(state.placeholder_state, CloudPlaceholderState::NotPlaceholder);
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert_eq!(
        state.status_summary,
        "No cloud storage provider was detected from the repository path."
    );
    assert_eq!(state.risk_reasons, Vec::<String>::new());
    assert!(!state.can_retry);
    assert!(!state.requires_reconnect);
    assert_eq!(snapshot(repo.path()), before);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn cloud_permission_state_implementation_detects_icloud_risk_without_downloads() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_nested_repo(
        root.path(),
        &["Library", "Mobile Documents", "com~apple~CloudDocs", "AreaMatrix"],
    );
    fs::write(repo.join("report.txt"), "cloud backed\n").expect("write cloud-backed file");
    let before = snapshot(&repo);

    let state =
        detect_cloud_storage_state(path_string(&repo)).expect("detect iCloud storage state");

    assert_eq!(state.provider_kind, CloudStorageProviderKind::ICloudDrive);
    assert_eq!(state.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(state.placeholder_state, CloudPlaceholderState::NotPlaceholder);
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert!(state
        .status_summary
        .contains("iCloud Drive path detected"));
    assert_eq!(state.risk_reasons.len(), 2);
    assert!(state
        .risk_reasons
        .iter()
        .any(|reason| reason.contains("placeholder files")));
    assert!(!state.can_retry);
    assert!(!state.requires_reconnect);
    assert_eq!(snapshot(&repo), before);
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn cloud_permission_state_implementation_detects_onedrive_risk_without_sdk_state() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_nested_repo(root.path(), &["Users", "me", "OneDrive", "AreaMatrix"]);
    fs::write(repo.join("spec.txt"), "onedrive backed\n").expect("write cloud-backed file");
    let before = snapshot(&repo);

    let state =
        detect_cloud_storage_state(path_string(&repo)).expect("detect OneDrive storage state");

    assert_eq!(state.provider_kind, CloudStorageProviderKind::OneDrive);
    assert_eq!(state.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(state.placeholder_state, CloudPlaceholderState::NotPlaceholder);
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert!(state.status_summary.contains("OneDrive path detected"));
    assert_eq!(state.risk_reasons.len(), 2);
    assert!(state
        .risk_reasons
        .iter()
        .any(|reason| reason.contains("OneDrive SDK")));
    assert!(!state.can_retry);
    assert!(!state.requires_reconnect);
    assert_eq!(snapshot(&repo), before);
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn cloud_permission_state_implementation_maps_placeholder_repo_path() {
    let root = tempfile::tempdir().expect("create temporary root");
    let placeholder_path = root.path().join("AreaMatrix.icloud");

    let result = detect_cloud_storage_state(path_string(&placeholder_path));

    assert!(matches!(result, Err(CoreError::ICloudPlaceholder { .. })));
    assert!(!root.path().join(".areamatrix").exists());
}
