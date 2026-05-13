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

fn removed(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    event(relative_path, ExternalEventKind::Removed, fs_event_id)
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

fn include_deleted_file_filter() -> FileFilter {
    FileFilter {
        include_deleted: Some(true),
        ..default_file_filter()
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

fn listed_files(repo: &Path, filter: FileFilter) -> Vec<area_matrix_core::FileEntry> {
    list_files(path_string(repo), filter).expect("list files")
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

fn file_status(repo: &Path, file_id: i64) -> (String, Option<i64>) {
    open_db(repo)
        .query_row(
            "SELECT status, deleted_at FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read file status")
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
            .expect("sync external created file");
    assert_eq!(result.detected_creates, 1);
    listed_files(repo, default_file_filter())
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

fn install_deleted_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_deleted_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'deleted'
             BEGIN
                 SELECT RAISE(FAIL, 'forced deleted change log failure');
             END;",
        )
        .expect("install deleted change log failure trigger");
}

#[test]
fn sync_external_removed_implementation_soft_deletes_file_log_and_cursor() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/remove.pdf", b"remove bytes", 10);
    write_repo_file(repo.path(), "docs/keeper.pdf", b"keeper");
    fs::remove_file(repo.path().join("docs/remove.pdf")).expect("simulate external deletion");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/remove.pdf", 11)],
    )
    .expect("sync external removed file");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 1);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(fs_cursor(repo.path()), Some(11));

    assert!(listed_files(repo.path(), default_file_filter()).is_empty());
    let deleted_files = listed_files(repo.path(), include_deleted_file_filter());
    assert_eq!(deleted_files.len(), 1);
    assert_eq!(deleted_files[0].id, entry.id);
    assert_eq!(deleted_files[0].path, "docs/remove.pdf");
    assert!(matches!(
        get_file(path_string(repo.path()), entry.id),
        Err(CoreError::FileNotFound { .. })
    ));

    assert_eq!(file_status(repo.path(), entry.id).0, "deleted");
    assert!(
        file_status(repo.path(), entry.id).1.is_some(),
        "deleted_at should be populated"
    );

    let deleted_change = listed_changes(repo.path())
        .into_iter()
        .find(|change| change.action == "deleted")
        .expect("deleted change should be recorded");
    assert_eq!(deleted_change.file_id, Some(entry.id));
    let detail = change_detail(&deleted_change);
    assert_eq!(detail["hard"], false);
    assert_eq!(detail["by"], "external");
    assert_eq!(
        fs::read(repo.path().join("docs/keeper.pdf")).expect("unrelated user file remains"),
        b"keeper"
    );
}

#[test]
fn sync_external_removed_implementation_is_idempotent_for_replayed_event() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/replay.pdf", b"replay bytes", 20);
    fs::remove_file(repo.path().join("docs/replay.pdf")).expect("simulate external deletion");
    sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/replay.pdf", 21)],
    )
    .expect("sync first removed event");

    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/replay.pdf", 22)],
    )
    .expect("replay removed event");

    assert_eq!(replayed.detected_deletes, 0);
    assert_eq!(fs_cursor(repo.path()), Some(22));
    assert_eq!(count_changes_with_action(repo.path(), "deleted"), 1);
    assert_eq!(file_status(repo.path(), entry.id).0, "deleted");
}

#[test]
fn sync_external_removed_implementation_rejects_existing_path_without_metadata_change() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/still-present.pdf", b"present bytes", 30);

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/still-present.pdf", 31)],
    );

    assert!(matches!(result, Err(CoreError::Io { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(30));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("active row remains visible")
            .path,
        "docs/still-present.pdf"
    );
    assert_eq!(count_changes_with_action(repo.path(), "deleted"), 0);
    assert_eq!(
        fs::read(repo.path().join("docs/still-present.pdf")).expect("user file remains readable"),
        b"present bytes"
    );
}

#[test]
fn sync_external_removed_implementation_rolls_back_db_and_cursor_on_log_failure() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/rollback.pdf", b"rollback bytes", 40);
    fs::remove_file(repo.path().join("docs/rollback.pdf")).expect("simulate external deletion");
    install_deleted_change_log_failure(repo.path());

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/rollback.pdf", 41)],
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(40));
    assert_eq!(file_status(repo.path(), entry.id).0, "active");
    assert_eq!(count_changes_with_action(repo.path(), "deleted"), 0);
}

#[test]
fn sync_external_removed_implementation_skips_internal_generated_paths_and_advances_cursor() {
    let repo = initialized_repo();

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            removed(".areamatrix/generated/internal.md", 50),
            removed("AREAMATRIX.md", 51),
        ],
    )
    .expect("sync skipped removed events");

    assert_eq!(result.detected_deletes, 0);
    assert_eq!(fs_cursor(repo.path()), Some(51));
    assert!(listed_files(repo.path(), include_deleted_file_filter()).is_empty());
    assert!(listed_changes(repo.path()).is_empty());
}

#[test]
fn sync_external_removed_implementation_rejects_escaping_or_placeholder_paths_without_state() {
    let repo = initialized_repo();
    let outside = tempfile::NamedTempFile::new().expect("create external file");

    let escaping = sync_external_changes(
        path_string(repo.path()),
        vec![ExternalEvent {
            path: path_string(outside.path()),
            kind: ExternalEventKind::Removed,
            fs_event_id: 60,
        }],
    );
    assert!(matches!(escaping, Err(CoreError::InvalidPath { .. })));

    assert_eq!(fs_cursor(repo.path()), None);

    let placeholder = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/waiting.pdf.icloud", 61)],
    );
    assert_eq!(
        placeholder,
        Err(CoreError::icloud_placeholder("icloud placeholder"))
    );
    assert_eq!(fs_cursor(repo.path()), None);
    assert!(listed_changes(repo.path()).is_empty());
}
