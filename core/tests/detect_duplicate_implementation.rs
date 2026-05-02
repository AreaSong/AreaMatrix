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

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn copied_options(strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: strategy,
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

fn file_status_and_path(repo: &Path, file_id: i64) -> (String, String) {
    open_db(repo)
        .query_row(
            "SELECT status, path FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read file status and path")
}

fn change_log_actions(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT action FROM change_log ORDER BY id ASC")
        .expect("prepare change log action query");
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query change log actions")
        .map(|row| row.expect("read change log action"))
        .collect()
}

fn change_log_detail(repo: &Path, file_id: i64, action: &str) -> serde_json::Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = ?2",
            (file_id, action),
            |row| row.get(0),
        )
        .expect("read change log detail json");
    serde_json::from_str(&detail_json).expect("parse change log detail")
}

fn install_deleted_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_deleted_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'deleted'
             BEGIN
                 SELECT RAISE(FAIL, 'forced deleted change log failure');
             END;",
        )
        .expect("install deleted change log failure trigger");
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

#[test]
fn detect_duplicate_ask_returns_existing_path_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::Ask),
    );

    assert_eq!(
        result,
        Err(CoreError::DuplicateFile {
            existing_path: first.path
        })
    );
    assert_eq!(
        fs::read(&source_b).expect("read duplicate source after ask result"),
        b"same bytes"
    );
    assert!(!repo.path().join("finance/second.pdf").exists());
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn detect_duplicate_keep_both_auto_numbers_when_target_name_matches_existing() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("report.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");
    let second = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::KeepBoth),
    )
    .expect("keep both duplicate with same target name");

    assert_eq!(first.path, "finance/report.pdf");
    assert_eq!(second.path, "finance/report_1.pdf");
    assert_eq!(first.hash_sha256, second.hash_sha256);
    assert_eq!(
        fs::read(repo.path().join(&second.path)).expect("read numbered duplicate final"),
        b"same bytes"
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 2);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 2);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn detect_duplicate_keep_both_does_not_mask_same_name_different_content_conflict() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"first bytes");
    let (_source_root_b, source_b) = source_file("report.pdf", b"second bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");
    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::KeepBoth),
    );

    assert_eq!(result, Err(CoreError::Conflict));
    assert_eq!(
        fs::read(repo.path().join(first.path)).expect("read original final"),
        b"first bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read rejected conflicting source"),
        b"second bytes"
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list active files");
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].path, "finance/report.pdf");
}

#[test]
fn detect_duplicate_overwrite_replaces_existing_entry_with_change_log() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("replacement.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");
    let replacement = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::Overwrite),
    )
    .expect("overwrite duplicate file after user confirmation");

    assert_eq!(replacement.path, first.path);
    assert_ne!(replacement.id, first.id);
    assert_eq!(
        fs::read(repo.path().join(&replacement.path)).expect("read replacement final file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read copied replacement source"),
        b"same bytes"
    );

    let (old_status, archived_path) = file_status_and_path(repo.path(), first.id);
    assert_eq!(old_status, "deleted");
    assert!(archived_path.starts_with(".areamatrix/trash/replace-"));
    assert_eq!(
        fs::read(repo.path().join(&archived_path)).expect("read archived replaced file"),
        b"same bytes"
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(
        change_log_actions(repo.path()),
        vec!["imported", "deleted", "imported"]
    );
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let deleted_detail = change_log_detail(repo.path(), first.id, "deleted");
    assert_eq!(deleted_detail["reason"], "duplicate_overwrite");
    assert_eq!(deleted_detail["from_path"], "finance/report.pdf");
    assert_eq!(deleted_detail["archived_path"], archived_path);
    let import_detail = change_log_detail(repo.path(), replacement.id, "imported");
    assert_eq!(import_detail["duplicate_strategy"], "overwrite");
    assert_eq!(import_detail["replaced_file_id"], first.id);
}

#[test]
fn detect_duplicate_overwrite_rolls_back_when_deleted_change_log_fails() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("replacement.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");
    install_deleted_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::Overwrite),
    );

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        fs::read(repo.path().join(first.path)).expect("read restored original final file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read replacement source after rollback"),
        b"same bytes"
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
