use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, preview_import_conflict_batch, ImportConflictBatchPreviewRequest,
    ImportConflictBatchStrategy, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use rusqlite::{params, Connection};

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub fn initialized_repo() -> tempfile::TempDir {
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

pub fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub fn create_conflict_schema(repo: &Path) {
    let request = ImportConflictBatchPreviewRequest {
        import_session_id: "bootstrap-session".to_owned(),
        conflict_ids: vec!["bootstrap-conflict".to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::KeepBoth,
        apply_to_all_similar_conflicts: false,
    };
    let _ignored = preview_import_conflict_batch(path_string(repo), request);
}

pub fn insert_active_file(repo: &Path, relative_path: &str, hash: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, format!("active bytes for {relative_path}")).expect("write active file");
    insert_file_row(repo, relative_path, "copied", "active", hash)
}

pub fn insert_staging_file(repo: &Path, staging_name: &str, current_name: &str, hash: &str) -> i64 {
    let relative_path = format!(".areamatrix/staging/{staging_name}");
    let staging_path = repo.join(&relative_path);
    fs::write(&staging_path, format!("staged bytes for {current_name}"))
        .expect("write staging file");
    insert_file_row_with_name(
        repo,
        &relative_path,
        current_name,
        "copied",
        "staging",
        hash,
    )
}

pub fn insert_import_session(repo: &Path, session_id: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO import_sessions (import_session_id, status, created_at, updated_at)
             VALUES (?1, 'pending', 100, 100)",
            [session_id],
        )
        .expect("insert import session");
}

pub fn insert_conflict(
    repo: &Path,
    session_id: &str,
    conflict_id: &str,
    conflict_type: &str,
    staging_file_id: i64,
    existing_file_id: i64,
    target_path: &str,
) {
    open_db(repo)
        .execute(
            "INSERT INTO import_conflicts (
                conflict_id, import_session_id, conflict_type, staging_file_id,
                existing_file_id, incoming_path, target_path, status,
                created_at, updated_at
             ) VALUES (
                ?1, ?2, ?3, ?4,
                ?5, ?6, ?7, 'pending',
                100, 100
             )",
            params![
                conflict_id,
                session_id,
                conflict_type,
                staging_file_id,
                existing_file_id,
                format!("incoming/{conflict_id}"),
                target_path,
            ],
        )
        .expect("insert import conflict");
}

pub fn file_status(repo: &Path, file_id: i64) -> (String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, status FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

fn insert_file_row(repo: &Path, relative_path: &str, mode: &str, status: &str, hash: &str) -> i64 {
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture path has filename");
    insert_file_row_with_name(repo, relative_path, current_name, mode, status, hash)
}

fn insert_file_row_with_name(
    repo: &Path,
    relative_path: &str,
    current_name: &str,
    mode: &str,
    status: &str,
    hash: &str,
) -> i64 {
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'docs', 13,
                ?3, ?4, 'imported', '/tmp/source',
                100, 100, ?5
             )",
            params![relative_path, current_name, hash, mode, status],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}
