use std::{fs, path::Path};

use area_matrix_core::{
    detect_sync_conflicts, import_file, init_repo, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode, SyncConflict, SyncConflictStatus,
};
use rusqlite::Connection;

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct ValidationSnapshot {
    pub(crate) files: Vec<(String, Vec<u8>)>,
    pub(crate) conflict_status: SyncConflictStatus,
    pub(crate) change_count: i64,
}

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn setup_same_name_conflict() -> (tempfile::TempDir, String, i64) {
    let repo = initialized_repo();
    let file_id = import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");
    assert_eq!(conflicts.len(), 1);
    (repo, conflicts[0].conflict_id.clone(), file_id)
}

pub(crate) fn conflict_state(repo: &Path) -> Vec<SyncConflict> {
    let value: String = open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'sync_conflict_state'",
            [],
            |row| row.get(0),
        )
        .expect("read sync conflict state");
    serde_json::from_str(&value).expect("sync conflict state parses")
}

pub(crate) fn sync_resolution_change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*)
             FROM change_log
             WHERE action = 'external_modified'
               AND json_extract(detail_json, '$.kind') = 'sync_conflict_resolved'",
            [],
            |row| row.get(0),
        )
        .expect("count sync conflict resolution changes")
}

pub(crate) fn active_file_snapshot(repo: &Path, file_id: i64) -> (String, i64, String) {
    open_db(repo)
        .query_row(
            "SELECT path, size_bytes, hash_sha256
             FROM files
             WHERE id = ?1 AND status = 'active'",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read active file row")
}

pub(crate) fn user_files(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_files(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

pub(crate) fn validation_snapshot(repo: &Path) -> ValidationSnapshot {
    ValidationSnapshot {
        files: user_files(repo),
        conflict_status: conflict_state(repo)[0].status.clone(),
        change_count: change_count(repo),
    }
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

fn import_repo_file(repo: &Path, target_directory: &str, filename: &str, bytes: &[u8]) -> i64 {
    let source = tempfile::NamedTempFile::new().expect("create source file");
    fs::write(source.path(), bytes).expect("write source file");
    import_file(
        path_string(repo),
        path_string(source.path()),
        ImportOptions {
            mode: StorageMode::Copied,
            destination: ImportDestination::SelectedDirectory,
            target_directory: Some(target_directory.to_owned()),
            override_category: None,
            override_filename: Some(filename.to_owned()),
            duplicate_strategy: area_matrix_core::DuplicateStrategy::Ask,
        },
    )
    .expect("import repository file")
    .id
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    fs::create_dir_all(path.parent().expect("fixture has parent directory"))
        .expect("create fixture parent");
    fs::write(path, bytes).expect("write repository file");
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

fn collect_user_files(repo: &Path, current: &Path, files: &mut Vec<(String, Vec<u8>)>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("entry is inside repo")
            .to_string_lossy()
            .replace('\\', "/");
        if relative.starts_with(".areamatrix") {
            continue;
        }
        if path.is_dir() {
            collect_user_files(repo, &path, files);
        } else {
            files.push((relative, fs::read(&path).expect("read user file")));
        }
    }
}
