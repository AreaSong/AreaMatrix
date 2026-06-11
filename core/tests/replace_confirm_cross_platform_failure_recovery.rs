use std::{fs, path::Path};

use area_matrix_core::{
    apply_import_conflict_batch, delete_file, import_file, map_core_error,
    preview_import_conflict_batch, preview_sync_conflict_resolution, resolve_sync_conflict,
    CoreError, DuplicateStrategy, ErrorKind, ErrorMappingInput, ErrorRecoverability,
    ImportConflictBatchApplyRequest, ImportConflictBatchPreviewRequest,
    ImportConflictBatchPreviewStatus, ImportConflictBatchStrategy, ImportDestination,
    ImportOptions, StorageMode, SyncConflictResolutionRequest, SyncConflictResolutionStrategy,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection, OptionalExtension};

mod support;

#[path = "support/import_conflict_batch.rs"]
mod import_conflict_batch_support;

use import_conflict_batch_support::{
    create_conflict_schema, file_status, initialized_repo, insert_active_file, insert_conflict,
    insert_import_session, insert_staging_file,
};
use support::system_trash_home::with_test_system_trash;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn source_file(name: &str, bytes: &[u8]) -> tempfile::TempDir {
    let source = tempfile::tempdir().expect("create source directory");
    fs::write(source.path().join(name), bytes).expect("write source file");
    source
}

fn import_options(filename: &str, strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("docs".to_owned()),
        override_category: None,
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: strategy,
    }
}

fn import_named_file(
    repo: &Path,
    filename: &str,
    bytes: &[u8],
    strategy: DuplicateStrategy,
) -> area_matrix_core::FileEntry {
    let source = source_file(filename, bytes);
    import_file(
        path_string(repo),
        path_string(&source.path().join(filename)),
        import_options(filename, strategy),
    )
    .expect("import file")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn active_file_row(repo: &Path, file_id: i64) -> Option<(String, String, Option<i64>)> {
    open_db(repo)
        .query_row(
            "SELECT path, status, deleted_at FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()
        .expect("read file row")
}

fn active_path_count(repo: &Path, path: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE path = ?1 AND status = 'active'",
            [path],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

fn action_count(repo: &Path, action: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE action = ?1",
            [action],
            |row| row.get(0),
        )
        .expect("count change-log rows")
}

fn user_files(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_files(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
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

fn install_imported_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_replace_imported_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced replace import change-log failure');
             END;",
        )
        .expect("install imported change-log failure trigger");
}

fn initialized_conflict_repo() -> tempfile::TempDir {
    let repo = initialized_repo();
    create_conflict_schema(repo.path());
    repo
}

fn replace_preview_request(
    session_id: &str,
    conflict_id: &str,
) -> ImportConflictBatchPreviewRequest {
    ImportConflictBatchPreviewRequest {
        import_session_id: session_id.to_owned(),
        conflict_ids: vec![conflict_id.to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::Replace,
        apply_to_all_similar_conflicts: false,
    }
}

fn apply_request_from_preview(
    preview: ImportConflictBatchPreviewRequest,
    replace_confirmed: bool,
) -> ImportConflictBatchApplyRequest {
    ImportConflictBatchApplyRequest {
        import_session_id: preview.import_session_id,
        conflict_ids: preview.conflict_ids,
        duplicate_strategy: preview.duplicate_strategy,
        same_name_strategy: preview.same_name_strategy,
        apply_to_all_similar_conflicts: preview.apply_to_all_similar_conflicts,
        replace_confirmed,
    }
}

fn conflict_status(repo: &Path, conflict_id: &str) -> (String, Option<String>, Option<String>) {
    open_db(repo)
        .query_row(
            "SELECT status, decision, failure_reason
               FROM import_conflicts
              WHERE conflict_id = ?1",
            [conflict_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read conflict status")
}

#[test]
fn replace_confirm_failure_edge_rejects_empty_and_illegal_inputs_without_writes() {
    let source = source_file("report.pdf", b"unused");
    let import_result = import_file(
        String::new(),
        path_string(&source.path().join("report.pdf")),
        import_options("report.pdf", DuplicateStrategy::Overwrite),
    );
    assert!(matches!(import_result, Err(CoreError::InvalidPath { .. })));

    let delete_result = delete_file(String::new(), 42);
    assert!(matches!(delete_result, Err(CoreError::InvalidPath { .. })));

    let preview_result = preview_sync_conflict_resolution(
        String::new(),
        String::new(),
        SyncConflictResolutionStrategy::UseIncoming,
    );
    assert!(matches!(preview_result, Err(CoreError::Io { .. })));

    let resolve_result = resolve_sync_conflict(
        String::new(),
        "conflict".to_owned(),
        SyncConflictResolutionRequest {
            strategy: SyncConflictResolutionStrategy::UseIncoming,
            preview_token: String::new(),
            replace_confirmed: true,
            replace_confirmation_id: Some("replace-confirmed".to_owned()),
        },
    );
    assert!(matches!(resolve_result, Err(CoreError::Io { .. })));

    let missing_token_result = resolve_sync_conflict(
        "/tmp/not-initialized".to_owned(),
        "conflict".to_owned(),
        SyncConflictResolutionRequest {
            strategy: SyncConflictResolutionStrategy::UseIncoming,
            preview_token: String::new(),
            replace_confirmed: true,
            replace_confirmation_id: Some("replace-confirmed".to_owned()),
        },
    );
    assert!(matches!(
        missing_token_result,
        Err(CoreError::Conflict { .. })
    ));

    let batch_result = apply_import_conflict_batch(
        String::new(),
        ImportConflictBatchApplyRequest {
            import_session_id: String::new(),
            conflict_ids: Vec::new(),
            duplicate_strategy: ImportConflictBatchStrategy::Skip,
            same_name_strategy: ImportConflictBatchStrategy::Replace,
            apply_to_all_similar_conflicts: false,
            replace_confirmed: false,
        },
        String::new(),
    );
    assert!(matches!(batch_result, Err(CoreError::Conflict { .. })));
}

#[test]
fn replace_confirm_failure_edge_import_overwrite_db_failure_restores_original_file() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let existing = import_named_file(
            repo.path(),
            "report.pdf",
            b"existing-version",
            DuplicateStrategy::Skip,
        );
        let before_files = user_files(repo.path());
        let before_row = active_file_row(repo.path(), existing.id);
        let before_deleted_count = action_count(repo.path(), "deleted");
        let source = source_file("report.pdf", b"replacement-version");
        install_imported_change_log_failure(repo.path());

        let result = import_file(
            path_string(repo.path()),
            path_string(&source.path().join("report.pdf")),
            import_options("report.pdf", DuplicateStrategy::Overwrite),
        );

        assert!(matches!(result, Err(CoreError::Db { .. })));
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(active_file_row(repo.path(), existing.id), before_row);
        assert_eq!(active_path_count(repo.path(), "docs/report.pdf"), 1);
        assert_eq!(action_count(repo.path(), "deleted"), before_deleted_count);
        assert_eq!(
            fs::read(repo.path().join("docs/report.pdf")).expect("read restored original"),
            b"existing-version"
        );
        assert_eq!(
            fs::read(source.path().join("report.pdf")).expect("source remains readable"),
            b"replacement-version"
        );
        assert!(
            fs::read_dir(trash_dir)
                .expect("read isolated trash")
                .next()
                .is_none(),
            "failed replace must not leave a user-facing Trash copy"
        );
    });
}

#[test]
fn replace_confirm_failure_edge_delete_db_failure_restores_file_and_retryable_state() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let entry = import_named_file(
            repo.path(),
            "delete-me.pdf",
            b"delete-target",
            DuplicateStrategy::Skip,
        );
        let before_files = user_files(repo.path());
        let before_row = active_file_row(repo.path(), entry.id);
        open_db(repo.path())
            .execute(
                "CREATE TRIGGER fail_delete_change_log
                 BEFORE INSERT ON change_log
                 WHEN NEW.action = 'deleted'
                 BEGIN
                   SELECT RAISE(ABORT, 'forced delete change-log failure');
                 END;",
                params![],
            )
            .expect("install delete failure trigger");

        let result = delete_file(path_string(repo.path()), entry.id);

        assert!(matches!(result, Err(CoreError::Db { .. })));
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(active_file_row(repo.path(), entry.id), before_row);
        assert_eq!(action_count(repo.path(), "deleted"), 0);
        assert!(
            fs::read_dir(trash_dir)
                .expect("read isolated trash")
                .next()
                .is_none(),
            "failed delete must not leave a user-facing Trash copy"
        );
    });
}

#[test]
fn replace_confirm_failure_edge_import_conflict_replace_requires_fresh_confirmation() {
    let repo = initialized_conflict_repo();
    insert_import_session(repo.path(), "replace-session");
    let existing = insert_active_file(repo.path(), "docs/report.pdf", "hash-old");
    let staging = insert_staging_file(repo.path(), "staged-replace", "report.pdf", "hash-new");
    insert_conflict(
        repo.path(),
        "replace-session",
        "name-replace",
        "same_name_different_content",
        staging,
        existing,
        "docs/report.pdf",
    );
    let request = replace_preview_request("replace-session", "name-replace");
    let preview = preview_import_conflict_batch(path_string(repo.path()), request.clone())
        .expect("preview replace conflict");
    assert!(preview.replace_confirmation_required);
    assert_eq!(
        preview.items[0].status,
        ImportConflictBatchPreviewStatus::NeedsConfirmation
    );
    let before_existing_bytes =
        fs::read(repo.path().join("docs/report.pdf")).expect("read existing file");
    let before_staging_bytes = fs::read(repo.path().join(".areamatrix/staging/staged-replace"))
        .expect("read staging file");

    let unconfirmed = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request.clone(), false),
        preview.preview_token.clone(),
    );
    assert!(matches!(unconfirmed, Err(CoreError::Conflict { .. })));

    let stale = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, true),
        format!("{}-stale", preview.preview_token),
    );
    assert!(matches!(stale, Err(CoreError::Conflict { .. })));

    assert_eq!(
        fs::read(repo.path().join("docs/report.pdf")).expect("read existing after rejects"),
        before_existing_bytes
    );
    assert_eq!(
        fs::read(repo.path().join(".areamatrix/staging/staged-replace"))
            .expect("read staging after rejects"),
        before_staging_bytes
    );
    assert_eq!(
        file_status(repo.path(), existing),
        (
            "docs/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "active".to_owned()
        )
    );
    assert_eq!(
        file_status(repo.path(), staging),
        (
            ".areamatrix/staging/staged-replace".to_owned(),
            "report.pdf".to_owned(),
            "staging".to_owned()
        )
    );
    assert_eq!(
        conflict_status(repo.path(), "name-replace"),
        ("pending".to_owned(), None, None)
    );
}

#[test]
fn replace_confirm_failure_edge_error_mapping_is_actionable_for_replace_failures() {
    for (kind, recoverability) in [
        (
            ErrorKind::PermissionDenied,
            ErrorRecoverability::UserActionRequired,
        ),
        (ErrorKind::Conflict, ErrorRecoverability::UserActionRequired),
        (ErrorKind::Io, ErrorRecoverability::Retryable),
        (ErrorKind::Db, ErrorRecoverability::UserActionRequired),
        (
            ErrorKind::StagingRecoveryRequired,
            ErrorRecoverability::UserActionRequired,
        ),
    ] {
        let mapping = map_core_error(ErrorMappingInput {
            kind: kind.clone(),
            path: Some("docs/report.pdf".to_owned()),
            reason: None,
            message: Some("replace failed".to_owned()),
        });

        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.recoverability, recoverability);
        assert!(
            !mapping.user_message.trim().is_empty(),
            "replace failures must not map to silent or empty UI messages"
        );
        assert!(
            !mapping.suggested_action.trim().is_empty(),
            "replace failures must expose an actionable recovery hint"
        );
    }
}
