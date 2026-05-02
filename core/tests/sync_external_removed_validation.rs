use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, sync_external_changes,
    ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileEntry, FileFilter,
    OverviewOutput, RepoInitMode, RepoInitOptions,
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

fn listed_files(repo: &Path, filter: FileFilter) -> Vec<FileEntry> {
    list_files(path_string(repo), filter).expect("list files")
}

fn listed_changes(repo: &Path) -> Vec<area_matrix_core::ChangeLogEntry> {
    list_changes(path_string(repo), default_change_filter()).expect("list changes")
}

fn deleted_changes(repo: &Path) -> Vec<area_matrix_core::ChangeLogEntry> {
    listed_changes(repo)
        .into_iter()
        .filter(|change| change.action == "deleted")
        .collect()
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
) -> FileEntry {
    write_repo_file(repo, relative_path, bytes);
    let result =
        sync_external_changes(path_string(repo), vec![created(relative_path, fs_event_id)])
            .expect("sync external created file fixture");
    assert_eq!(result.detected_creates, 1);
    listed_files(repo, default_file_filter())
        .into_iter()
        .find(|file| file.path == relative_path)
        .expect("created file row should be listed")
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
fn sync_external_removed_validation_success_hides_detail_logs_and_preserves_files() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/remove.pdf", b"remove bytes", 700);
    write_repo_file(repo.path(), "docs/keeper.pdf", b"keeper");
    fs::remove_file(repo.path().join("docs/remove.pdf")).expect("simulate external deletion");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/remove.pdf", 701)],
    )
    .expect("sync external removed event");

    assert_eq!(result.detected_creates, 0);
    assert_eq!(result.detected_renames, 0);
    assert_eq!(result.detected_deletes, 1);
    assert_eq!(result.detected_modifies, 0);
    assert!(result.errors.is_empty());
    assert_eq!(fs_cursor(repo.path()), Some(701));

    assert!(listed_files(repo.path(), default_file_filter()).is_empty());
    let deleted_files = listed_files(repo.path(), include_deleted_file_filter());
    assert_eq!(deleted_files.len(), 1);
    assert_eq!(deleted_files[0].id, entry.id);
    assert!(matches!(
        get_file(path_string(repo.path()), entry.id),
        Err(CoreError::FileNotFound { .. })
    ));

    assert_eq!(file_status(repo.path(), entry.id).0, "deleted");
    let deleted = deleted_changes(repo.path());
    assert_eq!(deleted.len(), 1);
    assert_eq!(deleted[0].file_id, Some(entry.id));
    assert_eq!(deleted[0].filename, "remove.pdf");
    assert_eq!(deleted[0].category, "docs");
    let detail = change_detail(&deleted[0]);
    assert_eq!(detail["hard"], false);
    assert_eq!(detail["by"], "external");
    assert_eq!(
        fs::read(repo.path().join("docs/keeper.pdf")).expect("unrelated user file remains"),
        b"keeper"
    );
}

#[test]
fn sync_external_removed_validation_existing_path_is_error_without_state_change() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/present.pdf", b"present bytes", 710);

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/present.pdf", 711)],
    );

    assert!(matches!(result, Err(CoreError::Io { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(710));
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("active row remains visible")
            .path,
        "docs/present.pdf"
    );
    assert_eq!(
        file_status(repo.path(), entry.id),
        ("active".to_owned(), None)
    );
    assert!(deleted_changes(repo.path()).is_empty());
    assert_eq!(
        fs::read(repo.path().join("docs/present.pdf")).expect("user file remains readable"),
        b"present bytes"
    );
}

#[test]
fn sync_external_removed_validation_db_failure_rolls_back_status_log_and_cursor() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/rollback.pdf", b"rollback bytes", 720);
    fs::remove_file(repo.path().join("docs/rollback.pdf")).expect("simulate external deletion");
    install_deleted_change_log_failure(repo.path());

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/rollback.pdf", 721)],
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(720));
    assert_eq!(
        file_status(repo.path(), entry.id),
        ("active".to_owned(), None)
    );
    assert!(deleted_changes(repo.path()).is_empty());
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("rolled-back metadata remains active")
            .path,
        "docs/rollback.pdf"
    );
}

#[test]
fn sync_external_removed_validation_does_not_claim_modified_event_scope() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/scope.txt", b"scope bytes", 730);
    fs::remove_file(repo.path().join("docs/scope.txt")).expect("simulate external deletion");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            removed("docs/scope.txt", 731),
            modified("docs/scope.txt", 732),
        ],
    )
    .expect("sync only the bound removed capability");

    assert_eq!(result.detected_deletes, 1);
    assert_eq!(result.detected_modifies, 0);
    assert_eq!(fs_cursor(repo.path()), Some(730));
    assert!(matches!(
        get_file(path_string(repo.path()), entry.id),
        Err(CoreError::FileNotFound { .. })
    ));

    assert_eq!(deleted_changes(repo.path()).len(), 1);
}

#[test]
fn sync_external_removed_validation_rejects_bad_paths_without_state() {
    let repo = initialized_repo();
    let outside = tempfile::NamedTempFile::new().expect("create external file");

    let escaping = sync_external_changes(
        path_string(repo.path()),
        vec![ExternalEvent {
            path: path_string(outside.path()),
            kind: ExternalEventKind::Removed,
            fs_event_id: 740,
        }],
    );

    assert!(matches!(escaping, Err(CoreError::InvalidPath { .. })));

    assert_eq!(fs_cursor(repo.path()), None);

    let placeholder = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/waiting.pdf.icloud", 741)],
    );

    assert_eq!(
        placeholder,
        Err(CoreError::icloud_placeholder("icloud placeholder"))
    );
    assert_eq!(fs_cursor(repo.path()), None);
    assert!(listed_files(repo.path(), include_deleted_file_filter()).is_empty());
    assert!(listed_changes(repo.path()).is_empty());
}
