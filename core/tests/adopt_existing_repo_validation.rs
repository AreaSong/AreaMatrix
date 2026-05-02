use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, resume_scan_session, CoreError, FileFilter,
    FileOrigin, OverviewOutput, RepoInitMode, RepoInitOptions, ScanSessionKind, ScanSessionStatus,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn adopt_options() -> RepoInitOptions {
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

#[test]
fn adopt_existing_repo_validation_proves_filesystem_and_db_consistency() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme = repo.path().join("README.md");
    let docs = repo.path().join("docs");
    let spec = docs.join("spec.txt");
    let root_overview = repo.path().join("AREAMATRIX.md");
    fs::create_dir(&docs).expect("create docs directory");
    fs::write(&readme, "# User project\n").expect("write user README");
    fs::write(&spec, "spec content\n").expect("write user document");
    fs::write(&root_overview, "user-authored overview\n").expect("write user overview");
    let before = snapshot_user_files(&[&readme, &spec, &root_overview]);

    init_repo(path_string(repo.path()), adopt_options()).expect("adopt existing repository");

    assert_eq!(
        snapshot_user_files(&[&readme, &spec, &root_overview]),
        before
    );
    assert!(repo.path().join(".areamatrix/generated/root.md").is_file());
    assert!(foreign_key_check(repo.path()).is_empty());

    let mut files =
        list_files(path_string(repo.path()), empty_filter()).expect("list adopted files");
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
        .expect("read latest scan session")
        .expect("adopt scan session should exist");
    assert_eq!(session.kind, ScanSessionKind::Adopt);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.inserted, 2);
    assert_eq!(session.updated, 0);
    assert_eq!(session.errors, Vec::<String>::new());
}

#[test]
fn adopt_existing_repo_validation_rejects_root_overview_without_metadata_side_effects() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "# User project\n").expect("write user README");
    let mut options = adopt_options();
    options.overview_output = OverviewOutput::RootAreaMatrixFile;

    let result = init_repo(path_string(repo.path()), options);

    assert!(matches!(result, Err(CoreError::Config { .. })));

    assert_eq!(
        fs::read_to_string(&readme).expect("read preserved README"),
        "# User project\n"
    );
    assert!(!repo.path().join(".areamatrix").exists());
    assert!(!repo.path().join("AREAMATRIX.md").exists());
}

#[test]
fn adopt_existing_repo_validation_unknown_resume_session_does_not_mutate_user_files() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "# User project\n").expect("write user README");
    init_repo(path_string(repo.path()), adopt_options()).expect("adopt existing repository");
    let before = fs::read_to_string(&readme).expect("read README before resume failure");

    let result = resume_scan_session(path_string(repo.path()), i64::MAX);

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(
        fs::read_to_string(&readme).expect("read README after resume failure"),
        before
    );
    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("adopt scan session should still exist");
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert!(foreign_key_check(repo.path()).is_empty());
}

fn snapshot_user_files(paths: &[&PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                (*path).clone(),
                fs::read(path).expect("read user file snapshot"),
            )
        })
        .collect()
}

fn foreign_key_check(repo_path: &Path) -> Vec<String> {
    let connection =
        Connection::open(repo_path.join(".areamatrix/index.db")).expect("open repository db");
    let mut statement = connection
        .prepare("PRAGMA foreign_key_check")
        .expect("prepare foreign key check");
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("run foreign key check");
    rows.map(|row| row.expect("read foreign key check row"))
        .collect()
}
