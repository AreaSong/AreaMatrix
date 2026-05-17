use std::fs;

use area_matrix_core::{
    batch_move_to_category, load_config, preview_batch_move_to_category, BatchCategoryResultStatus,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::params;

#[path = "support/batch_category_failure.rs"]
mod batch_category_failure;
use batch_category_failure::{
    assert_conflict_error, assert_db_error, initialized_repo, insert_indexed_file,
    insert_repo_owned_file, install_batch_category_change_log_failure,
    install_batch_category_undo_failure, open_db, path_string, relative_directory_entries,
    snapshot,
};

#[test]
fn batch_change_category_rollback_safety_restores_file_and_sidecar_on_item_db_failure() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    fs::write(repo.path().join("finance/report.pdf.md"), "important note")
        .expect("write note sidecar");
    open_db(repo.path())
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at) VALUES (?1, ?2, 100)",
            params![file_id, "important note"],
        )
        .expect("insert note row");
    install_batch_category_change_log_failure(repo.path(), Some(file_id));
    let before = snapshot(repo.path());

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
    )
    .expect("preview repo-owned move");
    let report = batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
        preview.preview_token,
    )
    .expect("item DB failure returns explicit failed report");

    assert_eq!(report.moved_count, 0);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.item_results[0].status,
        BatchCategoryResultStatus::Failed
    );
    assert!(report.item_results[0]
        .error
        .as_deref()
        .expect("failed item carries db error")
        .contains("Db"));
    assert_eq!(snapshot(repo.path()), before);
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read restored file"),
        b"fixture bytes for finance/report.pdf"
    );
    assert!(repo.path().join("finance/report.pdf.md").exists());
    assert!(!repo.path().join("docs/report.pdf").exists());
    assert!(!repo.path().join("docs/report.pdf.md").exists());
    assert!(!repo.path().join("docs").exists());
}

#[test]
fn batch_change_category_rollback_safety_undo_failure_rolls_back_db_and_filesystem() {
    let repo = initialized_repo();
    let moved_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("indexed.pdf");
    fs::write(&external, b"indexed source").expect("write indexed source");
    let indexed_id = insert_indexed_file(repo.path(), &external, "finance");
    let before = snapshot(repo.path());
    install_batch_category_undo_failure(repo.path());

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![moved_id, indexed_id],
        "docs".to_owned(),
        true,
    )
    .expect("preview mixed batch category change");
    assert_db_error(batch_move_to_category(
        path_string(repo.path()),
        vec![moved_id, indexed_id],
        "docs".to_owned(),
        true,
        preview.preview_token,
    ));

    assert_eq!(snapshot(repo.path()), before);
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("docs/report.pdf").exists());
    assert!(external.exists());
}

#[test]
fn batch_change_category_rollback_safety_stale_preview_prevents_partial_writes() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
    )
    .expect("preview batch category change");
    open_db(repo.path())
        .execute(
            "UPDATE files SET updated_at = updated_at + 1 WHERE id = ?1",
            params![file_id],
        )
        .expect("simulate external DB state change");
    let before = snapshot(repo.path());

    assert_conflict_error(batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
        preview.preview_token,
    ));

    assert_eq!(snapshot(repo.path()), before);
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("docs/report.pdf").exists());
}

#[test]
fn batch_change_category_rollback_safety_preserves_files_and_avoids_remote_ai_state() {
    let repo = initialized_repo();
    let readme = repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README");
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/local.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let before_staging =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"));
    let before_generated =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated"));
    let external_root = tempfile::tempdir().expect("create external root");
    let external = external_root.path().join("external.pdf");
    fs::write(&external, b"external source").expect("write external indexed file");
    let indexed_id = insert_indexed_file(repo.path(), &external, "finance");
    let external_before = fs::read(&external).expect("read external source before metadata update");

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id, indexed_id],
        "docs".to_owned(),
        false,
    )
    .expect("preview metadata-only batch category change");
    let report = batch_move_to_category(
        path_string(repo.path()),
        vec![file_id, indexed_id],
        "docs".to_owned(),
        false,
        preview.preview_token,
    )
    .expect("apply metadata-only batch category change");

    assert_eq!(report.metadata_only_count, 2);
    assert_eq!(report.moved_count, 0);
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert!(
        !load_config(path_string(repo.path()))
            .expect("load repo config")
            .ai_enabled
    );
    assert_eq!(
        fs::read(repo.path().join("finance/local.pdf")).expect("read unchanged repo file"),
        b"fixture bytes for finance/local.pdf"
    );
    assert_eq!(
        fs::read(&external).expect("read external source"),
        external_before
    );
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README after batch change"),
        "user readme\n"
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        before_staging
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        before_generated
    );
}
