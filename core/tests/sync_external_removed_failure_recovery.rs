use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, list_files, sync_external_changes,
    ChangeFilter, CoreError, ExternalEvent, ExternalEventKind, FileEntry, FileFilter,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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

fn created(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind: ExternalEventKind::Created,
        fs_event_id,
    }
}

fn removed(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind: ExternalEventKind::Removed,
        fs_event_id,
    }
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

fn change_filter() -> ChangeFilter {
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
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

fn deleted_change_count(repo: &Path) -> usize {
    list_changes(path_string(repo), change_filter())
        .expect("list change log")
        .into_iter()
        .filter(|change| change.action == "deleted")
        .count()
}

fn listed_paths(repo: &Path, filter: FileFilter) -> Vec<String> {
    let mut paths = list_files(path_string(repo), filter)
        .expect("list files")
        .into_iter()
        .map(|file| file.path)
        .collect::<Vec<_>>();
    paths.sort();
    paths
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
            .expect("sync external created file");
    assert_eq!(result.detected_creates, 1);
    list_files(path_string(repo), default_file_filter())
        .expect("list active files")
        .into_iter()
        .find(|file| file.path == relative_path)
        .expect("created file row should be active")
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
fn sync_external_removed_failure_recovery_replays_after_batch_path_state_is_fixed() {
    let repo = initialized_repo();
    let first = sync_created_file(repo.path(), "docs/first.pdf", b"first", 1);
    let second = sync_created_file(repo.path(), "docs/second.pdf", b"second", 2);
    write_repo_file(repo.path(), "docs/keeper.pdf", b"keeper");

    fs::remove_file(repo.path().join("docs/first.pdf")).expect("simulate first external delete");
    let failed = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/first.pdf", 3), removed("docs/second.pdf", 4)],
    );

    assert!(matches!(failed, Err(CoreError::Io { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(2));
    assert_eq!(file_status(repo.path(), first.id).0, "active");
    assert_eq!(file_status(repo.path(), second.id).0, "active");
    assert_eq!(deleted_change_count(repo.path()), 0);

    fs::remove_file(repo.path().join("docs/second.pdf")).expect("repair second external delete");
    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/first.pdf", 3), removed("docs/second.pdf", 4)],
    )
    .expect("replay fixed removed-event batch");

    assert_eq!(replayed.detected_deletes, 2);
    assert_eq!(fs_cursor(repo.path()), Some(4));
    assert_eq!(
        listed_paths(repo.path(), default_file_filter()),
        Vec::<String>::new()
    );
    assert_eq!(
        listed_paths(repo.path(), include_deleted_file_filter()),
        vec!["docs/first.pdf", "docs/second.pdf"]
    );
    assert_eq!(file_status(repo.path(), first.id).0, "deleted");
    assert_eq!(file_status(repo.path(), second.id).0, "deleted");
    assert_eq!(deleted_change_count(repo.path()), 2);
    assert_eq!(
        fs::read(repo.path().join("docs/keeper.pdf")).expect("unrelated user file remains"),
        b"keeper"
    );
}

#[test]
fn sync_external_removed_failure_recovery_db_failure_rolls_back_status_log_and_cursor() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/rollback.pdf", b"rollback", 10);
    fs::remove_file(repo.path().join("docs/rollback.pdf")).expect("simulate external delete");
    install_deleted_change_log_failure(repo.path());

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/rollback.pdf", 11)],
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(10));
    assert_eq!(
        file_status(repo.path(), entry.id),
        ("active".to_owned(), None)
    );
    assert_eq!(deleted_change_count(repo.path()), 0);
    assert_eq!(
        get_file(path_string(repo.path()), entry.id)
            .expect("rolled-back row remains visible")
            .path,
        "docs/rollback.pdf"
    );
}

#[test]
fn sync_external_removed_failure_recovery_replayed_event_is_noop_without_duplicate_log() {
    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "docs/replay.pdf", b"replay", 20);
    fs::remove_file(repo.path().join("docs/replay.pdf")).expect("simulate external delete");

    let first = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/replay.pdf", 21)],
    )
    .expect("sync first removed event");
    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![removed("docs/replay.pdf", 21)],
    )
    .expect("replay same removed event");

    assert_eq!(first.detected_deletes, 1);
    assert_eq!(replayed.detected_deletes, 0);
    assert_eq!(fs_cursor(repo.path()), Some(21));
    assert_eq!(file_status(repo.path(), entry.id).0, "deleted");
    assert_eq!(deleted_change_count(repo.path()), 1);
}

#[cfg(unix)]
#[test]
fn sync_external_removed_failure_recovery_permission_denied_keeps_metadata_and_cursor() {
    use std::{io, os::unix::fs::PermissionsExt};

    let repo = initialized_repo();
    let entry = sync_created_file(repo.path(), "blocked/secret.pdf", b"secret", 30);
    let blocked_dir = repo.path().join("blocked");
    let blocked_path = blocked_dir.join("secret.pdf");
    let original_permissions = fs::metadata(&blocked_dir)
        .expect("read blocked directory permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&blocked_dir, denied_permissions).expect("remove directory permissions");

    let metadata_error = match fs::symlink_metadata(&blocked_path) {
        Ok(_) => {
            fs::set_permissions(&blocked_dir, original_permissions)
                .expect("restore directory permissions");
            return;
        }
        Err(error) => error,
    };
    if metadata_error.kind() != io::ErrorKind::PermissionDenied {
        fs::set_permissions(&blocked_dir, original_permissions)
            .expect("restore directory permissions");
        return;
    }

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![removed("blocked/secret.pdf", 31)],
    );

    fs::set_permissions(&blocked_dir, original_permissions).expect("restore directory permissions");

    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(fs_cursor(repo.path()), Some(30));
    assert_eq!(file_status(repo.path(), entry.id).0, "active");
    assert_eq!(deleted_change_count(repo.path()), 0);
    assert_eq!(
        fs::read(blocked_path).expect("blocked user file remains readable after restore"),
        b"secret"
    );
}
