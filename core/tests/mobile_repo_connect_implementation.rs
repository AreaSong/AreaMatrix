use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, load_config, validate_repo_path, CoreError,
    FileFilter, FileOrigin, OverviewOutput, RepoInitMode, RepoInitOptions, RepoPathIssue,
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
        .map(|path| (path.clone(), fs::read(path).expect("read file snapshot")))
        .collect()
}

fn db_connection(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

#[test]
fn mobile_repo_connect_empty_directory_initializes_only_after_explicit_confirmed_call() {
    let repo = tempfile::tempdir().expect("create empty mobile repository directory");

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate mobile-selected path");

    assert!(validation.exists);
    assert!(validation.is_directory);
    assert!(validation.is_readable);
    assert!(validation.is_writable);
    assert!(validation.is_empty);
    assert!(!validation.is_initialized);
    assert_eq!(validation.recommended_mode, Some(RepoInitMode::CreateEmpty));
    assert_eq!(validation.issues, Vec::<RepoPathIssue>::new());
    assert!(!repo.path().join(".areamatrix").exists());

    init_repo(path_string(repo.path()), create_empty_options())
        .expect("initialize after shared confirmation page");

    let connected =
        validate_repo_path(path_string(repo.path())).expect("revalidate initialized mobile repo");
    let config = load_config(path_string(repo.path())).expect("load connected mobile repo config");

    assert!(connected.is_initialized);
    assert_eq!(connected.recommended_mode, None);
    assert_eq!(connected.issues, vec![RepoPathIssue::AlreadyInitialized]);
    assert_eq!(config.repo_path, path_string(repo.path()));
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(!repo.path().join("README.md").exists());
    assert!(!repo.path().join("AREAMATRIX.md").exists());
    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());

    let connection = db_connection(repo.path());
    let config_rows: i64 = connection
        .query_row("SELECT COUNT(*) FROM repo_config", [], |row| row.get(0))
        .expect("count repo_config rows");
    assert_eq!(config_rows, 10);
}

#[test]
fn mobile_repo_connect_non_empty_directory_adopts_without_modifying_user_files() {
    let repo = tempfile::tempdir().expect("create non-empty mobile repository directory");
    let readme = repo.path().join("README.md");
    let docs_dir = repo.path().join("docs");
    let spec = docs_dir.join("spec.txt");
    let user_overview = repo.path().join("AREAMATRIX.md");
    fs::create_dir(&docs_dir).expect("create user docs directory");
    fs::write(&readme, "# User project\n").expect("write user README");
    fs::write(&spec, "spec content\n").expect("write user document");
    fs::write(&user_overview, "user overview\n").expect("write user AREAMATRIX");
    let before = snapshot_files(&[readme.clone(), spec.clone(), user_overview.clone()]);

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate non-empty mobile path");

    assert!(!validation.is_empty);
    assert!(!validation.is_initialized);
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
        .expect("adopt after shared confirmation page");

    assert_eq!(
        snapshot_files(&[readme.clone(), spec.clone(), user_overview.clone()]),
        before
    );
    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());

    let mut files =
        list_files(path_string(repo.path()), empty_filter()).expect("list adopted mobile files");
    files.sort_by(|left, right| left.path.cmp(&right.path));
    assert_eq!(
        files.iter().map(|file| file.path.as_str()).collect::<Vec<_>>(),
        vec!["README.md", "docs/spec.txt"]
    );
    for file in files {
        assert_eq!(file.storage_mode, StorageMode::Indexed);
        assert_eq!(file.origin, FileOrigin::Adopted);
        assert_eq!(file.source_path, None);
    }

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest adopt scan session")
        .expect("adopt scan session exists");
    assert_eq!(session.kind, ScanSessionKind::Adopt);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.inserted, 2);
    assert_eq!(session.errors, Vec::<String>::new());

    let connection = db_connection(repo.path());
    let adopted_rows: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM files \
             WHERE storage_mode = 'indexed' AND origin = 'adopted' AND status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count adopted rows");
    assert_eq!(adopted_rows, 2);
}

#[test]
fn mobile_repo_connect_maps_core_errors_without_platform_ui_dependencies() {
    let repo = tempfile::tempdir().expect("create mobile repository directory");
    let internal = repo.path().join(".areamatrix").join("staging");
    let placeholder = repo.path().join("Document.pdf.icloud");

    let invalid = validate_repo_path(String::new());
    let internal_result = validate_repo_path(path_string(&internal));
    let placeholder_result = validate_repo_path(path_string(&placeholder));

    assert!(matches!(invalid, Err(CoreError::InvalidPath { .. })));
    assert!(matches!(
        internal_result,
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(matches!(
        placeholder_result,
        Err(CoreError::ICloudPlaceholder { .. })
    ));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[cfg(unix)]
#[test]
fn mobile_repo_connect_permission_denied_does_not_create_metadata() {
    use std::os::unix::fs::PermissionsExt;

    let repo = tempfile::tempdir().expect("create readonly mobile repository directory");
    let original_permissions = fs::metadata(repo.path())
        .expect("read repository permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o555);
    fs::set_permissions(repo.path(), readonly_permissions).expect("make repo readonly");

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate readonly directory");
    let result = init_repo(path_string(repo.path()), create_empty_options());

    fs::set_permissions(repo.path(), original_permissions).expect("restore repo permissions");

    assert_eq!(validation.recommended_mode, None);
    assert_eq!(validation.issues, vec![RepoPathIssue::NotWritable]);
    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert!(!repo.path().join(".areamatrix").exists());
}
