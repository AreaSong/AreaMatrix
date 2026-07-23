#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{DuplicateStrategy, ImportDestination, ImportOptions, StorageMode};
use rusqlite::{params, OptionalExtension};

use super::batch_delete_validation::{open_db, path_string};

pub(crate) fn import_options(mode: StorageMode, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
        content_locale: area_matrix_core::ContentLocale::En,
    }
}

pub(crate) fn change_actions(repo: &Path) -> Vec<(i64, String, serde_json::Value)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, action, detail_json FROM change_log ORDER BY id")
        .expect("prepare change rows query");
    statement
        .query_map([], |row| {
            let detail_json: String = row.get(2)?;
            Ok((
                row.get(0)?,
                row.get(1)?,
                serde_json::from_str(&detail_json).expect("change detail is json"),
            ))
        })
        .expect("query change rows")
        .map(|row| row.expect("read change row"))
        .collect()
}

pub(crate) fn deleted_changes(repo: &Path) -> Vec<(i64, String, serde_json::Value)> {
    change_actions(repo)
        .into_iter()
        .filter(|(_, action, _)| action == "deleted")
        .collect()
}

pub(crate) fn undo_inverse(repo: &Path, token: &str) -> serde_json::Value {
    let inverse_json: String = open_db(repo)
        .query_row(
            "SELECT inverse_json FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .expect("read undo inverse");
    serde_json::from_str(&inverse_json).expect("undo inverse is json")
}

pub(crate) fn indexed_file(repo: &Path, source_path: &Path, category: &str) -> i64 {
    let current_name = source_path
        .file_name()
        .and_then(|value| value.to_str())
        .expect("fixture has filename");
    let path = path_string(source_path);
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 13,
                ?4, 'indexed', 'imported', ?1,
                100, 100, 'active'
             )",
            params![
                path,
                current_name,
                category,
                format!("{:064x}", path_string(source_path).len()),
            ],
        )
        .expect("insert indexed file row");
    connection.last_insert_rowid()
}

pub(crate) fn adopt_file(repo: &Path, relative_path: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create adopted parent");
    fs::write(&file_path, b"adopted bytes").expect("write adopted fixture");
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
                ?1, ?2, ?2, 'finance', 13,
                ?3, 'copied', 'adopted', NULL,
                100, 100, 'active'
             )",
            params![
                relative_path,
                current_name,
                format!("{:064x}", relative_path.len())
            ],
        )
        .expect("insert adopted file row");
    connection.last_insert_rowid()
}

pub(crate) fn archive_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/archives"))
        .expect("read archives directory")
        .map(|entry| entry.expect("read archive entry").path())
        .collect()
}

pub(crate) fn undo_status(repo: &Path, token: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT status FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .optional()
        .expect("read undo status")
}

pub(crate) fn install_batch_trash_undo_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_batch_trash_undo
             BEFORE INSERT ON undo_actions
             WHEN NEW.kind = 'trash_delete'
             BEGIN
               SELECT RAISE(ABORT, 'forced batch trash undo failure');
             END;",
        )
        .expect("install batch trash undo failure trigger");
}
