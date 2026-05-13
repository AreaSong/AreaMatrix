use std::path::Path;

use area_matrix_core::{
    init_repo, list_files, CoreError, FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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

fn list_filter() -> FileFilter {
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

fn insert_file(repo: &Path, path: &str, category: &str, imported_at: i64, status: &str) {
    let current_name = path.rsplit('/').next().unwrap_or(path);
    open_db(repo)
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 1,
                ?4, 'copied', 'imported', NULL,
                ?5, ?5, ?6
             )",
            params![
                path,
                current_name,
                category,
                format!("{imported_at:064x}"),
                imported_at,
                status,
            ],
        )
        .expect("insert file row");
}

fn seed_many_active_files(repo: &Path, count: i64) {
    let mut connection = open_db(repo);
    let tx = connection.transaction().expect("start seed transaction");
    {
        let mut statement = tx
            .prepare(
                "INSERT INTO files (
                    path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path,
                    imported_at, updated_at, status
                 ) VALUES (
                    ?1, ?2, ?2, 'docs', 1,
                    ?3, 'copied', 'imported', NULL,
                    ?4, ?4, 'active'
                 )",
            )
            .expect("prepare seed insert");

        for index in 0..count {
            let current_name = format!("file-{index}.txt");
            let path = format!("docs/{current_name}");
            statement
                .execute(params![path, current_name, format!("{index:064x}"), index])
                .expect("insert seeded active file");
        }
    }
    tx.commit().expect("commit seeded files");
}

fn current_names(files: &[area_matrix_core::FileEntry]) -> Vec<&str> {
    files
        .iter()
        .map(|file| file.current_name.as_str())
        .collect()
}

#[test]
fn list_files_validation_empty_repo_returns_empty_array() {
    let repo = initialized_repo();

    let files = list_files(path_string(repo.path()), list_filter()).expect("list empty repo");

    assert_eq!(files, Vec::new());
}

#[test]
fn list_files_validation_filters_orders_paginates_and_hides_deleted_by_default() {
    let repo = initialized_repo();
    insert_file(repo.path(), "finance/old.pdf", "finance", 10, "active");
    insert_file(repo.path(), "finance/window-a.pdf", "finance", 20, "active");
    insert_file(repo.path(), "finance/window-b.pdf", "finance", 30, "active");
    insert_file(repo.path(), "finance/deleted.pdf", "finance", 40, "deleted");
    insert_file(repo.path(), "finance/staging.pdf", "finance", 50, "staging");
    insert_file(repo.path(), "docs/window.pdf", "docs", 35, "active");

    let mut filter = list_filter();
    filter.category = Some("finance".to_owned());
    filter.imported_after = Some(20);
    filter.imported_before = Some(50);
    filter.limit = 1;
    filter.offset = 1;

    let files = list_files(path_string(repo.path()), filter).expect("list filtered active files");

    assert_eq!(current_names(&files), vec!["window-a.pdf"]);

    let mut include_deleted = list_filter();
    include_deleted.category = Some("finance".to_owned());
    include_deleted.include_deleted = Some(true);

    let visible =
        list_files(path_string(repo.path()), include_deleted).expect("list deleted metadata");

    assert_eq!(
        current_names(&visible),
        vec!["deleted.pdf", "window-b.pdf", "window-a.pdf", "old.pdf"]
    );
}

#[test]
fn list_files_validation_clamps_limit_to_one_thousand() {
    let repo = initialized_repo();
    seed_many_active_files(repo.path(), 1001);

    let mut filter = list_filter();
    filter.limit = 10_000;

    let files = list_files(path_string(repo.path()), filter).expect("list clamped files");

    assert_eq!(files.len(), 1000);
    assert_eq!(
        files.first().map(|file| file.current_name.as_str()),
        Some("file-1000.txt")
    );
    assert_eq!(
        files.last().map(|file| file.current_name.as_str()),
        Some("file-1.txt")
    );
}

#[test]
fn list_files_validation_requires_initialized_repo() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");

    let result = list_files(path_string(repo.path()), list_filter());

    assert_eq!(
        result,
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
}

#[test]
fn list_files_validation_maps_unreadable_metadata_query_to_db_error() {
    let repo = initialized_repo();
    open_db(repo.path())
        .execute_batch("DROP TABLE files;")
        .expect("remove files table to simulate metadata corruption");

    let result = list_files(path_string(repo.path()), list_filter());

    assert!(matches!(result, Err(CoreError::Db { .. })));
}
