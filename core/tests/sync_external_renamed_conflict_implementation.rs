use std::fs;

use area_matrix_core::{get_file, sync_external_changes, CoreError};
use pretty_assertions::assert_eq;

#[path = "support/sync_external_renamed.rs"]
mod support;

use support::{
    count_changes_with_action, fs_cursor, initialized_repo, insert_nonactive_path,
    install_renamed_change_log_failure, listed_changes, listed_files, path_string, renamed,
    sync_created_file, write_repo_file,
};

#[test]
fn sync_external_renamed_implementation_only_replays_same_event_id() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"rename bytes");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/renamed.pdf"),
    )
    .expect("simulate external filesystem rename");
    sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf", 2)],
    )
    .expect("sync first renamed event");

    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf", 2)],
    )
    .expect("replay the same renamed event");

    assert_eq!(replayed.detected_renames, 0);
    assert_eq!(fs_cursor(repo.path()), Some(2));
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 1);
    let conflicting = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf", 3)],
    );

    assert!(matches!(conflicting, Err(CoreError::Conflict { .. })));
    assert_eq!(fs_cursor(repo.path()), Some(2));
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 1);
    let retained = get_file(path_string(repo.path()), entry.id).expect("get retained renamed file");
    assert_eq!(retained.id, entry.id);
    assert_eq!(retained.path, "docs/renamed.pdf");
    assert_eq!(retained.current_name, "renamed.pdf");
    assert_eq!(retained.hash_sha256, entry.hash_sha256);
    assert!(!repo.path().join("docs/original.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("docs/renamed.pdf"))
            .expect("renamed user file remains unchanged after conflicting event"),
        b"rename bytes"
    );
}

#[test]
fn sync_external_renamed_implementation_rejects_unpaired_target_without_state() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/unpaired.pdf", b"unpaired bytes");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/unpaired.pdf", 10)],
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));

    assert_eq!(fs_cursor(repo.path()), None);
    assert!(listed_files(repo.path()).is_empty());
    assert!(listed_changes(repo.path()).is_empty());
    assert_eq!(
        fs::read(repo.path().join("docs/unpaired.pdf")).expect("unpaired user file remains"),
        b"unpaired bytes"
    );
}

#[test]
fn sync_external_renamed_implementation_rejects_hash_match_while_source_still_exists() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"duplicate bytes");
    fs::copy(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/copied.pdf"),
    )
    .expect("create same-hash external copy without removing source");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/copied.pdf", 50)],
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(fs_cursor(repo.path()), Some(1));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("original row remains active")
            .path,
        "docs/original.pdf"
    );
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 0);
}

#[test]
fn sync_external_renamed_implementation_reports_conflict_for_staging_target_path() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"staging collision");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/target.pdf"),
    )
    .expect("simulate external rename to staging-reserved path");
    insert_nonactive_path(repo.path(), "docs/target.pdf", "staging");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/target.pdf", 55)],
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(fs_cursor(repo.path()), Some(1));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("source metadata remains active")
            .path,
        "docs/original.pdf"
    );
}

#[test]
fn sync_external_renamed_implementation_reports_conflict_for_deleted_target_path() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"deleted collision");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/target.pdf"),
    )
    .expect("simulate external rename to deleted-reserved path");
    insert_nonactive_path(repo.path(), "docs/target.pdf", "deleted");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/target.pdf", 56)],
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(fs_cursor(repo.path()), Some(1));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("source metadata remains active")
            .path,
        "docs/original.pdf"
    );
}

#[test]
fn sync_external_renamed_implementation_rolls_back_db_and_cursor_on_log_failure() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"rollback bytes");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/renamed.pdf"),
    )
    .expect("simulate external filesystem rename");
    install_renamed_change_log_failure(repo.path());

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf", 2)],
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(1));
    let unchanged = get_file(path_string(repo.path()), entry.id).expect("get unchanged DB row");
    assert_eq!(unchanged.path, "docs/original.pdf");
    assert_eq!(unchanged.current_name, "original.pdf");
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 0);
    assert_eq!(
        fs::read(repo.path().join("docs/renamed.pdf"))
            .expect("renamed user file remains readable after DB rollback"),
        b"rollback bytes"
    );
}
