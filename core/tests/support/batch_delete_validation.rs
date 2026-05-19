#![allow(dead_code)]

use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use rusqlite::{params, Connection};
use walkdir::WalkDir;

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct BatchDeleteSnapshot {
    pub(crate) files: Vec<(i64, String, String, String)>,
    pub(crate) changes: Vec<(i64, String)>,
    pub(crate) undo_actions: Vec<(String, String)>,
    pub(crate) visible_paths: Vec<String>,
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

pub(crate) fn import_fixture(
    repo: &Path,
    name: &str,
    content: &[u8],
    mode: StorageMode,
) -> area_matrix_core::FileEntry {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source = source_root.path().join(name);
    fs::write(&source, content).expect("write source fixture");
    import_file(
        path_string(repo),
        path_string(&source),
        import_options(mode, name),
    )
    .expect("import fixture through Core API")
}

pub(crate) fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, std::path::PathBuf) {
    let root = tempfile::tempdir().expect("create source directory");
    let path = root.path().join(name);
    fs::write(&path, content).expect("write source file");
    (root, path)
}

pub(crate) fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub(crate) fn file_status(repo: &Path, file_id: i64) -> String {
    open_db(repo)
        .query_row(
            "SELECT status FROM files WHERE id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .expect("read file status")
}

pub(crate) fn insert_indexed_file(repo: &Path, source: &Path, category: &str) -> i64 {
    let name = source
        .file_name()
        .and_then(|value| value.to_str())
        .expect("fixture has filename");
    let source_path = path_string(source);
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (?1, ?2, ?2, ?3, 13, ?4, 'indexed', 'imported', ?1, 100, 100, 'active')",
            params![source_path, name, category, format!("{:064x}", name.len())],
        )
        .expect("insert indexed file row");
    connection.last_insert_rowid()
}

pub(crate) fn snapshot(repo: &Path) -> BatchDeleteSnapshot {
    BatchDeleteSnapshot {
        files: file_rows(repo),
        changes: change_rows(repo),
        undo_actions: undo_rows(repo),
        visible_paths: visible_paths(repo),
    }
}

pub(crate) fn install_removed_from_index_log_failure(repo: &Path, file_id: i64) {
    open_db(repo)
        .execute_batch(&format!(
            "CREATE TRIGGER fail_removed_index_{file_id}
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'removed_from_index' AND NEW.file_id = {file_id}
             BEGIN
               SELECT RAISE(ABORT, 'forced removed_from_index validation failure');
             END;"
        ))
        .expect("install removed_from_index failure trigger");
}

fn import_options(mode: StorageMode, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, status, storage_mode FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn change_rows(repo: &Path) -> Vec<(i64, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, action FROM change_log ORDER BY id")
        .expect("prepare change rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query change rows")
        .map(|row| row.expect("read change row"))
        .collect()
}

fn undo_rows(repo: &Path) -> Vec<(String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT token, kind FROM undo_actions ORDER BY created_at, token")
        .expect("prepare undo rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query undo rows")
        .map(|row| row.expect("read undo row"))
        .collect()
}

fn visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = WalkDir::new(repo)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter_map(|entry| {
            let relative = entry.path().strip_prefix(repo).ok()?;
            if relative.components().next()?.as_os_str() == ".areamatrix" {
                return None;
            }
            Some(relative.to_string_lossy().into_owned())
        })
        .collect::<Vec<_>>();
    paths.sort();
    paths
}
