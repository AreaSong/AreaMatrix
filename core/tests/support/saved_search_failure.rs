#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, CoreError, CreateSavedSearchRequest, ErrorKind, ErrorRecoverability, OverviewOutput,
    RepoInitMode, RepoInitOptions, SavedSearchQuery, SearchFilter, SearchScope, SearchSort,
    SearchTagMatchMode, StorageMode, UpdateSavedSearchRequest,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct SavedSearchFailureSnapshot {
    saved_searches: Vec<SavedSearchRow>,
    files: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    staging_entries: Vec<PathBuf>,
    generated_entries: Vec<PathBuf>,
    user_visible_paths: Vec<String>,
}

#[derive(Debug, Eq, PartialEq)]
struct SavedSearchRow {
    id: i64,
    name: String,
    query_json: String,
    icon: Option<String>,
    color: Option<String>,
    pinned: i64,
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
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    repo
}

pub(crate) fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub(crate) fn saved_query() -> SavedSearchQuery {
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

pub(crate) fn create_request(name: &str) -> CreateSavedSearchRequest {
    CreateSavedSearchRequest {
        name: name.to_owned(),
        query: saved_query(),
        icon: Some("magnifyingglass".to_owned()),
        color: Some("blue".to_owned()),
        pinned: false,
    }
}

pub(crate) fn update_request(id: i64, name: &str) -> UpdateSavedSearchRequest {
    UpdateSavedSearchRequest {
        id,
        name: name.to_owned(),
        query: saved_query(),
        icon: Some("folder".to_owned()),
        color: Some("green".to_owned()),
        pinned: true,
    }
}

pub(crate) fn snapshot(repo: &Path) -> SavedSearchFailureSnapshot {
    SavedSearchFailureSnapshot {
        saved_searches: saved_search_rows(repo),
        files: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        staging_entries: directory_entries(&repo.join(".areamatrix/staging")),
        generated_entries: directory_entries(&repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn saved_search_rows(repo: &Path) -> Vec<SavedSearchRow> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, name, query_json, icon, color, pinned FROM saved_searches ORDER BY id")
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
            })
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

pub(crate) fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count table rows")
}

pub(crate) fn table_exists(repo: &Path, table: &str) -> bool {
    open_db(repo)
        .query_row(
            "SELECT EXISTS(
                SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1
             )",
            [table],
            |row| row.get::<_, i64>(0),
        )
        .expect("query table existence")
        == 1
}

fn directory_entries(path: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = fs::read_dir(path)
        .expect("read directory")
        .map(|entry| entry.expect("read directory entry").path())
        .collect();
    entries.sort();
    entries
}

pub(crate) fn user_visible_paths(repo: &Path) -> Vec<String> {
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

pub(crate) fn insert_active_file(repo: &Path) {
    let file_path = repo.join("finance/invoice.pdf");
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, b"saved search fixture").expect("write fixture file");

    open_db(repo)
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                'finance/invoice.pdf', 'invoice.pdf', 'invoice.pdf', 'finance', 20,
                ?1, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![format!("{:064x}", 1)],
        )
        .expect("insert active file row");
}

pub(crate) fn assert_config_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Config");
    assert!(matches!(error, CoreError::Config { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Config);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

pub(crate) fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) -> CoreError {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    error
}
