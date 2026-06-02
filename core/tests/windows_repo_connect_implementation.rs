use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_files, load_config, validate_repo_path, CoreError, FileFilter, FileOrigin,
    OverviewOutput, PlatformPathKind, RepoInitMode, RepoInitOptions, RepoPathIssue, StorageMode,
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
        .map(|path| (path.clone(), fs::read(path).expect("read user file snapshot")))
        .collect()
}

#[test]
fn windows_repo_connect_initializes_windows_shaped_empty_path_after_confirmation() {
    let root = tempfile::tempdir().expect("create Windows-shaped test root");
    let repo = root.path().join("C:\\Users\\me\\Documents\\AreaMatrix");
    fs::create_dir_all(&repo).expect("create Windows-shaped empty repo path");

    let validation = validate_repo_path(path_string(&repo)).expect("validate Windows path");

    assert!(validation.exists);
    assert!(validation.is_directory);
    assert!(validation.is_empty);
    assert!(!validation.is_onedrive_path);
    assert_eq!(validation.platform_path_kind, PlatformPathKind::Local);
    assert!(!validation.is_case_sensitive_path);
    assert_eq!(validation.recommended_mode, Some(RepoInitMode::CreateEmpty));
    assert_eq!(
        validation.issues,
        vec![RepoPathIssue::WindowsCaseInsensitive]
    );
    assert!(!repo.join(".areamatrix").exists());

    init_repo(path_string(&repo), create_empty_options()).expect("initialize Windows repo");
    let connected = validate_repo_path(path_string(&repo)).expect("revalidate initialized repo");
    let config = load_config(path_string(&repo)).expect("load Windows repo config");

    assert!(connected.is_initialized);
    assert_eq!(connected.recommended_mode, None);
    assert_eq!(
        connected.issues,
        vec![
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::AlreadyInitialized,
        ]
    );
    assert_eq!(config.repo_path, path_string(&repo));
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(repo.join(".areamatrix/index.db").is_file());
    assert!(repo.join(".areamatrix/generated/root.md").is_file());
    assert!(!repo.join("README.md").exists());
    assert!(!repo.join("AREAMATRIX.md").exists());
}

#[test]
fn windows_repo_connect_adopts_onedrive_non_empty_path_without_touching_user_files() {
    let root = tempfile::tempdir().expect("create Windows OneDrive test root");
    let repo = root
        .path()
        .join("C:\\Users\\me\\OneDrive - Example Org\\AreaMatrix");
    let docs = repo.join("docs");
    let readme = repo.join("README.md");
    let spec = docs.join("spec.txt");
    let user_overview = repo.join("AREAMATRIX.md");
    fs::create_dir_all(&docs).expect("create user docs directory");
    fs::write(&readme, "# User project\n").expect("write user README");
    fs::write(&spec, "spec content\n").expect("write user document");
    fs::write(&user_overview, "user overview\n").expect("write user AREAMATRIX");
    let before = snapshot_files(&[readme.clone(), spec.clone(), user_overview.clone()]);

    let validation = validate_repo_path(path_string(&repo)).expect("validate OneDrive repo path");

    assert!(!validation.is_empty);
    assert!(validation.is_onedrive_path);
    assert_eq!(validation.platform_path_kind, PlatformPathKind::OneDrive);
    assert!(!validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(
        validation.issues,
        vec![
            RepoPathIssue::OneDrivePath,
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::NonEmptyDirectory,
        ]
    );
    assert!(!repo.join(".areamatrix").exists());

    let rejected = init_repo(path_string(&repo), create_empty_options());
    assert!(matches!(rejected, Err(CoreError::Config { .. })));
    assert_eq!(
        snapshot_files(&[readme.clone(), spec.clone(), user_overview.clone()]),
        before
    );
    assert!(!repo.join(".areamatrix").exists());

    init_repo(path_string(&repo), adopt_existing_options())
        .expect("adopt Windows OneDrive repo after confirmation");
    let config = load_config(path_string(&repo)).expect("load adopted Windows repo config");
    let mut files = list_files(path_string(&repo), empty_filter()).expect("list adopted files");
    files.sort_by(|left, right| left.path.cmp(&right.path));

    assert_eq!(
        snapshot_files(&[readme.clone(), spec.clone(), user_overview.clone()]),
        before
    );
    assert_eq!(config.repo_path, path_string(&repo));
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
    assert!(repo.join(".areamatrix/index.db").is_file());
    assert!(repo.join(".areamatrix/generated/root.md").is_file());
}

#[test]
fn windows_repo_connect_rejects_windows_reserved_names_before_filesystem_writes() {
    for path in [
        "C:\\Users\\me\\CON\\AreaMatrix",
        "C:\\Users\\me\\Reports\\nul.txt",
        "\\\\server\\share\\LPT1\\AreaMatrix",
    ] {
        let result = validate_repo_path(path.to_owned());

        assert_eq!(result, Err(CoreError::invalid_path("invalid path")));
    }
}

#[test]
fn windows_repo_connect_blocks_metadata_internal_paths_with_windows_separators() {
    let root = tempfile::tempdir().expect("create Windows internal path root");
    let repo = root.path().join("C:\\Users\\me\\AreaMatrix");
    fs::create_dir_all(&repo).expect("create Windows repo directory");

    for raw in [
        path_string(&repo.join(".areamatrix\\staging")),
        path_string(&repo.join(".AREAMATRIX\\generated")),
    ] {
        let result = validate_repo_path(raw);

        assert!(matches!(result, Err(CoreError::InvalidPath { .. })));
        assert!(!repo.join(".areamatrix").exists());
    }
}

#[test]
fn windows_repo_connect_classifies_unc_and_mixed_separators_without_sdk_side_effects() {
    let root = tempfile::tempdir().expect("create mixed-separator test root");
    let onedrive_repo = root.path().join("C:\\Users/me\\OneDrive/AreaMatrix");
    fs::create_dir_all(&onedrive_repo).expect("create mixed-separator OneDrive repo");

    let unc = validate_repo_path("\\\\server\\share\\AreaMatrix".to_owned())
        .expect("validate UNC-shaped missing path");
    let onedrive = validate_repo_path(path_string(&onedrive_repo)).expect("validate OneDrive path");

    assert!(!unc.exists);
    assert_eq!(unc.platform_path_kind, PlatformPathKind::NetworkShare);
    assert!(!unc.is_case_sensitive_path);
    assert_eq!(
        unc.issues,
        vec![
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::MissingPath,
        ]
    );
    assert!(onedrive.is_onedrive_path);
    assert_eq!(onedrive.platform_path_kind, PlatformPathKind::OneDrive);
    assert_eq!(
        onedrive.issues,
        vec![RepoPathIssue::OneDrivePath, RepoPathIssue::WindowsCaseInsensitive]
    );
    assert!(!onedrive_repo.join(".areamatrix").exists());
}
