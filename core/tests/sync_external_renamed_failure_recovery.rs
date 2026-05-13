use std::{fs, path::Path};

use area_matrix_core::{
    get_file, get_fs_event_cursor, init_repo, list_changes, sync_external_changes, ChangeFilter,
    CoreError, ExternalEvent, ExternalEventKind, OverviewOutput, RepoInitMode, RepoInitOptions,
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

fn renamed(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind: ExternalEventKind::Renamed,
        fs_event_id,
    }
}

fn sync_created_file(repo: &Path, relative_path: &str, bytes: &[u8], fs_event_id: i64) -> i64 {
    write_repo_file(repo, relative_path, bytes);
    let result =
        sync_external_changes(path_string(repo), vec![created(relative_path, fs_event_id)])
            .expect("sync external created file");
    assert_eq!(result.detected_creates, 1);
    file_id_for_path(repo, relative_path)
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs event cursor")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_id_for_path(repo: &Path, relative_path: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT id FROM files WHERE path = ?1 AND status = 'active'",
            [relative_path],
            |row| row.get(0),
        )
        .expect("find active file row")
}

fn active_paths(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT path FROM files WHERE status = 'active' ORDER BY path")
        .expect("prepare active paths query");
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query active paths")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect active paths")
}

fn change_log_count(repo: &Path, action: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE action = ?1",
            [action],
            |row| row.get(0),
        )
        .expect("count change log rows")
}

fn change_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: Some("renamed".to_owned()),
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn install_file_path_update_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_external_rename_file_update
             BEFORE UPDATE OF path ON files
             BEGIN
                 SELECT RAISE(FAIL, 'forced external rename file update failure');
             END;",
        )
        .expect("install file path update failure trigger");
}

#[test]
fn sync_external_renamed_failure_recovery_replays_after_missing_target_without_partial_state() {
    let repo = initialized_repo();
    let first_id = sync_created_file(repo.path(), "docs/first.pdf", b"first", 1);
    let second_id = sync_created_file(repo.path(), "docs/second.pdf", b"second", 2);
    fs::rename(
        repo.path().join("docs/first.pdf"),
        repo.path().join("docs/first-renamed.pdf"),
    )
    .expect("simulate first external rename");

    let failed = sync_external_changes(
        path_string(repo.path()),
        vec![
            renamed("docs/first-renamed.pdf", 3),
            renamed("docs/second-renamed.pdf", 4),
        ],
    );

    assert!(matches!(failed, Err(CoreError::FileNotFound { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(2));
    assert_eq!(
        active_paths(repo.path()),
        vec!["docs/first.pdf", "docs/second.pdf"]
    );
    assert_eq!(change_log_count(repo.path(), "renamed"), 0);
    assert_eq!(
        fs::read(repo.path().join("docs/first-renamed.pdf"))
            .expect("first renamed user file remains readable"),
        b"first"
    );

    fs::rename(
        repo.path().join("docs/second.pdf"),
        repo.path().join("docs/second-renamed.pdf"),
    )
    .expect("repair second external rename target");
    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![
            renamed("docs/first-renamed.pdf", 3),
            renamed("docs/second-renamed.pdf", 4),
        ],
    )
    .expect("replay repaired rename batch");

    assert_eq!(replayed.detected_renames, 2);
    assert_eq!(fs_cursor(repo.path()), Some(4));
    assert_eq!(
        active_paths(repo.path()),
        vec!["docs/first-renamed.pdf", "docs/second-renamed.pdf"]
    );
    assert_eq!(
        get_file(path_string(repo.path()), first_id)
            .expect("get first renamed file")
            .current_name,
        "first-renamed.pdf"
    );
    assert_eq!(
        get_file(path_string(repo.path()), second_id)
            .expect("get second renamed file")
            .current_name,
        "second-renamed.pdf"
    );
    let changes = list_changes(path_string(repo.path()), change_filter()).expect("list changes");
    assert_eq!(changes.len(), 2);
}

#[test]
fn sync_external_renamed_failure_recovery_db_update_failure_rolls_back_row_log_and_cursor() {
    let repo = initialized_repo();
    let file_id = sync_created_file(repo.path(), "docs/original.pdf", b"rollback", 10);
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/renamed.pdf"),
    )
    .expect("simulate external rename");
    install_file_path_update_failure(repo.path());

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf", 11)],
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert_eq!(fs_cursor(repo.path()), Some(10));
    let unchanged = get_file(path_string(repo.path()), file_id).expect("get unchanged file");
    assert_eq!(unchanged.path, "docs/original.pdf");
    assert_eq!(unchanged.current_name, "original.pdf");
    assert_eq!(change_log_count(repo.path(), "renamed"), 0);
    assert_eq!(
        fs::read(repo.path().join("docs/renamed.pdf"))
            .expect("renamed user file remains readable after DB rollback"),
        b"rollback"
    );
}

#[cfg(unix)]
#[test]
fn sync_external_renamed_failure_recovery_permission_denied_keeps_db_cursor_and_file_intact() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let file_id = sync_created_file(repo.path(), "docs/original.pdf", b"blocked", 20);
    fs::rename(
        repo.path().join("docs/original.pdf"),
        repo.path().join("docs/renamed.pdf"),
    )
    .expect("simulate external rename");
    let renamed_path = repo.path().join("docs/renamed.pdf");
    let original_permissions = fs::metadata(&renamed_path)
        .expect("read renamed file permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&renamed_path, blocked_permissions).expect("remove read permissions");
    if fs::read(&renamed_path).is_ok() {
        fs::set_permissions(&renamed_path, original_permissions)
            .expect("restore readable permissions");
        return;
    }

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![renamed("docs/renamed.pdf", 21)],
    );

    fs::set_permissions(&renamed_path, original_permissions).expect("restore readable permissions");

    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(fs_cursor(repo.path()), Some(20));
    let unchanged = get_file(path_string(repo.path()), file_id).expect("get unchanged file");
    assert_eq!(unchanged.path, "docs/original.pdf");
    assert_eq!(unchanged.current_name, "original.pdf");
    assert_eq!(change_log_count(repo.path(), "renamed"), 0);
    assert_eq!(
        fs::read(renamed_path).expect("renamed user file remains readable after restore"),
        b"blocked"
    );
}
