use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, import_file, init_repo, CoreError, DuplicateStrategy, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("finance/2026".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_file_with_status(repo: &Path, path: &str, status: &str, imported_at: i64) -> i64 {
    let current_name = path.rsplit('/').next().expect("test path has a filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'finance', 128,
                ?3, 'copied', 'imported', NULL,
                ?4, ?4, ?5
             )",
            params![
                path,
                current_name,
                format!("{imported_at:064x}"),
                imported_at,
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
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

#[test]
fn get_file_detail_validation_returns_complete_active_entry_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"detail bytes");
    let source_bytes = fs::read(&source).expect("read source before import");

    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import copied file for detail validation");
    let before_change_logs = change_log_count(repo.path());

    let detail = get_file(path_string(repo.path()), imported.id).expect("get imported detail");

    assert_eq!(detail, imported);
    assert_eq!(
        fs::read(&source).expect("read source after detail query"),
        source_bytes
    );
    assert_eq!(
        fs::read(repo.path().join(&detail.path)).expect("read repo file after detail query"),
        source_bytes
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), before_change_logs);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn get_file_detail_validation_requires_initialized_repo_and_existing_active_id() {
    let uninitialized_repo = tempfile::tempdir().expect("create uninitialized repository");
    assert_eq!(
        get_file(path_string(uninitialized_repo.path()), 1),
        Err(CoreError::RepoNotInitialized)
    );

    let repo = initialized_repo();
    assert_eq!(
        get_file(path_string(repo.path()), 404),
        Err(CoreError::FileNotFound)
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 0);
    assert_eq!(change_log_count(repo.path()), 0);
}

#[test]
fn get_file_detail_validation_hides_deleted_and_staging_rows() {
    let repo = initialized_repo();
    let deleted_id = insert_file_with_status(repo.path(), "finance/deleted.pdf", "deleted", 10);
    let staging_id = insert_file_with_status(repo.path(), "finance/staging.pdf", "staging", 20);

    assert_eq!(
        get_file(path_string(repo.path()), deleted_id),
        Err(CoreError::FileNotFound)
    );
    assert_eq!(
        get_file(path_string(repo.path()), staging_id),
        Err(CoreError::FileNotFound)
    );
    assert_eq!(count_file_rows(repo.path(), "deleted"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 1);
    assert_eq!(change_log_count(repo.path()), 0);
}

#[test]
fn get_file_detail_validation_maps_metadata_query_failure_to_db_error() {
    let repo = initialized_repo();
    open_db(repo.path())
        .execute_batch("DROP TABLE files;")
        .expect("remove files table to simulate metadata corruption");

    let result = get_file(path_string(repo.path()), 1);

    assert_eq!(result, Err(CoreError::Db));
}
