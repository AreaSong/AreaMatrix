use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    acknowledge_onedrive_risk_notice, detect_cloud_storage_state, init_repo,
    CloudStorageProviderKind, CloudStorageRecommendedAction, CloudStorageRiskLevel, CoreError,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_onedrive_repo(root: &Path) -> PathBuf {
    let repo = root
        .join("Users")
        .join("me")
        .join("OneDrive")
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

#[test]
fn onedrive_risk_state_implementation_persists_notice_acknowledgement_via_core_api() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    init_empty_repo(&repo);
    fs::write(repo.join("README.md"), b"user readme").expect("write user file after init");
    let before_user_file = fs::read(repo.join("README.md")).expect("read user file before probe");

    let first =
        detect_cloud_storage_state(path_string(&repo)).expect("detect initial OneDrive state");

    assert_eq!(first.provider_kind, CloudStorageProviderKind::OneDrive);
    assert_eq!(first.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(
        first.recommended_action,
        CloudStorageRecommendedAction::AcknowledgeNotice
    );
    assert!(first.requires_notice_acknowledgement);
    assert!(!first.notice_acknowledged);

    let acknowledged = acknowledge_onedrive_risk_notice(path_string(&repo))
        .expect("persist OneDrive notice acknowledgement through Core API");

    assert_eq!(
        acknowledged.provider_kind,
        CloudStorageProviderKind::OneDrive
    );
    assert_eq!(acknowledged.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(
        acknowledged.recommended_action,
        CloudStorageRecommendedAction::None
    );
    assert!(!acknowledged.requires_notice_acknowledgement);
    assert!(acknowledged.notice_acknowledged);

    let reloaded =
        detect_cloud_storage_state(path_string(&repo)).expect("reload acknowledged OneDrive state");
    assert!(!reloaded.requires_notice_acknowledgement);
    assert!(reloaded.notice_acknowledged);
    assert_eq!(
        fs::read(repo.join("README.md")).expect("read user file after probe"),
        before_user_file
    );
}

#[test]
fn onedrive_risk_state_implementation_keeps_uninitialized_probe_read_only() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    fs::write(repo.join("notes.txt"), b"user notes").expect("write user file");
    let before_user_file = fs::read(repo.join("notes.txt")).expect("read user file before probe");

    let state = detect_cloud_storage_state(path_string(&repo)).expect("detect OneDrive state");

    assert_eq!(state.provider_kind, CloudStorageProviderKind::OneDrive);
    assert_eq!(
        state.recommended_action,
        CloudStorageRecommendedAction::AcknowledgeNotice
    );
    assert!(state.requires_notice_acknowledgement);
    assert!(!state.notice_acknowledged);
    assert_eq!(
        fs::read(repo.join("notes.txt")).expect("read user file after probe"),
        before_user_file
    );
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn onedrive_risk_state_implementation_does_not_initialize_repo_when_acknowledging_notice() {
    let root = tempfile::tempdir().expect("create temporary root");
    let repo = create_onedrive_repo(root.path());
    fs::write(repo.join("notes.txt"), b"user notes").expect("write user file");
    let before_user_file = fs::read(repo.join("notes.txt")).expect("read user file before ack");

    let error = acknowledge_onedrive_risk_notice(path_string(&repo))
        .expect_err("acknowledgement requires initialized repository metadata");

    assert!(matches!(error, CoreError::Io { .. }));
    assert_eq!(
        fs::read(repo.join("notes.txt")).expect("read user file after failed ack"),
        before_user_file
    );
    assert!(!repo.join(".areamatrix").exists());
}
