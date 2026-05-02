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

fn moved_auto_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Moved,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn moved_selected_directory_options(directory: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Moved,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some(directory.to_owned()),
        override_category: None,
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

fn count_file_rows(repo: &Path, status: &str) -> i64 {
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

fn assert_no_import_side_effects(repo: &Path) {
    assert!(!repo.join("finance").exists());
    assert_eq!(count_file_rows(repo, "active"), 0);
    assert_eq!(count_file_rows(repo, "staging"), 0);
    assert_eq!(change_log_count(repo), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn assert_file_row_matches_move(repo: &Path, file_id: i64, entry_path: &str, source: &Path) {
    let connection = open_db(repo);
    let (path, status, storage_mode, source_path): (String, String, String, Option<String>) =
        connection
            .query_row(
                "SELECT path, status, storage_mode, source_path FROM files WHERE id = ?1",
                [file_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read moved file row");

    assert_eq!(path, entry_path);
    assert_eq!(status, "active");
    assert_eq!(storage_mode, "moved");
    assert_eq!(source_path.as_deref(), Some(path_string(source).as_str()));
}

fn assert_change_log_matches_move(repo: &Path, file_id: i64, source: &Path) {
    let connection = open_db(repo);
    let (action, detail_json): (String, String) = connection
        .query_row(
            "SELECT action, detail_json FROM change_log WHERE file_id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read moved import change log row");
    let detail: Value = serde_json::from_str(&detail_json).expect("parse import detail json");

    assert_eq!(action, "imported");
    assert_eq!(detail["source"], path_string(source));
    assert_eq!(detail["mode"], "moved");
    assert_eq!(detail["category"], "finance");
    assert_eq!(detail["destination"], "selected_directory");
}

#[test]
fn import_move_file_validation_proves_success_fs_db_and_change_log_consistency() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    let source_path = path_string(&source);
    let source_bytes = fs::read(&source).expect("read source before moved import");

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        moved_selected_directory_options("finance/2026"),
    )
    .expect("move file into selected directory");

    assert!(!source.exists(), "moved import should consume source path");
    assert_eq!(entry.path, "finance/2026/invoice.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.storage_mode, StorageMode::Moved);
    assert_eq!(entry.source_path.as_deref(), Some(source_path.as_str()));
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read active moved file"),
        source_bytes
    );

    let listed = list_files(path_string(repo.path()), empty_filter()).expect("list active files");
    assert_eq!(listed, vec![entry.clone()]);
    assert_file_row_matches_move(repo.path(), entry.id, &entry.path, &source);
    assert_change_log_matches_move(repo.path(), entry.id, &source);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_move_file_validation_rejects_metadata_internal_source_without_side_effects() {
    let repo = initialized_repo();
    let source = repo.path().join(".areamatrix/generated/internal.pdf");
    fs::write(&source, b"internal bytes").expect("write internal metadata file");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        moved_auto_options(),
    );

    assert!(matches!(result, Err(CoreError::InvalidPath { .. })));

    assert_eq!(
        fs::read(&source).expect("read internal file after rejected moved import"),
        b"internal bytes"
    );
    assert_no_import_side_effects(repo.path());
}

#[test]
fn import_move_file_validation_rejects_metadata_destination_before_moving_source() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("source.pdf", b"source bytes");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        moved_selected_directory_options(".areamatrix/staging"),
    );

    assert!(matches!(result, Err(CoreError::InvalidPath { .. })));

    assert_eq!(
        fs::read(&source).expect("read source after rejected destination"),
        b"source bytes"
    );
    assert_no_import_side_effects(repo.path());
}

#[test]
fn import_move_file_validation_duplicate_skip_restores_source_and_keeps_existing_state() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    let entry = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        moved_auto_options(),
    )
    .expect("import first moved file");
    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        moved_auto_options(),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == "finance/first.pdf"
        ),
        "duplicate error should report the existing moved path"
    );
    assert_eq!(
        fs::read(repo.path().join(entry.path)).expect("read existing moved file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read restored duplicate source"),
        b"same bytes"
    );
    assert!(!repo.path().join("finance/second.pdf").exists());
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
