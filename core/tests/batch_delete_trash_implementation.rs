use std::{
    fs,
    path::{Path, PathBuf},
};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use area_matrix_core::{
    batch_delete_to_trash, import_file, init_repo, list_undo_actions, preview_batch_delete,
    undo_action, BatchDeleteMode, BatchDeletePreviewStatus, BatchDeleteResultStatus, CoreError,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode, UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection, OptionalExtension};

mod support;

use support::system_trash_home::with_test_system_trash;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_status(repo: &Path, file_id: i64) -> String {
    open_db(repo)
        .query_row(
            "SELECT status FROM files WHERE id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .expect("read file status")
}

fn change_actions(repo: &Path) -> Vec<(i64, String, serde_json::Value)> {
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

fn undo_inverse(repo: &Path, token: &str) -> serde_json::Value {
    let inverse_json: String = open_db(repo)
        .query_row(
            "SELECT inverse_json FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .expect("read undo inverse");
    serde_json::from_str(&inverse_json).expect("undo inverse is json")
}

fn indexed_file(repo: &Path, source_path: &Path, category: &str) -> i64 {
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

fn adopt_file(repo: &Path, relative_path: &str) -> i64 {
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

fn archive_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/archives"))
        .expect("read archives directory")
        .map(|entry| entry.expect("read archive entry").path())
        .collect()
}

fn undo_status(repo: &Path, token: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT status FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .optional()
        .expect("read undo status")
}

fn install_batch_trash_undo_failure(repo: &Path) {
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

#[test]
fn batch_delete_trash_implementation_moves_repo_owned_files_and_creates_batch_undo() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let readme = repo.path().join("README.md");
        fs::write(&readme, "user readme\n").expect("write user README");
        let (_first_root, first_source) = source_file("first.pdf", b"first bytes");
        let first = import_file(
            path_string(repo.path()),
            path_string(&first_source),
            import_options(StorageMode::Copied, "first.pdf"),
        )
        .expect("import first copied file");
        let (_second_root, second_source) = source_file("second.pdf", b"second bytes");
        let second = import_file(
            path_string(repo.path()),
            path_string(&second_source),
            import_options(StorageMode::Moved, "second.pdf"),
        )
        .expect("import second moved file");

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![first.id, second.id, first.id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview batch trash delete");

        assert_eq!(preview.requested_file_count, 2);
        assert!(preview.can_apply);
        assert!(preview.trash_available);
        assert!(preview.undo_available);
        assert!(preview.preview_token.starts_with("preview:batch-delete:"));
        assert_eq!(preview.will_trash_count, 2);
        assert!(preview
            .items
            .iter()
            .all(|item| item.status == BatchDeletePreviewStatus::WillMoveToTrash));
        assert!(repo.path().join(&first.path).exists());
        assert!(repo.path().join(&second.path).exists());

        let report = batch_delete_to_trash(
            path_string(repo.path()),
            vec![first.id, second.id, first.id],
            BatchDeleteMode::MoveToTrash,
            preview.preview_token,
        )
        .expect("apply batch trash delete");

        assert_eq!(report.requested_file_count, 2);
        assert_eq!(report.moved_to_trash_count, 2);
        assert_eq!(report.removed_from_index_count, 0);
        assert_eq!(report.skipped_count, 0);
        assert_eq!(report.failed_count, 0);
        assert_eq!(report.affected_file_ids, vec![first.id, second.id]);
        assert!(report
            .item_results
            .iter()
            .all(|item| item.status == BatchDeleteResultStatus::MovedToTrash));
        let undo_token = report.undo_token.expect("batch trash creates undo token");
        assert!(undo_token.starts_with("undo:batch-trash-delete:"));

        assert!(!repo.path().join(&first.path).exists());
        assert!(!repo.path().join(&second.path).exists());
        assert_eq!(
            fs::read(trash_dir.join("first.pdf")).expect("read first trash item"),
            b"first bytes"
        );
        assert_eq!(
            fs::read(trash_dir.join("second.pdf")).expect("read second trash item"),
            b"second bytes"
        );
        assert_eq!(
            fs::read_to_string(readme).expect("read user README"),
            "user readme\n"
        );
        assert_eq!(file_status(repo.path(), first.id), "deleted");
        assert_eq!(file_status(repo.path(), second.id), "deleted");
        assert_eq!(archive_entries(repo.path()), Vec::<PathBuf>::new());

        let deleted_changes = change_actions(repo.path())
            .into_iter()
            .filter(|(_, action, _)| action == "deleted")
            .collect::<Vec<_>>();
        assert_eq!(deleted_changes.len(), 2);
        assert!(deleted_changes
            .iter()
            .all(|(_, _, detail)| detail["kind"] == "batch_delete_trash"));
        assert!(deleted_changes
            .iter()
            .all(|(_, _, detail)| detail["trash_location"] == "system"));

        let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
        let action = actions
            .iter()
            .find(|action| action.action_id == undo_token)
            .expect("find batch trash undo action");
        assert_eq!(action.kind, "trash_delete");
        assert_eq!(action.summary, "Moved 2 files to Trash.");
        assert_eq!(action.affected_count, 2);
        assert_eq!(action.status, UndoActionStatus::Pending);

        let inverse = undo_inverse(repo.path(), &undo_token);
        assert_eq!(inverse["kind"], "restore_batch_deleted_files");
        assert_eq!(inverse["items"].as_array().expect("items array").len(), 2);

        let undo =
            undo_action(path_string(repo.path()), undo_token.clone()).expect("undo batch trash");
        assert_eq!(undo.status, UndoActionStatus::Executed);
        assert_eq!(undo.affected_count, 2);
        assert_eq!(
            undo_status(repo.path(), &undo_token).as_deref(),
            Some("executed")
        );
        assert_eq!(
            fs::read(repo.path().join(&first.path)).expect("read restored first file"),
            b"first bytes"
        );
        assert_eq!(
            fs::read(repo.path().join(&second.path)).expect("read restored second file"),
            b"second bytes"
        );
        assert!(!trash_dir.join("first.pdf").exists());
        assert!(!trash_dir.join("second.pdf").exists());
        assert_eq!(file_status(repo.path(), first.id), "active");
        assert_eq!(file_status(repo.path(), second.id), "active");
    });
}

#[test]
fn batch_delete_trash_implementation_remove_index_only_touches_metadata() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_external_root, external_source) = source_file("external.pdf", b"external bytes");
        let indexed_id = indexed_file(repo.path(), &external_source, "finance");
        let adopted_id = adopt_file(repo.path(), "finance/adopted.pdf");
        fs::remove_file(repo.path().join("finance/adopted.pdf")).expect("simulate missing adopted");

        let skipped_preview = preview_batch_delete(
            path_string(repo.path()),
            vec![indexed_id, adopted_id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview wrong mode for index-only entries");

        assert!(skipped_preview.can_apply);
        assert_eq!(skipped_preview.will_trash_count, 0);
        assert_eq!(skipped_preview.index_only_count, 0);
        assert_eq!(skipped_preview.missing_count, 1);
        assert_eq!(skipped_preview.skipped_count, 1);
        assert_eq!(
            skipped_preview.items[0].status,
            BatchDeletePreviewStatus::Skipped
        );
        assert_eq!(
            skipped_preview.items[1].status,
            BatchDeletePreviewStatus::Missing
        );

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![indexed_id, adopted_id],
            BatchDeleteMode::RemoveFromIndex,
        )
        .expect("preview index-only removal");

        assert!(preview.can_apply);
        assert!(!preview.undo_available);
        assert_eq!(preview.will_trash_count, 0);
        assert_eq!(preview.index_only_count, 1);
        assert_eq!(preview.missing_count, 1);
        assert_eq!(preview.blocked_count, 0);

        let report = batch_delete_to_trash(
            path_string(repo.path()),
            vec![indexed_id, adopted_id],
            BatchDeleteMode::RemoveFromIndex,
            preview.preview_token,
        )
        .expect("apply index-only removal");

        assert_eq!(report.moved_to_trash_count, 0);
        assert_eq!(report.removed_from_index_count, 2);
        assert_eq!(report.failed_count, 0);
        assert_eq!(report.undo_token, None);
        assert!(report
            .item_results
            .iter()
            .all(|item| item.status == BatchDeleteResultStatus::RemovedFromIndex));
        assert_eq!(
            fs::read(&external_source).expect("external source remains untouched"),
            b"external bytes"
        );
        assert_eq!(fs::read_dir(trash_dir).expect("read trash").count(), 0);
        assert_eq!(file_status(repo.path(), indexed_id), "deleted");
        assert_eq!(file_status(repo.path(), adopted_id), "deleted");

        let removed_changes = change_actions(repo.path())
            .into_iter()
            .filter(|(_, action, _)| action == "removed_from_index")
            .collect::<Vec<_>>();
        assert_eq!(removed_changes.len(), 2);
        assert!(removed_changes
            .iter()
            .all(|(_, _, detail)| detail["index_only"] == true));
        assert_eq!(
            list_undo_actions(path_string(repo.path()))
                .expect("list undo actions")
                .len(),
            0
        );
    });
}

#[test]
fn batch_delete_trash_implementation_rejects_apply_when_preview_state_changes() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("stale.pdf", b"stale bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "stale.pdf"),
        )
        .expect("import copied file");

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![entry.id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview batch delete");
        fs::rename(
            repo.path().join(&entry.path),
            repo.path().join("finance/stale-renamed.pdf"),
        )
        .expect("simulate external state drift after preview");

        let error = batch_delete_to_trash(
            path_string(repo.path()),
            vec![entry.id],
            BatchDeleteMode::MoveToTrash,
            preview.preview_token,
        )
        .expect_err("stale preview must be rejected");

        assert!(matches!(error, CoreError::Conflict { .. }));
        assert_eq!(file_status(repo.path(), entry.id), "active");
        assert!(repo.path().join("finance/stale-renamed.pdf").exists());
        assert!(change_actions(repo.path())
            .into_iter()
            .all(|(_, action, _)| action != "deleted"));
    });
}

#[test]
fn batch_delete_trash_implementation_rejects_apply_when_file_contents_change() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("changed.pdf", b"before preview");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "changed.pdf"),
        )
        .expect("import copied file");
        let file_path = repo.path().join(&entry.path);

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![entry.id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview batch delete");
        fs::write(&file_path, b"after preview").expect("simulate same-path content drift");

        let error = batch_delete_to_trash(
            path_string(repo.path()),
            vec![entry.id],
            BatchDeleteMode::MoveToTrash,
            preview.preview_token,
        )
        .expect_err("stale preview must be rejected after same-path content drift");

        assert!(matches!(error, CoreError::Conflict { .. }));
        assert_eq!(file_status(repo.path(), entry.id), "active");
        assert_eq!(
            fs::read(&file_path).expect("read changed file"),
            b"after preview"
        );
        assert_eq!(fs::read_dir(trash_dir).expect("read trash").count(), 0);
        assert!(change_actions(repo.path())
            .into_iter()
            .all(|(_, action, _)| action != "deleted"));
    });
}

#[test]
fn batch_delete_trash_implementation_rolls_back_when_undo_write_fails() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("undo-fail.pdf", b"undo failure bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "undo-fail.pdf"),
        )
        .expect("import copied file");
        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![entry.id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview batch delete");
        install_batch_trash_undo_failure(repo.path());

        let error = batch_delete_to_trash(
            path_string(repo.path()),
            vec![entry.id],
            BatchDeleteMode::MoveToTrash,
            preview.preview_token,
        )
        .expect_err("undo action write failure must surface as Db");

        assert!(matches!(error, CoreError::Db { .. }));
        assert_eq!(
            file_status(repo.path(), entry.id),
            "active",
            "DB state is restored when batch undo cannot be written"
        );
        assert_eq!(
            fs::read(repo.path().join(&entry.path)).expect("read restored repo file"),
            b"undo failure bytes"
        );
        assert!(
            !trash_dir.join("undo-fail.pdf").exists(),
            "Trash item is moved back during rollback"
        );
        assert!(change_actions(repo.path())
            .into_iter()
            .all(|(_, action, _)| action != "deleted"));
        assert_eq!(
            list_undo_actions(path_string(repo.path()))
                .expect("list undo actions")
                .len(),
            0
        );
    });
}

#[cfg(unix)]
#[test]
fn batch_delete_trash_implementation_maps_inspection_permission_errors() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        let restricted_root = tempfile::tempdir().expect("create restricted source root");
        let restricted_file = restricted_root.path().join("restricted.pdf");
        fs::write(&restricted_file, b"restricted bytes").expect("write restricted file");
        let indexed_id = indexed_file(repo.path(), &restricted_file, "finance");

        let mut permissions = fs::metadata(restricted_root.path())
            .expect("read restricted root metadata")
            .permissions();
        permissions.set_mode(0o000);
        fs::set_permissions(restricted_root.path(), permissions)
            .expect("make restricted root inaccessible");

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![indexed_id],
            BatchDeleteMode::RemoveFromIndex,
        );

        let mut restored_permissions = fs::metadata(restricted_root.path())
            .expect("read restricted root metadata for restore")
            .permissions();
        restored_permissions.set_mode(0o700);
        fs::set_permissions(restricted_root.path(), restored_permissions)
            .expect("restore restricted root permissions");

        let preview = preview.expect("permission issue is reported per row");
        assert!(!preview.can_apply);
        assert_eq!(preview.blocked_count, 1);
        assert_eq!(preview.items[0].status, BatchDeletePreviewStatus::Blocked);
        assert!(preview.items[0]
            .reason
            .as_deref()
            .expect("blocked reason")
            .contains("PermissionDenied"));
        assert_eq!(file_status(repo.path(), indexed_id), "active");
    });
}
