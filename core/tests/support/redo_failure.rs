#![allow(dead_code)]

use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, CoreError, ErrorKind, ErrorRecoverability, OverviewOutput, RepoInitMode,
    RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct RedoSnapshot {
    pub(crate) files: Vec<(i64, String, String, String)>,
    pub(crate) tags: Vec<(i64, String)>,
    pub(crate) changes: Vec<(i64, String, String)>,
    pub(crate) undo_actions: Vec<(String, String, String)>,
    pub(crate) staging_entries: Vec<String>,
    pub(crate) generated_entries: Vec<String>,
    pub(crate) user_visible_paths: Vec<String>,
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

pub(crate) fn insert_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
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
                100, 100, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

pub(crate) fn snapshot(repo: &Path) -> RedoSnapshot {
    RedoSnapshot {
        files: file_rows(repo),
        tags: tag_rows(repo),
        changes: change_rows(repo),
        undo_actions: undo_rows(repo),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

pub(crate) fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, current_name, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

pub(crate) fn tag_rows(repo: &Path) -> Vec<(i64, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, tag FROM tags ORDER BY file_id, tag")
        .expect("prepare tag rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query tag rows")
        .map(|row| row.expect("read tag row"))
        .collect()
}

pub(crate) fn change_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(file_id, 0), action, detail_json
               FROM change_log
              ORDER BY id",
        )
        .expect("prepare change rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query change rows")
        .map(|row| row.expect("read change row"))
        .collect()
}

pub(crate) fn undo_rows(repo: &Path) -> Vec<(String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT token, kind, status FROM undo_actions ORDER BY token")
        .expect("prepare undo rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query undo rows")
        .map(|row| row.expect("read undo row"))
        .collect()
}

pub(crate) fn relative_directory_entries(repo: &Path, root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    if root.exists() {
        collect_relative_paths(repo, root, &mut entries);
    }
    entries.sort();
    entries
}

pub(crate) fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

pub(crate) fn only_undo_token(repo: &Path) -> String {
    open_db(repo)
        .query_row("SELECT token FROM undo_actions", [], |row| row.get(0))
        .expect("read only undo token")
}

pub(crate) fn undo_status(repo: &Path, token: &str) -> String {
    open_db(repo)
        .query_row(
            "SELECT status FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .expect("read undo status")
}

pub(crate) fn repo_config_value(repo: &Path, key: &str) -> String {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .expect("read repo config value")
}

pub(crate) fn install_redo_tag_change_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_redo_tag_change
             BEFORE INSERT ON change_log
             WHEN NEW.detail_json LIKE '%redo_batch_tag_added%'
             BEGIN
               SELECT RAISE(ABORT, 'forced redo tag change-log failure');
             END;",
        )
        .expect("install redo tag change-log failure trigger");
}

pub(crate) fn install_redo_file_change_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_redo_file_change
             BEFORE INSERT ON change_log
             WHEN NEW.detail_json LIKE '%redo_file_action%'
             BEGIN
               SELECT RAISE(ABORT, 'forced redo file change-log failure');
             END;",
        )
        .expect("install redo file change-log failure trigger");
}

pub(crate) fn install_redo_file_change_slow_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_redo_file_change_slow
             BEFORE INSERT ON change_log
             WHEN NEW.detail_json LIKE '%redo_file_action%'
             BEGIN
               SELECT length(randomblob(8000000));
               SELECT RAISE(ABORT, 'forced redo slow file change-log failure');
             END;",
        )
        .expect("install slow redo file change-log failure trigger");
}

pub(crate) fn drop_trigger(repo: &Path, trigger_name: &str) {
    open_db(repo)
        .execute_batch(&format!("DROP TRIGGER {trigger_name};"))
        .expect("drop trigger");
}

pub(crate) fn assert_error_mapping(
    error: &CoreError,
    kind: ErrorKind,
    recoverability: ErrorRecoverability,
) {
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, kind);
    assert_eq!(mapping.recoverability, recoverability);
}

fn collect_relative_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let entry = entry.expect("read directory entry");
        let path = entry.path();
        paths.push(relative_path(repo, &path));
        if path.is_dir() {
            collect_relative_paths(repo, &path, paths);
        }
    }
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = relative_path(repo, &path);
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn relative_path(repo: &Path, path: &Path) -> String {
    path.strip_prefix(repo)
        .expect("path is inside repo")
        .to_string_lossy()
        .into_owned()
}
