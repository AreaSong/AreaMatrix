use area_matrix_core::{
    batch_move_to_category, preview_batch_move_to_category, BatchCategoryPreviewStatus,
    BatchCategoryResultStatus, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::params;

#[path = "support/batch_category_failure.rs"]
mod batch_category_failure;
use batch_category_failure::{
    assert_classify_error, assert_conflict_error, assert_db_error, assert_file_not_found,
    assert_io_error, change_log_rows, file_row, initialized_repo, insert_repo_owned_file,
    install_batch_category_change_log_failure, open_db, path_string, snapshot, undo_action_rows,
    user_visible_paths,
};

#[cfg(unix)]
use batch_category_failure::{assert_permission_denied, UnixModeGuard};

#[test]
fn batch_change_category_failure_recovery_empty_and_invalid_inputs_do_not_mutate() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let before = snapshot(repo.path());

    assert_db_error(preview_batch_move_to_category(
        String::new(),
        vec![file_id],
        "docs".to_owned(),
        true,
    ));
    assert_db_error(preview_batch_move_to_category(
        path_string(&repo.path().join(".areamatrix")),
        vec![file_id],
        "docs".to_owned(),
        true,
    ));
    assert_file_not_found(preview_batch_move_to_category(
        path_string(repo.path()),
        Vec::new(),
        "docs".to_owned(),
        true,
    ));
    assert_file_not_found(preview_batch_move_to_category(
        path_string(repo.path()),
        vec![0],
        "docs".to_owned(),
        true,
    ));
    assert_classify_error(preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        String::new(),
        true,
    ));
    assert_classify_error(preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "missing-category".to_owned(),
        true,
    ));
    assert_conflict_error(batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
        String::new(),
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[cfg(unix)]
#[test]
fn batch_change_category_failure_recovery_permission_denied_is_api_error_without_mutation() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let before = snapshot(repo.path());

    let mut permission_guard = UnixModeGuard::set_mode(repo.path(), 0o000);
    assert_permission_denied(preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
    ));
    permission_guard.restore();

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn batch_change_category_failure_recovery_io_failure_is_api_error_without_mutation() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let before = snapshot(repo.path());
    let too_long_component = "a".repeat(10_000);
    let uninspectable_repo = repo.path().join(too_long_component);

    assert_io_error(preview_batch_move_to_category(
        path_string(&uninspectable_repo),
        vec![file_id],
        "docs".to_owned(),
        true,
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn batch_change_category_failure_recovery_sidecar_io_is_explicit_blocker() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    std::fs::create_dir(repo.path().join("finance/report.pdf.md"))
        .expect("create unreadable note sidecar shape");
    open_db(repo.path())
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at) VALUES (?1, ?2, 100)",
            params![file_id, "important note"],
        )
        .expect("insert note row");
    let before = snapshot(repo.path());

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
    )
    .expect("sidecar IO failure is returned as explicit blocked row");

    assert!(!preview.can_apply);
    assert_eq!(preview.blocked_count, 1);
    assert_eq!(preview.items[0].status, BatchCategoryPreviewStatus::Blocked);
    assert!(preview.items[0]
        .reason
        .as_deref()
        .expect("blocked item carries io reason")
        .contains("Io"));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn batch_change_category_failure_recovery_missing_targets_are_explicit() {
    let repo = initialized_repo();
    let active_id = insert_repo_owned_file(
        repo.path(),
        "finance/active.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let deleted_id = insert_repo_owned_file(
        repo.path(),
        "finance/deleted.pdf",
        "finance",
        StorageMode::Copied,
        "deleted",
    );
    let before_paths = user_visible_paths(repo.path());

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![active_id, deleted_id, 404],
        "docs".to_owned(),
        false,
    )
    .expect("missing targets are shown as skipped preview rows");

    assert!(preview.can_apply);
    assert_eq!(preview.metadata_only_count, 1);
    assert_eq!(preview.skipped_count, 2);
    assert_eq!(
        preview
            .items
            .iter()
            .map(|item| (item.file_id, item.status.clone()))
            .collect::<Vec<_>>(),
        vec![
            (active_id, BatchCategoryPreviewStatus::MetadataOnly),
            (deleted_id, BatchCategoryPreviewStatus::Skipped),
            (404, BatchCategoryPreviewStatus::Skipped),
        ]
    );
    assert!(preview
        .items
        .iter()
        .filter(|item| item.status == BatchCategoryPreviewStatus::Skipped)
        .all(|item| item.reason.as_deref() == Some("File is no longer active")));

    let report = batch_move_to_category(
        path_string(repo.path()),
        vec![active_id, deleted_id, 404],
        "docs".to_owned(),
        false,
        preview.preview_token,
    )
    .expect("skipped rows do not block applicable metadata update");

    assert_eq!(report.metadata_only_count, 1);
    assert_eq!(report.skipped_count, 2);
    assert_eq!(report.failed_count, 0);
    assert_eq!(file_row(repo.path(), active_id).2, "docs");
    assert_eq!(file_row(repo.path(), deleted_id).3, "deleted");
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn batch_change_category_failure_recovery_item_db_failure_rolls_back_only_that_item() {
    let repo = initialized_repo();
    let first_id = insert_repo_owned_file(
        repo.path(),
        "finance/first.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let second_id = insert_repo_owned_file(
        repo.path(),
        "finance/second.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    install_batch_category_change_log_failure(repo.path(), Some(second_id));
    let before_paths = user_visible_paths(repo.path());

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![first_id, second_id],
        "docs".to_owned(),
        false,
    )
    .expect("preview metadata-only batch category change");
    let report = batch_move_to_category(
        path_string(repo.path()),
        vec![first_id, second_id],
        "docs".to_owned(),
        false,
        preview.preview_token,
    )
    .expect("item DB failure returns partial report");

    assert_eq!(report.metadata_only_count, 1);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.item_results[0].status,
        BatchCategoryResultStatus::MetadataUpdated
    );
    assert_eq!(
        report.item_results[1].status,
        BatchCategoryResultStatus::Failed
    );
    assert!(report.item_results[1]
        .error
        .as_deref()
        .expect("failed item has db error")
        .contains("Db"));
    assert_eq!(change_log_rows(repo.path()).len(), 1);
    assert_eq!(undo_action_rows(repo.path()).len(), 1);
    assert_eq!(file_row(repo.path(), first_id).2, "docs");
    assert_eq!(file_row(repo.path(), second_id).2, "finance");
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}
