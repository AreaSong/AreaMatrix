use std::{fs, path::Path};

use area_matrix_core::{init_repo, OverviewOutput, RepoInitMode, RepoInitOptions};
use rusqlite::{params, Connection};
use serde_json::Value;
use sha2::{Digest, Sha256};

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct ValidationSnapshot {
    pub(crate) files: Vec<(i64, String, String, i64, String, Option<String>)>,
    pub(crate) change_count: i64,
    pub(crate) user_files: Vec<(String, Vec<u8>)>,
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

pub(crate) fn insert_missing_repo_file(repo: &Path, relative_path: &str, content: &[u8]) -> i64 {
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture path has file name");
    let category = relative_path
        .split_once('/')
        .map(|(category, _)| category)
        .unwrap_or("__root__");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (?1, ?2, ?2, ?3, ?4, ?5, 'copied', 'imported', NULL, 100, 200, 'active')",
            params![
                relative_path,
                current_name,
                category,
                content.len() as i64,
                sha256_hex(content),
            ],
        )
        .expect("insert missing file row");
    connection.last_insert_rowid()
}

pub(crate) fn write_repo_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create fixture parent directory");
    }
    fs::write(path, content).expect("write fixture file");
}

pub(crate) fn validation_snapshot(repo: &Path) -> ValidationSnapshot {
    ValidationSnapshot {
        files: file_rows(repo),
        change_count: change_count(repo),
        user_files: user_files(repo),
    }
}

pub(crate) fn change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

pub(crate) fn latest_change(repo: &Path) -> (String, Value) {
    let (action, detail_json): (String, String) = open_db(repo)
        .query_row(
            "SELECT action, detail_json FROM change_log ORDER BY id DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load latest change");
    let detail = serde_json::from_str(&detail_json).expect("parse change detail");
    (action, detail)
}

pub(crate) fn user_files(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_files(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn sha256_hex(content: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content);
    format!("{:x}", hasher.finalize())
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, i64, String, Option<String>)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT id, path, current_name, size_bytes, status, source_path
             FROM files ORDER BY id",
        )
        .expect("prepare files query");
    statement
        .query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
            ))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn collect_user_files(repo: &Path, current: &Path, files: &mut Vec<(String, Vec<u8>)>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let path = entry.expect("read directory entry").path();
        if is_repo_metadata_path(repo, &path) {
            continue;
        }
        if path.is_dir() {
            collect_user_files(repo, &path, files);
        } else {
            files.push((
                repo_relative_path(repo, &path),
                fs::read(&path).expect("read user file"),
            ));
        }
    }
}

fn is_repo_metadata_path(repo: &Path, path: &Path) -> bool {
    let relative = repo_relative_path(repo, path);
    relative == ".areamatrix" || relative.starts_with(".areamatrix/")
}

fn repo_relative_path(repo: &Path, path: &Path) -> String {
    path.strip_prefix(repo)
        .expect("path is inside repository")
        .to_string_lossy()
        .into_owned()
}
