use std::{fs, path::Path};

use area_matrix_core::{
    create_saved_search, init_repo, run_smart_list, CoreError, CreateSavedSearchRequest,
    OverviewOutput, RepoInitMode, RepoInitOptions, SavedSearchQuery, SearchDiagnosticSeverity,
    SearchFilter, SearchPagination, SearchScope, SearchSort, SearchTagMatchMode, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct SmartListSnapshot {
    saved_searches: Vec<(i64, String, String, i64, i64)>,
    files: Vec<(i64, String, String, String, i64)>,
    change_log_count: i64,
    tag_count: i64,
    note_count: i64,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
    user_file_bytes: Vec<(String, Vec<u8>)>,
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

fn first_page() -> SearchPagination {
    SearchPagination {
        limit: 50,
        offset: 0,
    }
}

fn smart_list_query() -> SavedSearchQuery {
    SavedSearchQuery {
        query: "report".to_owned(),
        filter: SearchFilter {
            scope: SearchScope::CurrentNode,
            current_path: Some("finance".to_owned()),
            category: Some("finance".to_owned()),
            file_kind: Some("pdf".to_owned()),
            tags: vec!["tax".to_owned()],
            tag_match_mode: SearchTagMatchMode::Any,
            imported_after: Some(90),
            imported_before: Some(400),
            modified_after: Some(100),
            modified_before: Some(400),
            storage_mode: Some(StorageMode::Copied),
            include_deleted: Some(false),
        },
        sort: SearchSort::NewestModified,
    }
}

fn create_request(name: &str, query: SavedSearchQuery) -> CreateSavedSearchRequest {
    CreateSavedSearchRequest {
        name: name.to_owned(),
        query,
        icon: Some("magnifyingglass".to_owned()),
        color: Some("blue".to_owned()),
        pinned: false,
    }
}

fn insert_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    storage_mode: &str,
    imported_at: i64,
    updated_at: i64,
) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create parent directory");
    fs::write(&file_path, format!("fixture bytes for {relative_path}"))
        .expect("write fixture file");
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture has filename");

    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 13,
                ?4, ?5, 'imported', NULL,
                ?6, ?7, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
                storage_mode,
                imported_at,
                updated_at,
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 100)",
            params![file_id, tag],
        )
        .expect("insert tag row");
}

fn insert_note(repo: &Path, file_id: i64, content: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at) VALUES (?1, ?2, 200)",
            params![file_id, content],
        )
        .expect("insert note row");
}

fn snapshot(repo: &Path) -> SmartListSnapshot {
    SmartListSnapshot {
        saved_searches: saved_search_rows(repo),
        files: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        tag_count: table_count(repo, "tags"),
        note_count: table_count(repo, "notes"),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_file_bytes: user_file_bytes(repo),
    }
}

fn saved_search_rows(repo: &Path) -> Vec<(i64, String, String, i64, i64)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT id, name, query_json, created_at, updated_at FROM saved_searches ORDER BY id",
        )
        .expect("prepare saved search rows query");
    statement
        .query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
            ))
        })
        .expect("query saved search rows")
        .map(|row| row.expect("read saved search row"))
        .collect()
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String, i64)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status, updated_at FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
            ))
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

fn user_file_bytes(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_file_bytes(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

fn collect_user_file_bytes(repo: &Path, current: &Path, files: &mut Vec<(String, Vec<u8>)>) {
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
        if path.is_dir() {
            collect_user_file_bytes(repo, &path, files);
        } else {
            files.push((relative, fs::read(&path).expect("read user fixture file")));
        }
    }
}

fn assert_snapshot_unchanged(repo: &Path, before: &SmartListSnapshot) {
    assert_eq!(&snapshot(repo), before);
}

#[test]
fn smart_list_implementation_runs_saved_query_with_search_results_shape() {
    let repo = initialized_repo();
    let newest = insert_file(
        repo.path(),
        "finance/new-report.pdf",
        "finance",
        "copied",
        150,
        320,
    );
    let older = insert_file(
        repo.path(),
        "finance/old-report.pdf",
        "finance",
        "copied",
        120,
        220,
    );
    let wrong_category = insert_file(
        repo.path(),
        "docs/new-report.pdf",
        "docs",
        "copied",
        160,
        330,
    );
    let wrong_kind = insert_file(
        repo.path(),
        "finance/report.md",
        "finance",
        "copied",
        170,
        340,
    );
    insert_tag(repo.path(), newest, "tax");
    insert_tag(repo.path(), older, "tax");
    insert_tag(repo.path(), wrong_category, "tax");
    insert_tag(repo.path(), wrong_kind, "tax");
    insert_note(repo.path(), newest, "quarterly report packet");
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Finance Reports", smart_list_query()),
    )
    .expect("create smart list");
    let before = snapshot(repo.path());

    let first = run_smart_list(
        path_string(repo.path()),
        saved.id,
        SearchPagination {
            limit: 1,
            offset: 0,
        },
    )
    .expect("run first smart list page");
    let second = run_smart_list(
        path_string(repo.path()),
        saved.id,
        SearchPagination {
            limit: 1,
            offset: 1,
        },
    )
    .expect("run second smart list page");

    assert_eq!(first.query, "report");
    assert_eq!(first.total_count, 2);
    assert_eq!(first.results.len(), 1);
    assert_eq!(first.results[0].entry.id, newest);
    assert_eq!(second.results.len(), 1);
    assert_eq!(second.results[0].entry.id, older);
    assert!(first.diagnostics.is_empty());
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_list_implementation_maps_missing_id_to_file_not_found_without_writes() {
    let repo = initialized_repo();
    insert_file(
        repo.path(),
        "finance/new-report.pdf",
        "finance",
        "copied",
        150,
        320,
    );
    let before = snapshot(repo.path());

    let error = run_smart_list(path_string(repo.path()), 404, first_page())
        .expect_err("missing smart list should fail");

    assert!(matches!(error, CoreError::FileNotFound { .. }));
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_list_implementation_reports_saved_query_diagnostics_without_writes() {
    let repo = initialized_repo();
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Diagnostic Smart List", smart_list_query()),
    )
    .expect("create smart list");
    open_db(repo.path())
        .execute(
            "UPDATE saved_searches
                SET query_json = json_set(query_json, '$.query', ?1)
              WHERE id = ?2",
            params!["kindd:pdf", saved.id],
        )
        .expect("inject saved query diagnostic fixture");
    let before = snapshot(repo.path());

    let page = run_smart_list(path_string(repo.path()), saved.id, first_page())
        .expect("diagnostic smart list returns a result page");

    assert_eq!(page.total_count, 0);
    assert!(page
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == SearchDiagnosticSeverity::Error));
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_list_implementation_rejects_unrepresentable_saved_filter_without_writes() {
    let repo = initialized_repo();
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Bad Filter Smart List", smart_list_query()),
    )
    .expect("create smart list");
    open_db(repo.path())
        .execute(
            "UPDATE saved_searches
                SET query_json = json_set(query_json, '$.filter.current_path', NULL)
              WHERE id = ?1",
            params![saved.id],
        )
        .expect("inject invalid saved filter fixture");
    let before = snapshot(repo.path());

    let error = run_smart_list(path_string(repo.path()), saved.id, first_page())
        .expect_err("invalid saved filter should fail");

    assert!(matches!(error, CoreError::Config { .. }));
    assert_snapshot_unchanged(repo.path(), &before);
}
