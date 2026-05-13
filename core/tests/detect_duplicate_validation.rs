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

mod support;
use support::system_trash_home::with_test_system_trash;

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

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn active_paths_for_hash(repo: &Path, hash: &str) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT path FROM files
             WHERE hash_sha256 = ?1 AND status = 'active'
             ORDER BY path ASC",
        )
        .expect("prepare active hash path query");
    statement
        .query_map([hash], |row| row.get::<_, String>(0))
        .expect("query active hash paths")
        .map(|row| row.expect("read active hash path"))
        .collect()
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

fn change_log_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = ?2",
            (file_id, action),
            |row| row.get(0),
        )
        .expect("read change log detail json");
    serde_json::from_str(&detail_json).expect("parse change log detail")
}

fn assert_clean_duplicate_state(repo: &Path, active: i64, deleted: i64, change_logs: i64) {
    assert_eq!(count_file_rows(repo, "active"), active);
    assert_eq!(count_file_rows(repo, "deleted"), deleted);
    assert_eq!(count_file_rows(repo, "staging"), 0);
    assert_eq!(change_log_count(repo), change_logs);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

#[test]
fn detect_duplicate_validation_skip_and_ask_return_existing_path_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");

    for strategy in [DuplicateStrategy::Skip, DuplicateStrategy::Ask] {
        let result = import_file(
            path_string(repo.path()),
            path_string(&source_b),
            copied_options(strategy),
        );
        assert_eq!(
            result,
            Err(CoreError::DuplicateFile {
                existing_path: first.path.clone()
            })
        );
    }

    assert_eq!(
        fs::read(&source_b).expect("read duplicate source after rejected imports"),
        b"same bytes"
    );
    assert!(!repo.path().join("finance/second.pdf").exists());
    assert_clean_duplicate_state(repo.path(), 1, 0, 1);

    let listed = list_files(path_string(repo.path()), empty_filter()).expect("list active files");
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].path, first.path);
}

#[test]
fn detect_duplicate_validation_keep_both_creates_distinct_active_paths_with_same_hash() {
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
    .expect("keep both duplicate file");

    assert_eq!(first.hash_sha256, second.hash_sha256);
    assert_eq!(first.path, "finance/report.pdf");
    assert_eq!(second.path, "finance/report_1.pdf");
    assert_eq!(
        active_paths_for_hash(repo.path(), &first.hash_sha256),
        vec!["finance/report.pdf", "finance/report_1.pdf"]
    );
    assert_eq!(
        fs::read(repo.path().join(&first.path)).expect("read first duplicate final file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&second.path)).expect("read numbered duplicate final file"),
        b"same bytes"
    );
    assert_clean_duplicate_state(repo.path(), 2, 0, 2);
}

#[test]
fn detect_duplicate_validation_overwrite_archives_old_file_and_logs_replacement() {
    with_test_system_trash(|trash_dir| {
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
        .expect("overwrite duplicate after user confirmation");

        assert_eq!(replacement.path, first.path);
        assert_ne!(replacement.id, first.id);
        assert_eq!(
            fs::read(repo.path().join(&replacement.path)).expect("read replacement final file"),
            b"same bytes"
        );
        assert_eq!(
            fs::read(&source_b).expect("read copied source after overwrite"),
            b"same bytes"
        );

        let (old_status, archived_path) = file_status_and_path(repo.path(), first.id);
        assert_eq!(old_status, "deleted");
        assert!(archived_path.starts_with("system-trash://replace-"));
        assert!(!repo.path().join(".areamatrix/trash").exists());
        assert_clean_duplicate_state(repo.path(), 1, 1, 3);

        let deleted_detail = change_log_detail(repo.path(), first.id, "deleted");
        assert_eq!(deleted_detail["reason"], "duplicate_overwrite");
        assert_eq!(deleted_detail["from_path"], "finance/report.pdf");
        assert_eq!(deleted_detail["archived_path"], archived_path);
        assert_eq!(deleted_detail["trash_location"], "system");
        assert_eq!(deleted_detail["trashed"], true);
        assert_eq!(
            fs::read(trash_dir.join("report.pdf")).expect("read old file from system Trash"),
            b"same bytes"
        );
        let imported_detail = change_log_detail(repo.path(), replacement.id, "imported");
        assert_eq!(imported_detail["duplicate_strategy"], "overwrite");
        assert_eq!(imported_detail["replaced_file_id"], first.id);
        assert_eq!(imported_detail["replaced_path"], "finance/report.pdf");
    });
}
