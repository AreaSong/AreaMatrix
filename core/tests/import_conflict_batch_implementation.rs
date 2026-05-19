use area_matrix_core::{
    apply_import_conflict_batch, preview_import_conflict_batch, ImportConflictBatchApplyRequest,
    ImportConflictBatchPreviewRequest, ImportConflictBatchResultStatus,
    ImportConflictBatchStrategy,
};
use pretty_assertions::assert_eq;

#[path = "support/import_conflict_batch.rs"]
mod import_conflict_batch_support;

use import_conflict_batch_support::{
    create_conflict_schema, file_status, initialized_repo, insert_active_file, insert_conflict,
    insert_import_session, insert_staging_file, open_db, path_string,
};

#[test]
fn import_conflict_batch_implementation_previews_and_applies_skip_and_keep_both() {
    let repo = initialized_repo();
    create_conflict_schema(repo.path());
    let session_id = "session-42";
    insert_import_session(repo.path(), session_id);
    let existing_duplicate = insert_active_file(repo.path(), "docs/duplicate.pdf", "hash-dup");
    let existing_named = insert_active_file(repo.path(), "docs/report.pdf", "hash-existing");
    let duplicate_staging =
        insert_staging_file(repo.path(), "staged-duplicate", "duplicate.pdf", "hash-dup");
    let named_staging = insert_staging_file(repo.path(), "staged-report", "report.pdf", "hash-new");
    insert_conflict(
        repo.path(),
        session_id,
        "dup-1",
        "duplicate_hash",
        duplicate_staging,
        existing_duplicate,
        "docs/duplicate.pdf",
    );
    insert_conflict(
        repo.path(),
        session_id,
        "name-1",
        "same_name_different_content",
        named_staging,
        existing_named,
        "docs/report.pdf",
    );

    let preview_request = ImportConflictBatchPreviewRequest {
        import_session_id: session_id.to_owned(),
        conflict_ids: vec!["dup-1".to_owned(), "name-1".to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::KeepBoth,
        apply_to_all_similar_conflicts: false,
    };

    let preview = preview_import_conflict_batch(path_string(repo.path()), preview_request.clone())
        .expect("preview import conflict batch");

    assert!(preview.can_apply);
    assert_eq!(preview.skip_count, 1);
    assert_eq!(preview.keep_both_count, 1);
    assert_eq!(preview.replace_count, 0);
    let keep_both = preview
        .items
        .iter()
        .find(|item| item.conflict_id == "name-1")
        .expect("keep-both preview row");
    assert_eq!(keep_both.target_path.as_deref(), Some("docs/report_1.pdf"));
    assert!(repo
        .path()
        .join(".areamatrix/staging/staged-report")
        .exists());
    assert!(!repo.path().join("docs/report_1.pdf").exists());

    let report = apply_import_conflict_batch(
        path_string(repo.path()),
        ImportConflictBatchApplyRequest {
            import_session_id: session_id.to_owned(),
            conflict_ids: preview_request.conflict_ids,
            duplicate_strategy: preview_request.duplicate_strategy,
            same_name_strategy: preview_request.same_name_strategy,
            apply_to_all_similar_conflicts: preview_request.apply_to_all_similar_conflicts,
            replace_confirmed: false,
        },
        preview.preview_token,
    )
    .expect("apply import conflict batch");

    assert_eq!(report.resolved_count, 2);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.kept_both_count, 1);
    assert_eq!(report.replaced_count, 0);
    assert_eq!(report.failed_count, 0);
    assert_eq!(report.affected_file_ids, vec![named_staging]);
    assert!(report.undo_token.is_some());
    assert_eq!(report.change_log_actions, vec!["imported"]);
    assert_eq!(
        report
            .item_results
            .iter()
            .find(|item| item.conflict_id == "dup-1")
            .expect("skip result")
            .status,
        ImportConflictBatchResultStatus::Skipped
    );

    assert_eq!(
        file_status(repo.path(), duplicate_staging),
        (
            ".areamatrix/staging/staged-duplicate".to_owned(),
            "duplicate.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
    assert_eq!(
        file_status(repo.path(), named_staging),
        (
            "docs/report_1.pdf".to_owned(),
            "report_1.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert!(!repo
        .path()
        .join(".areamatrix/staging/staged-report")
        .exists());
    assert!(repo.path().join("docs/report_1.pdf").exists());
    assert_eq!(
        conflict_statuses(repo.path()),
        vec![
            (
                "dup-1".to_owned(),
                "resolved".to_owned(),
                Some("skip".to_owned())
            ),
            (
                "name-1".to_owned(),
                "resolved".to_owned(),
                Some("keep_both".to_owned()),
            ),
        ]
    );
    assert_eq!(change_log_actions(repo.path()), vec!["imported"]);
}

#[test]
fn import_conflict_batch_continues_pending_rows_after_partial_keep_both_apply() {
    let repo = initialized_repo();
    create_conflict_schema(repo.path());
    let session_id = "partial-session";
    insert_import_session(repo.path(), session_id);
    let existing_report = insert_active_file(repo.path(), "docs/report.pdf", "hash-report-old");
    let existing_budget = insert_active_file(repo.path(), "docs/budget.pdf", "hash-budget-old");
    let report_staging = insert_staging_file(
        repo.path(),
        "staged-report",
        "report.pdf",
        "hash-report-new",
    );
    let budget_staging = insert_staging_file(
        repo.path(),
        "staged-budget",
        "budget.pdf",
        "hash-budget-new",
    );
    insert_conflict(
        repo.path(),
        session_id,
        "name-1",
        "same_name_different_content",
        report_staging,
        existing_report,
        "docs/report.pdf",
    );
    insert_conflict(
        repo.path(),
        session_id,
        "name-2",
        "same_name_different_content",
        budget_staging,
        existing_budget,
        "docs/budget.pdf",
    );

    let first_request = keep_both_request(session_id, "name-1");
    let first_preview =
        preview_import_conflict_batch(path_string(repo.path()), first_request.clone())
            .expect("preview first partial import conflict batch");
    assert!(first_preview.can_apply);
    assert_eq!(first_preview.included_count, 1);
    assert_eq!(first_preview.keep_both_count, 1);

    let first_report = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(first_request),
        first_preview.preview_token,
    )
    .expect("apply first partial import conflict batch");
    assert_eq!(first_report.resolved_count, 1);
    assert_eq!(first_report.kept_both_count, 1);
    assert_eq!(first_report.failed_count, 0);
    assert_eq!(
        conflict_statuses(repo.path()),
        vec![
            (
                "name-1".to_owned(),
                "resolved".to_owned(),
                Some("keep_both".to_owned()),
            ),
            ("name-2".to_owned(), "pending".to_owned(), None),
        ]
    );
    assert_eq!(
        file_status(repo.path(), report_staging),
        (
            "docs/report_1.pdf".to_owned(),
            "report_1.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        file_status(repo.path(), budget_staging),
        (
            ".areamatrix/staging/staged-budget".to_owned(),
            "budget.pdf".to_owned(),
            "staging".to_owned(),
        )
    );

    let second_request = keep_both_request(session_id, "name-2");
    let second_preview =
        preview_import_conflict_batch(path_string(repo.path()), second_request.clone())
            .expect("preview remaining pending import conflict batch");
    assert!(second_preview.can_apply);
    assert_eq!(second_preview.included_count, 1);
    assert_eq!(second_preview.keep_both_count, 1);
    let second_item = second_preview
        .items
        .iter()
        .find(|item| item.conflict_id == "name-2")
        .expect("remaining pending preview row");
    assert_eq!(
        second_item.target_path.as_deref(),
        Some("docs/budget_1.pdf")
    );

    let second_report = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(second_request),
        second_preview.preview_token,
    )
    .expect("apply remaining pending import conflict batch");
    assert_eq!(second_report.resolved_count, 1);
    assert_eq!(second_report.kept_both_count, 1);
    assert_eq!(second_report.failed_count, 0);
    assert_eq!(
        file_status(repo.path(), budget_staging),
        (
            "docs/budget_1.pdf".to_owned(),
            "budget_1.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        conflict_statuses(repo.path()),
        vec![
            (
                "name-1".to_owned(),
                "resolved".to_owned(),
                Some("keep_both".to_owned()),
            ),
            (
                "name-2".to_owned(),
                "resolved".to_owned(),
                Some("keep_both".to_owned()),
            ),
        ]
    );
    assert_eq!(
        change_log_actions(repo.path()),
        vec!["imported", "imported"]
    );
}

fn keep_both_request(session_id: &str, conflict_id: &str) -> ImportConflictBatchPreviewRequest {
    ImportConflictBatchPreviewRequest {
        import_session_id: session_id.to_owned(),
        conflict_ids: vec![conflict_id.to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::KeepBoth,
        apply_to_all_similar_conflicts: false,
    }
}

fn apply_request_from_preview(
    preview_request: ImportConflictBatchPreviewRequest,
) -> ImportConflictBatchApplyRequest {
    ImportConflictBatchApplyRequest {
        import_session_id: preview_request.import_session_id,
        conflict_ids: preview_request.conflict_ids,
        duplicate_strategy: preview_request.duplicate_strategy,
        same_name_strategy: preview_request.same_name_strategy,
        apply_to_all_similar_conflicts: preview_request.apply_to_all_similar_conflicts,
        replace_confirmed: false,
    }
}

fn conflict_statuses(repo: &std::path::Path) -> Vec<(String, String, Option<String>)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT conflict_id, status, decision
               FROM import_conflicts
              ORDER BY conflict_id",
        )
        .expect("prepare conflict status query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query conflict statuses")
        .map(|row| row.expect("read conflict status"))
        .collect()
}

fn change_log_actions(repo: &std::path::Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT action FROM change_log ORDER BY id")
        .expect("prepare change-log query");
    statement
        .query_map([], |row| row.get(0))
        .expect("query change-log")
        .map(|row| row.expect("read change-log action"))
        .collect()
}
