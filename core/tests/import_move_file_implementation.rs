use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, CoreError, DuplicateStrategy, FileFilter,
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

fn moved_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Moved,
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

fn count_rows(repo: &Path, table: &str, status: Option<&str>) -> i64 {
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
            "CREATE TRIGGER fail_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced import change log failure');
             END;",
        )
        .expect("install import change-log failure trigger");
}

#[test]
fn import_move_file_implementation_moves_source_to_active_file_and_logs_change() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    let source_path = path_string(&source);

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        moved_options(),
    )
    .expect("import moved file");

    assert!(!source.exists(), "source path should be removed after move");
    assert_eq!(entry.path, "finance/invoice.pdf");
    assert_eq!(entry.original_name, "invoice.pdf");
    assert_eq!(entry.current_name, "invoice.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.storage_mode, StorageMode::Moved);
    assert_eq!(entry.source_path.as_deref(), Some(source_path.as_str()));
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read moved final file"),
        b"invoice bytes"
    );

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list files");
    assert_eq!(files, vec![entry.clone()]);

    let connection = open_db(repo.path());
    let (status, storage_mode, source_path_db): (String, String, Option<String>) = connection
        .query_row(
            "SELECT status, storage_mode, source_path FROM files WHERE id = ?1",
            [entry.id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read imported file row");
    assert_eq!(status, "active");
    assert_eq!(storage_mode, "moved");
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
    assert_eq!(detail["mode"], "moved");
    assert_eq!(detail["category"], "finance");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["by"], "user");
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_move_file_implementation_duplicate_hash_restores_source_without_new_rows() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    import_file(
        path_string(repo.path()),
        path_string(&source_a),
        moved_options(),
    )
    .expect("import first moved file");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        moved_options(),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == "finance/first.pdf"
        ),
        "duplicate error should report the existing moved path"
    );
    assert_eq!(
        fs::read(&source_b).expect("read restored duplicate source"),
        b"same bytes"
    );
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 1);
    assert_eq!(count_rows(repo.path(), "files", Some("staging")), 0);
    assert_eq!(count_rows(repo.path(), "change_log", None), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_move_file_implementation_name_conflict_restores_source_and_existing_file() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"first content");
    let (_source_root_b, source_b) = source_file("second.pdf", b"second content");
    let mut options = moved_options();
    options.override_filename = Some("same.pdf".to_owned());

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        options.clone(),
    )
    .expect("import first moved file");
    let result = import_file(path_string(repo.path()), path_string(&source_b), options);

    assert_eq!(result, Err(CoreError::Conflict));
    assert_eq!(
        fs::read(repo.path().join(first.path)).expect("read first imported file"),
        b"first content"
    );
    assert_eq!(
        fs::read(&source_b).expect("read restored conflicting source"),
        b"second content"
    );
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 1);
    assert_eq!(count_rows(repo.path(), "files", Some("staging")), 0);
    assert_eq!(count_rows(repo.path(), "change_log", None), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_move_file_implementation_db_failure_restores_source_and_cleans_final_state() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        moved_options(),
    );

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        fs::read(&source).expect("read source restored after DB failure"),
        b"invoice bytes"
    );
    assert!(!repo.path().join("finance/invoice.pdf").exists());
    assert!(!repo.path().join("finance").exists());
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 0);
    assert_eq!(count_rows(repo.path(), "files", Some("staging")), 0);
    assert_eq!(count_rows(repo.path(), "change_log", None), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
