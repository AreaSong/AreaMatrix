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

fn copied_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
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

fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active files")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

#[test]
fn import_copy_file_implementation_copies_source_to_active_file_and_logs_change() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");

    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import copied file");

    assert_eq!(fs::read(&source).expect("read source"), b"invoice bytes");
    assert_eq!(entry.path, "finance/invoice.pdf");
    assert_eq!(entry.original_name, "invoice.pdf");
    assert_eq!(entry.current_name, "invoice.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(
        entry.source_path.as_deref(),
        Some(path_string(&source).as_str())
    );
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read imported file"),
        b"invoice bytes"
    );

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list files");
    assert_eq!(files, vec![entry.clone()]);

    let connection = open_db(repo.path());
    let status: String = connection
        .query_row(
            "SELECT status FROM files WHERE id = ?1",
            [entry.id],
            |row| row.get(0),
        )
        .expect("read file status");
    assert_eq!(status, "active");

    let (action, detail_json): (String, String) = connection
        .query_row(
            "SELECT action, detail_json FROM change_log WHERE file_id = ?1",
            [entry.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read import change log");
    assert_eq!(action, "imported");
    let detail: Value = serde_json::from_str(&detail_json).expect("parse detail json");
    assert_eq!(detail["source"], path_string(&source));
    assert_eq!(detail["mode"], "copied");
    assert_eq!(detail["category"], "finance");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["by"], "user");
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_copy_file_implementation_duplicate_hash_returns_error_without_new_rows() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(),
    )
    .expect("import first file");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == "finance/first.pdf"
        ),
        "duplicate error should report the existing imported path"
    );
    assert_eq!(
        fs::read(&source_b).expect("read duplicate source"),
        b"same bytes"
    );
    assert_eq!(active_file_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_copy_file_implementation_name_conflict_does_not_overwrite_existing_file() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"first content");
    let (_source_root_b, source_b) = source_file("second.pdf", b"second content");
    let mut options = copied_options();
    options.override_filename = Some("same.pdf".to_owned());

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        options.clone(),
    )
    .expect("import first file");
    let result = import_file(path_string(repo.path()), path_string(&source_b), options);

    assert_eq!(result, Err(CoreError::Conflict));
    assert_eq!(
        fs::read(repo.path().join(first.path)).expect("read first imported file"),
        b"first content"
    );
    assert_eq!(
        fs::read(&source_b).expect("read second source"),
        b"second content"
    );
    assert_eq!(active_file_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_copy_file_implementation_invalid_filename_leaves_no_file_or_db_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("source.pdf", b"content");
    let mut options = copied_options();
    options.override_filename = Some("bad/name.pdf".to_owned());

    let result = import_file(path_string(repo.path()), path_string(&source), options);

    assert_eq!(result, Err(CoreError::InvalidPath));
    assert_eq!(fs::read(&source).expect("read source"), b"content");
    assert!(!repo.path().join("finance").exists());
    assert_eq!(active_file_count(repo.path()), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_copy_file_implementation_indexed_mode_does_not_create_copy() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("source.pdf", b"content");
    let mut options = copied_options();
    options.mode = StorageMode::Indexed;

    let entry = import_file(path_string(repo.path()), path_string(&source), options)
        .expect("indexed mode is implemented by C1-08");

    assert_eq!(fs::read(&source).expect("read source"), b"content");
    assert_eq!(entry.path, path_string(&source));
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert!(!repo.path().join("finance/source.pdf").exists());
    assert_eq!(active_file_count(repo.path()), 1);
}
