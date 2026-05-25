use std::{
    fs,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};

use area_matrix_core::{
    batch_add_tags, delete_file, list_redo_actions, move_to_category, redo_action, rename_file,
    undo_action, ErrorKind, ErrorRecoverability, RedoActionStatus,
};
use pretty_assertions::assert_eq;

mod support;

use support::{
    redo_failure::{
        assert_error_mapping, change_rows, drop_trigger, file_rows, initialized_repo, insert_file,
        install_redo_file_change_failure, install_redo_file_change_slow_failure,
        install_redo_tag_change_failure, only_undo_token, open_db, path_string,
        relative_directory_entries, repo_config_value, snapshot, tag_rows, undo_rows, undo_status,
        user_visible_paths,
    },
    system_trash_home::with_test_system_trash,
};

#[test]
fn redo_action_log_failure_recovery_empty_stack_is_read_only() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let actions = list_redo_actions(path_string(repo.path())).expect("list empty redo stack");

    assert!(actions.is_empty());
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn redo_action_log_failure_recovery_invalid_inputs_map_to_documented_errors() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let empty = redo_action(path_string(repo.path()), "  ".to_owned())
        .expect_err("empty redo action id is invalid");
    assert_error_mapping(
        &empty,
        ErrorKind::FileNotFound,
        ErrorRecoverability::RefreshRequired,
    );

    let metadata = list_redo_actions(
        repo.path()
            .join(".areamatrix")
            .to_string_lossy()
            .into_owned(),
    )
    .expect_err("metadata-internal repo path is invalid for C2-18");
    assert_error_mapping(
        &metadata,
        ErrorKind::Db,
        ErrorRecoverability::UserActionRequired,
    );

    let missing = redo_action(path_string(repo.path()), "redo:missing".to_owned())
        .expect_err("missing redo action is not executable");
    assert_error_mapping(
        &missing,
        ErrorKind::FileNotFound,
        ErrorRecoverability::RefreshRequired,
    );

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn redo_action_log_failure_recovery_cleared_action_returns_expired_without_mutation() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let second_id = insert_file(repo.path(), "docs/plan.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![first_id],
        vec!["Urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token is created");
    undo_action(path_string(repo.path()), token.clone()).expect("execute undo");
    batch_add_tags(
        path_string(repo.path()),
        vec![second_id],
        vec!["Later".to_owned()],
    )
    .expect("new write clears redo stack");
    let before = snapshot(repo.path());

    let error =
        redo_action(path_string(repo.path()), token).expect_err("cleared redo action is expired");

    assert_error_mapping(
        &error,
        ErrorKind::ExpiredAction,
        ErrorRecoverability::RefreshRequired,
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn redo_action_log_failure_recovery_db_metadata_errors_do_not_mutate() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token exists");
    undo_action(path_string(repo.path()), token.clone()).expect("create redo row");
    let before_files = file_rows(repo.path());
    let before_changes = change_rows(repo.path());
    let before_undo_actions = undo_rows(repo.path());
    let before_visible = user_visible_paths(repo.path());

    open_db(repo.path())
        .execute_batch("DROP TABLE tags;")
        .expect("drop tags table to force redo metadata DB error");

    let list_error = list_redo_actions(path_string(repo.path()))
        .expect_err("missing redo metadata table fails list");
    assert_error_mapping(&list_error, ErrorKind::Db, ErrorRecoverability::Fatal);

    let redo_error = redo_action(path_string(repo.path()), token)
        .expect_err("missing redo metadata table fails execute");
    assert_error_mapping(&redo_error, ErrorKind::Db, ErrorRecoverability::Fatal);

    assert_eq!(file_rows(repo.path()), before_files);
    assert_eq!(change_rows(repo.path()), before_changes);
    assert_eq!(undo_rows(repo.path()), before_undo_actions);
    assert_eq!(user_visible_paths(repo.path()), before_visible);
}

#[test]
fn redo_action_log_failure_recovery_db_write_error_rolls_back_tags_and_status() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let second_id = insert_file(repo.path(), "docs/plan.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![first_id, second_id],
        vec!["urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token exists");
    undo_action(path_string(repo.path()), token.clone()).expect("create redo row");
    let before = snapshot(repo.path());
    install_redo_tag_change_failure(repo.path());

    let error = redo_action(path_string(repo.path()), token.clone())
        .expect_err("redo change-log DB failure aborts redo transaction");

    assert_error_mapping(
        &error,
        ErrorKind::Db,
        ErrorRecoverability::UserActionRequired,
    );
    assert_eq!(snapshot(repo.path()), before);

    drop_trigger(repo.path(), "fail_redo_tag_change");
    let result =
        redo_action(path_string(repo.path()), token).expect("retry redo after DB recovery");
    assert_eq!(result.status, RedoActionStatus::Executed);
    assert_eq!(
        tag_rows(repo.path()),
        vec![
            (first_id, "urgent".to_owned()),
            (second_id, "urgent".to_owned())
        ]
    );
}

#[test]
fn redo_action_log_failure_recovery_external_directory_blocks_rename_without_mutation() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/draft.pdf", "docs");
    rename_file(path_string(repo.path()), file_id, "final.pdf".to_owned()).expect("rename file");
    let token = only_undo_token(repo.path());
    undo_action(path_string(repo.path()), token.clone()).expect("undo rename");
    fs::remove_file(repo.path().join("docs/draft.pdf")).expect("remove restored file");
    fs::create_dir(repo.path().join("docs/draft.pdf"))
        .expect("replace restored file with directory");
    let before = snapshot(repo.path());

    let actions = list_redo_actions(path_string(repo.path())).expect("list redo actions");
    assert_eq!(actions[0].status, RedoActionStatus::Blocked);
    assert_eq!(
        actions[0].disabled_reason.as_deref(),
        Some("File changed after undo")
    );
    let error = redo_action(path_string(repo.path()), token.clone())
        .expect_err("redo must not move a directory as a file");

    assert_error_mapping(
        &error,
        ErrorKind::Conflict,
        ErrorRecoverability::UserActionRequired,
    );
    assert_eq!(undo_status(repo.path(), &token), "executed");
    assert_eq!(snapshot(repo.path()), before);
    assert!(repo.path().join("docs/draft.pdf").is_dir());
    assert!(!repo.path().join("docs/final.pdf").exists());
}

#[test]
fn redo_action_log_failure_recovery_external_directory_blocks_trash_without_mutation() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let file_id = insert_file(repo.path(), "docs/report.pdf", "docs");
        delete_file(path_string(repo.path()), file_id).expect("delete file to trash");
        let token = only_undo_token(repo.path());
        undo_action(path_string(repo.path()), token.clone()).expect("undo trash delete");
        fs::remove_file(repo.path().join("docs/report.pdf")).expect("remove restored file");
        fs::create_dir(repo.path().join("docs/report.pdf"))
            .expect("replace restored file with directory");
        let before = snapshot(repo.path());

        let actions = list_redo_actions(path_string(repo.path())).expect("list redo actions");
        assert_eq!(actions[0].status, RedoActionStatus::Blocked);
        assert_eq!(
            actions[0].disabled_reason.as_deref(),
            Some("File changed after undo")
        );
        let error = redo_action(path_string(repo.path()), token.clone())
            .expect_err("redo must not trash a directory as a file");

        assert_error_mapping(
            &error,
            ErrorKind::Conflict,
            ErrorRecoverability::UserActionRequired,
        );
        assert_eq!(undo_status(repo.path(), &token), "executed");
        assert_eq!(snapshot(repo.path()), before);
        assert!(repo.path().join("docs/report.pdf").is_dir());
        assert!(!trash_dir.join("report.pdf").exists());
    });
}

#[test]
fn redo_action_log_failure_recovery_real_io_error_does_not_leave_partial_redo() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance");
    move_to_category(path_string(repo.path()), file_id, "docs".to_owned())
        .expect("move file to docs");
    let token = only_undo_token(repo.path());
    undo_action(path_string(repo.path()), token.clone()).expect("undo move");
    fs::remove_dir(repo.path().join("docs")).expect("remove empty redo destination directory");
    fs::write(
        repo.path().join("docs"),
        b"destination parent path is now a file",
    )
    .expect("replace redo destination parent with a file");
    let before_rows = file_rows(repo.path());
    let before_changes = change_rows(repo.path());
    let before_undo_actions = undo_rows(repo.path());
    let before_staging =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"));

    let error =
        redo_action(path_string(repo.path()), token.clone()).expect_err("redo move hits real IO");

    assert_error_mapping(&error, ErrorKind::Io, ErrorRecoverability::Retryable);
    assert_eq!(file_rows(repo.path()), before_rows);
    assert_eq!(change_rows(repo.path()), before_changes);
    assert_eq!(undo_rows(repo.path()), before_undo_actions);
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        before_staging
    );
    assert_eq!(undo_status(repo.path(), &token), "executed");
    assert!(repo.path().join("finance/report.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("restored file remains readable"),
        b"fixture bytes for finance/report.pdf"
    );
    assert_eq!(
        fs::read(repo.path().join("docs")).expect("blocking destination remains intact"),
        b"destination parent path is now a file"
    );
}

#[test]
fn redo_action_log_failure_recovery_db_failure_rolls_back_real_file_move() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/draft.pdf", "docs");
    rename_file(path_string(repo.path()), file_id, "final.pdf".to_owned()).expect("rename file");
    let token = only_undo_token(repo.path());
    undo_action(path_string(repo.path()), token.clone()).expect("undo rename");
    let before = snapshot(repo.path());
    install_redo_file_change_failure(repo.path());

    let error = redo_action(path_string(repo.path()), token.clone())
        .expect_err("redo file change-log failure rolls back the moved file");

    assert_error_mapping(
        &error,
        ErrorKind::Db,
        ErrorRecoverability::UserActionRequired,
    );
    assert_eq!(snapshot(repo.path()), before);
    assert_eq!(undo_status(repo.path(), &token), "executed");
    assert!(repo.path().join("docs/draft.pdf").exists());
    assert!(!repo.path().join("docs/final.pdf").exists());
    drop_trigger(repo.path(), "fail_redo_file_change");
}

#[cfg(unix)]
#[test]
fn redo_action_log_failure_recovery_rollback_failure_is_observable_and_quarantined() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/draft.pdf", "docs");
    rename_file(path_string(repo.path()), file_id, "final.pdf".to_owned()).expect("rename file");
    let token = only_undo_token(repo.path());
    undo_action(path_string(repo.path()), token.clone()).expect("undo rename");
    install_redo_file_change_slow_failure(repo.path());
    let before_rows = file_rows(repo.path());
    let before_changes = change_rows(repo.path());
    let before_undo_actions = undo_rows(repo.path());
    let stop_watcher = Arc::new(AtomicBool::new(false));
    let watcher_stop = Arc::clone(&stop_watcher);
    let restored_path = repo.path().join("docs/draft.pdf");
    let expected_path = repo.path().join("docs/final.pdf");
    let watcher = thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(2);
        while !watcher_stop.load(Ordering::SeqCst) && Instant::now() < deadline {
            if expected_path.exists() && !restored_path.exists() {
                fs::write(&restored_path, b"external bytes")
                    .expect("write simulated external rollback conflict");
                return;
            }
            thread::sleep(Duration::from_millis(1));
        }
    });

    let error = redo_action(path_string(repo.path()), token.clone())
        .expect_err("rollback failure must be returned as an IO error");
    stop_watcher.store(true, Ordering::SeqCst);
    watcher
        .join()
        .expect("rollback conflict watcher should not panic");

    assert_error_mapping(&error, ErrorKind::Io, ErrorRecoverability::Retryable);
    assert_eq!(file_rows(repo.path()), before_rows);
    assert_eq!(change_rows(repo.path()), before_changes);
    assert_eq!(undo_rows(repo.path()), before_undo_actions);
    assert_eq!(undo_status(repo.path(), &token), "executed");
    assert_eq!(
        fs::read(repo.path().join("docs/draft.pdf")).expect("external conflicting file remains"),
        b"external bytes"
    );
    assert!(!repo.path().join("docs/final.pdf").exists());

    let recovery_entries =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"));
    assert_eq!(recovery_entries.len(), 2);
    assert!(recovery_entries
        .iter()
        .any(|entry| entry == ".areamatrix/staging/redo-rollback-recovery"));
    let recovered_file = recovery_entries
        .iter()
        .find(|entry| entry.starts_with(".areamatrix/staging/redo-rollback-recovery/"))
        .expect("moved redo file is quarantined for recovery");
    assert_eq!(
        fs::read(repo.path().join(recovered_file)).expect("read quarantined redo file"),
        b"fixture bytes for docs/draft.pdf"
    );
}

#[cfg(unix)]
#[test]
fn redo_action_log_failure_recovery_permission_denied_is_structured_without_mutation() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/draft.pdf", "docs");
    rename_file(path_string(repo.path()), file_id, "final.pdf".to_owned()).expect("rename file");
    let token = only_undo_token(repo.path());
    undo_action(path_string(repo.path()), token.clone()).expect("undo rename");
    let before = snapshot(repo.path());
    let docs_dir = repo.path().join("docs");
    let original_permissions = fs::metadata(&docs_dir)
        .expect("read docs permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&docs_dir, denied_permissions).expect("make docs untraversable");

    let result = redo_action(path_string(repo.path()), token.clone());

    fs::set_permissions(&docs_dir, original_permissions).expect("restore docs permissions");
    let error = result.expect_err("untraversable directory blocks redo");
    assert_error_mapping(
        &error,
        ErrorKind::PermissionDenied,
        ErrorRecoverability::UserActionRequired,
    );
    assert_eq!(undo_status(repo.path(), &token), "executed");
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn redo_action_log_failure_recovery_never_uses_ai_or_remote_state() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/local.pdf", "docs");
    let before_ai_enabled = repo_config_value(repo.path(), "ai_enabled");
    let before_staging =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"));
    let before_generated =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated"));
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["private".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token exists");
    undo_action(path_string(repo.path()), token.clone()).expect("undo local tag action");

    redo_action(path_string(repo.path()), token).expect("redo local tag action");

    assert_eq!(before_ai_enabled, "false");
    assert_eq!(
        repo_config_value(repo.path(), "ai_enabled"),
        before_ai_enabled
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        before_staging
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        before_generated
    );
    assert!(change_rows(repo.path())
        .iter()
        .all(|(_, _, detail)| !detail.contains("api_key") && !detail.contains("secret")));
}
