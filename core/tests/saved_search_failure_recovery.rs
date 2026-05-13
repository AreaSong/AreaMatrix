use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    create_saved_search, delete_saved_search, init_repo, list_saved_searches, update_saved_search,
    CoreError, CreateSavedSearchRequest, ErrorKind, ErrorRecoverability, OverviewOutput,
    RepoInitMode, RepoInitOptions, SavedSearchQuery, SearchFilter, SearchScope, SearchSort,
    SearchTagMatchMode, StorageMode, UpdateSavedSearchRequest,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct SavedSearchFailureSnapshot {
    saved_searches: Vec<SavedSearchRow>,
    files: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    staging_entries: Vec<PathBuf>,
    generated_entries: Vec<PathBuf>,
    user_visible_paths: Vec<String>,
}

#[derive(Debug, Eq, PartialEq)]
struct SavedSearchRow {
    id: i64,
    name: String,
    query_json: String,
    icon: Option<String>,
    color: Option<String>,
    pinned: i64,
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

fn saved_query() -> SavedSearchQuery {
    SavedSearchQuery {
        query: "invoice OR receipt".to_owned(),
        filter: SearchFilter {
            scope: SearchScope::CurrentNode,
            current_path: Some("finance/2026".to_owned()),
            category: Some("finance".to_owned()),
            file_kind: Some("pdf".to_owned()),
            tags: vec!["tax".to_owned()],
            tag_match_mode: SearchTagMatchMode::Any,
            imported_after: Some(100),
            imported_before: Some(200),
            modified_after: Some(120),
            modified_before: Some(220),
            storage_mode: Some(StorageMode::Copied),
            include_deleted: Some(false),
        },
        sort: SearchSort::NewestModified,
    }
}

fn create_request(name: &str) -> CreateSavedSearchRequest {
    CreateSavedSearchRequest {
        name: name.to_owned(),
        query: saved_query(),
        icon: Some("magnifyingglass".to_owned()),
        color: Some("blue".to_owned()),
        pinned: false,
    }
}

fn update_request(id: i64, name: &str) -> UpdateSavedSearchRequest {
    UpdateSavedSearchRequest {
        id,
        name: name.to_owned(),
        query: saved_query(),
        icon: Some("folder".to_owned()),
        color: Some("green".to_owned()),
        pinned: true,
    }
}

fn snapshot(repo: &Path) -> SavedSearchFailureSnapshot {
    SavedSearchFailureSnapshot {
        saved_searches: saved_search_rows(repo),
        files: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        staging_entries: directory_entries(&repo.join(".areamatrix/staging")),
        generated_entries: directory_entries(&repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn saved_search_rows(repo: &Path) -> Vec<SavedSearchRow> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, name, query_json, icon, color, pinned FROM saved_searches ORDER BY id")
        .expect("prepare saved search rows query");
    statement
        .query_map([], |row| {
            Ok(SavedSearchRow {
                id: row.get(0)?,
                name: row.get(1)?,
                query_json: row.get(2)?,
                icon: row.get(3)?,
                color: row.get(4)?,
                pinned: row.get(5)?,
            })
        })
        .expect("query saved search rows")
        .map(|row| row.expect("read saved search row"))
        .collect()
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

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count table rows")
}

fn table_exists(repo: &Path, table: &str) -> bool {
    open_db(repo)
        .query_row(
            "SELECT EXISTS(
                SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1
             )",
            [table],
            |row| row.get::<_, i64>(0),
        )
        .expect("query table existence")
        == 1
}

fn directory_entries(path: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = fs::read_dir(path)
        .expect("read directory")
        .map(|entry| entry.expect("read directory entry").path())
        .collect();
    entries.sort();
    entries
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

fn insert_active_file(repo: &Path) {
    let file_path = repo.join("finance/invoice.pdf");
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, b"saved search fixture").expect("write fixture file");

    open_db(repo)
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                'finance/invoice.pdf', 'invoice.pdf', 'invoice.pdf', 'finance', 20,
                ?1, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![format!("{:064x}", 1)],
        )
        .expect("insert active file row");
}

fn assert_config_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Config");
    assert!(matches!(error, CoreError::Config { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Config);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) -> CoreError {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    error
}

#[test]
fn saved_search_failure_recovery_empty_repo_lists_empty_without_side_effects() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let searches =
        list_saved_searches(path_string(repo.path())).expect("list empty saved searches");

    assert!(searches.is_empty());
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_invalid_inputs_are_config_and_non_mutating() {
    let repo = initialized_repo();
    insert_active_file(repo.path());
    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create baseline saved search");
    let before = snapshot(repo.path());

    let mut invalid_query = create_request("Bad query");
    invalid_query.query.query = "kindd:pdf".to_owned();
    assert_config_error(create_saved_search(path_string(repo.path()), invalid_query));

    let mut invalid_filter = create_request("Bad filter");
    invalid_filter.query.filter.imported_after = Some(200);
    invalid_filter.query.filter.imported_before = Some(100);
    assert_config_error(create_saved_search(
        path_string(repo.path()),
        invalid_filter,
    ));

    assert_config_error(update_saved_search(
        path_string(repo.path()),
        update_request(0, "Invalid id"),
    ));
    assert_config_error(delete_saved_search(path_string(repo.path()), -1));
    assert_config_error(list_saved_searches(String::new()));

    let mut empty_icon = update_request(saved.id, "Still Finance");
    empty_icon.icon = Some(" ".to_owned());
    assert_config_error(update_saved_search(path_string(repo.path()), empty_icon));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_duplicate_names_are_structured_and_non_mutating() {
    let repo = initialized_repo();
    let first = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create first saved search");
    let second = create_saved_search(path_string(repo.path()), create_request("Receipts"))
        .expect("create second saved search");
    let before = snapshot(repo.path());

    assert_config_error(create_saved_search(
        path_string(repo.path()),
        create_request("finance pdfs"),
    ));
    assert_db_error(update_saved_search(
        path_string(repo.path()),
        update_request(second.id, &first.name),
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_post_insert_read_failure_rolls_back_partial_row() {
    let repo = initialized_repo();
    insert_active_file(repo.path());
    let before = snapshot(repo.path());
    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER poison_saved_search_after_insert
             AFTER INSERT ON saved_searches
             BEGIN
               UPDATE saved_searches SET query_json = '{' WHERE id = NEW.id;
             END;",
        )
        .expect("install insert poison trigger");

    assert_db_error(create_saved_search(
        path_string(repo.path()),
        create_request("Blocked"),
    ));
    assert_eq!(snapshot(repo.path()), before);

    open_db(repo.path())
        .execute_batch("DROP TRIGGER poison_saved_search_after_insert;")
        .expect("drop insert poison trigger");
    let saved = create_saved_search(path_string(repo.path()), create_request("Recovered"))
        .expect("retry create after trigger is removed");
    assert_eq!(saved.name, "Recovered");
}

#[test]
fn saved_search_failure_recovery_post_update_read_failure_rolls_back_existing_row() {
    let repo = initialized_repo();
    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create baseline saved search");
    let before = snapshot(repo.path());
    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER poison_saved_search_after_update
             AFTER UPDATE ON saved_searches
             WHEN NEW.name = 'Blocked Update'
             BEGIN
               UPDATE saved_searches SET query_json = '{' WHERE id = NEW.id;
             END;",
        )
        .expect("install update poison trigger");

    assert_db_error(update_saved_search(
        path_string(repo.path()),
        update_request(saved.id, "Blocked Update"),
    ));
    assert_eq!(snapshot(repo.path()), before);

    open_db(repo.path())
        .execute_batch("DROP TRIGGER poison_saved_search_after_update;")
        .expect("drop update poison trigger");
    let updated = update_saved_search(
        path_string(repo.path()),
        update_request(saved.id, "Recovered Update"),
    )
    .expect("retry update after trigger is removed");
    assert_eq!(updated.name, "Recovered Update");
}

#[test]
fn saved_search_failure_recovery_malformed_metadata_is_db_error_not_silent_drop() {
    let repo = initialized_repo();
    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");
    open_db(repo.path())
        .execute(
            "UPDATE saved_searches SET query_json = '{' WHERE id = ?1",
            params![saved.id],
        )
        .expect("corrupt saved search query json");
    let before = snapshot(repo.path());

    let error = assert_db_error(list_saved_searches(path_string(repo.path())));

    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_uninitialized_repo_is_db_error_without_metadata_creation() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");

    assert_db_error(list_saved_searches(path_string(repo.path())));
    assert_db_error(create_saved_search(
        path_string(repo.path()),
        create_request("Finance PDFs"),
    ));

    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read user readme"),
        b"user readme"
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn saved_search_failure_recovery_missing_table_is_db_error_without_auto_schema_write() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user readme").expect("write user file");
    open_db(repo.path())
        .execute_batch(
            "DROP INDEX IF EXISTS idx_saved_searches_sidebar;
             DROP TABLE saved_searches;",
        )
        .expect("remove saved_searches table fixture");
    let before_paths = user_visible_paths(repo.path());

    assert_db_error(list_saved_searches(path_string(repo.path())));
    assert_db_error(create_saved_search(
        path_string(repo.path()),
        create_request("Finance PDFs"),
    ));

    assert!(!table_exists(repo.path(), "saved_searches"));
    assert_eq!(user_visible_paths(repo.path()), before_paths);
    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read user readme"),
        b"user readme"
    );
}

#[test]
fn saved_search_failure_recovery_corrupted_db_is_fatal_mapping_and_preserves_files() {
    let repo = tempfile::tempdir().expect("create corrupted repository directory");
    let user_file = repo.path().join("finance/invoice.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create user dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");
    fs::create_dir(repo.path().join(".areamatrix")).expect("create metadata directory");
    fs::write(repo.path().join(".areamatrix/index.db"), b"not sqlite")
        .expect("write corrupted database fixture");

    let error = assert_db_error(list_saved_searches(path_string(repo.path())));

    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(
        fs::read(&user_file).expect("read user file after db failure"),
        b"user file bytes"
    );
}

#[cfg(unix)]
#[test]
fn saved_search_failure_recovery_permission_denied_is_structured_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");
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

    let result = create_saved_search(path_string(repo.path()), create_request("Blocked"));

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_db_error(result);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn saved_search_failure_recovery_failures_do_not_enable_ai_or_remote_state() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());
    let mut invalid_query = create_request("Bad query");
    invalid_query.query.query = "kindd:pdf".to_owned();

    assert_config_error(create_saved_search(path_string(repo.path()), invalid_query));

    let ai_enabled: String = open_db(repo.path())
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'ai_enabled'",
            [],
            |row| row.get(0),
        )
        .expect("read ai_enabled config");
    assert_eq!(ai_enabled, "false");
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_eq!(snapshot(repo.path()), before);
}
