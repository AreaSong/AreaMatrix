use std::{fs, path::Path};

use area_matrix_core::{
    apply_import_conflict_batch, preview_import_conflict_batch, CoreError,
    ImportConflictBatchApplyReport, ImportConflictBatchApplyRequest,
    ImportConflictBatchPreviewReport, ImportConflictBatchPreviewRequest,
    ImportConflictBatchPreviewStatus, ImportConflictBatchResultStatus, ImportConflictBatchStrategy,
};
use pretty_assertions::assert_eq;

#[path = "support/import_conflict_batch.rs"]
mod import_conflict_batch_support;

use import_conflict_batch_support::{
    create_conflict_schema, file_status, initialized_repo, insert_active_file, insert_conflict,
    insert_import_session, insert_staging_file, open_db, path_string,
};

#[test]
fn import_conflict_batch_requires_confirmation_then_replaces_recoverably() {
    let fixture = replace_fixture("replace-session", "name-replace", "staged-replace");
    let repo = fixture.repo;
    let preview_request = fixture.preview_request;
    let preview = preview_import_conflict_batch(path_string(repo.path()), preview_request.clone())
        .expect("preview replace import conflict");
    assert_replace_preview(&preview, "name-replace", "docs/report.pdf");

    assert!(matches!(
        apply_import_conflict_batch(
            path_string(repo.path()),
            apply_request_from_preview(preview_request.clone(), false),
            preview.preview_token.clone(),
        ),
        Err(CoreError::Conflict { .. })
    ));
    assert_unconfirmed_replace_left_files(repo.path(), fixture.existing, fixture.staging);

    let report = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(preview_request, true),
        preview.preview_token,
    )
    .expect("apply confirmed replace import conflict");
    assert_confirmed_replace_report(&report, fixture.existing, fixture.staging, "name-replace");
    assert_replaced_files(
        repo.path(),
        fixture.existing,
        fixture.staging,
        "name-replace",
    );
}

#[test]
fn import_conflict_batch_queues_ask_per_item_without_promoting_staging() {
    let repo = initialized_conflict_repo();
    let session_id = "ask-session";
    insert_import_session(repo.path(), session_id);
    let existing = insert_active_file(repo.path(), "docs/manual.pdf", "hash-old");
    let staging = insert_staging_file(repo.path(), "staged-ask", "manual.pdf", "hash-new");
    insert_conflict(
        repo.path(),
        session_id,
        "ask-1",
        "same_name_different_content",
        staging,
        existing,
        "docs/manual.pdf",
    );

    let preview_request = ImportConflictBatchPreviewRequest {
        import_session_id: session_id.to_owned(),
        conflict_ids: vec!["ask-1".to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::AskPerItem,
        apply_to_all_similar_conflicts: false,
    };

    let preview = preview_import_conflict_batch(path_string(repo.path()), preview_request.clone())
        .expect("preview ask-per-item import conflict");
    assert_ask_per_item_preview(&preview);

    let report = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(preview_request, false),
        preview.preview_token,
    )
    .expect("apply ask-per-item import conflict");

    assert_ask_per_item_report(&report);
    assert_ask_per_item_kept_files(repo.path(), existing, staging);
}

#[test]
fn import_conflict_batch_preserves_staging_and_conflict_after_replace_failure() {
    let fixture = replace_fixture("failed-replace-session", "replace-fails", "staged-failure");
    let repo = fixture.repo;
    let preview_request = fixture.preview_request;
    let preview = preview_import_conflict_batch(path_string(repo.path()), preview_request.clone())
        .expect("preview failed replace import conflict");

    write_failure_fixture_bytes(repo.path(), "staged-failure");
    open_db(repo.path())
        .execute("DROP TABLE change_log", [])
        .expect("simulate DB failure after filesystem moves");

    let report = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(preview_request, true),
        preview.preview_token,
    )
    .expect("replace apply returns per-item failure report");

    assert_replace_failure_report(&report);
    assert_replace_failure_kept_files(repo.path(), fixture.existing, fixture.staging);
}

#[test]
fn import_conflict_batch_preflights_undo_write_before_mutating_files() {
    let fixture = replace_fixture("undo-preflight-session", "undo-preflight", "staged-undo");
    let repo = fixture.repo;
    let preview_request = fixture.preview_request;
    let preview = preview_import_conflict_batch(path_string(repo.path()), preview_request.clone())
        .expect("preview replace import conflict");
    write_failure_fixture_bytes(repo.path(), "staged-undo");
    install_import_conflict_undo_failure(repo.path());

    let error = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(preview_request, true),
        preview.preview_token,
    )
    .expect_err("undo write preflight aborts before mutation");

    assert!(matches!(error, CoreError::Db { .. }));
    assert_replace_undo_failure_left_files(repo.path(), fixture.existing, fixture.staging);
}

#[test]
fn import_conflict_batch_rolls_back_after_late_undo_write_failure() {
    let fixture = replace_fixture("late-undo-session", "late-undo", "staged-late-undo");
    let repo = fixture.repo;
    let preview_request = fixture.preview_request;
    let preview = preview_import_conflict_batch(path_string(repo.path()), preview_request.clone())
        .expect("preview replace import conflict");
    write_failure_fixture_bytes(repo.path(), "staged-late-undo");
    install_late_import_conflict_undo_failure(repo.path());

    let error = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(preview_request, true),
        preview.preview_token,
    )
    .expect_err("late undo write failure rolls back mutation");

    assert!(matches!(error, CoreError::Db { .. }));
    assert_replace_undo_failure_left_files(repo.path(), fixture.existing, fixture.staging);
}

struct ReplaceFixture {
    repo: tempfile::TempDir,
    existing: i64,
    staging: i64,
    preview_request: ImportConflictBatchPreviewRequest,
}

fn initialized_conflict_repo() -> tempfile::TempDir {
    let repo = initialized_repo();
    create_conflict_schema(repo.path());
    repo
}

fn replace_fixture(session_id: &str, conflict_id: &str, staging_name: &str) -> ReplaceFixture {
    let repo = initialized_conflict_repo();
    insert_import_session(repo.path(), session_id);
    let existing = insert_active_file(repo.path(), "docs/report.pdf", "hash-old");
    let staging = insert_staging_file(repo.path(), staging_name, "report.pdf", "hash-new");
    insert_conflict(
        repo.path(),
        session_id,
        conflict_id,
        "same_name_different_content",
        staging,
        existing,
        "docs/report.pdf",
    );
    ReplaceFixture {
        repo,
        existing,
        staging,
        preview_request: replace_preview_request(session_id, conflict_id),
    }
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
    preview_request: ImportConflictBatchPreviewRequest,
    replace_confirmed: bool,
) -> ImportConflictBatchApplyRequest {
    ImportConflictBatchApplyRequest {
        import_session_id: preview_request.import_session_id,
        conflict_ids: preview_request.conflict_ids,
        duplicate_strategy: preview_request.duplicate_strategy,
        same_name_strategy: preview_request.same_name_strategy,
        apply_to_all_similar_conflicts: preview_request.apply_to_all_similar_conflicts,
        replace_confirmed,
    }
}

fn assert_replace_preview(
    preview: &ImportConflictBatchPreviewReport,
    conflict_id: &str,
    target_path: &str,
) {
    assert!(preview.can_apply);
    assert!(preview.replace_confirmation_required);
    assert_eq!(preview.replace_count, 1);
    let preview_item = preview
        .items
        .iter()
        .find(|item| item.conflict_id == conflict_id)
        .expect("replace preview row");
    assert_eq!(
        preview_item.status,
        ImportConflictBatchPreviewStatus::NeedsConfirmation
    );
    assert_eq!(preview_item.target_path.as_deref(), Some(target_path));
}

fn assert_unconfirmed_replace_left_files(repo: &Path, existing: i64, staging: i64) {
    assert_eq!(
        file_status(repo, existing),
        (
            "docs/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        file_status(repo, staging),
        (
            ".areamatrix/staging/staged-replace".to_owned(),
            "report.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
}

fn assert_confirmed_replace_report(
    report: &ImportConflictBatchApplyReport,
    existing: i64,
    staging: i64,
    conflict_id: &str,
) {
    assert_eq!(report.resolved_count, 1);
    assert_eq!(report.replaced_count, 1);
    assert_eq!(report.failed_count, 0);
    assert_eq!(report.affected_file_ids, vec![existing, staging]);
    assert_eq!(report.change_log_actions, vec!["deleted", "imported"]);
    assert!(report.undo_token.is_some());
    let item = report
        .item_results
        .iter()
        .find(|item| item.conflict_id == conflict_id)
        .expect("replace result row");
    assert_eq!(item.status, ImportConflictBatchResultStatus::Replaced);
    assert_eq!(item.file_id, Some(staging));
    assert_eq!(item.final_path.as_deref(), Some("docs/report.pdf"));
}

fn assert_replaced_files(repo: &Path, existing: i64, staging: i64, conflict_id: &str) {
    let (archived_path, _archived_name, archived_status) = file_status(repo, existing);
    assert!(archived_path.starts_with(".areamatrix/trash-pending/import-conflict-"));
    assert_eq!(archived_status, "deleted");
    assert_eq!(
        file_status(repo, staging),
        (
            "docs/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert!(repo.join(&archived_path).exists());
    assert_eq!(
        fs::read_to_string(repo.join("docs/report.pdf")).expect("read replacement final file"),
        "staged bytes for report.pdf"
    );
    assert_eq!(
        conflict_status(repo, conflict_id),
        ("resolved".to_owned(), Some("replace".to_owned()), None,)
    );
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

fn assert_ask_per_item_preview(preview: &ImportConflictBatchPreviewReport) {
    assert!(preview.can_apply);
    assert_eq!(preview.ask_per_item_count, 1);
    assert_eq!(preview.pending_count, 0);
}

fn assert_ask_per_item_report(report: &ImportConflictBatchApplyReport) {
    assert_eq!(report.resolved_count, 1);
    assert_eq!(report.queued_for_per_item_count, 1);
    assert_eq!(report.failed_count, 0);
    assert!(report.affected_file_ids.is_empty());
    assert!(report.undo_token.is_none());
    assert_eq!(report.change_log_actions, Vec::<String>::new());
    assert_eq!(
        report.item_results[0].status,
        ImportConflictBatchResultStatus::QueuedForPerItem
    );
}

fn assert_ask_per_item_kept_files(repo: &Path, existing: i64, staging: i64) {
    assert_eq!(
        file_status(repo, staging),
        (
            ".areamatrix/staging/staged-ask".to_owned(),
            "manual.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
    assert!(repo.join(".areamatrix/staging/staged-ask").exists());
    assert_eq!(
        file_status(repo, existing),
        (
            "docs/manual.pdf".to_owned(),
            "manual.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        conflict_status(repo, "ask-1"),
        (
            "queued_for_per_item".to_owned(),
            Some("ask_per_item".to_owned()),
            None,
        )
    );
}

fn write_failure_fixture_bytes(repo: &Path, staging_name: &str) {
    fs::write(
        repo.join(".areamatrix/staging").join(staging_name),
        b"staged bytes that must survive rollback",
    )
    .expect("rewrite staging fixture");
    fs::write(
        repo.join("docs/report.pdf"),
        b"original bytes that must be restored",
    )
    .expect("rewrite existing fixture");
}

fn assert_replace_failure_report(report: &ImportConflictBatchApplyReport) {
    assert_eq!(report.resolved_count, 0);
    assert_eq!(report.replaced_count, 0);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.failure_summary.as_deref(),
        Some("1 import conflict(s) failed and remain staged for retry")
    );
    assert_eq!(
        report.item_results[0].status,
        ImportConflictBatchResultStatus::Failed
    );
    assert!(report.item_results[0]
        .error
        .as_deref()
        .is_some_and(|reason| reason.contains("no such table: change_log")));
}

fn assert_replace_failure_kept_files(repo: &Path, existing: i64, staging: i64) {
    assert_eq!(
        fs::read(repo.join(".areamatrix/staging/staged-failure"))
            .expect("staging remains after replace failure"),
        b"staged bytes that must survive rollback"
    );
    assert_eq!(
        fs::read(repo.join("docs/report.pdf"))
            .expect("existing file restored after replace failure"),
        b"original bytes that must be restored"
    );
    assert_eq!(
        file_status(repo, existing),
        (
            "docs/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        file_status(repo, staging),
        (
            ".areamatrix/staging/staged-failure".to_owned(),
            "report.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
    let (status, decision, failure_reason) = conflict_status(repo, "replace-fails");
    assert_eq!(status, "failed");
    assert_eq!(decision.as_deref(), Some("replace"));
    assert!(failure_reason
        .as_deref()
        .is_some_and(|reason| reason.contains("no such table: change_log")));
}

fn install_late_import_conflict_undo_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_real_import_conflict_undo
             BEFORE INSERT ON undo_actions
             WHEN NEW.kind = 'import_conflict_batch'
              AND NEW.summary_json NOT LIKE '%preflight%'
             BEGIN
               SELECT RAISE(ABORT, 'forced late import conflict undo failure');
             END;",
        )
        .expect("install late import conflict undo failure trigger");
}

fn install_import_conflict_undo_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_import_conflict_undo
             BEFORE INSERT ON undo_actions
             WHEN NEW.kind = 'import_conflict_batch'
             BEGIN
               SELECT RAISE(ABORT, 'forced import conflict undo failure');
             END;",
        )
        .expect("install import conflict undo failure trigger");
}

fn assert_replace_undo_failure_left_files(repo: &Path, existing: i64, staging: i64) {
    let (staging_path, staging_name, staging_status) = file_status(repo, staging);
    assert_eq!(
        fs::read(repo.join(&staging_path)).expect("staging remains after undo failure"),
        b"staged bytes that must survive rollback"
    );
    assert_eq!(
        fs::read(repo.join("docs/report.pdf")).expect("existing file restored after undo failure"),
        b"original bytes that must be restored"
    );
    assert_eq!(
        file_status(repo, existing),
        (
            "docs/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        (staging_name, staging_status),
        ("report.pdf".to_owned(), "staging".to_owned())
    );
}
