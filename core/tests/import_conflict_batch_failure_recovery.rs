use std::{fs, path::Path};

use area_matrix_core::{
    apply_import_conflict_batch, map_core_error, preview_import_conflict_batch, CoreError,
    ErrorKind, ErrorMappingInput, ErrorRecoverability, ImportConflictBatchApplyRequest,
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
fn import_conflict_batch_rejects_empty_or_missing_scope_without_mutation() {
    let repo = initialized_conflict_repo();
    insert_import_session(repo.path(), "empty-scope-session");
    let existing = insert_active_file(repo.path(), "docs/report.pdf", "hash-old");
    let staging = insert_staging_file(repo.path(), "staged-empty", "report.pdf", "hash-new");
    insert_conflict(
        repo.path(),
        "empty-scope-session",
        "name-empty",
        "same_name_different_content",
        staging,
        existing,
        "docs/report.pdf",
    );

    let empty_conflicts = ImportConflictBatchPreviewRequest {
        import_session_id: "empty-scope-session".to_owned(),
        conflict_ids: Vec::new(),
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::KeepBoth,
        apply_to_all_similar_conflicts: false,
    };
    let missing_conflict = ImportConflictBatchPreviewRequest {
        import_session_id: "empty-scope-session".to_owned(),
        conflict_ids: vec!["missing-conflict".to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::KeepBoth,
        apply_to_all_similar_conflicts: false,
    };

    assert!(matches!(
        preview_import_conflict_batch(path_string(repo.path()), empty_conflicts),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        preview_import_conflict_batch(path_string(repo.path()), missing_conflict),
        Err(CoreError::FileNotFound { .. })
    ));

    assert_staging_and_existing_unchanged(
        repo.path(),
        existing,
        staging,
        "docs/report.pdf",
        ".areamatrix/staging/staged-empty",
    );
    assert_eq!(
        conflict_status(repo.path(), "name-empty"),
        ("pending".to_owned(), None, None)
    );
}

#[test]
fn import_conflict_batch_maps_staging_residue_to_recovery_required() {
    let repo = initialized_conflict_repo();
    insert_import_session(repo.path(), "missing-staging-session");
    let existing = insert_active_file(repo.path(), "docs/report.pdf", "hash-old");
    let staging = insert_staging_file(repo.path(), "staged-missing", "report.pdf", "hash-new");
    insert_conflict(
        repo.path(),
        "missing-staging-session",
        "name-missing-staging",
        "same_name_different_content",
        staging,
        existing,
        "docs/report.pdf",
    );
    fs::remove_file(repo.path().join(".areamatrix/staging/staged-missing"))
        .expect("remove staged file to simulate recovery-required residue");

    let error = preview_import_conflict_batch(
        path_string(repo.path()),
        keep_both_request("missing-staging-session", "name-missing-staging"),
    )
    .expect_err("missing staged file requires recovery");

    assert!(matches!(error, CoreError::StagingRecoveryRequired { .. }));
    assert_eq!(
        map_core_error(ErrorMappingInput {
            kind: ErrorKind::StagingRecoveryRequired,
            path: Some(".areamatrix/staging/staged-missing".to_owned()),
            reason: None,
            message: None,
        })
        .recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(
        file_status(repo.path(), staging),
        (
            ".areamatrix/staging/staged-missing".to_owned(),
            "report.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
    assert_eq!(file_status(repo.path(), existing).2, "active");
    assert_eq!(
        conflict_status(repo.path(), "name-missing-staging"),
        ("pending".to_owned(), None, None)
    );
}

#[test]
fn import_conflict_batch_blocks_stale_preview_token_before_writes() {
    let repo = initialized_conflict_repo();
    insert_import_session(repo.path(), "stale-token-session");
    let existing = insert_active_file(repo.path(), "docs/report.pdf", "hash-old");
    let staging = insert_staging_file(repo.path(), "staged-stale", "report.pdf", "hash-new");
    insert_conflict(
        repo.path(),
        "stale-token-session",
        "name-stale",
        "same_name_different_content",
        staging,
        existing,
        "docs/report.pdf",
    );
    let request = keep_both_request("stale-token-session", "name-stale");
    let preview = preview_import_conflict_batch(path_string(repo.path()), request.clone())
        .expect("preview stale token fixture");

    let error = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, false),
        format!("{}-stale", preview.preview_token),
    )
    .expect_err("stale preview token blocks apply");

    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_staging_and_existing_unchanged(
        repo.path(),
        existing,
        staging,
        "docs/report.pdf",
        ".areamatrix/staging/staged-stale",
    );
    assert_eq!(
        conflict_status(repo.path(), "name-stale"),
        ("pending".to_owned(), None, None)
    );
}

#[test]
fn import_conflict_batch_returns_error_when_failure_state_cannot_be_persisted() {
    let repo = initialized_conflict_repo();
    insert_import_session(repo.path(), "failure-state-session");
    let existing = insert_active_file(repo.path(), "docs/report.pdf", "hash-old");
    let staging = insert_staging_file(
        repo.path(),
        "staged-failure-state",
        "report.pdf",
        "hash-new",
    );
    insert_conflict(
        repo.path(),
        "failure-state-session",
        "name-failure-state",
        "same_name_different_content",
        staging,
        existing,
        "docs/report.pdf",
    );
    let request = keep_both_request("failure-state-session", "name-failure-state");
    let preview = preview_import_conflict_batch(path_string(repo.path()), request.clone())
        .expect("preview failure-state fixture");
    fs::write(
        repo.path().join(".areamatrix/staging/staged-failure-state"),
        b"staged bytes that must remain after failed status persistence",
    )
    .expect("rewrite staging fixture");
    fs::write(
        repo.path().join("docs/report.pdf"),
        b"existing bytes that must remain after failed status persistence",
    )
    .expect("rewrite existing fixture");
    install_change_log_failure_for_file(repo.path(), staging);
    install_import_conflict_status_failure(repo.path());

    let error = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, false),
        preview.preview_token,
    )
    .expect_err("failure status persistence error must propagate");

    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(
        fs::read(repo.path().join(".areamatrix/staging/staged-failure-state"))
            .expect("staging remains after failed status persistence"),
        b"staged bytes that must remain after failed status persistence"
    );
    assert_eq!(
        fs::read(repo.path().join("docs/report.pdf"))
            .expect("existing file remains after failed status persistence"),
        b"existing bytes that must remain after failed status persistence"
    );
    assert_eq!(
        file_status(repo.path(), staging),
        (
            ".areamatrix/staging/staged-failure-state".to_owned(),
            "report.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
    assert_eq!(file_status(repo.path(), existing).2, "active");
    assert_eq!(
        conflict_status(repo.path(), "name-failure-state"),
        ("pending".to_owned(), None, None)
    );
}

#[test]
fn import_conflict_batch_reports_io_failure_without_final_half_product() {
    let repo = initialized_conflict_repo();
    insert_import_session(repo.path(), "io-failure-session");
    let existing = insert_active_file(repo.path(), "docs/report.pdf", "hash-old");
    let staging = insert_staging_file(repo.path(), "staged-io", "report.pdf", "hash-new");
    insert_conflict(
        repo.path(),
        "io-failure-session",
        "name-io",
        "same_name_different_content",
        staging,
        existing,
        "docs/report.pdf",
    );
    let request = keep_both_request("io-failure-session", "name-io");
    let preview = preview_import_conflict_batch(path_string(repo.path()), request.clone())
        .expect("preview IO failure fixture");
    let docs_dir = repo.path().join("docs");
    let original_permissions = fs::metadata(&docs_dir)
        .expect("read docs permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_readonly(true);
    fs::set_permissions(&docs_dir, readonly_permissions).expect("make docs read-only");

    let report = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, false),
        preview.preview_token,
    )
    .expect("item-level IO failure returns report");
    fs::set_permissions(&docs_dir, original_permissions).expect("restore docs permissions");

    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.item_results[0].status,
        ImportConflictBatchResultStatus::Failed
    );
    assert!(report.item_results[0]
        .error
        .as_deref()
        .is_some_and(|message| message == "permission denied" || message == "io error"));
    assert_eq!(
        file_status(repo.path(), staging),
        (
            ".areamatrix/staging/staged-io".to_owned(),
            "report.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
    assert!(repo.path().join(".areamatrix/staging/staged-io").exists());
    assert!(!repo.path().join("docs/report_1.pdf").exists());
    assert_eq!(file_status(repo.path(), existing).2, "active");
    assert_eq!(conflict_status(repo.path(), "name-io").0, "failed");
}

#[test]
fn import_conflict_batch_rolls_back_prior_success_when_later_error_aborts_batch() {
    let repo = initialized_conflict_repo();
    insert_import_session(repo.path(), "rollback-prior-session");
    let existing_one = insert_active_file(repo.path(), "docs/one.pdf", "hash-one-old");
    let existing_two = insert_active_file(repo.path(), "docs/two.pdf", "hash-two-old");
    let staging_one = insert_staging_file(repo.path(), "staged-one", "one.pdf", "hash-one-new");
    let staging_two = insert_staging_file(repo.path(), "staged-two", "two.pdf", "hash-two-new");
    insert_conflict(
        repo.path(),
        "rollback-prior-session",
        "name-one",
        "same_name_different_content",
        staging_one,
        existing_one,
        "docs/one.pdf",
    );
    insert_conflict(
        repo.path(),
        "rollback-prior-session",
        "name-two",
        "same_name_different_content",
        staging_two,
        existing_two,
        "docs/two.pdf",
    );
    let request = ImportConflictBatchPreviewRequest {
        import_session_id: "rollback-prior-session".to_owned(),
        conflict_ids: vec!["name-one".to_owned(), "name-two".to_owned()],
        duplicate_strategy: ImportConflictBatchStrategy::Skip,
        same_name_strategy: ImportConflictBatchStrategy::KeepBoth,
        apply_to_all_similar_conflicts: false,
    };
    let preview = preview_import_conflict_batch(path_string(repo.path()), request.clone())
        .expect("preview rollback-prior fixture");
    install_change_log_failure_for_file(repo.path(), staging_two);
    install_import_conflict_status_failure_for(repo.path(), "name-two");

    let error = apply_import_conflict_batch(
        path_string(repo.path()),
        apply_request_from_preview(request, false),
        preview.preview_token,
    )
    .expect_err("second item failed status persistence aborts and rolls back first success");

    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(
        file_status(repo.path(), staging_one),
        (
            ".areamatrix/staging/staged-one".to_owned(),
            "one.pdf".to_owned(),
            "staging".to_owned(),
        )
    );
    assert!(repo.path().join(".areamatrix/staging/staged-one").exists());
    assert!(!repo.path().join("docs/one_1.pdf").exists());
    assert_eq!(
        conflict_status(repo.path(), "name-one"),
        ("pending".to_owned(), None, None)
    );
    assert_eq!(
        conflict_status(repo.path(), "name-two"),
        ("pending".to_owned(), None, None)
    );
    assert_eq!(file_status(repo.path(), existing_one).2, "active");
    assert_eq!(file_status(repo.path(), existing_two).2, "active");
    assert!(repo.path().join(".areamatrix/staging/staged-two").exists());
}

fn initialized_conflict_repo() -> tempfile::TempDir {
    let repo = initialized_repo();
    create_conflict_schema(repo.path());
    repo
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

fn assert_staging_and_existing_unchanged(
    repo: &Path,
    existing: i64,
    staging: i64,
    existing_path: &str,
    staging_path: &str,
) {
    assert_eq!(file_status(repo, existing).0, existing_path);
    assert_eq!(file_status(repo, existing).2, "active");
    assert_eq!(file_status(repo, staging).0, staging_path);
    assert_eq!(file_status(repo, staging).2, "staging");
    assert!(repo.join(existing_path).exists());
    assert!(repo.join(staging_path).exists());
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

fn install_import_conflict_status_failure(repo: &Path) {
    install_import_conflict_status_failure_for(repo, "name-failure-state");
}

fn install_import_conflict_status_failure_for(repo: &Path, conflict_id: &str) {
    open_db(repo)
        .execute_batch(&format!(
            "CREATE TRIGGER fail_import_conflict_status_{}
             BEFORE UPDATE OF status ON import_conflicts
             WHEN NEW.status = 'failed' AND NEW.conflict_id = '{}'
             BEGIN
               SELECT RAISE(ABORT, 'forced import conflict failed status persistence failure');
             END;",
            conflict_id.replace('-', "_"),
            conflict_id.replace('\'', "''")
        ))
        .expect("install import conflict status failure trigger");
}

fn install_change_log_failure_for_file(repo: &Path, file_id: i64) {
    open_db(repo)
        .execute_batch(&format!(
            "CREATE TRIGGER fail_import_conflict_change_log_{file_id}
             BEFORE INSERT ON change_log
             WHEN NEW.file_id = {file_id} AND NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced import conflict change-log failure');
             END;"
        ))
        .expect("install import conflict change-log failure trigger");
}
