use std::{fs, path::Path};

use area_matrix_core::{
    add_tag, init_repo, list_tags, remove_tag, CoreError, ErrorKind, ErrorRecoverability,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct TagFailureSnapshot {
    files: Vec<(i64, String, String, String)>,
    tags: Vec<(i64, String, i64)>,
    change_logs: Vec<(i64, String, String)>,
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

fn snapshot(repo: &Path) -> TagFailureSnapshot {
    TagFailureSnapshot {
        files: file_rows(repo),
        tags: tag_rows(repo),
        change_logs: change_log_rows(repo),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn tag_rows(repo: &Path) -> Vec<(i64, String, i64)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, tag, added_at FROM tags ORDER BY file_id, tag")
        .expect("prepare tag rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
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

fn assert_invalid_path<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with InvalidPath");
    assert!(matches!(error, CoreError::InvalidPath { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::InvalidPath);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
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
fn tag_crud_failure_recovery_empty_repo_lists_empty_without_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/empty.pdf", "active");
    let before = snapshot(repo.path());

    let tags = list_tags(path_string(repo.path()), file_id).expect("list empty tag set");

    assert!(tags.file_tags.is_empty());
    assert!(tags.available_tags.is_empty());
    assert!(tags.recent_tags.is_empty());
    assert_eq!(tags.updated_at, 0);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_crud_failure_recovery_invalid_inputs_are_structured_and_non_mutating() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/tagged.pdf", "active");
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());

    assert_invalid_path(add_tag(String::new(), file_id, "new".to_owned()));
    assert_invalid_path(add_tag(
        path_string(&repo.path().join(".areamatrix")),
        file_id,
        "new".to_owned(),
    ));
    assert_invalid_path(add_tag(path_string(repo.path()), file_id, " ".to_owned()));
    assert_invalid_path(add_tag(
        path_string(repo.path()),
        file_id,
        "bad/tag".to_owned(),
    ));
    assert_invalid_path(remove_tag(
        path_string(repo.path()),
        file_id,
        "bad:tag".to_owned(),
    ));
    assert_file_not_found(add_tag(path_string(repo.path()), 0, "new".to_owned()));
    assert_file_not_found(list_tags(path_string(repo.path()), -1));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_crud_failure_recovery_missing_or_deleted_file_returns_refreshable_error() {
    let repo = initialized_repo();
    let deleted_id = insert_file(repo.path(), "docs/deleted.pdf", "deleted");
    let before = snapshot(repo.path());

    assert_file_not_found(add_tag(
        path_string(repo.path()),
        deleted_id,
        "urgent".to_owned(),
    ));
    assert_file_not_found(remove_tag(
        path_string(repo.path()),
        404,
        "urgent".to_owned(),
    ));
    assert_file_not_found(list_tags(path_string(repo.path()), 404));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_crud_failure_recovery_change_log_failure_rolls_back_added_relation() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/new-tag.pdf", "active");
    let before = snapshot(repo.path());
    install_tag_change_log_failure(repo.path(), "tag_added");

    assert_db_error(add_tag(
        path_string(repo.path()),
        file_id,
        "urgent".to_owned(),
    ));

    assert_eq!(snapshot(repo.path()), before);

    drop_trigger(repo.path(), "fail_tag_added_change_log");
    let tags = add_tag(path_string(repo.path()), file_id, "urgent".to_owned())
        .expect("retry add tag after change-log failure is removed");
    assert_eq!(
        tags.file_tags
            .iter()
            .map(|record| record.value.as_str())
            .collect::<Vec<_>>(),
        vec!["urgent"]
    );
}

#[test]
fn tag_crud_failure_recovery_change_log_failure_rolls_back_removed_relation() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/remove-tag.pdf", "active");
    insert_tag(repo.path(), file_id, "urgent", 100);
    let before = snapshot(repo.path());
    install_tag_change_log_failure(repo.path(), "tag_removed");

    assert_db_error(remove_tag(
        path_string(repo.path()),
        file_id,
        "urgent".to_owned(),
    ));

    assert_eq!(snapshot(repo.path()), before);

    drop_trigger(repo.path(), "fail_tag_removed_change_log");
    let tags = remove_tag(path_string(repo.path()), file_id, "urgent".to_owned())
        .expect("retry remove tag after change-log failure is removed");
    assert!(tags.file_tags.is_empty());
}

#[test]
fn tag_crud_failure_recovery_tag_table_failure_has_no_user_file_or_generated_side_effects() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/source.pdf", "active");
    let user_file = repo.path().join("docs/source.pdf");
    let before_paths = user_visible_paths(repo.path());
    let before_staging =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"));
    let before_generated =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated"));
    open_db(repo.path())
        .execute_batch("DROP TABLE tags;")
        .expect("remove tags table to simulate metadata failure");

    assert_db_error(add_tag(
        path_string(repo.path()),
        file_id,
        "blocked".to_owned(),
    ));
    assert_db_error(list_tags(path_string(repo.path()), file_id));

    assert_eq!(
        fs::read(user_file).expect("read user file"),
        b"fixture bytes for docs/source.pdf"
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

#[test]
fn tag_crud_failure_recovery_uninitialized_repo_is_db_error_without_metadata_creation() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");

    assert_db_error(list_tags(path_string(repo.path()), 1));
    assert_db_error(add_tag(path_string(repo.path()), 1, "urgent".to_owned()));

    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read user readme"),
        b"user readme"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn tag_crud_failure_recovery_corrupted_db_is_fatal_and_preserves_user_files() {
    let repo = tempfile::tempdir().expect("create corrupted repository directory");
    let user_file = repo.path().join("docs/client.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create docs dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");
    let metadata_dir = repo.path().join(".areamatrix");
    fs::create_dir(&metadata_dir).expect("create metadata directory");
    fs::create_dir(metadata_dir.join("staging")).expect("create staging directory");
    fs::create_dir(metadata_dir.join("generated")).expect("create generated directory");
    fs::write(metadata_dir.join("index.db"), b"not a sqlite database")
        .expect("write corrupted database fixture");

    let error = assert_db_error(list_tags(path_string(repo.path()), 1));

    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(
        fs::read(user_file).expect("read user file after corrupted db failure"),
        b"user file bytes"
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        Vec::<String>::new()
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        Vec::<String>::new()
    );
}

#[cfg(unix)]
#[test]
fn tag_crud_failure_recovery_permission_denied_is_structured_and_non_mutating() {
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

    let result = add_tag(path_string(repo.path()), file_id, "blocked".to_owned());

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_db_error(result);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_crud_failure_recovery_does_not_create_ai_remote_or_secret_state() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/local.pdf", "active");
    let before = snapshot(repo.path());

    add_tag(path_string(repo.path()), file_id, "local".to_owned()).expect("add local tag");
    remove_tag(path_string(repo.path()), file_id, "local".to_owned()).expect("remove local tag");
    list_tags(path_string(repo.path()), file_id).expect("list local tags");

    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_eq!(
        user_visible_paths(repo.path()),
        vec!["docs".to_owned(), "docs/local.pdf".to_owned()]
    );
    assert!(snapshot(repo.path()).change_logs.len() > before.change_logs.len());
}

fn install_tag_change_log_failure(repo: &Path, kind: &str) {
    let trigger_name = format!("fail_{kind}_change_log");
    let sql = format!(
        "CREATE TRIGGER {trigger_name}
         BEFORE INSERT ON change_log
         WHEN NEW.action = 'external_modified'
          AND json_extract(NEW.detail_json, '$.kind') = '{kind}'
         BEGIN
           SELECT RAISE(ABORT, 'forced tag change_log failure');
         END;"
    );
    open_db(repo)
        .execute_batch(&sql)
        .expect("install tag change-log failure trigger");
}

fn drop_trigger(repo: &Path, trigger_name: &str) {
    open_db(repo)
        .execute_batch(&format!("DROP TRIGGER {trigger_name};"))
        .expect("drop trigger");
}
