use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    create_saved_search, delete_saved_search, init_repo, list_saved_searches, update_saved_search,
    CoreError, CreateSavedSearchRequest, ErrorKind, ErrorRecoverability, ErrorSeverity,
    OverviewOutput, RepoInitMode, RepoInitOptions, SavedSearchQuery, SearchFilter, SearchScope,
    SearchSort, SearchTagMatchMode, StorageMode, UpdateSavedSearchRequest,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

#[derive(Debug, Eq, PartialEq)]
struct SavedSearchSafetySnapshot {
    saved_searches: Vec<(i64, String, String)>,
    files: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    staging_entries: Vec<PathBuf>,
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

fn saved_search_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM saved_searches", [], |row| row.get(0))
        .expect("count saved searches")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active files")
}

fn saved_search_snapshot(repo: &Path) -> SavedSearchSafetySnapshot {
    SavedSearchSafetySnapshot {
        saved_searches: saved_search_rows(repo),
        files: file_rows(repo),
        change_log_count: change_log_count(repo),
        staging_entries: directory_entries(&repo.join(".areamatrix/staging")),
    }
}

fn saved_search_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, name, query_json FROM saved_searches ORDER BY id")
        .expect("prepare saved search rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
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

fn directory_entries(path: &Path) -> Vec<PathBuf> {
    if !path.exists() {
        return Vec::new();
    }
    let mut entries: Vec<PathBuf> = fs::read_dir(path)
        .expect("read directory")
        .map(|entry| entry.expect("read directory entry").path())
        .collect();
    entries.sort();
    entries
}

fn assert_config_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Config");
    assert!(matches!(error, CoreError::Config { .. }));
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, ErrorKind::Config);
    assert_eq!(mapping.severity, ErrorSeverity::Medium);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
}

fn assert_create_config_error(repo: &Path, request: CreateSavedSearchRequest) {
    assert_config_error(create_saved_search(path_string(repo), request));
}

fn insert_active_file(repo: &Path) -> i64 {
    let file_path = repo.join("finance/invoice.pdf");
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, b"fixture bytes").expect("write fixture file");

    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                'finance/invoice.pdf', 'invoice.pdf', 'invoice.pdf', 'finance', 13,
                ?1, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![format!("{:064x}", 1)],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

#[test]
fn saved_search_implementation_empty_repo_lists_empty_without_writes() {
    let repo = initialized_repo();
    let before = saved_search_snapshot(repo.path());

    let listed = list_saved_searches(path_string(repo.path())).expect("list saved searches");

    assert!(listed.is_empty());
    assert_eq!(saved_search_snapshot(repo.path()), before);
}

#[test]
fn saved_search_implementation_persists_and_restores_full_query_state() {
    let repo = initialized_repo();

    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");

    assert!(saved.id > 0);
    assert_eq!(saved.name, "Finance PDFs");
    assert_eq!(saved.query, saved_query());
    assert_eq!(saved.icon.as_deref(), Some("magnifyingglass"));
    assert_eq!(saved.color.as_deref(), Some("blue"));
    assert!(!saved.pinned);
    assert!(saved.created_at > 0);
    assert!(saved.updated_at >= saved.created_at);

    let listed = list_saved_searches(path_string(repo.path())).expect("list saved searches");
    assert_eq!(listed, vec![saved]);
    assert_eq!(saved_search_count(repo.path()), 1);
    assert_eq!(change_log_count(repo.path()), 0);
}

#[test]
fn saved_search_implementation_updates_deletes_and_never_touches_files() {
    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path());
    let first = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create first saved search");
    let second = create_saved_search(path_string(repo.path()), create_request("Invoices"))
        .expect("create second");

    let mut updated_query = saved_query();
    updated_query.query = "receipt".to_owned();
    updated_query.sort = SearchSort::NameAsc;
    let updated = update_saved_search(
        path_string(repo.path()),
        UpdateSavedSearchRequest {
            id: second.id,
            name: "Pinned Receipts".to_owned(),
            query: updated_query.clone(),
            icon: None,
            color: Some("green".to_owned()),
            pinned: true,
        },
    )
    .expect("update saved search");

    assert_eq!(updated.id, second.id);
    assert_eq!(updated.name, "Pinned Receipts");
    assert_eq!(updated.query, updated_query);
    assert!(updated.pinned);
    assert_eq!(updated.created_at, second.created_at);
    assert!(updated.updated_at >= second.updated_at);

    let listed = list_saved_searches(path_string(repo.path())).expect("list saved searches");
    assert_eq!(
        listed.iter().map(|item| item.id).collect::<Vec<_>>(),
        vec![second.id, first.id]
    );

    delete_saved_search(path_string(repo.path()), updated.id).expect("delete saved search");
    let remaining =
        list_saved_searches(path_string(repo.path())).expect("list remaining saved searches");
    assert_eq!(
        remaining.iter().map(|item| item.id).collect::<Vec<_>>(),
        vec![first.id]
    );
    assert_eq!(saved_search_count(repo.path()), 1);
    assert_eq!(active_file_count(repo.path()), 1);
    assert!(repo.path().join("finance/invoice.pdf").is_file());
    assert_eq!(change_log_count(repo.path()), 0);

    let file_still_active: i64 = open_db(repo.path())
        .query_row(
            "SELECT COUNT(*) FROM files WHERE id = ?1 AND status = 'active'",
            [file_id],
            |row| row.get(0),
        )
        .expect("count active fixture file");
    assert_eq!(file_still_active, 1);
}

#[test]
fn saved_search_implementation_rejects_duplicate_names_invalid_query_and_missing_rows() {
    let repo = initialized_repo();
    create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");

    assert_create_config_error(repo.path(), create_request("finance pdfs"));

    let mut invalid_query = create_request("Bad query");
    invalid_query.query.query = "kindd:pdf".to_owned();
    assert_create_config_error(repo.path(), invalid_query);

    let mut invalid_scope = create_request("Bad scope");
    invalid_scope.query.filter.scope = SearchScope::CurrentNode;
    invalid_scope.query.filter.current_path = None;
    assert_create_config_error(repo.path(), invalid_scope);

    assert_create_config_error(repo.path(), create_request(" "));
    let mut invalid_name = create_request("Too long");
    invalid_name.name = "a".repeat(65);
    assert_create_config_error(repo.path(), invalid_name);

    let mut invalid_icon = create_request("Invalid icon");
    invalid_icon.icon = Some(" ".to_owned());
    assert_create_config_error(repo.path(), invalid_icon);

    let mut invalid_color = create_request("Invalid color");
    invalid_color.color = Some("a".repeat(65));
    assert_create_config_error(repo.path(), invalid_color);

    let missing_update = update_saved_search(
        path_string(repo.path()),
        UpdateSavedSearchRequest {
            id: 404,
            name: "Missing".to_owned(),
            query: saved_query(),
            icon: None,
            color: None,
            pinned: false,
        },
    );
    assert_db_error(missing_update);

    let missing_delete = delete_saved_search(path_string(repo.path()), 404);
    assert_db_error(missing_delete);
    assert_config_error(delete_saved_search(path_string(repo.path()), 0));
    assert_config_error(list_saved_searches(String::new()));
    assert_eq!(saved_search_count(repo.path()), 1);
}

#[test]
fn saved_search_implementation_write_failures_do_not_leave_partial_records() {
    let repo = initialized_repo();
    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");
    let before = saved_search_snapshot(repo.path());

    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER saved_searches_abort_insert
               BEFORE INSERT ON saved_searches
               BEGIN
                 SELECT RAISE(ABORT, 'forced saved_search insert failure');
               END;
             CREATE TRIGGER saved_searches_abort_update
               BEFORE UPDATE ON saved_searches
               BEGIN
                 SELECT RAISE(ABORT, 'forced saved_search update failure');
               END;
             CREATE TRIGGER saved_searches_abort_delete
               BEFORE DELETE ON saved_searches
               BEGIN
                 SELECT RAISE(ABORT, 'forced saved_search delete failure');
               END;",
        )
        .expect("install saved search failure triggers");

    assert_db_error(create_saved_search(
        path_string(repo.path()),
        create_request("Blocked insert"),
    ));
    assert_db_error(update_saved_search(
        path_string(repo.path()),
        UpdateSavedSearchRequest {
            id: saved.id,
            name: "Blocked update".to_owned(),
            query: saved_query(),
            icon: Some("folder".to_owned()),
            color: Some("green".to_owned()),
            pinned: true,
        },
    ));
    assert_db_error(delete_saved_search(path_string(repo.path()), saved.id));

    assert_eq!(saved_search_snapshot(repo.path()), before);
}

#[test]
fn saved_search_implementation_db_corruption_preserves_user_files_and_staging() {
    let repo = tempfile::tempdir().expect("create corrupted repository directory");
    let user_file = repo.path().join("finance/invoice.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create user dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");
    let metadata = repo.path().join(".areamatrix");
    fs::create_dir(&metadata).expect("create metadata directory");
    fs::create_dir(metadata.join("staging")).expect("create staging directory");
    fs::create_dir(metadata.join("generated")).expect("create generated directory");
    fs::write(metadata.join("index.db"), b"not a sqlite database")
        .expect("write corrupted database fixture");

    assert_db_error(create_saved_search(
        path_string(repo.path()),
        create_request("Finance PDFs"),
    ));
    assert_db_error(list_saved_searches(path_string(repo.path())));

    assert_eq!(
        fs::read(&user_file).expect("read user file after failure"),
        b"user file bytes"
    );
    assert!(directory_entries(&metadata.join("staging")).is_empty());
    assert!(directory_entries(&metadata.join("generated")).is_empty());
}

#[cfg(unix)]
#[test]
fn saved_search_implementation_db_permission_error_is_structured_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");
    let before = saved_search_snapshot(repo.path());
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

    let result = list_saved_searches(path_string(repo.path()));

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_db_error(result);
    assert_eq!(saved_search_snapshot(repo.path()), before);
}

#[test]
fn saved_search_implementation_sorts_pinned_first_then_unpinned_by_name() {
    let repo = initialized_repo();
    let mut b = create_request("Bravo");
    b.pinned = false;
    let b = create_saved_search(path_string(repo.path()), b).expect("create bravo");

    let mut a = create_request("Alpha");
    a.pinned = false;
    let a = create_saved_search(path_string(repo.path()), a).expect("create alpha");

    let mut pinned = create_request("Pinned");
    pinned.pinned = true;
    let pinned = create_saved_search(path_string(repo.path()), pinned).expect("create pinned");

    let listed = list_saved_searches(path_string(repo.path())).expect("list saved searches");
    assert_eq!(
        listed.iter().map(|item| item.id).collect::<Vec<_>>(),
        vec![pinned.id, a.id, b.id]
    );
}

#[test]
fn saved_search_implementation_has_no_ai_remote_or_secret_side_effects() {
    let repo = initialized_repo();
    let before = saved_search_snapshot(repo.path());

    let saved = create_saved_search(path_string(repo.path()), create_request("Finance PDFs"))
        .expect("create saved search");
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
    assert_eq!(saved_search_snapshot(repo.path()).files, before.files);
    assert_eq!(
        saved_search_snapshot(repo.path()).change_log_count,
        before.change_log_count
    );
    assert_eq!(
        saved_search_snapshot(repo.path()).staging_entries,
        before.staging_entries
    );
    assert_eq!(
        list_saved_searches(path_string(repo.path()))
            .expect("list saved searches")
            .iter()
            .map(|item| item.id)
            .collect::<Vec<_>>(),
        vec![saved.id]
    );
}
