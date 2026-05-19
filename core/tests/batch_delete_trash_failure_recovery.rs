use std::{
    fs,
    path::{Path, PathBuf},
};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use area_matrix_core::{
    batch_delete_to_trash, import_file, init_repo, list_undo_actions, preview_batch_delete,
    BatchDeleteMode, BatchDeletePreviewStatus, BatchDeleteResultStatus, CoreError,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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

fn import_options(filename: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
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

fn change_actions(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT action FROM change_log ORDER BY id")
        .expect("prepare change rows query");
    statement
        .query_map([], |row| row.get(0))
        .expect("query change rows")
        .map(|row| row.expect("read change row"))
        .collect()
}

fn indexed_file(repo: &Path, source_path: &Path) -> i64 {
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
                ?1, ?2, ?2, 'finance', 13,
                ?3, 'indexed', 'imported', ?1,
                100, 100, 'active'
             )",
            params![
                path,
                current_name,
                format!("{:064x}", path_string(source_path).len())
            ],
        )
        .expect("insert indexed file row");
    connection.last_insert_rowid()
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

fn install_removed_from_index_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_removed_from_index_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'removed_from_index'
             BEGIN
               SELECT RAISE(ABORT, 'forced removed_from_index log failure');
             END;",
        )
        .expect("install removed_from_index log failure trigger");
}

#[test]
fn batch_delete_failure_recovery_maps_empty_and_invalid_inputs() {
    let uninitialized_repo = tempfile::tempdir().expect("create uninitialized repo");

    assert!(matches!(
        preview_batch_delete(String::new(), vec![1], BatchDeleteMode::MoveToTrash),
        Err(CoreError::PermissionDenied { .. })
    ));
    assert!(matches!(
        preview_batch_delete(
            path_string(uninitialized_repo.path()),
            Vec::new(),
            BatchDeleteMode::MoveToTrash
        ),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        preview_batch_delete(
            path_string(uninitialized_repo.path()),
            vec![0],
            BatchDeleteMode::MoveToTrash
        ),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        preview_batch_delete(
            path_string(uninitialized_repo.path()),
            vec![1],
            BatchDeleteMode::MoveToTrash
        ),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        batch_delete_to_trash(
            path_string(uninitialized_repo.path()),
            vec![1],
            BatchDeleteMode::MoveToTrash,
            String::new()
        ),
        Err(CoreError::Conflict { .. })
    ));
}

#[cfg(unix)]
#[test]
fn batch_delete_failure_recovery_disables_apply_when_trash_is_not_writable() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root, source) = source_file("blocked-trash.pdf", b"blocked trash bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options("blocked-trash.pdf"),
        )
        .expect("import copied file");

        let mut restricted = fs::metadata(trash_dir)
            .expect("read trash permissions")
            .permissions();
        restricted.set_mode(0o500);
        fs::set_permissions(trash_dir, restricted).expect("make trash not writable");

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![entry.id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview reports trash as unavailable");

        let mut restored = fs::metadata(trash_dir)
            .expect("read trash permissions for restore")
            .permissions();
        restored.set_mode(0o700);
        fs::set_permissions(trash_dir, restored).expect("restore trash permissions");

        assert!(!preview.trash_available);
        assert!(!preview.can_apply);
        assert_eq!(preview.blocked_count, 1);
        assert_eq!(preview.items[0].status, BatchDeletePreviewStatus::Blocked);
        assert!(preview.items[0]
            .reason
            .as_deref()
            .expect("blocked reason")
            .contains("PermissionDenied"));
        assert_eq!(file_status(repo.path(), entry.id), "active");
        assert!(repo.path().join(&entry.path).exists());
    });
}

#[test]
fn batch_delete_failure_recovery_reports_db_item_failure_without_touching_source() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_external_root, external_source) = source_file("external.pdf", b"external bytes");
        let indexed_id = indexed_file(repo.path(), &external_source);
        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![indexed_id],
            BatchDeleteMode::RemoveFromIndex,
        )
        .expect("preview index-only removal");
        install_removed_from_index_log_failure(repo.path());

        let report = batch_delete_to_trash(
            path_string(repo.path()),
            vec![indexed_id],
            BatchDeleteMode::RemoveFromIndex,
            preview.preview_token,
        )
        .expect("per-item db failure returns execution report");

        assert_eq!(report.removed_from_index_count, 0);
        assert_eq!(report.failed_count, 1);
        assert_eq!(
            report.item_results[0].status,
            BatchDeleteResultStatus::Failed
        );
        assert!(report.item_results[0]
            .error
            .as_deref()
            .expect("db error is surfaced")
            .contains("Db:"));
        assert_eq!(file_status(repo.path(), indexed_id), "active");
        assert_eq!(
            fs::read(&external_source).expect("read external source"),
            b"external bytes"
        );
        assert_eq!(fs::read_dir(trash_dir).expect("read trash").count(), 0);
    });
}

#[test]
fn batch_delete_failure_recovery_rolls_back_mixed_metadata_when_undo_write_fails() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_keep_root, keep_source) = source_file("keep.pdf", b"keep bytes");
        let keep = import_file(
            path_string(repo.path()),
            path_string(&keep_source),
            import_options("keep.pdf"),
        )
        .expect("import file that will reach Trash");
        let (_missing_root, missing_source) = source_file("missing.pdf", b"missing bytes");
        let missing = import_file(
            path_string(repo.path()),
            path_string(&missing_source),
            import_options("missing.pdf"),
        )
        .expect("import file that will be missing before apply");
        fs::remove_file(repo.path().join(&missing.path)).expect("simulate missing repo file");

        let skipped_preview = preview_batch_delete(
            path_string(repo.path()),
            vec![keep.id, missing.id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview mixed trash and skipped missing metadata removal");
        assert_eq!(skipped_preview.will_trash_count, 1);
        assert_eq!(skipped_preview.missing_count, 0);
        assert_eq!(skipped_preview.skipped_count, 1);
        install_batch_trash_undo_failure(repo.path());

        let error = batch_delete_to_trash(
            path_string(repo.path()),
            vec![keep.id, missing.id],
            BatchDeleteMode::MoveToTrash,
            skipped_preview.preview_token,
        )
        .expect_err("undo action write failure must abort the batch");

        assert!(matches!(error, CoreError::Db { .. }));
        assert_eq!(file_status(repo.path(), keep.id), "active");
        assert_eq!(file_status(repo.path(), missing.id), "active");
        assert_eq!(
            fs::read(repo.path().join(&keep.path)).expect("repo-owned file restored"),
            b"keep bytes"
        );
        assert!(!repo.path().join(&missing.path).exists());
        assert_eq!(fs::read_dir(trash_dir).expect("read trash").count(), 0);
        assert!(change_actions(repo.path())
            .into_iter()
            .all(|action| action != "deleted" && action != "removed_from_index"));
        assert_eq!(
            list_undo_actions(path_string(repo.path()))
                .expect("list undo actions")
                .len(),
            0
        );
    });
}
