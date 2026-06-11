use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, load_config, validate_repo_path, CoreError,
    FileFilter, FileOrigin, OverviewOutput, PlatformPathKind, RepoInitMode, RepoInitOptions,
    RepoPathIssue, ScanSessionKind, ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;

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

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
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

#[test]
fn linux_repo_connect_initializes_empty_local_directory_after_confirmation() {
    let repo = tempfile::tempdir().expect("create empty Linux repository directory");

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate Linux local path");

    assert!(validation.exists);
    assert!(validation.is_directory);
    assert!(validation.is_readable);
    assert!(validation.is_writable);
    assert!(validation.is_empty);
    assert!(!validation.is_initialized);
    assert_eq!(validation.platform_path_kind, PlatformPathKind::Local);
    assert!(validation.is_case_sensitive_path);
    assert_eq!(validation.recommended_mode, Some(RepoInitMode::CreateEmpty));
    assert_eq!(validation.issues, Vec::<RepoPathIssue>::new());
    assert!(!repo.path().join(".areamatrix").exists());

    init_repo(path_string(repo.path()), create_empty_options())
        .expect("initialize Linux repository after confirmation");

    let connected =
        validate_repo_path(path_string(repo.path())).expect("revalidate initialized Linux repo");
    let config = load_config(path_string(repo.path())).expect("load Linux repo config");

    assert!(connected.is_initialized);
    assert_eq!(connected.recommended_mode, None);
    assert_eq!(connected.issues, vec![RepoPathIssue::AlreadyInitialized]);
    assert_eq!(config.repo_path, path_string(repo.path()));
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());
    assert!(!repo.path().join("README.md").exists());
    assert!(!repo.path().join("AREAMATRIX.md").exists());
}

#[test]
fn linux_repo_connect_adopts_non_empty_local_directory_without_touching_user_files() {
    let repo = tempfile::tempdir().expect("create non-empty Linux repository directory");
    let docs = repo.path().join("docs");
    let readme = repo.path().join("README.md");
    let spec = docs.join("spec.txt");
    let user_overview = repo.path().join("AREAMATRIX.md");
    fs::create_dir(&docs).expect("create Linux user docs directory");
    fs::write(&readme, "# User project\n").expect("write user README");
    fs::write(&spec, "spec content\n").expect("write user document");
    fs::write(&user_overview, "user overview\n").expect("write user AREAMATRIX");
    let before = snapshot_files(&[readme.clone(), spec.clone(), user_overview.clone()]);

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate non-empty Linux path");

    assert!(!validation.is_empty);
    assert!(!validation.is_initialized);
    assert_eq!(validation.platform_path_kind, PlatformPathKind::Local);
    assert!(validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(validation.issues, vec![RepoPathIssue::NonEmptyDirectory]);
    assert!(!repo.path().join(".areamatrix").exists());

    let rejected = init_repo(path_string(repo.path()), create_empty_options());
    assert!(matches!(rejected, Err(CoreError::Config { .. })));
    assert_eq!(
        snapshot_files(&[readme.clone(), spec.clone(), user_overview.clone()]),
        before
    );
    assert!(!repo.path().join(".areamatrix").exists());

    init_repo(path_string(repo.path()), adopt_existing_options())
        .expect("adopt Linux repository after confirmation");

    assert_eq!(
        snapshot_files(&[readme.clone(), spec.clone(), user_overview.clone()]),
        before
    );
    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());

    let mut files =
        list_files(path_string(repo.path()), empty_filter()).expect("list adopted Linux files");
    files.sort_by(|left, right| left.path.cmp(&right.path));
    assert_eq!(
        files
            .iter()
            .map(|file| file.path.as_str())
            .collect::<Vec<_>>(),
        vec!["README.md", "docs/spec.txt"]
    );
    for file in files {
        assert_eq!(file.storage_mode, StorageMode::Indexed);
        assert_eq!(file.origin, FileOrigin::Adopted);
        assert_eq!(file.source_path, None);
    }

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest Linux adopt scan session")
        .expect("adopt scan session exists");
    assert_eq!(session.kind, ScanSessionKind::Adopt);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.inserted, 2);
    assert_eq!(session.errors, Vec::<String>::new());
}

#[test]
fn linux_repo_connect_keeps_local_folder_risk_state_structured_and_read_only() {
    let root = tempfile::tempdir().expect("create Linux risk-state root");
    let missing_network = PathBuf::from("//server/share/AreaMatrix");
    let missing_local = root.path().join("AreaMatrix");

    let network = validate_repo_path(path_string(&missing_network))
        .expect("validate network-shaped missing Linux path");
    let local =
        validate_repo_path(path_string(&missing_local)).expect("validate missing Linux path");

    assert!(!network.exists);
    assert_eq!(network.platform_path_kind, PlatformPathKind::NetworkShare);
    assert!(!network.is_case_sensitive_path);
    assert_eq!(
        network.issues,
        vec![
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::MissingPath
        ]
    );
    assert!(!local.exists);
    assert_eq!(local.platform_path_kind, PlatformPathKind::Local);
    assert!(local.is_case_sensitive_path);
    assert_eq!(local.issues, vec![RepoPathIssue::MissingPath]);
    assert!(!missing_network.exists());
    assert!(!missing_local.exists());
}
