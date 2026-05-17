use std::fs;

use area_matrix_core::{
    batch_rename, map_core_error, preview_batch_rename, BatchRenamePreviewStatus,
    BatchRenameResultStatus, CoreError, ErrorKind, ErrorMappingInput, StorageMode,
};
use rusqlite::params;

#[allow(dead_code)]
#[path = "support/batch_rename_preview.rs"]
mod batch_rename_preview_support;

#[path = "support/batch_rename_failure.rs"]
mod batch_rename_failure_support;

use batch_rename_preview_support::{
    file_row, import_fixture, indexed_file, initialized_repo, open_db, path_string, prefix_rule,
    replace_rule,
};

use batch_rename_failure_support::{
    assert_error_kind, install_batch_rename_undo_failure, install_renamed_change_log_failure,
    snapshot,
};

#[test]
fn batch_rename_failure_edge_empty_invalid_and_mapping_do_not_mutate() {
    let repo = initialized_repo();
    let entry = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "source.pdf",
        b"report bytes",
    );
    let before = snapshot(repo.path());

    assert_error_kind(
        preview_batch_rename(String::new(), vec![entry.id], prefix_rule("ProjectA_"))
            .expect_err("empty repo path is invalid"),
        ErrorKind::InvalidPath,
    );
    assert_error_kind(
        preview_batch_rename(
            path_string(&repo.path().join(".areamatrix")),
            vec![entry.id],
            prefix_rule("ProjectA_"),
        )
        .expect_err("metadata-internal repo path is invalid"),
        ErrorKind::InvalidPath,
    );
    assert_error_kind(
        preview_batch_rename(
            path_string(repo.path()),
            Vec::new(),
            prefix_rule("ProjectA_"),
        )
        .expect_err("empty selection is file-not-found"),
        ErrorKind::FileNotFound,
    );
    assert_error_kind(
        preview_batch_rename(path_string(repo.path()), vec![0], prefix_rule("ProjectA_"))
            .expect_err("invalid id is file-not-found"),
        ErrorKind::FileNotFound,
    );
    assert_error_kind(
        preview_batch_rename(
            path_string(repo.path()),
            vec![entry.id],
            prefix_rule("bad/name"),
        )
        .expect_err("invalid generated text is invalid path"),
        ErrorKind::InvalidPath,
    );
    assert_error_kind(
        preview_batch_rename(
            path_string(repo.path()),
            vec![entry.id],
            replace_rule("", "final", false),
        )
        .expect_err("empty replacement find text is invalid path"),
        ErrorKind::InvalidPath,
    );
    assert_error_kind(
        batch_rename(
            path_string(repo.path()),
            vec![entry.id],
            prefix_rule("ProjectA_"),
            String::new(),
        )
        .expect_err("missing preview token is a conflict"),
        ErrorKind::Conflict,
    );

    for (kind, expected) in [
        (ErrorKind::InvalidPath, "unknown path"),
        (ErrorKind::Conflict, "unknown path"),
        (ErrorKind::FileNotFound, "unknown path"),
        (ErrorKind::PermissionDenied, "unknown path"),
        (ErrorKind::Io, "unspecified message"),
        (ErrorKind::Db, "unspecified message"),
    ] {
        let mapped = map_core_error(ErrorMappingInput {
            kind,
            path: None,
            reason: None,
            message: None,
        });
        assert_eq!(mapped.raw_context, expected);
    }

    assert_eq!(snapshot(repo.path()), before);
}

#[cfg(unix)]
#[test]
fn batch_rename_failure_edge_permission_denied_disables_apply_without_mutation() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let entry = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "source.pdf",
        b"report bytes",
    );
    let file_path = repo.path().join("finance/report.pdf");
    let original_permissions = fs::metadata(&file_path)
        .expect("read file permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o444);
    fs::set_permissions(&file_path, readonly_permissions).expect("make file readonly");
    let before = snapshot(repo.path());

    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![entry.id],
        prefix_rule("ProjectA_"),
    )
    .expect("permission failure is returned as a blocked preview row");

    fs::set_permissions(&file_path, original_permissions).expect("restore file permissions");

    assert!(!preview.can_apply);
    assert_eq!(preview.blocked_count, 1);
    assert_eq!(preview.items[0].status, BatchRenamePreviewStatus::ReadOnly);
    assert!(preview.items[0]
        .reason
        .as_deref()
        .expect("blocked row carries permission reason")
        .contains("PermissionDenied"));
    assert_eq!(snapshot(repo.path()), before);
    assert_eq!(
        fs::read(&file_path).expect("read original file"),
        b"report bytes"
    );
}

#[test]
fn batch_rename_failure_edge_io_and_db_errors_are_explicit_without_mutation() {
    let repo = initialized_repo();
    let entry = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "source.pdf",
        b"report bytes",
    );
    let blocked_parent = repo.path().join("not-a-directory");
    fs::write(&blocked_parent, b"plain file").expect("write non-directory path component");
    let uninspectable_source = blocked_parent.join("external.pdf");
    let indexed_id = indexed_file(repo.path(), &uninspectable_source, "finance");
    let before = snapshot(repo.path());

    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![indexed_id],
        prefix_rule("ProjectA_"),
    )
    .expect("indexed source inspection IO failure is a blocked row");

    assert!(!preview.can_apply);
    assert_eq!(preview.blocked_count, 1);
    assert_eq!(
        preview.items[0].status,
        BatchRenamePreviewStatus::ExternalChange
    );
    assert!(preview.items[0]
        .reason
        .as_deref()
        .expect("blocked row carries IO reason")
        .contains("Io"));

    install_renamed_change_log_failure(repo.path(), None);
    let db_preview = preview_batch_rename(
        path_string(repo.path()),
        vec![entry.id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview before forced DB apply failure");
    let report = batch_rename(
        path_string(repo.path()),
        vec![entry.id],
        prefix_rule("ProjectA_"),
        db_preview.preview_token,
    )
    .expect("per-item DB failure returns an execution report");

    assert_eq!(report.renamed_count, 0);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.item_results[0].status,
        BatchRenameResultStatus::Failed
    );
    assert!(report.item_results[0]
        .error
        .as_deref()
        .expect("failed row carries DB reason")
        .contains("Db"));
    assert_eq!(snapshot(repo.path()), before);
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("finance/ProjectA_report.pdf").exists());
}

#[test]
fn batch_rename_failure_edge_partial_item_failure_keeps_successes_undoable() {
    let repo = initialized_repo();
    let first = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "first.pdf",
        "first-source.pdf",
        b"first bytes",
    );
    let second = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "second.pdf",
        "second-source.pdf",
        b"second bytes",
    );
    install_renamed_change_log_failure(repo.path(), Some(second.id));

    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id, second.id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview mixed batch rename");
    let report = batch_rename(
        path_string(repo.path()),
        vec![first.id, second.id],
        prefix_rule("ProjectA_"),
        preview.preview_token,
    )
    .expect("item DB failure preserves successful rows in the report");

    assert_eq!(report.renamed_count, 1);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.item_results[0].status,
        BatchRenameResultStatus::Renamed
    );
    assert_eq!(
        report.item_results[1].status,
        BatchRenameResultStatus::Failed
    );
    assert!(report
        .undo_token
        .as_deref()
        .expect("successful row creates undo")
        .starts_with("undo:rename-files:"));
    assert_eq!(
        fs::read(repo.path().join("finance/ProjectA_first.pdf")).expect("read renamed first"),
        b"first bytes"
    );
    assert!(!repo.path().join("finance/first.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/second.pdf")).expect("read restored second"),
        b"second bytes"
    );
    assert!(!repo.path().join("finance/ProjectA_second.pdf").exists());
    assert_eq!(
        file_row(repo.path(), first.id),
        (
            "finance/ProjectA_first.pdf".to_owned(),
            "ProjectA_first.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert_eq!(
        file_row(repo.path(), second.id),
        (
            "finance/second.pdf".to_owned(),
            "second.pdf".to_owned(),
            "finance".to_owned()
        )
    );
}

#[test]
fn batch_rename_failure_edge_undo_write_failure_rolls_back_all_successes() {
    let repo = initialized_repo();
    let readme = repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README");
    let first = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "source.pdf",
        b"report bytes",
    );
    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("external.pdf");
    fs::write(&external, b"external bytes").expect("write external source");
    let indexed_id = indexed_file(repo.path(), &external, "finance");
    let before = snapshot(repo.path());

    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![first.id, indexed_id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview batch rename");
    install_batch_rename_undo_failure(repo.path());

    let error = batch_rename(
        path_string(repo.path()),
        vec![first.id, indexed_id],
        prefix_rule("ProjectA_"),
        preview.preview_token,
    )
    .expect_err("undo write failure aborts the whole batch");

    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(snapshot(repo.path()), before);
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read restored report"),
        b"report bytes"
    );
    assert!(!repo.path().join("finance/ProjectA_report.pdf").exists());
    assert_eq!(
        fs::read(&external).expect("read indexed external source"),
        b"external bytes"
    );
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README"),
        "user readme\n"
    );
}

#[test]
fn batch_rename_failure_edge_stale_preview_preserves_filesystem_and_db() {
    let repo = initialized_repo();
    let entry = import_fixture(
        repo.path(),
        StorageMode::Copied,
        "report.pdf",
        "source.pdf",
        b"report bytes",
    );
    let preview = preview_batch_rename(
        path_string(repo.path()),
        vec![entry.id],
        prefix_rule("ProjectA_"),
    )
    .expect("preview batch rename");
    let before = snapshot(repo.path());

    open_db(repo.path())
        .execute(
            "UPDATE files SET updated_at = updated_at + 1 WHERE id = ?1",
            params![entry.id],
        )
        .expect("simulate metadata change after preview");

    let error = batch_rename(
        path_string(repo.path()),
        vec![entry.id],
        prefix_rule("ProjectA_"),
        preview.preview_token,
    )
    .expect_err("stale preview token is rejected");

    assert!(matches!(error, CoreError::Conflict { .. }));
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("finance/ProjectA_report.pdf").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned()
        )
    );
    assert_eq!(
        snapshot(repo.path()).user_visible_paths,
        before.user_visible_paths
    );
    assert_eq!(
        snapshot(repo.path()).renamed_change_count,
        before.renamed_change_count
    );
    assert_eq!(
        snapshot(repo.path()).undo_action_count,
        before.undo_action_count
    );
}
