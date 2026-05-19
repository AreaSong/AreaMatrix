use std::{fs, path::Path};

use pretty_assertions::assert_eq;

use area_matrix_core::{CoreError, ErrorKind};

use super::batch_rename_preview_support::open_db;

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct RenameSnapshot {
    pub(crate) file_rows: Vec<(i64, String, String, String)>,
    pub(crate) user_visible_paths: Vec<String>,
    pub(crate) renamed_change_count: i64,
    pub(crate) undo_action_count: i64,
}

pub(crate) fn snapshot(repo: &Path) -> RenameSnapshot {
    RenameSnapshot {
        file_rows: active_file_rows(repo),
        user_visible_paths: user_visible_paths(repo),
        renamed_change_count: count_rows(repo, "change_log", "action = 'renamed'"),
        undo_action_count: count_rows(repo, "undo_actions", "kind = 'rename_files'"),
    }
}

fn active_file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
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

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(root: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read fixture directory") {
        let entry = entry.expect("read fixture directory entry");
        let path = entry.path();
        if path
            .strip_prefix(root)
            .expect("path is under repo")
            .starts_with(".areamatrix")
        {
            continue;
        }
        if path.is_dir() {
            collect_user_visible_paths(root, &path, paths);
        } else {
            paths.push(
                path.strip_prefix(root)
                    .expect("path is under repo")
                    .display()
                    .to_string(),
            );
        }
    }
}

fn count_rows(repo: &Path, table: &str, predicate: &str) -> i64 {
    let sql = format!("SELECT COUNT(*) FROM {table} WHERE {predicate}");
    open_db(repo)
        .query_row(&sql, [], |row| row.get(0))
        .expect("count rows")
}

pub(crate) fn install_renamed_change_log_failure(repo: &Path, file_id: Option<i64>) {
    let condition = file_id
        .map(|file_id| format!("NEW.action = 'renamed' AND NEW.file_id = {file_id}"))
        .unwrap_or_else(|| "NEW.action = 'renamed'".to_owned());
    open_db(repo)
        .execute_batch(&format!(
            "CREATE TRIGGER fail_batch_rename_change_log
             BEFORE INSERT ON change_log
             WHEN {condition}
             BEGIN
               SELECT RAISE(ABORT, 'forced batch rename change-log failure');
             END;"
        ))
        .expect("install batch rename change-log failure trigger");
}

pub(crate) fn install_batch_rename_undo_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_batch_rename_undo
             BEFORE INSERT ON undo_actions
             WHEN NEW.kind = 'rename_files'
             BEGIN
               SELECT RAISE(ABORT, 'forced batch rename undo failure');
             END;",
        )
        .expect("install batch rename undo failure trigger");
}

pub(crate) fn assert_error_kind(error: CoreError, expected: ErrorKind) {
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, expected);
}
