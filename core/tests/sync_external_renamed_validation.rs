use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, list_tree_json,
    sync_external_changes, ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileFilter,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use serde_json::Value;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent directory");
    }
    fs::write(path, bytes).expect("write repository file");
}

fn event(relative_path: &str, kind: ExternalEventKind, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind,
        fs_event_id,
    }
}

fn created(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Created, fs_event_id)
}

fn renamed(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Renamed, fs_event_id)
}

fn modified(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Modified, fs_event_id)
}

fn default_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn default_change_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn listed_files(repo: &Path) -> Vec<area_matrix_core::FileEntry> {
    list_files(path_string(repo), default_file_filter()).expect("list files")
}

fn listed_changes(repo: &Path) -> Vec<area_matrix_core::ChangeLogEntry> {
    list_changes(path_string(repo), default_change_filter()).expect("list changes")
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
}

fn change_detail(change: &area_matrix_core::ChangeLogEntry) -> Value {
    serde_json::from_str(&change.detail_json).expect("change detail should be JSON object")
}

fn sync_created_file(
    repo: &Path,
    relative_path: &str,
    bytes: &[u8],
    fs_event_id: i64,
) -> area_matrix_core::FileEntry {
    write_repo_file(repo, relative_path, bytes);
    let result =
        sync_external_changes(path_string(repo), vec![created(relative_path, fs_event_id)])
            .expect("sync external created file fixture");
    assert_eq!(result.detected_creates, 1);
    listed_files(repo)
        .into_iter()
        .find(|file| file.path == relative_path)
        .expect("created file row should be listed")
}

fn rename_user_file(repo: &Path, from: &str, to: &str) {
    fs::rename(repo.join(from), repo.join(to)).expect("simulate external filesystem rename");
}

fn renamed_change(repo: &Path) -> area_matrix_core::ChangeLogEntry {
    listed_changes(repo)
        .into_iter()
        .find(|change| change.action == "renamed")
        .expect("renamed change should be recorded")
}

#[test]
fn sync_external_renamed_validation_success_path_reaches_list_detail_log_tree_and_cursor() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"validation bytes", 500);
    rename_user_file(repo.path(), "docs/original.pdf", "docs/renamed.pdf");
    let user_bytes_before_sync =
        fs::read(repo.path().join("docs/renamed.pdf")).expect("read externally renamed file");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf", 501)],
    )
    .expect("sync external renamed event");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(fs_cursor(repo.path()), Some(501));

    let files = listed_files(repo.path());
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].id, entry.id);
    assert_eq!(files[0].path, "docs/renamed.pdf");
    assert_eq!(files[0].current_name, "renamed.pdf");
    assert_eq!(files[0].category, "docs");

    let detail = get_file(path_string(repo.path()), entry.id).expect("get renamed file detail");
    assert_eq!(detail.path, "docs/renamed.pdf");
    assert_eq!(detail.current_name, "renamed.pdf");

    let tree_json =
        list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list tree json");
    assert!(tree_json.contains("\"relative_path\":\"docs\""));
    assert!(tree_json.contains("\"file_count\":1"));

    let change = renamed_change(repo.path());
    assert_eq!(change.file_id, Some(entry.id));
    let detail = change_detail(&change);
    assert_eq!(detail["from_path"], "docs/original.pdf");
    assert_eq!(detail["to_path"], "docs/renamed.pdf");
    assert_eq!(detail["from_name"], "original.pdf");
    assert_eq!(detail["to_name"], "renamed.pdf");
    assert_eq!(detail["by"], "external");
    assert_eq!(
        fs::read(repo.path().join("docs/renamed.pdf")).expect("renamed user file remains readable"),
        user_bytes_before_sync
    );
}

#[test]
fn sync_external_renamed_validation_missing_target_leaves_db_cursor_and_file_intact() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"missing target", 510);

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/missing.pdf", 511)],
    );

    assert_eq!(result, Err(CoreError::FileNotFound));
    assert_eq!(fs_cursor(repo.path()), Some(510));
    let unchanged = get_file(path_string(repo.path()), entry.id).expect("get unchanged file");
    assert_eq!(unchanged.path, "docs/original.pdf");
    assert_eq!(unchanged.current_name, "original.pdf");
    assert!(listed_changes(repo.path())
        .into_iter()
        .all(|change| change.action != "renamed"));
    assert_eq!(
        fs::read(repo.path().join("docs/original.pdf")).expect("original user file remains"),
        b"missing target"
    );
}

#[test]
fn sync_external_renamed_validation_ambiguous_hash_match_is_conflict_without_state_change() {
    let repo = initialized_repo();
    let first = sync_created_file(repo.path(), "docs/first.pdf", b"same bytes", 520);
    let second = sync_created_file(repo.path(), "docs/second.pdf", b"same bytes", 521);
    rename_user_file(repo.path(), "docs/first.pdf", "docs/first-renamed.pdf");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/first-renamed.pdf", 522)],
    );

    assert_eq!(result, Err(CoreError::Conflict));
    assert_eq!(fs_cursor(repo.path()), Some(521));
    assert_eq!(
        get_file(path_string(repo.path()), first.id)
            .expect("get first unchanged file")
            .path,
        "docs/first.pdf"
    );
    assert_eq!(
        get_file(path_string(repo.path()), second.id)
            .expect("get second unchanged file")
            .path,
        "docs/second.pdf"
    );
    assert!(listed_changes(repo.path())
        .into_iter()
        .all(|change| change.action != "renamed"));
    assert_eq!(
        fs::read(repo.path().join("docs/first-renamed.pdf"))
            .expect("externally renamed user file remains readable"),
        b"same bytes"
    );
}

#[test]
fn sync_external_renamed_validation_does_not_claim_cursor_for_unimplemented_event_kinds() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.txt", b"scope boundary", 530);
    rename_user_file(repo.path(), "docs/original.txt", "docs/renamed.txt");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            renamed("docs/renamed.txt", 531),
            modified("docs/renamed.txt", 532),
        ],
    )
    .expect("sync only the bound renamed capability");

    assert_eq!(result.detected_renames, 1);
    assert_eq!(result.detected_modifies, 0);
    assert_eq!(result.detected_deletes, 0);
    assert_eq!(fs_cursor(repo.path()), Some(530));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("get renamed file")
            .path,
        "docs/renamed.txt"
    );
}
