use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, CoreError, DuplicateStrategy, FileFilter, FileOrigin,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn indexed_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Indexed,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
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

fn file_count(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count file rows by status")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
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
            "CREATE TRIGGER fail_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced import change log failure');
             END;",
        )
        .expect("install import change-log failure trigger");
}

fn assert_no_index_side_effects(repo: &Path) {
    assert!(!repo.join("finance").exists());
    assert_eq!(file_count(repo, "active"), 0);
    assert_eq!(file_count(repo, "staging"), 0);
    assert_eq!(change_log_count(repo), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

#[test]
fn import_index_file_implementation_records_external_reference_without_copying() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    let source_path = path_string(&source);

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        indexed_options(),
    )
    .expect("index external file");

    assert_eq!(fs::read(&source).expect("read source"), b"invoice bytes");
    assert!(!repo.path().join("finance").exists());
    assert_eq!(entry.path, source_path);
    assert_eq!(entry.original_name, "invoice.pdf");
    assert_eq!(entry.current_name, "invoice.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(source_path.as_str()));

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list files");
    assert_eq!(files, vec![entry.clone()]);

    let connection = open_db(repo.path());
    let (status, storage_mode, path, source_path_db): (String, String, String, Option<String>) =
        connection
            .query_row(
                "SELECT status, storage_mode, path, source_path FROM files WHERE id = ?1",
                [entry.id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read indexed file row");
    assert_eq!(status, "active");
    assert_eq!(storage_mode, "indexed");
    assert_eq!(path, source_path);
    assert_eq!(source_path_db.as_deref(), Some(source_path.as_str()));

    let (action, detail_json): (String, String) = connection
        .query_row(
            "SELECT action, detail_json FROM change_log WHERE file_id = ?1",
            [entry.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read import change log");
    assert_eq!(action, "imported");
    let detail: Value = serde_json::from_str(&detail_json).expect("parse detail json");
    assert_eq!(detail["source"], source_path);
    assert_eq!(detail["mode"], "indexed");
    assert_eq!(detail["category"], "finance");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["by"], "user");
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_index_file_implementation_duplicate_hash_leaves_source_and_db_unchanged() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    import_file(
        path_string(repo.path()),
        path_string(&source_a),
        indexed_options(),
    )
    .expect("index first source");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        indexed_options(),
    );

    let existing_path = path_string(&source_a);
    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path: reported }) if reported == existing_path
        ),
        "duplicate error should report the indexed source path"
    );
    assert_eq!(
        fs::read(&source_b).expect("read duplicate source"),
        b"same bytes"
    );
    assert!(!repo.path().join("finance").exists());
    assert_eq!(file_count(repo.path(), "active"), 1);
    assert_eq!(file_count(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_index_file_implementation_db_failure_rolls_back_metadata_only() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"index rollback");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(
        fs::read(&source).expect("read source after DB failure"),
        b"index rollback"
    );
    assert_no_index_side_effects(repo.path());
}

#[test]
fn import_index_file_implementation_rejects_missing_source_without_side_effects() {
    let repo = initialized_repo();
    let missing = repo.path().join("missing.pdf");

    let result = import_file(
        path_string(repo.path()),
        path_string(&missing),
        indexed_options(),
    );

    assert!(matches!(result, Err(CoreError::FileNotFound { .. })));

    assert_no_index_side_effects(repo.path());
}

#[test]
fn import_index_file_implementation_list_files_keeps_missing_indexed_source_metadata() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("listed.pdf", b"listed bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    )
    .expect("index external file");

    fs::remove_file(&source).expect("remove indexed source fixture");

    let files = list_files(path_string(repo.path()), empty_filter())
        .expect("list indexed metadata after source removal");

    assert_eq!(files, vec![entry]);
    assert_eq!(file_count(repo.path(), "active"), 1);
    assert_eq!(change_log_count(repo.path()), 1);
}
