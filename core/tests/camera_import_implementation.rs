use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, CoreError, DuplicateStrategy, FileAvailabilityStatus,
    FileFilter, FileOrigin, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

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

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn captured_photo(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let camera_temp = tempfile::tempdir().expect("create platform camera temp directory");
    let source_path = camera_temp.path().join(name);
    fs::write(&source_path, content).expect("write captured photo fixture");
    (camera_temp, source_path)
}

fn camera_import_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("photos".to_owned()),
        override_filename: Some("Photo 2026-04-29 1130.jpg".to_owned()),
        duplicate_strategy: DuplicateStrategy::KeepBoth,
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn row_count(repo: &Path, table: &str, status: Option<&str>) -> i64 {
    let connection = open_db(repo);
    match status {
        Some(status) => connection
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE status = ?1"),
                [status],
                |row| row.get(0),
            )
            .expect("count rows by status"),
        None => connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .expect("count rows"),
    }
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn install_import_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_camera_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced camera import metadata failure');
             END;",
        )
        .expect("install camera import metadata failure trigger");
}

#[test]
fn camera_import_implementation_copies_platform_temp_photo_into_repo() {
    let repo = initialized_repo();
    let (_camera_temp, source) = captured_photo("capture.jpg", b"captured photo bytes");
    let source_path = path_string(&source);

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        camera_import_options(),
    )
    .expect("import captured camera photo");

    assert_eq!(
        fs::read(&source).expect("read platform temp photo"),
        b"captured photo bytes"
    );
    assert_eq!(entry.path, "photos/Photo 2026-04-29 1130.jpg");
    assert_eq!(entry.original_name, "capture.jpg");
    assert_eq!(entry.current_name, "Photo 2026-04-29 1130.jpg");
    assert_eq!(entry.category, "photos");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(source_path.as_str()));
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read copied repo photo"),
        b"captured photo bytes"
    );

    fs::remove_file(&source).expect("platform can clean camera temp photo");
    assert!(
        repo.path().join(&entry.path).is_file(),
        "Core must not tie final repo file lifetime to the platform temp file"
    );

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list mobile library");
    assert_eq!(files, vec![entry.clone()]);

    let (status, storage_mode, source_path_db): (String, String, Option<String>) =
        open_db(repo.path())
            .query_row(
                "SELECT status, storage_mode, source_path FROM files WHERE id = ?1",
                [entry.id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("read imported camera file row");
    assert_eq!(status, "active");
    assert_eq!(storage_mode, "copied");
    assert_eq!(source_path_db.as_deref(), Some(source_path.as_str()));

    let (action, detail_json): (String, String) = open_db(repo.path())
        .query_row(
            "SELECT action, detail_json FROM change_log WHERE file_id = ?1",
            [entry.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read camera import change log");
    assert_eq!(action, "imported");
    let detail: Value = serde_json::from_str(&detail_json).expect("parse import detail json");
    assert_eq!(detail["source"], source_path);
    assert_eq!(detail["mode"], "copied");
    assert_eq!(detail["category"], "photos");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["requested_name"], "Photo 2026-04-29 1130.jpg");
    assert_eq!(detail["final_path"], entry.path);
    assert_eq!(detail["by"], "user");

    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn camera_import_implementation_cancel_without_core_call_writes_no_metadata() {
    let repo = initialized_repo();
    let (_camera_temp, source) = captured_photo("cancelled.jpg", b"cancelled photo bytes");

    assert_eq!(
        fs::read(&source).expect("read cancelled platform temp photo"),
        b"cancelled photo bytes"
    );
    assert_eq!(row_count(repo.path(), "files", None), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!repo.path().join("photos").exists());
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn camera_import_implementation_db_failure_keeps_temp_and_existing_repo_files() {
    let repo = initialized_repo();
    let (_first_temp, first_source) = captured_photo("first.jpg", b"existing photo bytes");
    let first = import_file(
        path_string(repo.path()),
        path_string(&first_source),
        camera_import_options(),
    )
    .expect("import existing camera photo");
    let first_file = repo.path().join(&first.path);
    let first_before = fs::read(&first_file).expect("read existing repo photo");

    let (_failed_temp, failed_source) = captured_photo("second.jpg", b"failed photo bytes");
    install_import_change_log_failure(repo.path());
    let result = import_file(
        path_string(repo.path()),
        path_string(&failed_source),
        camera_import_options(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(&failed_source).expect("read failed platform temp photo"),
        b"failed photo bytes"
    );
    assert_eq!(
        fs::read(&first_file).expect("read existing repo photo after failed import"),
        first_before
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 1);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 1);
    assert!(!repo
        .path()
        .join("photos/Photo 2026-04-29 1130_1.jpg")
        .exists());
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn camera_import_implementation_invalid_temp_path_writes_no_db_or_files() {
    let repo = initialized_repo();
    let missing = repo.path().join(".areamatrix/staging/camera-temp.jpg");

    let result = import_file(
        path_string(repo.path()),
        path_string(&missing),
        camera_import_options(),
    );

    assert!(matches!(result, Err(CoreError::InvalidPath { .. })));
    assert_eq!(row_count(repo.path(), "files", None), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!repo.path().join("photos").exists());
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
