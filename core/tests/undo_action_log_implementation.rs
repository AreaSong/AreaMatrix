use std::{fs, path::Path, sync::Mutex};

use area_matrix_core::{
    batch_add_tags, delete_file, init_repo, list_undo_actions, move_to_category, rename_file,
    undo_action, CoreError, OverviewOutput, RepoInitMode, RepoInitOptions, UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

static HOME_ENV_LOCK: Mutex<()> = Mutex::new(());
const FORCE_USER_TRASH_ENV: &str = "AREAMATRIX_TEST_FORCE_USER_TRASH";

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

fn insert_indexed_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
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
                ?4, 'indexed', 'imported', ?1,
                100, 100, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len() + 1000),
            ],
        )
        .expect("insert indexed file row");
    connection.last_insert_rowid()
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, status FROM files WHERE id = ?1",
            params![file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read file row")
}

fn undo_action_ids(repo: &Path, kind: &str) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT token FROM undo_actions WHERE kind = ?1 ORDER BY created_at DESC")
        .expect("prepare undo token query");
    statement
        .query_map(params![kind], |row| row.get(0))
        .expect("query undo tokens")
        .map(|row| row.expect("read undo token"))
        .collect()
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

fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 100)",
            params![file_id, tag],
        )
        .expect("insert tag row");
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

fn change_log_rows(repo: &Path) -> Vec<(i64, String, serde_json::Value)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(file_id, 0), action, detail_json
               FROM change_log
              ORDER BY id",
        )
        .expect("prepare change-log query");
    statement
        .query_map([], |row| {
            let detail: String = row.get(2)?;
            Ok((
                row.get(0)?,
                row.get(1)?,
                serde_json::from_str(&detail).expect("change detail json is valid"),
            ))
        })
        .expect("query change-log")
        .map(|row| row.expect("read change-log row"))
        .collect()
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

#[test]
fn undo_action_log_implementation_lists_pending_batch_tag_action() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs");

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["Urgent".to_owned(), "ClientA".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token is created");

    let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");

    assert_eq!(actions.len(), 1);
    assert_eq!(actions[0].action_id, token);
    assert_eq!(actions[0].kind, "batch_add_tags");
    assert_eq!(actions[0].affected_count, 2);
    assert_eq!(actions[0].status, UndoActionStatus::Pending);
    assert!(actions[0].can_undo);
    assert_eq!(actions[0].disabled_reason, None);
}

#[test]
fn undo_action_log_implementation_executes_batch_tag_inverse_transactionally() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let second_id = insert_file(repo.path(), "docs/plan.pdf", "docs");
    insert_tag(repo.path(), first_id, "baseline");
    let before_paths = user_visible_paths(repo.path());

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![first_id, second_id],
        vec!["Urgent".to_owned(), "Baseline".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token is created");

    let result = undo_action(path_string(repo.path()), token.clone()).expect("execute undo");

    assert_eq!(result.action_id, token);
    assert_eq!(result.status, UndoActionStatus::Executed);
    assert_eq!(result.affected_count, 3);
    assert_eq!(
        result.refresh_targets,
        vec!["files", "tags", "undo_actions", "change_log"]
    );
    assert_eq!(
        undo_status(repo.path(), result.action_id.as_str()),
        "executed"
    );
    assert_eq!(
        tag_rows(repo.path()),
        vec![(first_id, "baseline".to_owned())]
    );
    assert_eq!(user_visible_paths(repo.path()), before_paths);

    let changes = change_log_rows(repo.path());
    assert_eq!(changes.len(), 6);
    assert_eq!(
        changes
            .iter()
            .filter(|(_, _, detail)| detail["kind"] == "undo_batch_tag_removed")
            .count(),
        3
    );
}

#[test]
fn undo_action_log_implementation_blocks_when_external_change_removed_relation() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["Urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token is created");
    open_db(repo.path())
        .execute(
            "DELETE FROM tags WHERE file_id = ?1 AND tag = 'urgent'",
            params![file_id],
        )
        .expect("simulate external metadata change");
    let before_changes = change_log_rows(repo.path());

    let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
    assert_eq!(actions[0].status, UndoActionStatus::Blocked);
    assert!(!actions[0].can_undo);
    assert_eq!(
        actions[0].disabled_reason.as_deref(),
        Some("Tag relation already changed")
    );

    let error = undo_action(path_string(repo.path()), token.clone())
        .expect_err("unsafe external change blocks undo");
    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_eq!(undo_status(repo.path(), token.as_str()), "pending");
    assert_eq!(change_log_rows(repo.path()), before_changes);
}

#[test]
fn undo_action_log_implementation_executes_rename_inverse() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/draft.pdf", "docs");

    rename_file(path_string(repo.path()), file_id, "final.pdf".to_owned()).expect("rename file");

    let token = undo_action_ids(repo.path(), "rename_files")
        .pop()
        .expect("rename undo token exists");
    let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
    assert_eq!(actions[0].action_id, token);
    assert_eq!(actions[0].kind, "rename_files");
    assert_eq!(actions[0].status, UndoActionStatus::Pending);
    assert!(actions[0].can_undo);

    let result = undo_action(path_string(repo.path()), token.clone()).expect("undo rename");

    assert_eq!(result.status, UndoActionStatus::Executed);
    assert_eq!(file_row(repo.path(), file_id).0, "docs/draft.pdf");
    assert!(repo.path().join("docs/draft.pdf").exists());
    assert!(!repo.path().join("docs/final.pdf").exists());
    assert_eq!(undo_status(repo.path(), &token), "executed");
}

#[test]
fn undo_action_log_implementation_executes_move_inverse() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance");

    move_to_category(path_string(repo.path()), file_id, "docs".to_owned())
        .expect("move file to docs");

    let token = undo_action_ids(repo.path(), "move_files")
        .pop()
        .expect("move undo token exists");
    undo_action(path_string(repo.path()), token.clone()).expect("undo move");

    assert_eq!(
        file_row(repo.path(), file_id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned(),
            "active".to_owned(),
        )
    );
    assert!(repo.path().join("finance/report.pdf").exists());
    assert!(!repo.path().join("docs/report.pdf").exists());
    assert_eq!(undo_status(repo.path(), &token), "executed");
}

#[test]
fn undo_action_log_implementation_executes_index_only_category_inverse() {
    let repo = initialized_repo();
    let file_id = insert_indexed_file(repo.path(), "/external/report.pdf", "finance");

    move_to_category(path_string(repo.path()), file_id, "docs".to_owned())
        .expect("change indexed category");

    let token = undo_action_ids(repo.path(), "change_category")
        .pop()
        .expect("change-category undo token exists");
    undo_action(path_string(repo.path()), token.clone()).expect("undo indexed category");

    assert_eq!(
        file_row(repo.path(), file_id),
        (
            "/external/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(undo_status(repo.path(), &token), "executed");
}

#[test]
fn undo_action_log_implementation_executes_delete_inverse_from_trash() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let file_id = insert_file(repo.path(), "docs/report.pdf", "docs");

        delete_file(path_string(repo.path()), file_id).expect("delete file to test trash");

        let token = undo_action_ids(repo.path(), "trash_delete")
            .pop()
            .expect("delete undo token exists");
        let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
        assert_eq!(actions[0].status, UndoActionStatus::Pending);
        assert!(trash_dir.join("report.pdf").exists());

        let result = undo_action(path_string(repo.path()), token.clone()).expect("undo delete");

        assert_eq!(result.status, UndoActionStatus::Executed);
        assert_eq!(
            file_row(repo.path(), file_id),
            (
                "docs/report.pdf".to_owned(),
                "report.pdf".to_owned(),
                "docs".to_owned(),
                "active".to_owned(),
            )
        );
        assert!(repo.path().join("docs/report.pdf").exists());
        assert!(!trash_dir.join("report.pdf").exists());
        assert_eq!(undo_status(repo.path(), &token), "executed");
    });
}

#[test]
fn undo_action_log_implementation_blocks_file_action_after_external_move() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/draft.pdf", "docs");
    rename_file(path_string(repo.path()), file_id, "final.pdf".to_owned())
        .expect("rename file before external change");
    fs::remove_file(repo.path().join("docs/final.pdf")).expect("simulate external removal");

    let actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");

    assert_eq!(actions[0].kind, "rename_files");
    assert_eq!(actions[0].status, UndoActionStatus::Blocked);
    assert!(!actions[0].can_undo);
    assert_eq!(
        actions[0].disabled_reason.as_deref(),
        Some("File no longer exists")
    );
}

#[test]
fn undo_action_log_implementation_rejects_missing_and_repeated_action() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["Urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token is created");

    undo_action(path_string(repo.path()), token.clone()).expect("first undo succeeds");
    let repeated = undo_action(path_string(repo.path()), token)
        .expect_err("executed action is no longer pending");
    assert!(matches!(repeated, CoreError::FileNotFound { .. }));

    let missing = undo_action(path_string(repo.path()), "undo:missing".to_owned())
        .expect_err("missing action fails");
    assert!(matches!(missing, CoreError::FileNotFound { .. }));
}
