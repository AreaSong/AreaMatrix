use std::path::Path;

use area_matrix_core::{
    get_file, init_repo, CoreError, FileOrigin, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_file(repo: &Path, path: &str, status: &str, imported_at: i64) -> i64 {
    let current_name = path.rsplit('/').next().expect("test path has a filename");
    let source_path = format!("/source/{current_name}");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'finance', 2048,
                ?3, 'copied', 'imported', ?4,
                ?5, ?6, ?7
             )",
            params![
                path,
                current_name,
                format!("{imported_at:064x}"),
                source_path,
                imported_at,
                imported_at + 10,
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn insert_indexed_file(repo: &Path, source_path: &str) -> i64 {
    let current_name = source_path
        .rsplit('/')
        .next()
        .expect("test source path has a filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'finance', 512,
                ?3, 'indexed', 'imported', ?1,
                100, 110, 'active'
             )",
            params![source_path, current_name, format!("{:064x}", 512)],
        )
        .expect("insert indexed file row");
    connection.last_insert_rowid()
}

#[test]
fn get_file_detail_implementation_returns_complete_active_file_entry() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "active", 100);

    let entry = get_file(path_string(repo.path()), file_id).expect("get active file detail");

    assert_eq!(entry.id, file_id);
    assert_eq!(entry.path, "finance/report.pdf");
    assert_eq!(entry.original_name, "report.pdf");
    assert_eq!(entry.current_name, "report.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.size_bytes, 2048);
    assert_eq!(entry.hash_sha256, format!("{:064x}", 100));
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some("/source/report.pdf"));
    assert_eq!(entry.imported_at, 100);
    assert_eq!(entry.updated_at, 110);
}

#[test]
fn get_file_detail_implementation_requires_initialized_repo() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");

    let result = get_file(path_string(repo.path()), 1);

    assert_eq!(
        result,
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
}

#[test]
fn get_file_detail_implementation_returns_not_found_for_missing_deleted_or_staging_rows() {
    let repo = initialized_repo();
    let deleted_id = insert_file(repo.path(), "finance/deleted.pdf", "deleted", 10);
    let staging_id = insert_file(repo.path(), "finance/staging.pdf", "staging", 20);

    assert!(matches!(
        get_file(path_string(repo.path()), 999),
        Err(CoreError::FileNotFound { .. })
    ));

    assert!(matches!(
        get_file(path_string(repo.path()), deleted_id),
        Err(CoreError::FileNotFound { .. })
    ));

    assert!(matches!(
        get_file(path_string(repo.path()), staging_id),
        Err(CoreError::FileNotFound { .. })
    ));
}

#[test]
fn get_file_detail_implementation_does_not_probe_indexed_source_path() {
    let repo = initialized_repo();
    let missing_source = repo.path().join("missing-external.pdf");
    let missing_source_path = path_string(&missing_source);
    let file_id = insert_indexed_file(repo.path(), &missing_source_path);

    let entry = get_file(path_string(repo.path()), file_id)
        .expect("get indexed metadata without probing source path");

    assert_eq!(entry.path, missing_source_path);
    assert_eq!(entry.current_name, "missing-external.pdf");
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(entry.source_path.as_deref(), Some(entry.path.as_str()));
}
