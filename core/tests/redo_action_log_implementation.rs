use std::{fs, path::Path};

use area_matrix_core::{
    batch_add_tags, init_repo, list_redo_actions, list_undo_actions, redo_action, undo_action,
    CoreError, OverviewOutput, RedoActionStatus, RepoInitMode, RepoInitOptions, UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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

fn undo_status(repo: &Path, token: &str) -> String {
    open_db(repo)
        .query_row(
            "SELECT status FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .expect("read undo status")
}

fn change_log_kinds(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT detail_json FROM change_log ORDER BY id")
        .expect("prepare change-log query");
    statement
        .query_map([], |row| {
            let detail: String = row.get(0)?;
            let value: serde_json::Value =
                serde_json::from_str(&detail).expect("change detail json is valid");
            Ok(value["kind"].as_str().unwrap_or_default().to_owned())
        })
        .expect("query change-log")
        .map(|row| row.expect("read change-log row"))
        .collect()
}

#[test]
fn redo_action_log_implementation_lists_successfully_undone_batch_tag_action() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["Urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token is created");

    undo_action(path_string(repo.path()), token.clone()).expect("execute undo");
    let actions = list_redo_actions(path_string(repo.path())).expect("list redo actions");

    assert_eq!(actions.len(), 1);
    assert_eq!(actions[0].action_id, token);
    assert_eq!(actions[0].kind, "batch_add_tags");
    assert_eq!(actions[0].affected_count, 1);
    assert_eq!(actions[0].status, RedoActionStatus::Available);
    assert!(actions[0].can_redo);
    assert_eq!(actions[0].disabled_reason, None);
}

#[test]
fn redo_action_log_implementation_executes_batch_tag_redo_and_restores_undo_stack() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let second_id = insert_file(repo.path(), "docs/plan.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![first_id, second_id],
        vec!["Urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token is created");
    undo_action(path_string(repo.path()), token.clone()).expect("execute undo");
    assert_eq!(tag_rows(repo.path()), Vec::<(i64, String)>::new());

    let result = redo_action(path_string(repo.path()), token.clone()).expect("execute redo");

    assert_eq!(result.action_id, token);
    assert_eq!(result.status, RedoActionStatus::Executed);
    assert_eq!(result.affected_count, 2);
    assert_eq!(
        result.refresh_targets,
        vec![
            "files",
            "tags",
            "undo_actions",
            "redo_actions",
            "change_log"
        ]
    );
    assert_eq!(result.undo_token.as_deref(), Some(result.action_id.as_str()));
    assert_eq!(
        tag_rows(repo.path()),
        vec![(first_id, "urgent".to_owned()), (second_id, "urgent".to_owned())]
    );
    assert_eq!(undo_status(repo.path(), result.action_id.as_str()), "pending");
    assert_eq!(list_redo_actions(path_string(repo.path())).expect("list redo actions"), vec![]);

    let undo_actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
    assert_eq!(undo_actions[0].status, UndoActionStatus::Pending);
    assert!(change_log_kinds(repo.path())
        .iter()
        .any(|kind| kind == "redo_batch_tag_added"));
}

#[test]
fn redo_action_log_implementation_clears_stack_after_new_write() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/spec.pdf", "docs");
    let second_id = insert_file(repo.path(), "docs/plan.pdf", "docs");
    let report = batch_add_tags(
        path_string(repo.path()),
        vec![first_id],
        vec!["Urgent".to_owned()],
    )
    .expect("batch add tags");
    let token = report.undo_token.expect("undo token is created");
    undo_action(path_string(repo.path()), token.clone()).expect("execute undo");

    batch_add_tags(
        path_string(repo.path()),
        vec![second_id],
        vec!["Later".to_owned()],
    )
    .expect("new write clears redo stack");

    let actions = list_redo_actions(path_string(repo.path())).expect("list redo actions");
    let cleared = actions
        .iter()
        .find(|action| action.action_id == token)
        .expect("cleared redo action remains visible with reason");
    assert_eq!(cleared.status, RedoActionStatus::Cleared);
    assert!(!cleared.can_redo);
    assert_eq!(
        cleared.disabled_reason.as_deref(),
        Some("Redo action was cleared by a new write")
    );
    assert!(matches!(
        redo_action(path_string(repo.path()), token),
        Err(CoreError::ExpiredAction { .. })
    ));
}
