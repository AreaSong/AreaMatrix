use std::{fs, path::Path};

use area_matrix_core::{
    get_fs_event_cursor, init_repo, list_files, sync_external_changes, CoreError, ExternalEvent,
    ExternalEventKind, FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions,
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

fn file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs cursor")
}

#[test]
fn sync_external_created_failure_recovery_db_error_rolls_back_rows_and_cursor() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/external.pdf", b"external bytes");
    open_db(repo.path())
        .execute("DROP TABLE change_log", [])
        .expect("remove change_log table to force transactional DB failure");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/external.pdf", 100)],
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(active_file_count(repo.path()), 0);
    assert_eq!(fs_cursor(repo.path()), None);
    assert_eq!(
        fs::read(repo.path().join("docs/external.pdf")).expect("user file remains readable"),
        b"external bytes"
    );
}

#[test]
fn sync_external_created_failure_recovery_replays_after_missing_file_without_partial_state() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/good.pdf", b"good");

    let failed = sync_external_changes(
        path_string(repo.path()),
        vec![
            created("docs/good.pdf", 110),
            created("docs/missing.pdf", 111),
        ],
    );

    assert!(matches!(failed, Err(CoreError::Io { .. })));

    assert_eq!(active_file_count(repo.path()), 0);
    assert_eq!(fs_cursor(repo.path()), None);

    write_repo_file(repo.path(), "docs/missing.pdf", b"recovered");
    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![
            created("docs/good.pdf", 110),
            created("docs/missing.pdf", 111),
        ],
    )
    .expect("replay fixed created-event batch");

    assert_eq!(replayed.detected_creates, 2);
    assert_eq!(fs_cursor(repo.path()), Some(111));

    let mut paths = list_files(path_string(repo.path()), file_filter())
        .expect("list replayed files")
        .into_iter()
        .map(|file| file.path)
        .collect::<Vec<_>>();
    paths.sort();
    assert_eq!(paths, vec!["docs/good.pdf", "docs/missing.pdf"]);
}

#[cfg(unix)]
#[test]
fn sync_external_created_failure_recovery_permission_denied_keeps_files_db_and_cursor_unchanged() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/good.pdf", b"good");
    write_repo_file(repo.path(), "docs/blocked.pdf", b"blocked");
    let blocked_path = repo.path().join("docs/blocked.pdf");
    let original_permissions = fs::metadata(&blocked_path)
        .expect("read blocked file permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&blocked_path, blocked_permissions).expect("remove file read permissions");
    if fs::read(&blocked_path).is_ok() {
        fs::set_permissions(&blocked_path, original_permissions)
            .expect("restore blocked file permissions");
        return;
    }

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![
            created("docs/good.pdf", 120),
            created("docs/blocked.pdf", 121),
        ],
    );

    fs::set_permissions(&blocked_path, original_permissions)
        .expect("restore blocked file permissions");

    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(active_file_count(repo.path()), 0);
    assert_eq!(fs_cursor(repo.path()), None);
    assert_eq!(
        fs::read(repo.path().join("docs/good.pdf")).expect("good user file remains readable"),
        b"good"
    );
    assert_eq!(
        fs::read(blocked_path).expect("blocked user file remains readable after restore"),
        b"blocked"
    );
}
