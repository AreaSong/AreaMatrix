use std::{fs, path::Path};

use rusqlite::{params, Connection};

use super::{
    apply_external_sync_batch, ExternalModifiedRow, ExternalRemovedRow, ExternalRenamedRow,
    ExternalSyncApplyResult, ExternalSyncReceiptRow,
};
use crate::{
    CoreError, CoreResult, ExternalEvent, ExternalEventKind, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    crate::init_repo(
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

fn sync_file(repo: &Path, relative_path: &str) -> crate::FileEntry {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("file parent")).expect("create file parent");
    fs::write(&file_path, b"original").expect("write file fixture");
    crate::sync::sync_external_changes(
        path_string(repo),
        vec![ExternalEvent {
            path: relative_path.to_owned(),
            kind: ExternalEventKind::Created,
            fs_event_id: 1,
        }],
    )
    .expect("sync file fixture");
    crate::list_files(
        path_string(repo),
        FileFilter {
            category: None,
            include_deleted: None,
            imported_after: None,
            imported_before: None,
            limit: 10,
            offset: 0,
        },
    )
    .expect("list file fixture")
    .remove(0)
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn receipt(kind: &str, path: &str) -> ExternalSyncReceiptRow {
    ExternalSyncReceiptRow {
        event_id: 2,
        kind: kind.to_owned(),
        path: path.to_owned(),
        file_id: None,
        previous_category: None,
        current_category: Some("docs".to_owned()),
    }
}

fn assert_conflict(result: CoreResult<ExternalSyncApplyResult>, expected_path: &str) {
    match result {
        Err(CoreError::Conflict { path }) => assert_eq!(path, expected_path),
        Err(error) => panic!("expected path conflict, got {error:?}"),
        Ok(_) => panic!("stale row must not be applied"),
    }
}

fn assert_no_failed_apply_side_effects(repo: &Path) {
    let connection = open_db(repo);
    let receipt_count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM external_sync_receipts WHERE event_id = 2",
            [],
            |row| row.get(0),
        )
        .expect("count external sync receipts");
    assert_eq!(receipt_count, 0);
    let change_count: i64 = connection
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows");
    assert_eq!(change_count, 1);
}

#[test]
fn apply_external_sync_batch_rejects_stale_renamed_row() {
    let repo = initialized_repo();
    let file = sync_file(repo.path(), "docs/original.txt");
    open_db(repo.path())
        .execute(
            "UPDATE files SET path = 'docs/concurrent.txt' WHERE id = ?1",
            [file.id],
        )
        .expect("simulate concurrent rename");

    let result = apply_external_sync_batch(
        repo.path(),
        Vec::new(),
        vec![ExternalRenamedRow {
            file_id: file.id,
            from_path: file.path,
            path: "docs/renamed.txt".to_owned(),
            current_name: "renamed.txt".to_owned(),
            category: "docs".to_owned(),
            size_bytes: file.size_bytes,
            hash_sha256: file.hash_sha256.clone(),
            expected_size_bytes: file.size_bytes,
            expected_hash_sha256: file.hash_sha256,
            detail_json: "{}".to_owned(),
        }],
        Vec::new(),
        Vec::new(),
        vec![receipt("renamed", "docs/renamed.txt")],
    );

    assert_conflict(result, "docs/renamed.txt");
    let path: String = open_db(repo.path())
        .query_row("SELECT path FROM files WHERE id = ?1", [file.id], |row| {
            row.get(0)
        })
        .expect("read concurrently renamed row");
    assert_eq!(path, "docs/concurrent.txt");
    assert_no_failed_apply_side_effects(repo.path());
}

#[test]
fn apply_external_sync_batch_rejects_stale_modified_row() {
    let repo = initialized_repo();
    let file = sync_file(repo.path(), "docs/modified.txt");
    open_db(repo.path())
        .execute(
            "UPDATE files SET size_bytes = 99, hash_sha256 = 'concurrent' WHERE id = ?1",
            [file.id],
        )
        .expect("simulate concurrent metadata update");

    let result = apply_external_sync_batch(
        repo.path(),
        Vec::new(),
        Vec::new(),
        vec![ExternalModifiedRow {
            file_id: file.id,
            expected_path: file.path.clone(),
            expected_size_bytes: file.size_bytes,
            expected_hash_sha256: file.hash_sha256,
            size_bytes: 12,
            hash_sha256: "planned".to_owned(),
            detail_json: "{}".to_owned(),
        }],
        Vec::new(),
        vec![receipt("modified", &file.path)],
    );

    assert_conflict(result, &file.path);
    let state: (i64, String) = open_db(repo.path())
        .query_row(
            "SELECT size_bytes, hash_sha256 FROM files WHERE id = ?1",
            [file.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read concurrently modified row");
    assert_eq!(state, (99, "concurrent".to_owned()));
    assert_no_failed_apply_side_effects(repo.path());
}

#[test]
fn apply_external_sync_batch_rejects_stale_removed_row() {
    let repo = initialized_repo();
    let file = sync_file(repo.path(), "docs/removed.txt");
    open_db(repo.path())
        .execute(
            "UPDATE files SET hash_sha256 = 'concurrent' WHERE id = ?1",
            [file.id],
        )
        .expect("simulate concurrent metadata update");

    let result = apply_external_sync_batch(
        repo.path(),
        Vec::new(),
        Vec::new(),
        Vec::new(),
        vec![ExternalRemovedRow {
            file_id: file.id,
            expected_path: file.path.clone(),
            expected_size_bytes: file.size_bytes,
            expected_hash_sha256: file.hash_sha256,
            detail_json: "{}".to_owned(),
        }],
        vec![receipt("removed", &file.path)],
    );

    assert_conflict(result, &file.path);
    let state: (String, String) = open_db(repo.path())
        .query_row(
            "SELECT status, hash_sha256 FROM files WHERE id = ?1",
            params![file.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read concurrently changed row");
    assert_eq!(state, ("active".to_owned(), "concurrent".to_owned()));
    assert_no_failed_apply_side_effects(repo.path());
}
