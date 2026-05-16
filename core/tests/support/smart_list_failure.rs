use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, CoreError, CreateSavedSearchRequest, ErrorKind, ErrorRecoverability, OverviewOutput,
    RepoInitMode, RepoInitOptions, SavedSearchQuery, SearchFilter, SearchPagination, SearchScope,
    SearchSort, SearchTagMatchMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct SmartListFailureSnapshot {
    saved_searches: Vec<SavedSearchRow>,
    pub(crate) files: Vec<(i64, String, String, String, i64)>,
    change_log_count: i64,
    tag_count: i64,
    note_count: i64,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
    user_file_bytes: Vec<(String, Vec<u8>)>,
}

#[derive(Debug, Eq, PartialEq)]
struct SavedSearchRow {
    id: i64,
    name: String,
    query_json: String,
    icon: Option<String>,
    color: Option<String>,
    pinned: i64,
    created_at: i64,
    updated_at: i64,
}

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn initialized_repo() -> tempfile::TempDir {
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

pub(crate) fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub(crate) fn first_page() -> SearchPagination {
    SearchPagination {
        limit: 50,
        offset: 0,
    }
}

fn default_filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: None,
        file_kind: None,
        tags: Vec::new(),
        tag_match_mode: SearchTagMatchMode::Any,
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: None,
        include_deleted: Some(false),
    }
}

pub(crate) fn smart_list_query() -> SavedSearchQuery {
    SavedSearchQuery {
        query: "report".to_owned(),
        filter: default_filter(),
        sort: SearchSort::Relevance,
    }
}

pub(crate) fn create_request(name: &str, query: SavedSearchQuery) -> CreateSavedSearchRequest {
    CreateSavedSearchRequest {
        name: name.to_owned(),
        query,
        icon: Some("magnifyingglass".to_owned()),
        color: Some("blue".to_owned()),
        pinned: false,
    }
}

pub(crate) fn insert_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
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
                ?4, 'copied', 'imported', NULL,
                100, 120, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

pub(crate) fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 100)",
            params![file_id, tag],
        )
        .expect("insert tag row");
}

pub(crate) fn insert_note(repo: &Path, file_id: i64, content: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at) VALUES (?1, ?2, 200)",
            params![file_id, content],
        )
        .expect("insert note row");
}

pub(crate) fn insert_change(repo: &Path, file_id: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, 'renamed', '{\"from\":\"draft\",\"to\":\"report\"}', 300)",
            params![file_id],
        )
        .expect("insert change-log row");
}

pub(crate) fn snapshot(repo: &Path) -> SmartListFailureSnapshot {
    SmartListFailureSnapshot {
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

fn saved_search_rows(repo: &Path) -> Vec<SavedSearchRow> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT id, name, query_json, icon, color, pinned, created_at, updated_at
               FROM saved_searches
              ORDER BY id",
        )
        .expect("prepare saved search rows query");
    statement
        .query_map([], |row| {
            Ok(SavedSearchRow {
                id: row.get(0)?,
                name: row.get(1)?,
                query_json: row.get(2)?,
                icon: row.get(3)?,
                color: row.get(4)?,
                pinned: row.get(5)?,
                created_at: row.get(6)?,
                updated_at: row.get(7)?,
            })
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

pub(crate) fn relative_directory_entries(repo: &Path, path: &Path) -> Vec<String> {
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

pub(crate) fn assert_snapshot_unchanged(repo: &Path, before: &SmartListFailureSnapshot) {
    assert_eq!(&snapshot(repo), before);
}

pub(crate) fn assert_config_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("smart list should fail with Config");
    assert!(matches!(error, CoreError::Config { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Config);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

pub(crate) fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) -> CoreError {
    let error = result.expect_err("smart list should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    error
}
