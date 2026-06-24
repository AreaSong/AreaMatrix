use std::fs;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use area_matrix_core::{
    batch_delete_to_trash, import_file, list_undo_actions, preview_batch_delete, undo_action,
    BatchDeleteMode, BatchDeletePreviewStatus, BatchDeleteResultStatus, CoreError, StorageMode,
    UndoActionStatus,
};
use pretty_assertions::assert_eq;

mod support;

use support::{
    batch_delete_trash::{
        adopt_file, archive_entries, change_actions, deleted_changes, import_options, indexed_file,
        install_batch_trash_undo_failure, undo_inverse, undo_status,
    },
    batch_delete_validation::{file_status, initialized_repo, path_string, source_file},
    system_trash_home::with_test_system_trash,
};

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
        assert!(archive_entries(repo.path()).is_empty());

        let deleted_changes = deleted_changes(repo.path());
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

        assert!(!skipped_preview.can_apply);
        assert_eq!(skipped_preview.will_trash_count, 0);
        assert_eq!(skipped_preview.index_only_count, 0);
        assert_eq!(skipped_preview.missing_count, 0);
        assert_eq!(skipped_preview.skipped_count, 2);
        assert_eq!(
            skipped_preview.items[0].status,
            BatchDeletePreviewStatus::Skipped
        );
        assert_eq!(
            skipped_preview.items[1].status,
            BatchDeletePreviewStatus::Skipped
        );
        assert!(skipped_preview.items[1]
            .reason
            .as_deref()
            .expect("missing row skipped reason")
            .contains("RemoveFromIndex"));

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
fn batch_delete_trash_implementation_excludes_blocked_items_and_moves_available_files() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_available_root, available_source) = source_file("available.pdf", b"available bytes");
        let available = import_file(
            path_string(repo.path()),
            path_string(&available_source),
            import_options(StorageMode::Copied, "available.pdf"),
        )
        .expect("import file available for Trash");
        let blocked_id = adopt_file(repo.path(), "finance/blocked-directory.pdf");
        fs::remove_file(repo.path().join("finance/blocked-directory.pdf"))
            .expect("replace adopted file with directory");
        fs::create_dir(repo.path().join("finance/blocked-directory.pdf"))
            .expect("create blocked directory at file path");

        let preview = preview_batch_delete(
            path_string(repo.path()),
            vec![available.id, blocked_id],
            BatchDeleteMode::MoveToTrash,
        )
        .expect("preview mixed available and blocked delete");

        assert!(preview.can_apply);
        assert_eq!(preview.will_trash_count, 1);
        assert_eq!(preview.blocked_count, 1);
        assert_eq!(preview.apply_blocked_reason, None);
        assert_eq!(
            preview.items[0].status,
            BatchDeletePreviewStatus::WillMoveToTrash
        );
        assert_eq!(preview.items[1].status, BatchDeletePreviewStatus::Blocked);

        let report = batch_delete_to_trash(
            path_string(repo.path()),
            vec![available.id, blocked_id],
            BatchDeleteMode::MoveToTrash,
            preview.preview_token,
        )
        .expect("apply moves available files and excludes blocked rows");

        assert_eq!(report.moved_to_trash_count, 1);
        assert_eq!(report.removed_from_index_count, 0);
        assert_eq!(report.skipped_count, 1);
        assert_eq!(report.failed_count, 0);
        assert_eq!(report.affected_file_ids, vec![available.id]);
        assert_eq!(
            report.item_results[0].status,
            BatchDeleteResultStatus::MovedToTrash
        );
        assert_eq!(
            report.item_results[1].status,
            BatchDeleteResultStatus::Skipped
        );
        assert!(report.item_results[1]
            .error
            .as_deref()
            .expect("blocked reason is preserved")
            .contains("FileNotFound"));
        assert!(report.undo_token.is_some());

        assert!(!repo.path().join(&available.path).exists());
        assert_eq!(
            fs::read(trash_dir.join("available.pdf")).expect("read moved Trash file"),
            b"available bytes"
        );
        assert_eq!(file_status(repo.path(), available.id), "deleted");
        assert_eq!(file_status(repo.path(), blocked_id), "active");
        assert!(
            repo.path().join("finance/blocked-directory.pdf").is_dir(),
            "blocked item is left unchanged"
        );
        let deleted_changes = deleted_changes(repo.path());
        assert_eq!(deleted_changes.len(), 1);
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
