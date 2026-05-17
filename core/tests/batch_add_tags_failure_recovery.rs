use std::{fs, path::Path};

use area_matrix_core::{
    batch_add_tags, init_repo, BatchMutationStatus, CoreError, ErrorKind, ErrorRecoverability,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct BatchTagSnapshot {
    files: Vec<(i64, String, String)>,
    tags: Vec<(i64, String)>,
    change_logs: Vec<(i64, String, String)>,
    undo_actions: Vec<(String, String, String)>,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
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

fn insert_file(repo: &Path, relative_path: &str, status: &str) -> i64 {
    let file_path = repo.join(relative_path);
    if status == "active" {
        fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
            .expect("create fixture directory");
        fs::write(&file_path, format!("fixture bytes for {relative_path}"))
            .expect("write fixture file");
    }

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
                ?1, ?2, ?2, 'docs', 13,
                ?3, 'copied', 'imported', NULL,
                100, 100, ?4
             )",
            params![
                relative_path,
                current_name,
                format!("{:064x}", relative_path.len()),
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn insert_tag(repo: &Path, file_id: i64, tag: &str, added_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, ?3)",
            params![file_id, tag, added_at],
        )
        .expect("insert tag row");
}

fn snapshot(repo: &Path) -> BatchTagSnapshot {
    BatchTagSnapshot {
        files: file_rows(repo),
        tags: tag_rows(repo),
        change_logs: change_log_rows(repo),
        undo_actions: undo_action_rows(repo),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
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

fn change_log_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(file_id, 0), action, detail_json
               FROM change_log
              ORDER BY id",
        )
        .expect("prepare change-log rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query change-log rows")
        .map(|row| row.expect("read change-log row"))
        .collect()
}

fn undo_action_rows(repo: &Path) -> Vec<(String, String, String)> {
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

fn relative_directory_entries(repo: &Path, root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    if root.exists() {
        collect_relative_paths(repo, root, &mut entries);
    }
    entries.sort();
    entries
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_relative_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let entry = entry.expect("read directory entry");
        let path = entry.path();
        paths.push(relative_path(repo, &path));
        if path.is_dir() {
            collect_relative_paths(repo, &path, paths);
        }
    }
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = relative_path(repo, &path);
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn relative_path(repo: &Path, path: &Path) -> String {
    path.strip_prefix(repo)
        .expect("path is inside repository")
        .to_string_lossy()
        .into_owned()
}

fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) -> CoreError {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    error
}

fn assert_file_not_found<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with FileNotFound");
    assert!(matches!(error, CoreError::FileNotFound { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::FileNotFound);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::RefreshRequired
    );
}

#[test]
fn batch_add_tags_failure_recovery_empty_and_invalid_inputs_do_not_mutate() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/tagged.pdf", "active");
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());

    assert_db_error(batch_add_tags(
        String::new(),
        vec![file_id],
        vec!["urgent".to_owned()],
    ));
    assert_db_error(batch_add_tags(
        path_string(&repo.path().join(".areamatrix")),
        vec![file_id],
        vec!["urgent".to_owned()],
    ));
    assert_file_not_found(batch_add_tags(
        path_string(repo.path()),
        Vec::new(),
        vec!["urgent".to_owned()],
    ));
    assert_file_not_found(batch_add_tags(
        path_string(repo.path()),
        vec![0],
        vec!["urgent".to_owned()],
    ));
    assert_db_error(batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        Vec::new(),
    ));
    assert_db_error(batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["bad/tag".to_owned()],
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn batch_add_tags_failure_recovery_missing_and_deleted_targets_are_reported_per_item() {
    let repo = initialized_repo();
    let active_id = insert_file(repo.path(), "docs/active.pdf", "active");
    let deleted_id = insert_file(repo.path(), "docs/deleted.pdf", "deleted");
    insert_tag(repo.path(), active_id, "baseline", 100);
    let before_paths = user_visible_paths(repo.path());

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![active_id, deleted_id, 404],
        vec!["urgent".to_owned()],
    )
    .expect("partial missing target returns report");

    assert_eq!(report.added_count, 1);
    assert_eq!(report.skipped_count, 0);
    assert_eq!(report.failed_count, 2);
    assert_eq!(
        report
            .item_results
            .iter()
            .map(|item| (item.file_id, item.status.clone()))
            .collect::<Vec<_>>(),
        vec![
            (active_id, BatchMutationStatus::Added),
            (deleted_id, BatchMutationStatus::Failed),
            (404, BatchMutationStatus::Failed),
        ]
    );
    for item in report
        .item_results
        .iter()
        .filter(|item| matches!(item.status, BatchMutationStatus::Failed))
    {
        assert!(item
            .error
            .as_deref()
            .expect("failed item has error")
            .contains("FileNotFound"));
    }
    assert_eq!(
        tag_rows(repo.path()),
        vec![
            (active_id, "baseline".to_owned()),
            (active_id, "urgent".to_owned()),
        ]
    );
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn batch_add_tags_failure_recovery_item_db_failure_rolls_back_item_only() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/first.pdf", "active");
    let second_id = insert_file(repo.path(), "docs/second.pdf", "active");
    install_batch_change_log_failure(repo.path(), Some(second_id));
    let before_paths = user_visible_paths(repo.path());

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![first_id, second_id],
        vec!["urgent".to_owned()],
    )
    .expect("item DB failure returns report");

    assert_eq!(report.added_count, 1);
    assert_eq!(report.failed_count, 1);
    assert_eq!(report.item_results[0].status, BatchMutationStatus::Added);
    assert_eq!(report.item_results[1].status, BatchMutationStatus::Failed);
    assert!(report.item_results[1]
        .error
        .as_deref()
        .expect("failed item has db error")
        .contains("Db"));
    assert_eq!(tag_rows(repo.path()), vec![(first_id, "urgent".to_owned())]);
    assert_eq!(change_log_rows(repo.path()).len(), 1);
    assert_eq!(undo_action_rows(repo.path()).len(), 1);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn batch_add_tags_failure_recovery_undo_failure_rolls_back_entire_batch() {
    let repo = initialized_repo();
    let first_id = insert_file(repo.path(), "docs/first.pdf", "active");
    let second_id = insert_file(repo.path(), "docs/second.pdf", "active");
    let before = snapshot(repo.path());
    install_undo_failure(repo.path());

    assert_db_error(batch_add_tags(
        path_string(repo.path()),
        vec![first_id, second_id],
        vec!["urgent".to_owned()],
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn batch_add_tags_failure_recovery_missing_metadata_tables_return_db_without_partial_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/source.pdf", "active");
    let before_paths = user_visible_paths(repo.path());
    open_db(repo.path())
        .execute_batch("DROP TABLE undo_actions;")
        .expect("drop undo table to simulate metadata corruption");

    let error = assert_db_error(batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["urgent".to_owned()],
    ));

    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(tag_rows(repo.path()), Vec::<(i64, String)>::new());
    assert_eq!(
        change_log_rows(repo.path()),
        Vec::<(i64, String, String)>::new()
    );
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[cfg(unix)]
#[test]
fn batch_add_tags_failure_recovery_permission_denied_is_db_error_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/locked.pdf", "active");
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());
    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read database permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&db_path, denied_permissions).expect("remove database permissions");

    if fs::File::open(&db_path).is_ok() {
        fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");
        return;
    }

    let result = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["blocked".to_owned()],
    );

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_db_error(result);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn batch_add_tags_failure_recovery_preserves_user_files_and_avoids_remote_ai_state() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/local.pdf", "active");
    let before_paths = user_visible_paths(repo.path());
    let before_staging =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"));
    let before_generated =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated"));

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![file_id],
        vec!["local".to_owned()],
    )
    .expect("add local batch tag");

    assert_eq!(report.added_count, 1);
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_eq!(
        fs::read(repo.path().join("docs/local.pdf")).expect("read user file"),
        b"fixture bytes for docs/local.pdf"
    );
    assert_eq!(user_visible_paths(repo.path()), before_paths);
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        before_staging
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        before_generated
    );
}

fn install_batch_change_log_failure(repo: &Path, file_id: Option<i64>) {
    let condition = match file_id {
        Some(id) => format!("AND NEW.file_id = {id}"),
        None => String::new(),
    };
    let sql = format!(
        "CREATE TRIGGER fail_batch_tag_change_log
         BEFORE INSERT ON change_log
         WHEN NEW.action = 'external_modified'
          AND json_extract(NEW.detail_json, '$.kind') = 'batch_tag_added'
          {condition}
         BEGIN
           SELECT RAISE(ABORT, 'forced batch tag change_log failure');
         END;"
    );
    open_db(repo)
        .execute_batch(&sql)
        .expect("install batch tag change-log failure trigger");
}

fn install_undo_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_batch_tag_undo
             BEFORE INSERT ON undo_actions
             WHEN NEW.kind = 'batch_add_tags'
             BEGIN
               SELECT RAISE(ABORT, 'forced undo action failure');
             END;",
        )
        .expect("install undo action failure trigger");
}
