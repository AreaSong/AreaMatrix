use std::{fs, path::Path};

use area_matrix_core::{
    create_saved_search, delete_saved_search, init_repo, list_saved_searches, run_smart_list,
    update_saved_search, CoreError, CoreResult, CreateSavedSearchRequest, ErrorKind,
    ErrorRecoverability, ErrorSeverity, OverviewOutput, RepoInitMode, RepoInitOptions, SavedSearch,
    SavedSearchQuery, SearchFilter, SearchPagination, SearchResultPage, SearchScope, SearchSort,
    SearchTagMatchMode, StorageMode, UpdateSavedSearchRequest,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-03-saved-search-crud.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const SEARCH_RS: &str = include_str!("../src/search.rs");
const SAVED_SEARCH_RS: &str = include_str!("../src/search/saved_search.rs");
const DB_SAVED_SEARCH_RS: &str = include_str!("../src/db/saved_search.rs");
const DB_MOD_RS: &str = include_str!("../src/db/mod.rs");

#[derive(Debug, Eq, PartialEq)]
struct SavedSearchValidationSnapshot {
    saved_searches: Vec<(i64, String, String, i64)>,
    files: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    tags_count: i64,
    notes_count: i64,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
    user_visible_paths: Vec<String>,
}

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
            tags: vec!["tax".to_owned(), "signed".to_owned()],
            tag_match_mode: SearchTagMatchMode::All,
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

fn update_request(id: i64, name: &str) -> UpdateSavedSearchRequest {
    UpdateSavedSearchRequest {
        id,
        name: name.to_owned(),
        query: saved_query(),
        icon: Some("folder".to_owned()),
        color: Some("green".to_owned()),
        pinned: true,
    }
}

fn snapshot(repo: &Path) -> SavedSearchValidationSnapshot {
    SavedSearchValidationSnapshot {
        saved_searches: saved_search_rows(repo),
        files: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        tags_count: table_count(repo, "tags"),
        notes_count: table_count(repo, "notes"),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn saved_search_rows(repo: &Path) -> Vec<(i64, String, String, i64)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, name, query_json, pinned FROM saved_searches ORDER BY id")
        .expect("prepare saved search rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query saved search rows")
        .map(|row| row.expect("read saved search row"))
        .collect()
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count metadata rows")
}

fn relative_directory_entries(repo: &Path, path: &Path) -> Vec<String> {
    let mut entries: Vec<String> = fs::read_dir(path)
        .expect("read metadata directory")
        .map(|entry| {
            entry
                .expect("read metadata entry")
                .path()
                .strip_prefix(repo)
                .expect("metadata path is inside repository")
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    entries.sort();
    entries
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repository")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn insert_active_file(repo: &Path) {
    let file_path = repo.join("finance/2026/invoice.pdf");
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, b"saved search validation fixture").expect("write fixture file");

    open_db(repo)
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                'finance/2026/invoice.pdf', 'invoice.pdf', 'invoice.pdf', 'finance', 31,
                ?1, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![format!("{:064x}", 1)],
        )
        .expect("insert active file row");
}

fn assert_config_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Config");
    assert!(matches!(error, CoreError::Config { .. }));
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, ErrorKind::Config);
    assert_eq!(mapping.severity, ErrorSeverity::Medium);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn saved_search_validation_covers_successful_crud_and_ui_recovery_state() {
    let repo = initialized_repo();
    insert_active_file(repo.path());
    let before = snapshot(repo.path());

    let first = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create first saved search");
    let second = create_saved_search(path_string(repo.path()), create_request("Invoices"))
        .expect("create second saved search");

    let mut edited_query = saved_query();
    edited_query.query = "receipt".to_owned();
    edited_query.filter.tags = vec!["tax".to_owned()];
    edited_query.sort = SearchSort::NameAsc;
    let updated = update_saved_search(
        path_string(repo.path()),
        UpdateSavedSearchRequest {
            id: second.id,
            name: "Pinned Receipts".to_owned(),
            query: edited_query.clone(),
            icon: None,
            color: Some("green".to_owned()),
            pinned: true,
        },
    )
    .expect("update saved search");

    assert_eq!(updated.id, second.id);
    assert_eq!(updated.query, edited_query);
    assert!(updated.pinned);
    assert_eq!(updated.created_at, second.created_at);

    let listed = list_saved_searches(path_string(repo.path())).expect("list saved searches");
    assert_eq!(
        listed.iter().map(|saved| saved.id).collect::<Vec<_>>(),
        vec![updated.id, first.id]
    );
    assert_eq!(listed[0].name, "Pinned Receipts");
    assert_eq!(
        listed[0].query.filter.current_path.as_deref(),
        Some("finance/2026")
    );
    assert_eq!(listed[0].query.sort, SearchSort::NameAsc);

    delete_saved_search(path_string(repo.path()), updated.id).expect("delete saved search");
    let remaining = list_saved_searches(path_string(repo.path())).expect("list after delete");
    assert_eq!(remaining, vec![first]);

    let after = snapshot(repo.path());
    assert_eq!(after.files, before.files);
    assert_eq!(after.change_log_count, before.change_log_count);
    assert_eq!(after.tags_count, before.tags_count);
    assert_eq!(after.notes_count, before.notes_count);
    assert_eq!(after.staging_entries, before.staging_entries);
    assert_eq!(after.generated_entries, before.generated_entries);
    assert_eq!(after.user_visible_paths, before.user_visible_paths);
}

#[test]
fn saved_search_validation_covers_failed_validation_and_persistence_paths_without_writes() {
    let repo = initialized_repo();
    insert_active_file(repo.path());
    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create baseline saved search");
    let before = snapshot(repo.path());

    assert_config_error(create_saved_search(
        path_string(repo.path()),
        create_request("finance pdfs"),
    ));

    let mut invalid_query = create_request("Bad query");
    invalid_query.query.query = "kindd:pdf".to_owned();
    assert_config_error(create_saved_search(path_string(repo.path()), invalid_query));

    let mut invalid_filter = create_request("Bad filter");
    invalid_filter.query.filter.imported_after = Some(200);
    invalid_filter.query.filter.imported_before = Some(100);
    assert_config_error(create_saved_search(
        path_string(repo.path()),
        invalid_filter,
    ));

    let mut invalid_update = update_request(saved.id, "Bad display metadata");
    invalid_update.icon = Some(" ".to_owned());
    assert_config_error(update_saved_search(
        path_string(repo.path()),
        invalid_update,
    ));

    assert_config_error(delete_saved_search(path_string(repo.path()), 0));
    assert_config_error(list_saved_searches(String::new()));
    assert_db_error(update_saved_search(
        path_string(repo.path()),
        update_request(404, "Missing"),
    ));
    assert_db_error(delete_saved_search(path_string(repo.path()), 404));

    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER saved_search_validation_abort_update
               BEFORE UPDATE ON saved_searches
               BEGIN
                 SELECT RAISE(ABORT, 'forced saved_search update failure');
               END;",
        )
        .expect("install saved search update failure trigger");
    assert_db_error(update_saved_search(
        path_string(repo.path()),
        update_request(saved.id, "Blocked update"),
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_validation_locks_core_api_udl_rust_and_docs_alignment() {
    fn assert_create(_: fn(String, CreateSavedSearchRequest) -> CoreResult<SavedSearch>) {}
    fn assert_update(_: fn(String, UpdateSavedSearchRequest) -> CoreResult<SavedSearch>) {}
    fn assert_delete(_: fn(String, i64) -> CoreResult<()>) {}
    fn assert_list(_: fn(String) -> CoreResult<Vec<SavedSearch>>) {}
    fn assert_run(_: fn(String, i64, SearchPagination) -> CoreResult<SearchResultPage>) {}

    assert_create(create_saved_search);
    assert_update(update_saved_search);
    assert_delete(delete_saved_search);
    assert_list(list_saved_searches);
    assert_run(run_smart_list);

    for fragment in [
        "# C2-03 saved-search-crud",
        "`create_saved_search`",
        "`update_saved_search`",
        "`delete_saved_search`",
        "`list_saved_searches`",
        "名称、query、filters、sort、scope。",
        "SavedSearch 记录。",
        "删除 Smart List 只删除保存查询，不删除任何文件。",
        "名称重复、非法 query、保存失败都有结构化错误。",
        "保存后可在 sidebar 恢复同一搜索条件。",
        "共享 Smart List 和跨端同步属于 Stage 4。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-03 | saved-search-sheet | C2-03 | saved search CRUD | saved_searches",
        "| S2-06 | smart-lists | C2-03, C2-04 | run/list smart lists | saved_searches",
        "搜索、filter、Smart List 不得移动、删除或改名文件。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "SavedSearch create_saved_search(string repo_path, CreateSavedSearchRequest request);",
        "SavedSearch update_saved_search(string repo_path, UpdateSavedSearchRequest request);",
        "void delete_saved_search(string repo_path, i64 saved_search_id);",
        "sequence<SavedSearch> list_saved_searches(string repo_path);",
        "SearchResultPage run_smart_list(",
        "SearchPagination pagination",
        "dictionary SavedSearchQuery",
        "string query;",
        "SearchFilter filter;",
        "SearchSort sort;",
        "dictionary CreateSavedSearchRequest",
        "string name;",
        "SavedSearchQuery query;",
        "string? icon;",
        "string? color;",
        "boolean pinned;",
        "dictionary UpdateSavedSearchRequest",
        "i64 id;",
        "dictionary SavedSearch",
        "i64 created_at;",
        "i64 updated_at;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub use saved_search::{",
        "create_saved_search",
        "delete_saved_search",
        "list_saved_searches",
        "update_saved_search",
        "run_smart_list",
        "CreateSavedSearchRequest",
        "SavedSearchQuery",
        "UpdateSavedSearchRequest",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for fragment in [
        "pub fn create_saved_search(",
        "pub fn update_saved_search(",
        "pub fn delete_saved_search(",
        "pub fn list_saved_searches(",
        "This API does not execute Smart Lists",
        "must not delete, move, rename, trash",
        "Returns `CoreError::Config { reason }`",
        "Returns `CoreError::Db { message }`",
        "db::create_saved_search_row",
        "db::update_saved_search_row",
        "db::delete_saved_search_row",
        "db::list_saved_search_rows",
    ] {
        assert_contains(SAVED_SEARCH_RS, fragment);
    }

    for fragment in [
        "CREATE TABLE IF NOT EXISTS saved_searches",
        "name TEXT NOT NULL COLLATE NOCASE UNIQUE",
        "query_json TEXT NOT NULL",
        "pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1))",
        "idx_saved_searches_sidebar",
    ] {
        assert_contains(DB_MOD_RS, fragment);
    }

    for fragment in [
        "INSERT INTO saved_searches",
        "UPDATE saved_searches",
        "DELETE FROM saved_searches",
        "ORDER BY pinned DESC",
        "lower(name) END ASC",
        "saved search name must be unique",
        "saved search name already exists",
    ] {
        assert_contains(DB_SAVED_SEARCH_RS, fragment);
    }
}
