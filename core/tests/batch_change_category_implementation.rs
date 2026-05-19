use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    batch_move_to_category, import_file, init_repo, preview_batch_move_to_category, read_note,
    undo_action, write_note, BatchCategoryPreviewStatus, BatchCategoryResultStatus,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode, UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn import_options(mode: StorageMode, category: &str, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn indexed_file(repo: &Path, external_path: &Path, category: &str) -> i64 {
    let current_name = external_path
        .file_name()
        .and_then(|name| name.to_str())
        .expect("fixture has file name");
    let path = path_string(external_path);
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
                format!("{:064x}", path_string(external_path).len()),
            ],
        )
        .expect("insert indexed file row");
    connection.last_insert_rowid()
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category FROM files WHERE id = ?1",
            params![file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

fn change_details(repo: &Path) -> Vec<serde_json::Value> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT detail_json FROM change_log WHERE action = 'moved' ORDER BY id")
        .expect("prepare moved changes query");
    statement
        .query_map([], |row| {
            let detail: String = row.get(0)?;
            Ok(serde_json::from_str(&detail).expect("change detail is json"))
        })
        .expect("query moved changes")
        .map(|row| row.expect("read moved change detail"))
        .collect()
}

fn undo_row(repo: &Path, token: &str) -> (String, String, serde_json::Value, serde_json::Value) {
    open_db(repo)
        .query_row(
            "SELECT kind, status, summary_json, inverse_json
               FROM undo_actions
              WHERE token = ?1",
            params![token],
            |row| {
                let summary: String = row.get(2)?;
                let inverse: String = row.get(3)?;
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    serde_json::from_str(&summary).expect("summary is json"),
                    serde_json::from_str(&inverse).expect("inverse is json"),
                ))
            },
        )
        .expect("read undo action")
}

#[test]
fn batch_change_category_moves_repo_owned_and_updates_indexed_metadata() {
    let repo = initialized_repo();
    let readme = repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README");

    let (_existing_root, existing_source) = source_file("existing.pdf", b"existing");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&existing_source),
        import_options(StorageMode::Copied, "docs", "same.pdf"),
    )
    .expect("import existing target");
    let (_moving_root, moving_source) = source_file("moving.pdf", b"moving");
    let moving = import_file(
        path_string(repo.path()),
        path_string(&moving_source),
        import_options(StorageMode::Copied, "finance", "same.pdf"),
    )
    .expect("import moving repo-owned file");
    write_note(
        path_string(repo.path()),
        moving.id,
        "attached note".to_owned(),
    )
    .expect("write note before batch category change");

    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("external.pdf");
    fs::write(&external, b"external").expect("write external indexed file");
    let indexed_id = indexed_file(repo.path(), &external, "finance");

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![moving.id, indexed_id, existing.id, moving.id],
        "docs".to_owned(),
        true,
    )
    .expect("preview batch category change");

    assert_eq!(preview.requested_file_count, 3);
    assert!(preview.preview_token.starts_with("preview:batch-category:"));
    assert!(preview.can_apply);
    assert_eq!(preview.will_move_count, 1);
    assert_eq!(preview.metadata_only_count, 1);
    assert_eq!(preview.unchanged_count, 1);
    assert_eq!(preview.blocked_count, 0);
    assert_eq!(
        preview.items[0].status,
        BatchCategoryPreviewStatus::WillMove
    );
    assert_eq!(
        preview.items[0].target_path.as_deref(),
        Some("docs/same_1.pdf")
    );
    assert_eq!(
        preview.items[1].status,
        BatchCategoryPreviewStatus::MetadataOnly
    );
    assert_eq!(
        preview.items[2].status,
        BatchCategoryPreviewStatus::Unchanged
    );
    assert!(!repo.path().join("docs/same_1.pdf").exists());

    let report = batch_move_to_category(
        path_string(repo.path()),
        vec![moving.id, indexed_id, existing.id, moving.id],
        "docs".to_owned(),
        true,
        preview.preview_token,
    )
    .expect("apply batch category change");

    assert_eq!(report.requested_file_count, 3);
    assert_eq!(report.moved_count, 1);
    assert_eq!(report.metadata_only_count, 1);
    assert_eq!(report.unchanged_count, 1);
    assert_eq!(report.failed_count, 0);
    assert_eq!(report.updated_files.len(), 2);
    assert_eq!(
        report.item_results[0].status,
        BatchCategoryResultStatus::Moved
    );
    assert_eq!(
        report.item_results[1].status,
        BatchCategoryResultStatus::MetadataUpdated
    );
    assert_eq!(
        report.item_results[2].status,
        BatchCategoryResultStatus::Unchanged
    );
    let token = report
        .undo_token
        .expect("successful writes create undo token");
    assert!(token.starts_with("undo:batch-category:"));

    assert_eq!(
        file_row(repo.path(), moving.id),
        (
            "docs/same_1.pdf".to_owned(),
            "same_1.pdf".to_owned(),
            "docs".to_owned()
        )
    );
    assert_eq!(
        file_row(repo.path(), indexed_id),
        (
            path_string(&external),
            "external.pdf".to_owned(),
            "docs".to_owned()
        )
    );
    assert!(!repo.path().join("finance/same.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("docs/same_1.pdf")).expect("read moved file"),
        b"moving"
    );
    assert!(external.exists());
    assert_eq!(
        read_note(path_string(repo.path()), moving.id).expect("read note after move"),
        Some("attached note".to_owned())
    );
    assert!(repo.path().join("docs/same_1.pdf.md").exists());
    assert_eq!(
        fs::read_to_string(&readme).expect("read README after batch change"),
        "user readme\n"
    );

    let changes = change_details(repo.path());
    assert_eq!(changes.len(), 2);
    assert!(changes
        .iter()
        .all(|detail| detail["kind"] == "batch_change_category"));
    assert!(changes
        .iter()
        .any(|detail| detail["index_only"] == serde_json::Value::Bool(true)));

    let (kind, status, summary, inverse) = undo_row(repo.path(), &token);
    assert_eq!(kind, "batch_change_category");
    assert_eq!(status, "pending");
    assert_eq!(summary["affected_count"], 2);
    assert_eq!(inverse["kind"], "restore_batch_file_state");
    assert_eq!(inverse["items"].as_array().expect("items array").len(), 2);
}

#[test]
fn batch_change_category_rejects_stale_preview_after_file_state_changes() {
    let repo = initialized_repo();
    let (_root, source) = source_file("report.pdf", b"report");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import file");
    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![entry.id],
        "docs".to_owned(),
        true,
    )
    .expect("preview batch move");

    open_db(repo.path())
        .execute(
            "UPDATE files SET updated_at = updated_at + 1 WHERE id = ?1",
            params![entry.id],
        )
        .expect("simulate external metadata change");

    let result = batch_move_to_category(
        path_string(repo.path()),
        vec![entry.id],
        "docs".to_owned(),
        true,
        preview.preview_token,
    );

    assert!(result.is_err());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("docs/report.pdf").exists());
}

#[test]
fn batch_change_category_undo_restores_moved_and_metadata_only_items() {
    let repo = initialized_repo();
    let (_root, source) = source_file("report.pdf", b"report");
    let moved = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import repo-owned file");
    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("indexed.pdf");
    fs::write(&external, b"indexed").expect("write indexed source");
    let indexed_id = indexed_file(repo.path(), &external, "finance");

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![moved.id, indexed_id],
        "docs".to_owned(),
        true,
    )
    .expect("preview batch category change");
    let report = batch_move_to_category(
        path_string(repo.path()),
        vec![moved.id, indexed_id],
        "docs".to_owned(),
        true,
        preview.preview_token,
    )
    .expect("apply batch category change");
    let token = report.undo_token.expect("undo token");

    let undo = undo_action(path_string(repo.path()), token.clone()).expect("undo batch category");

    assert_eq!(undo.status, UndoActionStatus::Executed);
    assert_eq!(undo.affected_count, 2);
    assert_eq!(
        file_row(repo.path(), moved.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert_eq!(
        file_row(repo.path(), indexed_id),
        (
            path_string(&external),
            "indexed.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("docs/report.pdf").exists());
    assert!(external.exists());

    let (_kind, status, _summary, _inverse) = undo_row(repo.path(), &token);
    assert_eq!(status, "executed");
}
