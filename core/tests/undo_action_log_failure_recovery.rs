use std::{fs, path::Path, sync::Mutex};

use area_matrix_core::{
    batch_add_tags, delete_file, init_repo, list_undo_actions, rename_file, undo_action, CoreError,
    ErrorKind, ErrorRecoverability, OverviewOutput, RepoInitMode, RepoInitOptions,
    UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

static HOME_ENV_LOCK: Mutex<()> = Mutex::new(());
const FORCE_USER_TRASH_ENV: &str = "AREAMATRIX_TEST_FORCE_USER_TRASH";

#[derive(Debug, Eq, PartialEq)]
struct UndoSnapshot {
    files: Vec<(i64, String, String, String)>,
    tags: Vec<(i64, String)>,
    changes: Vec<(i64, String, String)>,
    undo_actions: Vec<(String, String, String)>,
    user_visible_paths: Vec<String>,
}

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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, format!("fixture bytes for {relative_path}"))
        .expect("write fixture file");

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture has filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 13,
                ?4, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn snapshot(repo: &Path) -> UndoSnapshot {
    UndoSnapshot {
        files: file_rows(repo),
        tags: tag_rows(repo),
        changes: change_rows(repo),
        undo_actions: undo_rows(repo),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, current_name, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn tag_rows(repo: &Path) -> Vec<(i64, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, tag FROM tags ORDER BY file_id, tag")
        .expect("prepare tag rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query tag rows")
        .map(|row| row.expect("read tag row"))
        .collect()
}

fn change_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(file_id, 0), action, detail_json
               FROM change_log
              ORDER BY id",
        )
        .expect("prepare change rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query change rows")
        .map(|row| row.expect("read change row"))
        .collect()
}

fn undo_rows(repo: &Path) -> Vec<(String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT token, kind, status FROM undo_actions ORDER BY token")
        .expect("prepare undo rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query undo rows")
        .map(|row| row.expect("read undo row"))
        .collect()
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repository")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn undo_status(repo: &Path, token: &str) -> String {
    open_db(repo)
        .query_row(
            "SELECT status FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .expect("read undo status")
}

fn only_undo_token(repo: &Path) -> String {
    open_db(repo)
        .query_row("SELECT token FROM undo_actions", [], |row| row.get(0))
        .expect("read only undo token")
}

fn repo_config_value(repo: &Path, key: &str) -> String {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .expect("read repo config value")
}

fn install_undo_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_undo_change_log
             BEFORE INSERT ON change_log
             WHEN json_extract(NEW.detail_json, '$.by') = 'undo'
             BEGIN
               SELECT RAISE(ABORT, 'forced undo change_log failure');
             END;",
        )
        .expect("install undo change-log failure trigger");
}

fn drop_trigger(repo: &Path, trigger_name: &str) {
    open_db(repo)
        .execute_batch(&format!("DROP TRIGGER {trigger_name};"))
        .expect("drop trigger");
}

fn with_test_system_trash<R>(run: impl FnOnce(&Path) -> R) -> R {
    let _guard = HOME_ENV_LOCK.lock().expect("lock HOME override");
    let home = tempfile::tempdir().expect("create temporary HOME");
    let trash_dir = home.path().join(".Trash");
    fs::create_dir(&trash_dir).expect("create temporary system Trash");
    let previous_home = std::env::var_os("HOME");
    let previous_force = std::env::var_os(FORCE_USER_TRASH_ENV);
    std::env::set_var("HOME", home.path());
    std::env::set_var(FORCE_USER_TRASH_ENV, "1");
    let result = run(&trash_dir);
    match previous_home {
        Some(value) => std::env::set_var("HOME", value),
        None => std::env::remove_var("HOME"),
    }
    match previous_force {
        Some(value) => std::env::set_var(FORCE_USER_TRASH_ENV, value),
        None => std::env::remove_var(FORCE_USER_TRASH_ENV),
    }
    result
}

fn assert_error_mapping(error: &CoreError, kind: ErrorKind, recoverability: ErrorRecoverability) {
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, kind);
    assert_eq!(mapping.recoverability, recoverability);
}

#[test]
fn undo_action_log_failure_recovery_empty_stack_is_read_only() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let actions = list_undo_actions(path_string(repo.path())).expect("list empty undo stack");

    assert!(actions.is_empty());
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn undo_action_log_failure_recovery_invalid_inputs_map_to_documented_errors() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let empty = undo_action(path_string(repo.path()), "  ".to_owned())
        .expect_err("empty undo action id is invalid");
    assert_error_mapping(
        &empty,
        ErrorKind::FileNotFound,
        ErrorRecoverability::RefreshRequired,
    );

    let metadata = list_undo_actions(
        repo.path()
            .join(".areamatrix")
            .to_string_lossy()
            .into_owned(),
    )
    .expect_err("metadata-internal repo path is invalid for C2-07");
    assert_error_mapping(
        &metadata,
        ErrorKind::Db,
        ErrorRecoverability::UserActionRequired,
    );

    let missing = undo_action(path_string(repo.path()), "undo:missing".to_owned())
        .expect_err("missing pending action is not undoable");
    assert_error_mapping(
        &missing,
        ErrorKind::FileNotFound,
        ErrorRecoverability::RefreshRequired,
    );

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn undo_action_log_failure_recovery_db_metadata_errors_do_not_mutate() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["urgent".to_owned()],
    )
    .expect("batch add tags");
    let _token = report.undo_token.expect("undo token exists");
    let before = snapshot(repo.path());

    open_db(repo.path())
        .execute_batch("DROP TABLE tags;")
        .expect("drop tags table to force undo metadata DB error");

    let list_error = list_undo_actions(path_string(repo.path()))
        .expect_err("missing undo metadata table fails list");
    assert_error_mapping(&list_error, ErrorKind::Db, ErrorRecoverability::Fatal);

    let undo_error = undo_action(path_string(repo.path()), only_undo_token(repo.path()))
        .expect_err("missing undo metadata table fails execute");
    assert_error_mapping(&undo_error, ErrorKind::Db, ErrorRecoverability::Fatal);

    assert_eq!(file_rows(repo.path()), before.files);
    assert_eq!(change_rows(repo.path()), before.changes);
    assert_eq!(undo_rows(repo.path()), before.undo_actions);
    assert_eq!(user_visible_paths(repo.path()), before.user_visible_paths);
}

#[test]
fn undo_action_log_failure_recovery_db_write_error_rolls_back_tags_and_status() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token exists");
    let before = snapshot(repo.path());
    install_undo_change_log_failure(repo.path());

    let error = undo_action(path_string(repo.path()), token.clone())
        .expect_err("change-log DB failure aborts undo transaction");

    assert_error_mapping(
        &error,
        ErrorKind::Db,
        ErrorRecoverability::UserActionRequired,
    );
    assert_eq!(snapshot(repo.path()), before);

    drop_trigger(repo.path(), "fail_undo_change_log");
    let result =
        undo_action(path_string(repo.path()), token).expect("retry undo after DB recovery");
    assert_eq!(result.status, UndoActionStatus::Executed);
    assert!(tag_rows(repo.path()).is_empty());
}

#[test]
fn undo_action_log_failure_recovery_io_conflict_does_not_mark_file_action_executed() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/draft.pdf", "docs");
    rename_file(path_string(repo.path()), file_id, "final.pdf".to_owned()).expect("rename file");
    let token = only_undo_token(repo.path());
    fs::remove_file(repo.path().join("docs/final.pdf")).expect("remove renamed file");
    fs::create_dir(repo.path().join("docs/final.pdf"))
        .expect("replace renamed file with directory to simulate unsafe external change");
    let before = snapshot(repo.path());

    let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
    assert_eq!(actions[0].status, UndoActionStatus::Blocked);
    assert_eq!(
        actions[0].disabled_reason.as_deref(),
        Some("File changed after action")
    );

    let error = undo_action(path_string(repo.path()), token.clone())
        .expect_err("directory at expected path cannot be moved as a file");

    assert_error_mapping(&error, ErrorKind::Io, ErrorRecoverability::Retryable);
    assert_eq!(undo_status(repo.path(), &token), "pending");
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn undo_action_log_failure_recovery_restore_trash_io_failure_keeps_retryable_state() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let file_id = insert_file(repo.path(), "docs/report.pdf", "docs");
        delete_file(path_string(repo.path()), file_id).expect("delete file to trash");
        let token = only_undo_token(repo.path());
        fs::remove_file(trash_dir.join("report.pdf")).expect("remove trashed file");
        fs::create_dir(trash_dir.join("report.pdf")).expect("replace trash item with directory");
        let before = snapshot(repo.path());

        let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
        assert_eq!(actions[0].status, UndoActionStatus::Blocked);
        assert_eq!(
            actions[0].disabled_reason.as_deref(),
            Some("Trash item changed")
        );

        let error = undo_action(path_string(repo.path()), token.clone())
            .expect_err("changed trash item cannot restore as file");

        assert_error_mapping(&error, ErrorKind::Io, ErrorRecoverability::Retryable);
        assert_eq!(undo_status(repo.path(), &token), "pending");
        assert_eq!(snapshot(repo.path()), before);
        assert!(repo.path().join("docs").exists());
        assert!(!repo.path().join("docs/report.pdf").exists());
    });
}

#[cfg(unix)]
#[test]
fn undo_action_log_failure_recovery_permission_denied_is_structured_and_retryable() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/draft.pdf", "docs");
    rename_file(path_string(repo.path()), file_id, "final.pdf".to_owned()).expect("rename file");
    let token = only_undo_token(repo.path());
    let original_permissions = fs::metadata(repo.path().join("docs"))
        .expect("read directory permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o555);
    fs::set_permissions(repo.path().join("docs"), denied_permissions)
        .expect("make directory unwritable");

    let result = undo_action(path_string(repo.path()), token.clone());

    fs::set_permissions(repo.path().join("docs"), original_permissions)
        .expect("restore directory permissions");

    match result {
        Ok(_) => {}
        Err(error) => {
            assert_error_mapping(
                &error,
                ErrorKind::PermissionDenied,
                ErrorRecoverability::UserActionRequired,
            );
            assert_eq!(undo_status(repo.path(), &token), "pending");
        }
    }
}

#[test]
fn undo_action_log_failure_recovery_never_uses_ai_or_remote_state() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/local.pdf", "docs");
    let before_staging = repo.path().join(".areamatrix/staging");
    let before_visible = user_visible_paths(repo.path());
    let before_ai_enabled = repo_config_value(repo.path(), "ai_enabled");

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["private".to_owned()],
    )
    .expect("batch add tags");
    undo_action(
        path_string(repo.path()),
        report.undo_token.expect("undo token exists"),
    )
    .expect("undo local metadata-only tag action");

    assert!(before_staging.exists());
    assert_eq!(
        fs::read_dir(before_staging)
            .expect("read staging dir")
            .count(),
        0
    );
    assert_eq!(
        repo_config_value(repo.path(), "ai_enabled"),
        before_ai_enabled
    );
    assert_eq!(before_ai_enabled, "false");
    assert_eq!(user_visible_paths(repo.path()), before_visible);
    assert_eq!(tag_rows(repo.path()), Vec::<(i64, String)>::new());
}
