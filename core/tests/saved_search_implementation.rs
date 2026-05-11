use std::{fs, path::Path};

use area_matrix_core::{
    create_saved_search, delete_saved_search, init_repo, list_saved_searches, update_saved_search,
    CoreError, CreateSavedSearchRequest, OverviewOutput, RepoInitMode, RepoInitOptions,
    SavedSearchQuery, SearchFilter, SearchScope, SearchSort, SearchTagMatchMode, StorageMode,
    UpdateSavedSearchRequest,
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

fn saved_query() -> SavedSearchQuery {
    SavedSearchQuery {
        query: "invoice OR receipt".to_owned(),
        filter: SearchFilter {
            scope: SearchScope::CurrentNode,
            current_path: Some("finance/2026".to_owned()),
            category: Some("finance".to_owned()),
            file_kind: Some("pdf".to_owned()),
            tags: vec!["tax".to_owned()],
            tag_match_mode: SearchTagMatchMode::Any,
            imported_after: Some(100),
            imported_before: Some(200),
            modified_after: Some(120),
            modified_before: Some(220),
            storage_mode: Some(StorageMode::Copied),
            include_deleted: Some(false),
        },
        sort: SearchSort::NewestModified,
    }
}

fn create_request(name: &str) -> CreateSavedSearchRequest {
    CreateSavedSearchRequest {
        name: name.to_owned(),
        query: saved_query(),
        icon: Some("magnifyingglass".to_owned()),
        color: Some("blue".to_owned()),
        pinned: false,
    }
}

fn saved_search_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM saved_searches", [], |row| row.get(0))
        .expect("count saved searches")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
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

fn insert_active_file(repo: &Path) -> i64 {
    let file_path = repo.join("finance/invoice.pdf");
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, b"fixture bytes").expect("write fixture file");

    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                'finance/invoice.pdf', 'invoice.pdf', 'invoice.pdf', 'finance', 13,
                ?1, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![format!("{:064x}", 1)],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

#[test]
fn saved_search_implementation_persists_and_restores_full_query_state() {
    let repo = initialized_repo();

    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");

    assert!(saved.id > 0);
    assert_eq!(saved.name, "Finance PDFs");
    assert_eq!(saved.query, saved_query());
    assert_eq!(saved.icon.as_deref(), Some("magnifyingglass"));
    assert_eq!(saved.color.as_deref(), Some("blue"));
    assert!(!saved.pinned);
    assert!(saved.created_at > 0);
    assert!(saved.updated_at >= saved.created_at);

    let listed = list_saved_searches(path_string(repo.path())).expect("list saved searches");
    assert_eq!(listed, vec![saved]);
    assert_eq!(saved_search_count(repo.path()), 1);
    assert_eq!(change_log_count(repo.path()), 0);
}

#[test]
fn saved_search_implementation_updates_deletes_and_never_touches_files() {
    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path());
    let first = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create first saved search");
    let second = create_saved_search(path_string(repo.path()), create_request("Invoices"))
        .expect("create second");

    let mut updated_query = saved_query();
    updated_query.query = "receipt".to_owned();
    updated_query.sort = SearchSort::NameAsc;
    let updated = update_saved_search(
        path_string(repo.path()),
        UpdateSavedSearchRequest {
            id: second.id,
            name: "Pinned Receipts".to_owned(),
            query: updated_query.clone(),
            icon: None,
            color: Some("green".to_owned()),
            pinned: true,
        },
    )
    .expect("update saved search");

    assert_eq!(updated.id, second.id);
    assert_eq!(updated.name, "Pinned Receipts");
    assert_eq!(updated.query, updated_query);
    assert!(updated.pinned);
    assert_eq!(updated.created_at, second.created_at);
    assert!(updated.updated_at >= second.updated_at);

    let listed = list_saved_searches(path_string(repo.path())).expect("list saved searches");
    assert_eq!(
        listed.iter().map(|item| item.id).collect::<Vec<_>>(),
        vec![second.id, first.id]
    );

    delete_saved_search(path_string(repo.path()), updated.id).expect("delete saved search");
    let remaining =
        list_saved_searches(path_string(repo.path())).expect("list remaining saved searches");
    assert_eq!(
        remaining.iter().map(|item| item.id).collect::<Vec<_>>(),
        vec![first.id]
    );
    assert_eq!(saved_search_count(repo.path()), 1);
    assert_eq!(active_file_count(repo.path()), 1);
    assert!(repo.path().join("finance/invoice.pdf").is_file());
    assert_eq!(change_log_count(repo.path()), 0);

    let file_still_active: i64 = open_db(repo.path())
        .query_row(
            "SELECT COUNT(*) FROM files WHERE id = ?1 AND status = 'active'",
            [file_id],
            |row| row.get(0),
        )
        .expect("count active fixture file");
    assert_eq!(file_still_active, 1);
}

#[test]
fn saved_search_implementation_rejects_duplicate_names_invalid_query_and_missing_rows() {
    let repo = initialized_repo();
    create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");

    let duplicate = create_saved_search(path_string(repo.path()), create_request("finance pdfs"));
    assert!(matches!(duplicate, Err(CoreError::Config { .. })));
    assert_eq!(saved_search_count(repo.path()), 1);

    let mut invalid_query = create_request("Bad query");
    invalid_query.query.query = "kindd:pdf".to_owned();
    let invalid = create_saved_search(path_string(repo.path()), invalid_query);
    assert!(matches!(invalid, Err(CoreError::Config { .. })));
    assert_eq!(saved_search_count(repo.path()), 1);

    let mut invalid_scope = create_request("Bad scope");
    invalid_scope.query.filter.scope = SearchScope::CurrentNode;
    invalid_scope.query.filter.current_path = None;
    let invalid = create_saved_search(path_string(repo.path()), invalid_scope);
    assert!(matches!(invalid, Err(CoreError::Config { .. })));
    assert_eq!(saved_search_count(repo.path()), 1);

    let missing_update = update_saved_search(
        path_string(repo.path()),
        UpdateSavedSearchRequest {
            id: 404,
            name: "Missing".to_owned(),
            query: saved_query(),
            icon: None,
            color: None,
            pinned: false,
        },
    );
    assert!(matches!(missing_update, Err(CoreError::Db { .. })));

    let missing_delete = delete_saved_search(path_string(repo.path()), 404);
    assert!(matches!(missing_delete, Err(CoreError::Db { .. })));
    assert_eq!(saved_search_count(repo.path()), 1);
}

#[test]
fn saved_search_implementation_sorts_pinned_first_then_unpinned_by_name() {
    let repo = initialized_repo();
    let mut b = create_request("Bravo");
    b.pinned = false;
    let b = create_saved_search(path_string(repo.path()), b).expect("create bravo");

    let mut a = create_request("Alpha");
    a.pinned = false;
    let a = create_saved_search(path_string(repo.path()), a).expect("create alpha");

    let mut pinned = create_request("Pinned");
    pinned.pinned = true;
    let pinned = create_saved_search(path_string(repo.path()), pinned).expect("create pinned");

    let listed = list_saved_searches(path_string(repo.path())).expect("list saved searches");
    assert_eq!(
        listed.iter().map(|item| item.id).collect::<Vec<_>>(),
        vec![pinned.id, a.id, b.id]
    );
}

#[test]
fn saved_search_implementation_propagates_db_failures_as_structured_db_errors() {
    let repo = initialized_repo();
    open_db(repo.path())
        .execute("DROP TABLE saved_searches", [])
        .expect("drop saved_searches table");
    open_db(repo.path())
        .execute(
            "CREATE TABLE saved_searches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                query_json TEXT NOT NULL,
                pinned INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )",
            [],
        )
        .expect("create incompatible saved_searches table");

    let result = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"));

    assert!(matches!(result, Err(CoreError::Db { .. })));
}
