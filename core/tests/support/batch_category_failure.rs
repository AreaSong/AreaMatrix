#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use area_matrix_core::{
    init_repo, CoreError, ErrorKind, ErrorRecoverability, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct BatchCategorySnapshot {
    pub(crate) files: Vec<(i64, String, String, String, String)>,
    pub(crate) change_logs: Vec<(i64, String, String)>,
    pub(crate) undo_actions: Vec<(String, String, String)>,
    pub(crate) staging_entries: Vec<String>,
    pub(crate) generated_entries: Vec<String>,
    pub(crate) user_visible_paths: Vec<String>,
}

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
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

pub(crate) fn insert_repo_owned_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    storage_mode: StorageMode,
    status: &str,
) -> i64 {
    let file_path = repo.join(relative_path);
    if status == "active" {
        fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
            .expect("create fixture parent directory");
        fs::write(&file_path, format!("fixture bytes for {relative_path}"))
            .expect("write fixture file");
    }

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture has filename");
    let storage_mode_value = match storage_mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    };
    let source_path = if storage_mode == StorageMode::Indexed {
        Some(path_string(&file_path))
    } else {
        None
    };
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 13,
                ?4, ?5, 'imported', ?6,
                100, 100, ?7
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
                storage_mode_value,
                source_path,
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

pub(crate) fn insert_indexed_file(repo: &Path, source_path: &Path, category: &str) -> i64 {
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
                format!("{:064x}", current_name.len())
            ],
        )
        .expect("insert indexed file row");
    connection.last_insert_rowid()
}

pub(crate) fn snapshot(repo: &Path) -> BatchCategorySnapshot {
    BatchCategorySnapshot {
        files: file_rows(repo),
        change_logs: change_log_rows(repo),
        undo_actions: undo_action_rows(repo),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, current_name, category, status FROM files ORDER BY id")
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

pub(crate) fn file_row(repo: &Path, file_id: i64) -> (String, String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, status FROM files WHERE id = ?1",
            params![file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read file row")
}

pub(crate) fn change_log_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(file_id, 0), action, detail_json
               FROM change_log
              ORDER BY id",
        )
        .expect("prepare change-log rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query change-log rows")
        .map(|row| row.expect("read change-log row"))
        .collect()
}

pub(crate) fn undo_action_rows(repo: &Path) -> Vec<(String, String, String)> {
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
        .expect("path is inside repository")
        .to_string_lossy()
        .into_owned()
}

pub(crate) fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) -> CoreError {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    error
}

pub(crate) fn assert_io_error<T: std::fmt::Debug>(result: Result<T, CoreError>) -> CoreError {
    let error = result.expect_err("operation should fail with Io");
    assert!(matches!(error, CoreError::Io { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Io);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Retryable
    );
    error
}

pub(crate) fn assert_permission_denied<T: std::fmt::Debug>(
    result: Result<T, CoreError>,
) -> CoreError {
    let error = result.expect_err("operation should fail with PermissionDenied");
    assert!(matches!(error, CoreError::PermissionDenied { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::PermissionDenied);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
    error
}

pub(crate) fn assert_file_not_found<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with FileNotFound");
    assert!(matches!(error, CoreError::FileNotFound { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::FileNotFound);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::RefreshRequired
    );
}

pub(crate) fn assert_classify_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Classify");
    assert!(matches!(error, CoreError::Classify { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Classify);
}

pub(crate) fn assert_conflict_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Conflict");
    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Conflict);
}

pub(crate) fn install_batch_category_change_log_failure(repo: &Path, file_id: Option<i64>) {
    let condition = match file_id {
        Some(id) => format!("AND NEW.file_id = {id}"),
        None => String::new(),
    };
    let sql = format!(
        "CREATE TRIGGER fail_batch_category_change_log
         BEFORE INSERT ON change_log
         WHEN NEW.action = 'moved'
          AND json_extract(NEW.detail_json, '$.kind') = 'batch_change_category'
          {condition}
         BEGIN
           SELECT RAISE(ABORT, 'forced batch category change_log failure');
         END;"
    );
    open_db(repo)
        .execute_batch(&sql)
        .expect("install batch category change-log failure trigger");
}

pub(crate) fn install_batch_category_undo_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_batch_category_undo
             BEFORE INSERT ON undo_actions
             WHEN NEW.kind = 'batch_change_category'
             BEGIN
               SELECT RAISE(ABORT, 'forced batch category undo failure');
             END;",
        )
        .expect("install batch category undo failure trigger");
}

#[cfg(unix)]
pub(crate) struct UnixModeGuard {
    path: PathBuf,
    original_mode: u32,
    restored: bool,
}

#[cfg(unix)]
impl UnixModeGuard {
    pub(crate) fn set_mode(path: &Path, mode: u32) -> Self {
        let metadata = fs::metadata(path).expect("read original permissions");
        let original_mode = metadata.permissions().mode();
        let mut permissions = metadata.permissions();
        permissions.set_mode(mode);
        fs::set_permissions(path, permissions).expect("set restricted permissions");
        Self {
            path: path.to_path_buf(),
            original_mode,
            restored: false,
        }
    }

    pub(crate) fn restore(&mut self) {
        if self.restored {
            return;
        }
        let mut permissions = fs::metadata(&self.path)
            .expect("read permissions for restore")
            .permissions();
        permissions.set_mode(self.original_mode);
        fs::set_permissions(&self.path, permissions).expect("restore original permissions");
        self.restored = true;
    }
}

#[cfg(unix)]
impl Drop for UnixModeGuard {
    fn drop(&mut self) {
        self.restore();
    }
}
