use std::fs;

use area_matrix_core::{get_file, sync_external_changes};
use pretty_assertions::assert_eq;

#[path = "support/sync_external_renamed.rs"]
mod support;

use support::{
    change_detail, count_changes_with_action, fs_cursor, initialized_repo, listed_changes,
    listed_files, modified, path_string, removed, renamed, sync_created_file,
};

#[test]
fn sync_external_renamed_implementation_updates_file_log_and_cursor() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"rename bytes");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/renamed.pdf"),
    )
    .expect("simulate external filesystem rename");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf", 2)],
    )
    .expect("sync external renamed file");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(fs_cursor(repo.path()), Some(2));

    let files = listed_files(repo.path());
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].id, entry.id);
    assert_eq!(files[0].path, "docs/renamed.pdf");
    assert_eq!(files[0].current_name, "renamed.pdf");
    assert_eq!(files[0].category, "docs");

    let detail = get_file(path_string(repo.path()), entry.id).expect("get renamed file detail");
    assert_eq!(detail.path, "docs/renamed.pdf");
    assert_eq!(detail.current_name, "renamed.pdf");

    let changes = listed_changes(repo.path());
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 1);
    let renamed_change = changes
        .iter()
        .find(|change| change.action == "renamed")
        .expect("renamed change should be recorded");
    let detail = change_detail(renamed_change);
    assert_eq!(detail["event_id"], 2);
    assert_eq!(detail["from_path"], "docs/original.pdf");
    assert_eq!(detail["to_path"], "docs/renamed.pdf");
    assert_eq!(detail["from_name"], "original.pdf");
    assert_eq!(detail["to_name"], "renamed.pdf");
    assert_eq!(detail["from_category"], "docs");
    assert_eq!(detail["to_category"], "docs");
    assert_eq!(detail["by"], "external");
    assert_eq!(
        fs::read(repo.path().join("docs/renamed.pdf")).expect("renamed user file remains readable"),
        b"rename bytes"
    );
}

#[test]
fn sync_external_renamed_implementation_updates_cross_category_move() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"move bytes");
    let docs_overview = repo.path().join(".areamatrix/generated/nodes/docs.md");
    assert!(fs::read_to_string(&docs_overview)
        .expect("read source category overview")
        .contains("original.pdf"));
    fs::create_dir_all(repo.path().join("finance")).expect("create target category directory");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("finance/original.pdf"),
    )
    .expect("simulate external cross-category move");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("finance/original.pdf", 20)],
    )
    .expect("sync external cross-category move");

    assert_eq!(result.detected_renames, 1);
    assert_eq!(fs_cursor(repo.path()), Some(20));
    let moved = get_file(path_string(repo.path()), entry.id).expect("get moved DB row");
    assert_eq!(moved.path, "finance/original.pdf");
    assert_eq!(moved.category, "finance");
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 1);
    let detail = change_detail(
        &listed_changes(repo.path())
            .into_iter()
            .find(|change| change.action == "renamed")
            .expect("cross-category move log"),
    );
    assert_eq!(detail["from_category"], "docs");
    assert_eq!(detail["to_category"], "finance");
    assert!(!fs::read_to_string(&docs_overview)
        .expect("read refreshed source category overview")
        .contains("original.pdf"));
    assert!(
        fs::read_to_string(repo.path().join(".areamatrix/generated/nodes/finance.md"))
            .expect("read target category overview")
            .contains("original.pdf")
    );
    assert_eq!(
        fs::read(repo.path().join("finance/original.pdf"))
            .expect("moved user file remains readable"),
        b"move bytes"
    );
}

#[test]
fn sync_external_renamed_implementation_pairs_missing_source_with_target_without_soft_delete() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"paired rename");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/renamed.pdf"),
    )
    .expect("simulate paired external rename");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            removed("docs/original.pdf", 30),
            renamed("docs/renamed.pdf", 31),
        ],
    )
    .expect("sync paired rename events");

    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(fs_cursor(repo.path()), Some(31));
    let renamed_entry =
        get_file(path_string(repo.path()), entry.id).expect("get paired renamed row");
    assert_eq!(renamed_entry.path, "docs/renamed.pdf");
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 1);
    assert_eq!(count_changes_with_action(repo.path(), "deleted"), 0);
}

#[test]
fn sync_external_renamed_implementation_coalesces_modified_flag_for_same_target() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"rename and modify flags");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/renamed.pdf"),
    )
    .expect("simulate external rename with adjacent modified flag");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            renamed("docs/renamed.pdf", 40),
            modified("docs/renamed.pdf", 41),
        ],
    )
    .expect("sync coalesced rename and modified flags");

    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_modifies, 0);
    assert_eq!(fs_cursor(repo.path()), Some(41));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("get coalesced renamed file")
            .path,
        "docs/renamed.pdf"
    );
}

#[test]
fn sync_external_renamed_implementation_skips_managed_sidecar_renamed_with_base_file() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/report.pdf", b"report bytes");
    area_matrix_core::write_note(
        path_string(repo.path()),
        entry.id,
        "managed note".to_owned(),
    )
    .expect("create managed note sidecar");
    fs::rename(
        repo.path().join("docs/report.pdf"),
        repo.path().join("docs/renamed.pdf"),
    )
    .expect("rename base file");
    fs::rename(
        repo.path().join("docs/report.pdf.md"),
        repo.path().join("docs/renamed.pdf.md"),
    )
    .expect("rename managed sidecar");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            renamed("docs/renamed.pdf", 60),
            renamed("docs/renamed.pdf.md", 61),
        ],
    )
    .expect("sync base and managed sidecar rename");

    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_creates, 0);
    assert_eq!(fs_cursor(repo.path()), Some(61));
    assert_eq!(listed_files(repo.path()).len(), 1);
    assert_eq!(
        area_matrix_core::read_note(path_string(repo.path()), entry.id)
            .expect("read managed note after rename"),
        Some("managed note".to_owned())
    );
}

#[test]
fn sync_external_renamed_implementation_uses_materialized_icloud_target_path() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"materialized rename");
    fs::create_dir_all(repo.path().join("new")).expect("create materialized target directory");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("new/original.pdf"),
    )
    .expect("simulate materialized iCloud rename");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed(".new.icloud/original.pdf", 70)],
    )
    .expect("sync materialized iCloud rename");

    assert_eq!(result.detected_renames, 1);
    assert_eq!(fs_cursor(repo.path()), Some(70));
    let renamed_entry =
        get_file(path_string(repo.path()), entry.id).expect("get materialized renamed row");
    assert_eq!(renamed_entry.path, "new/original.pdf");
    assert_eq!(renamed_entry.category, "new");
    assert!(
        fs::read_to_string(repo.path().join(".areamatrix/generated/nodes/new.md"))
            .expect("read materialized target overview")
            .contains("original.pdf")
    );
    assert!(!repo
        .path()
        .join(".areamatrix/generated/nodes/.new.icloud.md")
        .exists());
}
