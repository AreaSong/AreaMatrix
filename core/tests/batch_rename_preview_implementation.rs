use std::fs;

use area_matrix_core::{
    batch_rename, list_undo_actions, preview_batch_rename, undo_action, BatchRenamePreviewStatus,
    BatchRenameResultStatus, CoreError, StorageMode, UndoActionStatus,
};
use pretty_assertions::assert_eq;

#[path = "support/batch_rename_preview.rs"]
mod batch_rename_preview_support;

use batch_rename_preview_support::{
    date_rule, file_row, import_fixture, indexed_file, initialized_repo, open_db, path_string,
    prefix_rule, renamed_details, replace_rule, sequence_rule,
};
use rusqlite::params;

#[test]
fn batch_rename_preview_implementation_is_side_effect_free_and_covers_each_file() {
    let repo = initialized_repo();
    let first = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "first.pdf",
        b"first bytes",
    );
    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("external.pdf");
    fs::write(&external, b"external bytes").expect("write external source");
    let indexed_id = indexed_file(repo.path(), &external, "finance");

    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id, indexed_id, first.id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview batch rename");

    assert_eq!(preview.requested_file_count, 2);
    assert!(preview.preview_token.starts_with("preview:batch-rename:"));
    assert!(preview.can_apply);
    assert_eq!(preview.will_rename_count, 1);
    assert_eq!(preview.display_only_count, 1);
    assert_eq!(preview.blocked_count, 0);
    assert_eq!(preview.items.len(), 2);
    assert_eq!(
        preview.items[0].new_name.as_deref(),
        Some("ProjectA_report.pdf")
    );
    assert_eq!(
        preview.items[0].target_path.as_deref(),
        Some("finance/ProjectA_report.pdf")
    );
    assert_eq!(preview.items[0].status, BatchRenamePreviewStatus::Ok);
    assert_eq!(
        preview.items[1].status,
        BatchRenamePreviewStatus::DisplayOnly
    );
    assert!(preview.items[1].index_only);
    assert!(!preview.items[1].will_rename_file);

    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("finance/ProjectA_report.pdf").exists());
    assert!(external.exists());
    assert_eq!(
        file_row(repo.path(), first.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert!(renamed_details(repo.path()).is_empty());
}

#[test]
fn batch_rename_implementation_renames_repo_owned_and_updates_indexed_display_name() {
    let repo = initialized_repo();
    let readme = repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README");
    let first = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "first.pdf",
        b"first bytes",
    );
    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("external.pdf");
    fs::write(&external, b"external bytes").expect("write external source");
    let indexed_id = indexed_file(repo.path(), &external, "finance");

    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id, indexed_id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview batch rename");
    let report = batch_rename(
        path_string(repo.path()),
        vec![first.id, indexed_id],
        prefix_rule("ProjectA_"),
        preview.preview_token,
    )
    .expect("apply batch rename");

    assert_eq!(report.requested_file_count, 2);
    assert_eq!(report.renamed_count, 1);
    assert_eq!(report.display_name_updated_count, 1);
    assert_eq!(report.unchanged_count, 0);
    assert_eq!(report.failed_count, 0);
    assert_eq!(report.updated_files.len(), 2);
    assert_eq!(
        report.item_results[0].status,
        BatchRenameResultStatus::Renamed
    );
    assert_eq!(
        report.item_results[1].status,
        BatchRenameResultStatus::DisplayNameUpdated
    );
    let undo_token = report.undo_token.expect("batch rename creates undo token");
    assert!(undo_token.starts_with("undo:rename-files:"));

    assert!(!repo.path().join("finance/report.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/ProjectA_report.pdf")).expect("read renamed file"),
        b"first bytes"
    );
    assert!(external.exists());
    assert_eq!(
        fs::read(&external).expect("read indexed external source"),
        b"external bytes"
    );
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README"),
        "user readme\n"
    );
    assert_eq!(
        file_row(repo.path(), first.id),
        (
            "finance/ProjectA_report.pdf".to_owned(),
            "ProjectA_report.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert_eq!(
        file_row(repo.path(), indexed_id),
        (
            path_string(&external),
            "ProjectA_external.pdf".to_owned(),
            "finance".to_owned()
        )
    );

    let details = renamed_details(repo.path());
    assert_eq!(details.len(), 2);
    assert!(details
        .iter()
        .all(|detail| detail["kind"] == "batch_rename"));
    assert!(details
        .iter()
        .any(|detail| detail["index_only"] == serde_json::Value::Bool(true)));

    let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
    let action = actions
        .iter()
        .find(|action| action.action_id == undo_token)
        .expect("find batch rename undo action");
    assert_eq!(action.kind, "rename_files");
    assert_eq!(action.affected_count, 2);
    assert_eq!(action.status, UndoActionStatus::Pending);

    let undo = undo_action(path_string(repo.path()), undo_token).expect("undo batch rename");
    assert_eq!(undo.status, UndoActionStatus::Executed);
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read restored file"),
        b"first bytes"
    );
    assert!(!repo.path().join("finance/ProjectA_report.pdf").exists());
    assert_eq!(
        file_row(repo.path(), indexed_id),
        (
            path_string(&external),
            "external.pdf".to_owned(),
            "finance".to_owned()
        )
    );
}

#[test]
fn batch_rename_preview_blocks_conflicts_missing_and_invalid_names() {
    let repo = initialized_repo();
    let existing = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "ProjectA_report.pdf",
        "existing.pdf",
        b"existing bytes",
    );
    let first = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "first.pdf",
        b"first bytes",
    );
    let missing_id = first.id + 1000;

    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id, existing.id, missing_id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview conflicts and missing rows");

    assert!(!preview.can_apply);
    assert_eq!(preview.blocked_count, 2);
    assert_eq!(preview.conflict_count, 0);
    assert_eq!(
        preview
            .items
            .iter()
            .find(|item| item.file_id == first.id)
            .expect("first row")
            .status,
        BatchRenamePreviewStatus::NameConflict
    );
    assert_eq!(
        preview
            .items
            .iter()
            .find(|item| item.file_id == missing_id)
            .expect("missing row")
            .status,
        BatchRenamePreviewStatus::Missing
    );

    let invalid = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id],
        prefix_rule("bad/name"),
    );
    assert!(matches!(invalid, Err(CoreError::InvalidPath { .. })));
}

#[test]
fn batch_rename_rejects_stale_preview_and_preserves_filesystem() {
    let repo = initialized_repo();
    let first = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "first.pdf",
        b"first bytes",
    );
    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview batch rename");

    open_db(repo.path())
        .execute(
            "UPDATE files SET updated_at = updated_at + 1 WHERE id = ?1",
            params![first.id],
        )
        .expect("simulate external metadata change");

    let result = batch_rename(
        path_string(repo.path()),
        vec![first.id],
        prefix_rule("ProjectA_"),
        preview.preview_token,
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("finance/ProjectA_report.pdf").exists());
    assert_eq!(
        file_row(repo.path(), first.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned()
        )
    );
}

#[test]
fn batch_rename_rules_support_date_sequence_and_replace_behaviors() {
    let repo = initialized_repo();
    let first = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "draft.final.pdf",
        "first.pdf",
        b"first bytes",
    );
    let second = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "summary.pdf",
        "second.pdf",
        b"second bytes",
    );

    let date_preview = preview_batch_rename(path_string(repo.path()), vec![first.id], date_rule())
        .expect("preview date prefix");
    let expected_date = chrono::DateTime::<chrono::Utc>::from_timestamp(first.imported_at, 0)
        .expect("import timestamp is valid")
        .format("%Y-%m-%d")
        .to_string();
    assert_eq!(
        date_preview.items[0].new_name.as_deref(),
        Some(format!("{expected_date}_draft.final.pdf").as_str())
    );

    let sequence_preview = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id, second.id],
        sequence_rule(),
    )
    .expect("preview sequence");
    assert_eq!(
        sequence_preview.items[0].new_name.as_deref(),
        Some("draft.final_01.pdf")
    );
    assert_eq!(
        sequence_preview.items[1].new_name.as_deref(),
        Some("summary_02.pdf")
    );

    let replace_preview = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id, second.id],
        replace_rule("DRAFT", "final", false),
    )
    .expect("preview replace text");
    assert_eq!(
        replace_preview.items[0].new_name.as_deref(),
        Some("final.final.pdf")
    );
    assert_eq!(
        replace_preview.items[1].status,
        BatchRenamePreviewStatus::Unchanged
    );
    assert!(replace_preview.can_apply);

    let unchanged_preview = preview_batch_rename(
        path_string(repo.path()),
        vec![second.id],
        replace_rule("missing", "final", false),
    )
    .expect("preview all unchanged");
    assert!(!unchanged_preview.can_apply);
    assert_eq!(
        unchanged_preview.apply_blocked_reason.as_deref(),
        Some("No filename changes.")
    );
}
