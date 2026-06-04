use std::{fs, path::Path};

use area_matrix_core::{
    get_missing_file_state, init_repo, relink_missing_file, remove_missing_file_record, CoreError,
    MissingFileReason, MissingFileRecoveryStatus, MissingFileRelinkRequest,
    MissingFileRemoveRecordRequest, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;
use sha2::{Digest, Sha256};

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn write_repo_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create fixture parent directory");
    }
    fs::write(path, content).expect("write fixture file");
}

fn sha256_hex(content: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content);
    format!("{:x}", hasher.finalize())
}

fn insert_missing_repo_file(repo: &Path, relative_path: &str, content: &[u8]) -> i64 {
    insert_file_row(
        repo,
        relative_path,
        sha256_hex(content),
        content.len() as i64,
    )
}

fn insert_file_row(repo: &Path, relative_path: &str, hash_sha256: String, size_bytes: i64) -> i64 {
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
             ) VALUES (
                ?1, ?2, ?2, ?3, ?4,
                ?5, 'copied', 'imported', NULL,
                100, 200, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                size_bytes,
                hash_sha256
            ],
        )
        .expect("insert missing file row");
    connection.last_insert_rowid()
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String, i64, String, Option<String>) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, size_bytes, status, source_path
             FROM files WHERE id = ?1",
            params![file_id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                ))
            },
        )
        .expect("load file row")
}

fn change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

fn latest_change(repo: &Path) -> (String, Value) {
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

#[test]
fn missing_file_recovery_state_reports_missing_row_without_writes() {
    let repo = initialized_repo();
    let expected_content = b"original report";
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", expected_content);

    let state =
        get_missing_file_state(path_string(repo.path()), file_id).expect("load recovery state");

    assert_eq!(state.file_id, file_id);
    assert_eq!(state.relative_path, "docs/missing.pdf");
    assert_eq!(state.reason, MissingFileReason::PathMissing);
    assert_eq!(
        state.expected_hash_sha256,
        Some(sha256_hex(expected_content))
    );
    assert!(state.can_locate);
    assert!(state.can_try_again);
    assert!(state.can_remove_record);
    assert!(state.remove_record_requires_confirmation);
    assert!(!state.can_run_rescan);
    assert_eq!(change_count(repo.path()), 0);
}

#[test]
fn relink_missing_file_updates_metadata_after_hash_match_without_moving_files() {
    let repo = initialized_repo();
    let content = b"restored report";
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", content);
    write_repo_file(repo.path(), "docs/restored.pdf", content);

    let report = relink_missing_file(
        path_string(repo.path()),
        MissingFileRelinkRequest {
            file_id,
            new_path: path_string(&repo.path().join("docs/restored.pdf")),
            confirmed: true,
        },
    )
    .expect("relink matching file");

    assert_eq!(report.status, MissingFileRecoveryStatus::Relinked);
    assert_eq!(report.previous_path, Some("docs/missing.pdf".to_owned()));
    assert_eq!(report.current_path, Some("docs/restored.pdf".to_owned()));
    assert!(report.hash_matched);
    assert!(!report.record_removed);
    assert!(!report.file_deleted);
    assert_eq!(
        report.change_log_action,
        Some("external_modified".to_owned())
    );

    assert_eq!(
        file_row(repo.path(), file_id),
        (
            "docs/restored.pdf".to_owned(),
            "restored.pdf".to_owned(),
            "docs".to_owned(),
            content.len() as i64,
            "active".to_owned(),
            None,
        )
    );
    assert_eq!(
        fs::read(repo.path().join("docs/restored.pdf")).unwrap(),
        content
    );
    assert!(!repo.path().join("docs/missing.pdf").exists());
    assert!(matches!(
        get_missing_file_state(path_string(repo.path()), file_id),
        Err(CoreError::FileNotFound { .. })
    ));
    let (action, detail) = latest_change(repo.path());
    assert_eq!(action, "external_modified");
    assert_eq!(detail["kind"], "missing_file_relinked");
    assert_eq!(detail["file_deleted"], false);
}

#[test]
fn relink_missing_file_hash_mismatch_keeps_metadata_and_change_log_unchanged() {
    let repo = initialized_repo();
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", b"original");
    write_repo_file(repo.path(), "docs/wrong.pdf", b"different");

    let report = relink_missing_file(
        path_string(repo.path()),
        MissingFileRelinkRequest {
            file_id,
            new_path: path_string(&repo.path().join("docs/wrong.pdf")),
            confirmed: true,
        },
    )
    .expect("hash mismatch is a report, not a thrown error");

    assert_eq!(report.status, MissingFileRecoveryStatus::HashMismatch);
    assert!(!report.hash_matched);
    assert!(!report.record_removed);
    assert!(!report.file_deleted);
    assert_eq!(report.change_log_action, None);
    assert_eq!(
        file_row(repo.path(), file_id),
        (
            "docs/missing.pdf".to_owned(),
            "missing.pdf".to_owned(),
            "docs".to_owned(),
            b"original".len() as i64,
            "active".to_owned(),
            None,
        )
    );
    assert_eq!(change_count(repo.path()), 0);
    assert_eq!(
        fs::read(repo.path().join("docs/wrong.pdf")).unwrap(),
        b"different"
    );
}

#[test]
fn remove_missing_file_record_soft_deletes_metadata_without_deleting_files() {
    let repo = initialized_repo();
    let file_id = insert_missing_repo_file(repo.path(), "docs/gone.pdf", b"gone");
    write_repo_file(repo.path(), "docs/unrelated.txt", b"keep me");

    let report = remove_missing_file_record(
        path_string(repo.path()),
        MissingFileRemoveRecordRequest {
            file_id,
            confirmed: true,
        },
    )
    .expect("remove missing metadata record");

    assert_eq!(report.status, MissingFileRecoveryStatus::RecordRemoved);
    assert!(report.record_removed);
    assert!(!report.file_deleted);
    assert_eq!(
        report.change_log_action,
        Some("removed_from_index".to_owned())
    );
    assert_eq!(file_row(repo.path(), file_id).4, "deleted");
    assert_eq!(
        fs::read(repo.path().join("docs/unrelated.txt")).unwrap(),
        b"keep me"
    );
    let (action, detail) = latest_change(repo.path());
    assert_eq!(action, "removed_from_index");
    assert_eq!(detail["kind"], "missing_file_record_removed");
    assert_eq!(detail["file_deleted"], false);
}
