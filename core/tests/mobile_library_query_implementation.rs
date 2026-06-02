use std::{fs, path::Path};

use area_matrix_core::{
    get_file, init_repo, list_changes, list_files, list_tree_json, ChangeFilter, CoreError,
    FileAvailabilityStatus, FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn default_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 50,
        offset: 0,
    }
}

fn default_change_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 50,
        offset: 0,
    }
}

fn write_repo_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let file_path = repo.join(relative_path);
    if let Some(parent) = file_path.parent() {
        fs::create_dir_all(parent).expect("create fixture parent directory");
    }
    fs::write(file_path, content).expect("write fixture file");
}

fn insert_file(repo: &Path, path: &str, category: &str, imported_at: i64) -> i64 {
    insert_file_row(repo, path, category, imported_at, true)
}

fn insert_missing_file_row(repo: &Path, path: &str, category: &str, imported_at: i64) -> i64 {
    insert_file_row(repo, path, category, imported_at, false)
}

fn insert_file_row(
    repo: &Path,
    path: &str,
    category: &str,
    imported_at: i64,
    write_file: bool,
) -> i64 {
    let current_name = path.rsplit('/').next().expect("test path has a filename");
    if write_file {
        write_repo_file(repo, path, format!("content-{imported_at}").as_bytes());
    }

    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, ?4,
                ?5, 'copied', 'imported', NULL,
                ?6, ?7, 'active'
             )",
            params![
                path,
                current_name,
                category,
                100 + imported_at,
                format!("{imported_at:064x}"),
                imported_at,
                imported_at + 1,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn insert_change(repo: &Path, file_id: i64, action: &str, detail: &str, occurred_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![file_id, action, detail, occurred_at],
        )
        .expect("insert change-log row");
}

fn metadata_counts(repo: &Path) -> (i64, i64) {
    let connection = open_db(repo);
    let file_count = connection
        .query_row("SELECT COUNT(*) FROM files", [], |row| row.get(0))
        .expect("count file rows");
    let change_count = connection
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows");
    (file_count, change_count)
}

fn file_bytes(repo: &Path, relative_path: &str) -> Vec<u8> {
    fs::read(repo.join(relative_path)).expect("read user fixture file")
}

fn parse_tree(tree_json: &str) -> Value {
    serde_json::from_str(tree_json).expect("parse C4-03 tree JSON")
}

fn child_slugs(node: &Value) -> Vec<&str> {
    node["children"]
        .as_array()
        .expect("TreeNode children should be an array")
        .iter()
        .map(|child| child["slug"].as_str().expect("child slug should be string"))
        .collect()
}

#[test]
fn mobile_library_query_implementation_paginates_rows_and_opens_core_detail() {
    let repo = initialized_repo();
    insert_file(repo.path(), "docs/old.pdf", "docs", 10);
    let middle_id = insert_file(repo.path(), "docs/middle.pdf", "docs", 20);
    insert_file(repo.path(), "finance/new.pdf", "finance", 30);
    let before_counts = metadata_counts(repo.path());
    let before_middle = file_bytes(repo.path(), "docs/middle.pdf");

    let mut first_page = default_file_filter();
    first_page.limit = 2;
    let files = list_files(path_string(repo.path()), first_page).expect("list first mobile page");

    assert_eq!(
        files
            .iter()
            .map(|file| file.current_name.as_str())
            .collect::<Vec<_>>(),
        vec!["new.pdf", "middle.pdf"]
    );

    let mut second_docs_page = default_file_filter();
    second_docs_page.category = Some("docs".to_owned());
    second_docs_page.limit = 1;
    second_docs_page.offset = 1;
    let files =
        list_files(path_string(repo.path()), second_docs_page).expect("list paged docs rows");

    assert_eq!(
        files
            .iter()
            .map(|file| file.current_name.as_str())
            .collect::<Vec<_>>(),
        vec!["old.pdf"]
    );

    let detail = get_file(path_string(repo.path()), middle_id).expect("open Core-backed detail");
    assert_eq!(detail.id, middle_id);
    assert_eq!(detail.path, "docs/middle.pdf");
    assert_eq!(detail.current_name, "middle.pdf");
    assert_eq!(detail.storage_mode, StorageMode::Copied);
    assert_eq!(
        detail.availability_status,
        FileAvailabilityStatus::Available
    );

    let tree = parse_tree(
        &list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list mobile tree"),
    );
    assert_eq!(tree["file_count"], 3);
    assert_eq!(child_slugs(&tree), vec!["docs", "finance"]);

    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(file_bytes(repo.path(), "docs/middle.pdf"), before_middle);
}

#[test]
fn mobile_library_query_implementation_lazily_pages_change_log_without_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/report.pdf", "docs", 10);
    for (action, occurred_at) in [
        ("imported", 100),
        ("renamed", 200),
        ("moved", 300),
        ("external_modified", 400),
    ] {
        insert_change(
            repo.path(),
            file_id,
            action,
            r#"{"source":"mobile-library-query-test"}"#,
            occurred_at,
        );
    }
    let before_counts = metadata_counts(repo.path());
    let before_report = file_bytes(repo.path(), "docs/report.pdf");

    let mut filter = default_change_filter();
    filter.file_id = Some(file_id);
    filter.limit = 2;
    filter.offset = 1;

    let changes =
        list_changes(path_string(repo.path()), filter).expect("list mobile detail log page");

    assert_eq!(
        changes
            .iter()
            .map(|change| change.action.as_str())
            .collect::<Vec<_>>(),
        vec!["moved", "renamed"]
    );
    assert_eq!(
        changes
            .iter()
            .map(|change| change.file_id)
            .collect::<Vec<_>>(),
        vec![Some(file_id), Some(file_id)]
    );

    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(file_bytes(repo.path(), "docs/report.pdf"), before_report);
}

#[test]
fn mobile_library_query_implementation_preserves_missing_rows_for_recovery_entry() {
    let repo = initialized_repo();
    let missing_id = insert_missing_file_row(repo.path(), "docs/missing.pdf", "docs", 50);
    insert_change(
        repo.path(),
        missing_id,
        "imported",
        r#"{"source":"missing-fixture.pdf"}"#,
        500,
    );
    let before_counts = metadata_counts(repo.path());

    let mut filter = default_file_filter();
    filter.category = Some("docs".to_owned());
    let files = list_files(path_string(repo.path()), filter).expect("list missing metadata row");

    assert_eq!(files.len(), 1);
    assert_eq!(files[0].id, missing_id);
    assert_eq!(files[0].path, "docs/missing.pdf");
    assert_eq!(
        files[0].availability_status,
        FileAvailabilityStatus::Missing
    );
    assert!(!repo.path().join(&files[0].path).exists());

    let detail =
        get_file(path_string(repo.path()), missing_id).expect("open missing metadata detail");
    assert_eq!(detail.id, missing_id);
    assert_eq!(detail.current_name, "missing.pdf");
    assert_eq!(detail.availability_status, FileAvailabilityStatus::Missing);

    let changes =
        list_changes(path_string(repo.path()), default_change_filter()).expect("list missing log");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].file_id, Some(missing_id));

    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert!(!repo.path().join("docs/missing.pdf").exists());
}

#[test]
fn mobile_library_query_implementation_maps_uninitialized_repo_consistently() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");

    assert_eq!(
        list_files(path_string(repo.path()), default_file_filter()),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
    assert_eq!(
        get_file(path_string(repo.path()), 1),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
    assert_eq!(
        list_changes(path_string(repo.path()), default_change_filter()),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
    assert_eq!(
        list_tree_json(path_string(repo.path()), "en".to_owned()),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
}
