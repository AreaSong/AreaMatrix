use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, sync_external_changes,
    ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
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

fn change_detail(change: &area_matrix_core::ChangeLogEntry) -> Value {
    serde_json::from_str(&change.detail_json).expect("change detail should be JSON object")
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn sync_created_file(
    repo: &Path,
    relative_path: &str,
    bytes: &[u8],
) -> area_matrix_core::FileEntry {
    write_repo_file(repo, relative_path, bytes);
    let result = sync_external_changes(path_string(repo), vec![created(relative_path, 1)])
        .expect("sync external created file");
    assert_eq!(result.detected_creates, 1);
    listed_files(repo)
        .into_iter()
        .find(|file| file.path == relative_path)
        .expect("created file row should be listed")
}

fn count_changes_with_action(repo: &Path, action: &str) -> usize {
    listed_changes(repo)
        .into_iter()
        .filter(|change| change.action == action)
        .count()
}

fn install_renamed_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_renamed_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'renamed'
             BEGIN
                 SELECT RAISE(FAIL, 'forced renamed change log failure');
             END;",
        )
        .expect("install renamed change log failure trigger");
}

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
    assert_eq!(detail["from_path"], "docs/original.pdf");
    assert_eq!(detail["to_path"], "docs/renamed.pdf");
    assert_eq!(detail["from_name"], "original.pdf");
    assert_eq!(detail["to_name"], "renamed.pdf");
    assert_eq!(detail["by"], "external");
    assert_eq!(
        fs::read(repo.path().join("docs/renamed.pdf")).expect("renamed user file remains readable"),
        b"rename bytes"
    );
}

#[test]
fn sync_external_renamed_implementation_is_idempotent_for_replayed_event() {
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
        vec![renamed("docs/renamed.pdf", 3)],
    )
    .expect("replay renamed event");

    assert_eq!(replayed.detected_renames, 0);
    assert_eq!(fs_cursor(repo.path()), Some(3));
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 1);
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("get renamed file")
            .path,
        "docs/renamed.pdf"
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
fn sync_external_renamed_implementation_rejects_cross_category_move_scope() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/original.pdf", b"move bytes");
    fs::create_dir_all(repo.path().join("finance")).expect("create target category directory");
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("finance/original.pdf"),
    )
    .expect("simulate external cross-category move");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("finance/original.pdf", 20)],
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(1));
    let unchanged = get_file(path_string(repo.path()), entry.id).expect("get original DB row");
    assert_eq!(unchanged.path, "docs/original.pdf");
    assert_eq!(count_changes_with_action(repo.path(), "renamed"), 0);
    assert_eq!(
        fs::read(repo.path().join("finance/original.pdf"))
            .expect("moved user file remains readable"),
        b"move bytes"
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
