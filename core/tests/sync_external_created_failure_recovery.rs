use std::{fs, path::Path};

use area_matrix_core::{
    get_fs_event_cursor, init_repo, list_files, sync_external_changes, CoreError, ExternalEvent,
    ExternalEventKind, FileFilter, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};

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
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
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

fn external_change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE action = 'external_modified'",
            [],
            |row| row.get(0),
        )
        .expect("count external change-log rows")
}

fn fs_cursor(repo: &Path) -> Option<i64> {
    get_fs_event_cursor(path_string(repo)).expect("read fs cursor")
}

fn receipt_locale(repo: &Path, event_id: i64) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT content_locale FROM external_sync_receipts WHERE event_id = ?1",
            [event_id],
            |row| row.get(0),
        )
        .optional()
        .expect("read external sync receipt locale")
        .flatten()
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
        "en".to_owned(),
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
        "en".to_owned(),
    );

    assert_eq!(failed, Err(CoreError::file_not_found("docs/missing.pdf")));

    assert_eq!(active_file_count(repo.path()), 0);
    assert_eq!(fs_cursor(repo.path()), None);

    write_repo_file(repo.path(), "docs/missing.pdf", b"recovered");
    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![
            created("docs/good.pdf", 110),
            created("docs/missing.pdf", 111),
        ],
        "en".to_owned(),
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

#[test]
fn sync_external_created_failure_recovery_overview_failure_defers_cursor_and_replay_repairs_output()
{
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/external.pdf", b"external bytes");
    let generated_nodes = repo.path().join(".areamatrix/generated/nodes");
    fs::remove_dir_all(&generated_nodes)
        .expect("remove generated nodes directory for failure setup");
    fs::write(&generated_nodes, b"block generated node directory")
        .expect("install generated output blocker");

    let failed = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/external.pdf", 115)],
        "en".to_owned(),
    );

    assert!(matches!(failed, Err(CoreError::Io { .. })));
    assert_eq!(active_file_count(repo.path()), 1);
    assert_eq!(fs_cursor(repo.path()), None);
    assert_eq!(receipt_locale(repo.path(), 115).as_deref(), Some("en"));

    fs::remove_file(&generated_nodes).expect("remove generated output blocker");
    fs::create_dir_all(&generated_nodes).expect("restore generated nodes directory");
    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![created("docs/external.pdf", 115)],
        "zh-Hans".to_owned(),
    )
    .expect("replay event after generated output recovers");

    assert_eq!(replayed.detected_creates, 0);
    assert_eq!(active_file_count(repo.path()), 1);
    assert_eq!(fs_cursor(repo.path()), Some(115));
    let node = fs::read_to_string(repo.path().join(".areamatrix/generated/nodes/docs.md"))
        .expect("read repaired generated node");
    assert!(node.starts_with("# Docs (docs)"));
    assert_eq!(receipt_locale(repo.path(), 115), None);
}

#[test]
fn sync_external_created_failure_recovery_cursor_failure_replays_without_duplicate_business_log() {
    let repo = initialized_repo();
    let relative_path = "docs/external.pdf";
    write_repo_file(repo.path(), relative_path, b"external bytes");
    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER fail_fs_event_cursor_write
             BEFORE INSERT ON fs_event_cursor
             BEGIN
                 SELECT RAISE(FAIL, 'forced cursor write failure');
             END;",
        )
        .expect("install cursor write failure trigger");

    let failed = sync_external_changes(
        path_string(repo.path()),
        vec![created(relative_path, 116)],
        "en".to_owned(),
    );

    assert!(matches!(failed, Err(CoreError::Db { .. })));
    assert_eq!(active_file_count(repo.path()), 1);
    assert_eq!(external_change_count(repo.path()), 1);
    assert_eq!(fs_cursor(repo.path()), None);
    assert_eq!(receipt_locale(repo.path(), 116).as_deref(), Some("en"));
    let overview = fs::read_to_string(repo.path().join(".areamatrix/generated/nodes/docs.md"))
        .expect("read overview committed before cursor failure");
    assert!(overview.contains("external.pdf"));

    open_db(repo.path())
        .execute("DROP TRIGGER fail_fs_event_cursor_write", [])
        .expect("remove cursor write failure trigger");
    fs::write(repo.path().join(relative_path), b"changed after commit")
        .expect("simulate a later external modification before replay");
    let replayed = sync_external_changes(
        path_string(repo.path()),
        vec![created(relative_path, 116)],
        "zh-Hans".to_owned(),
    )
    .expect("replay batch after cursor persistence recovers");

    assert_eq!(replayed.detected_creates, 0);
    assert_eq!(active_file_count(repo.path()), 1);
    assert_eq!(external_change_count(repo.path()), 1);
    assert_eq!(fs_cursor(repo.path()), Some(116));
    let replayed_overview =
        fs::read_to_string(repo.path().join(".areamatrix/generated/nodes/docs.md"))
            .expect("read replayed overview");
    assert!(replayed_overview.starts_with("# Docs (docs)"));
    assert_eq!(receipt_locale(repo.path(), 116), None);
    assert_eq!(
        fs::read(repo.path().join(relative_path)).expect("user file remains readable"),
        b"changed after commit"
    );
}

#[test]
fn sync_external_created_failure_recovery_reactivation_log_failure_restores_deleted_row() {
    let repo = initialized_repo();
    let relative_path = "docs/reappeared.pdf";
    write_repo_file(repo.path(), relative_path, b"before");
    sync_external_changes(
        path_string(repo.path()),
        vec![created(relative_path, 1)],
        "en".to_owned(),
    )
    .expect("sync initial external file");
    fs::remove_file(repo.path().join(relative_path)).expect("simulate external deletion");
    sync_external_changes(
        path_string(repo.path()),
        vec![removed(relative_path, 2)],
        "en".to_owned(),
    )
    .expect("sync external deletion");
    let before = open_db(repo.path())
        .query_row(
            "SELECT id, status, hash_sha256, size_bytes, deleted_at FROM files WHERE path = ?1",
            [relative_path],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, Option<i64>>(4)?,
                ))
            },
        )
        .expect("read deleted row before reactivation");
    write_repo_file(repo.path(), relative_path, b"after content");
    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER fail_external_reactivation_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'external_modified'
              AND json_extract(NEW.detail_json, '$.kind') = 'create'
             BEGIN
                 SELECT RAISE(FAIL, 'forced reactivation log failure');
             END;",
        )
        .expect("install reactivation log failure trigger");

    let result = sync_external_changes(
        path_string(repo.path()),
        vec![created(relative_path, 3)],
        "en".to_owned(),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(fs_cursor(repo.path()), Some(2));
    let after = open_db(repo.path())
        .query_row(
            "SELECT id, status, hash_sha256, size_bytes, deleted_at FROM files WHERE path = ?1",
            [relative_path],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, Option<i64>>(4)?,
                ))
            },
        )
        .expect("read deleted row after failed reactivation");
    assert_eq!(after, before);
    assert_eq!(after.1, "deleted");
    assert_eq!(
        fs::read(repo.path().join(relative_path)).expect("reappeared user file remains readable"),
        b"after content"
    );
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
        "en".to_owned(),
    );

    fs::set_permissions(&blocked_path, original_permissions)
        .expect("restore blocked file permissions");

    assert_eq!(
        result,
        Err(CoreError::permission_denied("docs/blocked.pdf"))
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
