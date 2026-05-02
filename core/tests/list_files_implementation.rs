use std::path::Path;

use area_matrix_core::{
    init_repo, list_files, CoreError, FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions,
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

fn default_filter() -> FileFilter {
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

fn insert_indexed_file(repo: &Path, source_path: &str, imported_at: i64) {
    let current_name = source_path.rsplit('/').next().unwrap_or(source_path);
    open_db(repo)
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'finance', 1,
                ?3, 'indexed', 'imported', ?1,
                ?4, ?4, 'active'
             )",
            params![
                source_path,
                current_name,
                format!("{imported_at:064x}"),
                imported_at,
            ],
        )
        .expect("insert indexed file row");
}

#[test]
fn list_files_implementation_empty_repo_returns_empty_array() {
    let repo = initialized_repo();

    let files = list_files(path_string(repo.path()), default_filter()).expect("list empty repo");

    assert_eq!(files, Vec::new());
}

#[test]
fn list_files_implementation_requires_initialized_repo() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");

    let result = list_files(path_string(repo.path()), default_filter());

    assert_eq!(result, Err(CoreError::RepoNotInitialized));
}

#[test]
fn list_files_implementation_does_not_probe_indexed_source_paths() {
    let repo = initialized_repo();
    let missing_source = repo.path().join("missing-external.pdf");
    let missing_source_path = path_string(&missing_source);
    insert_indexed_file(repo.path(), &missing_source_path, 40);

    let files = list_files(path_string(repo.path()), default_filter())
        .expect("list indexed metadata without probing source path");

    assert_eq!(files.len(), 1);
    assert_eq!(files[0].path, missing_source_path);
    assert_eq!(files[0].current_name, "missing-external.pdf");
    assert_eq!(files[0].storage_mode, StorageMode::Indexed);
    assert_eq!(
        files[0].source_path.as_deref(),
        Some(files[0].path.as_str())
    );
}

#[test]
fn list_files_implementation_excludes_deleted_and_staging_by_default() {
    let repo = initialized_repo();
    insert_file(repo.path(), "finance/active.pdf", "finance", 30, "active");
    insert_file(repo.path(), "finance/deleted.pdf", "finance", 20, "deleted");
    insert_file(repo.path(), "finance/staging.pdf", "finance", 10, "staging");

    let active_only =
        list_files(path_string(repo.path()), default_filter()).expect("list active files");

    assert_eq!(names(&active_only), vec!["active.pdf"]);

    let mut include_deleted = default_filter();
    include_deleted.include_deleted = Some(true);
    let visible_deleted =
        list_files(path_string(repo.path()), include_deleted).expect("list deleted files");

    assert_eq!(names(&visible_deleted), vec!["active.pdf", "deleted.pdf"]);
}

#[test]
fn list_files_implementation_filters_by_category_and_import_time_window() {
    let repo = initialized_repo();
    insert_file(repo.path(), "finance/old.pdf", "finance", 10, "active");
    insert_file(repo.path(), "finance/window.pdf", "finance", 20, "active");
    insert_file(repo.path(), "finance/boundary.pdf", "finance", 30, "active");
    insert_file(repo.path(), "docs/window.pdf", "docs", 25, "active");
    insert_file(repo.path(), "finance/new.pdf", "finance", 40, "active");

    let mut filter = default_filter();
    filter.category = Some("finance".to_owned());
    filter.imported_after = Some(20);
    filter.imported_before = Some(30);

    let files = list_files(path_string(repo.path()), filter).expect("list filtered files");

    assert_eq!(names(&files), vec!["window.pdf"]);
}

#[test]
fn list_files_implementation_orders_by_imported_at_desc_and_paginates() {
    let repo = initialized_repo();
    insert_file(repo.path(), "docs/old.pdf", "docs", 10, "active");
    insert_file(repo.path(), "docs/middle.pdf", "docs", 20, "active");
    insert_file(repo.path(), "docs/new.pdf", "docs", 30, "active");

    let mut filter = default_filter();
    filter.limit = 1;
    filter.offset = 1;

    let files = list_files(path_string(repo.path()), filter).expect("list paged files");

    assert_eq!(names(&files), vec!["middle.pdf"]);
}

#[test]
fn list_files_implementation_clamps_limit_to_one_thousand_rows() {
    let repo = initialized_repo();
    seed_many_active_files(repo.path(), 1001);

    let mut filter = default_filter();
    filter.limit = 2000;

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

fn names(files: &[area_matrix_core::FileEntry]) -> Vec<&str> {
    files
        .iter()
        .map(|file| file.current_name.as_str())
        .collect()
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
