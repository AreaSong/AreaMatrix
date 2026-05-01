use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{validate_repo_path, CoreError, RepoInitMode, RepoPathIssue};
use pretty_assertions::assert_eq;
use tempfile::TempDir;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

#[test]
fn validate_repo_path_recommends_create_empty_for_empty_directory() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate empty directory");

    assert!(validation.exists);
    assert!(validation.is_directory);
    assert!(validation.is_readable);
    assert!(validation.is_writable);
    assert!(validation.is_empty);
    assert!(!validation.is_initialized);
    assert!(!validation.is_inside_area_matrix);
    assert!(!validation.is_icloud_path);
    assert!(!validation.has_unfinished_scan_session);
    assert_eq!(validation.recommended_mode, Some(RepoInitMode::CreateEmpty));
    assert_eq!(validation.issues, Vec::<RepoPathIssue>::new());
}

#[test]
fn validate_repo_path_recommends_adopt_existing_without_touching_files() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let user_file = repo.path().join("README.md");
    fs::write(&user_file, "owned by user").expect("write user file");

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate non-empty directory");

    assert!(user_file.exists());
    assert!(!repo.path().join(".areamatrix").exists());
    assert!(!validation.is_empty);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(validation.issues, vec![RepoPathIssue::NonEmptyDirectory]);
}

#[test]
fn validate_repo_path_reports_initialized_repository_without_recommending_init() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    fs::create_dir(repo.path().join(".areamatrix")).expect("create metadata directory");

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate initialized directory");

    assert!(validation.is_empty);
    assert!(validation.is_initialized);
    assert_eq!(validation.recommended_mode, None);
    assert_eq!(validation.issues, vec![RepoPathIssue::AlreadyInitialized]);
}

#[test]
fn validate_repo_path_rejects_area_matrix_internal_paths() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let internal_path = repo.path().join(".areamatrix").join("staging");

    let result = validate_repo_path(path_string(&internal_path));

    assert_eq!(result, Err(CoreError::InvalidPath));
}

#[test]
fn validate_repo_path_reports_missing_path_as_structured_issue() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let missing_path = repo.path().join("missing");

    let validation = validate_repo_path(path_string(&missing_path)).expect("validate missing path");

    assert!(!validation.exists);
    assert_eq!(validation.recommended_mode, None);
    assert_eq!(validation.issues, vec![RepoPathIssue::MissingPath]);
}

#[test]
fn validate_repo_path_reports_regular_file_as_not_directory() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let file_path = repo.path().join("file.txt");
    fs::write(&file_path, "not a directory").expect("write regular file");

    let validation = validate_repo_path(path_string(&file_path)).expect("validate regular file");

    assert!(validation.exists);
    assert!(!validation.is_directory);
    assert_eq!(validation.recommended_mode, None);
    assert_eq!(validation.issues, vec![RepoPathIssue::NotDirectory]);
}

#[test]
fn validate_repo_path_rejects_icloud_placeholder_marker() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let placeholder = repo.path().join("Document.pdf.icloud");

    let result = validate_repo_path(path_string(&placeholder));

    assert_eq!(result, Err(CoreError::ICloudPlaceholder));
}

#[test]
fn validate_repo_path_reports_unfinished_scan_session_from_existing_metadata() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let metadata_dir = repo.path().join(".areamatrix");
    fs::create_dir(&metadata_dir).expect("create metadata directory");
    let db_path = metadata_dir.join("index.db");
    create_scan_session_db(&db_path, "running");

    let validation =
        validate_repo_path(path_string(repo.path())).expect("validate scan session state");

    assert!(validation.is_initialized);
    assert!(validation.has_unfinished_scan_session);
    assert_eq!(validation.recommended_mode, None);
    assert_eq!(
        validation.issues,
        vec![
            RepoPathIssue::AlreadyInitialized,
            RepoPathIssue::UnfinishedScanSession,
        ]
    );
}

#[cfg(unix)]
#[test]
fn validate_repo_path_reports_not_writable_without_creating_probe_files() {
    use std::os::unix::fs::PermissionsExt;

    let readonly_repo = ReadonlyTempDir::new();

    let validation =
        validate_repo_path(path_string(readonly_repo.path())).expect("validate read-only path");

    assert!(validation.exists);
    assert!(validation.is_directory);
    assert!(!validation.is_writable);
    assert_eq!(validation.recommended_mode, None);
    assert_eq!(validation.issues, vec![RepoPathIssue::NotWritable]);
    assert_eq!(
        fs::read_dir(readonly_repo.path())
            .expect("list read-only directory")
            .count(),
        0
    );

    drop(readonly_repo);

    struct ReadonlyTempDir {
        dir: TempDir,
        original_mode: u32,
    }

    impl ReadonlyTempDir {
        fn new() -> Self {
            let dir = tempfile::tempdir().expect("create temporary repository directory");
            let original_mode = fs::metadata(dir.path())
                .expect("read original permissions")
                .permissions()
                .mode();
            let mut permissions = fs::metadata(dir.path())
                .expect("read permissions before readonly")
                .permissions();
            permissions.set_mode(0o555);
            fs::set_permissions(dir.path(), permissions).expect("set readonly permissions");
            Self { dir, original_mode }
        }

        fn path(&self) -> &Path {
            self.dir.path()
        }
    }

    impl Drop for ReadonlyTempDir {
        fn drop(&mut self) {
            let mut permissions = fs::metadata(self.dir.path())
                .expect("read permissions before restore")
                .permissions();
            permissions.set_mode(self.original_mode);
            fs::set_permissions(self.dir.path(), permissions).expect("restore permissions");
        }
    }
}

fn create_scan_session_db(path: &PathBuf, status: &str) {
    let connection = rusqlite::Connection::open(path).expect("open scan session database");
    connection
        .execute(
            "CREATE TABLE scan_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                started_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                finished_at INTEGER,
                last_path TEXT,
                inserted INTEGER NOT NULL DEFAULT 0,
                updated INTEGER NOT NULL DEFAULT 0,
                skipped INTEGER NOT NULL DEFAULT 0,
                errors_json TEXT NOT NULL DEFAULT '[]'
            )",
            [],
        )
        .expect("create scan_sessions table");
    connection
        .execute(
            "INSERT INTO scan_sessions (
                kind, status, started_at, updated_at, inserted, updated, skipped, errors_json
            ) VALUES ('adopt', ?1, 1, 1, 0, 0, 0, '[]')",
            [status],
        )
        .expect("insert scan session");
}
