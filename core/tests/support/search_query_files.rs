#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, OverviewOutput, RepoInitMode, RepoInitOptions, SearchFilter, SearchPagination,
    SearchScope, SearchTagMatchMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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

pub(crate) fn default_filter() -> SearchFilter {
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

pub(crate) fn first_page() -> SearchPagination {
    SearchPagination {
        limit: 50,
        offset: 0,
    }
}

pub(crate) fn insert_copied_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    imported_at: i64,
    updated_at: i64,
) -> i64 {
    insert_file(
        repo,
        relative_path,
        category,
        "copied",
        imported_at,
        updated_at,
    )
}

pub(crate) fn insert_file(
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
    fs::write(&file_path, b"search fixture bytes").expect("write file fixture");
    insert_file_row(
        repo,
        relative_path,
        category,
        storage_mode,
        imported_at,
        updated_at,
    )
}

fn insert_file_row(
    repo: &Path,
    relative_path: &str,
    category: &str,
    storage_mode: &str,
    imported_at: i64,
    updated_at: i64,
) -> i64 {
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

pub(crate) fn insert_change(repo: &Path, file_id: i64, action: &str, detail: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, 200)",
            params![file_id, action, detail],
        )
        .expect("insert change-log row");
}

pub(crate) fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 100)",
            params![file_id, tag],
        )
        .expect("insert tag row");
}

pub(crate) fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active files")
}

pub(crate) fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

pub(crate) fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
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
            .expect("path is inside repo")
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

pub(crate) fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect();
    entries.sort();
    entries
}

pub(crate) fn generated_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/generated"))
        .expect("read generated directory")
        .map(|entry| entry.expect("read generated entry").path())
        .collect()
}

pub(crate) fn assert_search_left_repo_unchanged(
    repo: &Path,
    before_files: &[(i64, String, String, String)],
    before_changes: i64,
    before_visible_paths: &[String],
) {
    assert_eq!(file_rows(repo), before_files);
    assert_eq!(change_log_count(repo), before_changes);
    assert_eq!(user_visible_paths(repo), before_visible_paths);
    assert!(staging_entries(repo).is_empty());
}

pub(crate) fn insert_many_searchable_files(repo: &Path, count: i64) {
    let mut connection = open_db(repo);
    let transaction = connection
        .transaction()
        .expect("start bulk searchable file transaction");
    {
        let mut statement = transaction
            .prepare(
                "INSERT INTO files (
                    path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path,
                    imported_at, updated_at, status
                 ) VALUES (
                    ?1, ?2, ?2, 'bulk', 13,
                    ?3, 'copied', 'imported', NULL,
                    ?4, ?4, 'active'
                 )",
            )
            .expect("prepare bulk searchable file insert");
        for index in 0..count {
            let relative_path = format!("bulk/contract-{index:05}.txt");
            let current_name = format!("contract-{index:05}.txt");
            let hash = format!("{:064x}", index + 1);
            statement
                .execute(params![relative_path, current_name, hash, index + 1])
                .expect("insert bulk searchable file row");
        }
    }
    transaction
        .commit()
        .expect("commit bulk searchable file transaction");
}
