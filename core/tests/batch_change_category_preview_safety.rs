use std::fs;

use area_matrix_core::{preview_batch_move_to_category, BatchCategoryPreviewStatus, StorageMode};
use pretty_assertions::assert_eq;

#[path = "support/batch_category_failure.rs"]
mod batch_category_support;

use batch_category_support::{
    initialized_repo, insert_indexed_file, insert_repo_owned_file, path_string, snapshot,
};

#[cfg(unix)]
use batch_category_support::UnixModeGuard;

#[test]
fn batch_change_category_preview_distinguishes_repo_owned_metadata_only_from_index_only() {
    let repo = initialized_repo();
    let repo_owned_id = insert_repo_owned_file(
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

    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![repo_owned_id, indexed_id],
        "docs".to_owned(),
        false,
    )
    .expect("preview metadata-only batch category change");

    assert!(preview.can_apply);
    assert_eq!(preview.will_move_count, 0);
    assert_eq!(preview.metadata_only_count, 2);

    let repo_owned_item = preview
        .items
        .iter()
        .find(|item| item.file_id == repo_owned_id)
        .expect("repo-owned preview row is present");
    assert_eq!(
        repo_owned_item.status,
        BatchCategoryPreviewStatus::MetadataOnly
    );
    assert_eq!(
        repo_owned_item.storage_mode.as_ref(),
        Some(&StorageMode::Copied)
    );
    assert!(!repo_owned_item.index_only);
    assert!(!repo_owned_item.will_move_file);

    let indexed_item = preview
        .items
        .iter()
        .find(|item| item.file_id == indexed_id)
        .expect("indexed preview row is present");
    assert_eq!(
        indexed_item.status,
        BatchCategoryPreviewStatus::MetadataOnly
    );
    assert_eq!(
        indexed_item.storage_mode.as_ref(),
        Some(&StorageMode::Indexed)
    );
    assert!(indexed_item.index_only);
    assert!(!indexed_item.will_move_file);
}

#[cfg(unix)]
#[test]
fn batch_change_category_preview_blocks_unwritable_existing_target_directory() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    fs::create_dir_all(repo.path().join("docs")).expect("create target category directory");
    let before = snapshot(repo.path());

    let mut permissions = UnixModeGuard::set_mode(&repo.path().join("docs"), 0o555);
    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
    )
    .expect("unwritable target directory is returned as blocked preview row");
    permissions.restore();

    assert!(!preview.can_apply);
    assert_eq!(preview.blocked_count, 1);
    assert_eq!(preview.items[0].status, BatchCategoryPreviewStatus::Blocked);
    assert!(preview.items[0]
        .reason
        .as_deref()
        .expect("blocked item carries permission reason")
        .contains("PermissionDenied"));
    assert_eq!(snapshot(repo.path()), before);
}

#[cfg(unix)]
#[test]
fn batch_change_category_preview_blocks_unwritable_parent_for_new_target_directory() {
    let repo = initialized_repo();
    let file_id = insert_repo_owned_file(
        repo.path(),
        "finance/report.pdf",
        "finance",
        StorageMode::Copied,
        "active",
    );
    let before = snapshot(repo.path());

    let mut permissions = UnixModeGuard::set_mode(repo.path(), 0o555);
    let preview = preview_batch_move_to_category(
        path_string(repo.path()),
        vec![file_id],
        "docs".to_owned(),
        true,
    )
    .expect("unwritable parent directory is returned as blocked preview row");
    permissions.restore();

    assert!(!preview.can_apply);
    assert_eq!(preview.blocked_count, 1);
    assert_eq!(preview.items[0].status, BatchCategoryPreviewStatus::Blocked);
    assert!(preview.items[0]
        .reason
        .as_deref()
        .expect("blocked item carries permission reason")
        .contains("PermissionDenied"));
    assert!(!repo.path().join("docs").exists());
    assert_eq!(snapshot(repo.path()), before);
}
