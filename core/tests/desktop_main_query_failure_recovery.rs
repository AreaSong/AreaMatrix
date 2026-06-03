use std::{fs, path::Path};

use area_matrix_core::{
    get_file, init_repo, list_files, list_tree_json, map_core_error, search_files, CoreError,
    ErrorKind, ErrorMappingInput, ErrorRecoverability, FileFilter, OverviewOutput, RepoInitMode,
    RepoInitOptions, SearchFilter, SearchPagination, SearchScope, SearchSort, SearchTagMatchMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, PartialEq)]
struct QuerySnapshot {
    files: Vec<(i64, String, String)>,
    change_count: i64,
    user_paths: Vec<String>,
    staging_paths: Vec<String>,
    generated_paths: Vec<String>,
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
    .expect("initialize desktop query repository");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn default_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 50,
        offset: 0,
    }
}

fn default_search_filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: None,
        file_kind: None,
        tags: Vec::new(),
        tag_match_mode: SearchTagMatchMode::Any,
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: None,
        include_deleted: Some(false),
    }
}

fn first_page() -> SearchPagination {
    SearchPagination {
        limit: 50,
        offset: 0,
    }
}

fn write_repo_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create fixture parent directory");
    }
    fs::write(path, content).expect("write fixture file");
}

fn insert_file(repo: &Path, relative_path: &str, category: &str, imported_at: i64) -> i64 {
    write_repo_file(
        repo,
        relative_path,
        format!("desktop-{imported_at}").as_bytes(),
    );
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture path has filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 1,
                ?4, 'copied', 'imported', NULL,
                ?5, ?5, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{imported_at:064x}"),
                imported_at,
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn query_snapshot(repo: &Path) -> QuerySnapshot {
    QuerySnapshot {
        files: file_rows(repo),
        change_count: count_rows(repo, "change_log"),
        user_paths: visible_paths(repo),
        staging_paths: child_paths(repo, &repo.join(".areamatrix/staging")),
        generated_paths: child_paths(repo, &repo.join(".areamatrix/generated")),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, status FROM files ORDER BY id")
        .expect("prepare file row query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn count_rows(repo: &Path, table: &str) -> i64 {
    open_db(repo)
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .expect("count metadata rows")
}

fn visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read visible directory") {
        let entry = entry.expect("read visible directory entry");
        let path = entry.path();
        let relative = relative_path(repo, &path);
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_visible_paths(repo, &path, paths);
        }
    }
}

fn child_paths(repo: &Path, dir: &Path) -> Vec<String> {
    if !dir.exists() {
        return Vec::new();
    }
    let mut paths = fs::read_dir(dir)
        .expect("read metadata child directory")
        .map(|entry| relative_path(repo, &entry.expect("read metadata child entry").path()))
        .collect::<Vec<_>>();
    paths.sort();
    paths
}

fn relative_path(repo: &Path, path: &Path) -> String {
    path.strip_prefix(repo)
        .expect("path stays under repo")
        .to_string_lossy()
        .into_owned()
}

fn remove_sqlite_sidecars(repo: &Path) {
    for suffix in ["index.db-wal", "index.db-shm"] {
        let path = repo.join(".areamatrix").join(suffix);
        if path.exists() {
            fs::remove_file(path).expect("remove sqlite sidecar");
        }
    }
}

fn assert_error_kind(error: CoreError, kind: ErrorKind) -> CoreError {
    assert_eq!(error.to_error_mapping().kind, kind);
    error
}

fn assert_repo_still_read_only(repo: &Path, before: &QuerySnapshot) {
    assert_eq!(&query_snapshot(repo), before);
}

#[test]
fn desktop_main_query_failure_empty_repo_returns_empty_read_only_state() {
    let repo = initialized_repo();
    let before = query_snapshot(repo.path());

    let files = list_files(path_string(repo.path()), default_file_filter())
        .expect("list empty desktop state");
    let search = search_files(
        path_string(repo.path()),
        "anything".to_owned(),
        default_search_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search empty desktop state");
    let tree =
        list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list empty desktop tree");
    let tree_json: serde_json::Value =
        serde_json::from_str(&tree).expect("parse desktop tree JSON");

    assert!(files.is_empty());
    assert_eq!(search.total_count, 0);
    assert!(search.results.is_empty());
    assert_eq!(tree_json["file_count"], 0);
    assert_repo_still_read_only(repo.path(), &before);
}

#[test]
fn desktop_main_query_failure_invalid_inputs_return_structured_errors_without_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/report.pdf", "docs", 100);
    let before = query_snapshot(repo.path());
    let before_file = fs::read(repo.path().join("docs/report.pdf")).expect("read fixture file");

    let mut invalid_list_filter = default_file_filter();
    invalid_list_filter.imported_after = Some(200);
    invalid_list_filter.imported_before = Some(100);
    let list_error = list_files(path_string(repo.path()), invalid_list_filter)
        .expect_err("reversed list time range must fail");
    let file_error =
        get_file(path_string(repo.path()), 0).expect_err("non-positive file id must fail clearly");
    let mut invalid_search = default_search_filter();
    invalid_search.scope = SearchScope::CurrentNode;
    invalid_search.current_path = Some("../outside".to_owned());
    let search_error = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        invalid_search,
        SearchSort::Relevance,
        first_page(),
    )
    .expect_err("current-node path escaping repo must fail");

    assert_error_kind(list_error, ErrorKind::Db);
    assert_error_kind(file_error, ErrorKind::FileNotFound);
    assert_error_kind(search_error, ErrorKind::InvalidPath);
    assert_repo_still_read_only(repo.path(), &before);
    assert_eq!(
        fs::read(repo.path().join("docs/report.pdf")).expect("read fixture after failures"),
        before_file
    );
    assert!(get_file(path_string(repo.path()), file_id).is_ok());
}

#[test]
fn desktop_main_query_failure_uninitialized_repo_creates_no_metadata_or_user_file_changes() {
    let repo = tempfile::tempdir().expect("create uninitialized desktop repository");
    write_repo_file(repo.path(), "README.md", b"user readme");
    let before_readme = fs::read(repo.path().join("README.md")).expect("read README before");

    let errors = [
        list_files(path_string(repo.path()), default_file_filter())
            .expect_err("list_files requires initialized metadata"),
        get_file(path_string(repo.path()), 1).expect_err("get_file requires initialized metadata"),
        list_tree_json(path_string(repo.path()), "en".to_owned())
            .expect_err("list_tree_json requires initialized metadata"),
    ];
    let search_error = search_files(
        path_string(repo.path()),
        "readme".to_owned(),
        default_search_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect_err("search must not silently scan uninitialized repo");

    for error in errors {
        let mapping = error.to_error_mapping();
        assert_eq!(mapping.kind, ErrorKind::RepoNotInitialized);
        assert_eq!(
            mapping.recoverability,
            ErrorRecoverability::UserActionRequired
        );
    }
    assert_eq!(search_error.to_error_mapping().kind, ErrorKind::Db);
    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read README after query failures"),
        before_readme
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn desktop_main_query_failure_db_corruption_is_explicit_and_leaves_no_half_products() {
    let repo = initialized_repo();
    insert_file(repo.path(), "docs/corrupt-edge.pdf", "docs", 100);
    let before_user_paths = visible_paths(repo.path());
    let before_file =
        fs::read(repo.path().join("docs/corrupt-edge.pdf")).expect("read user file before");
    let metadata_dir = repo.path().join(".areamatrix");

    fs::write(metadata_dir.join("index.db"), b"not a sqlite database")
        .expect("corrupt repository database fixture");
    remove_sqlite_sidecars(repo.path());

    let list_error = list_files(path_string(repo.path()), default_file_filter())
        .expect_err("list_files must report DB corruption");
    let search_error = search_files(
        path_string(repo.path()),
        "corrupt".to_owned(),
        default_search_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect_err("search_files must report DB corruption");
    let tree_error = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect_err("tree must report DB corruption");

    for error in [list_error, search_error, tree_error] {
        let mapping = error.to_error_mapping();
        assert_eq!(mapping.kind, ErrorKind::Db);
        assert_eq!(mapping.recoverability, ErrorRecoverability::Fatal);
    }
    assert_eq!(visible_paths(repo.path()), before_user_paths);
    assert_eq!(
        fs::read(repo.path().join("docs/corrupt-edge.pdf")).expect("read user file after"),
        before_file
    );
    assert!(child_paths(repo.path(), &metadata_dir.join("staging")).is_empty());
}

#[test]
fn desktop_main_query_failure_tree_io_error_is_explicit_and_non_mutating() {
    let repo = initialized_repo();
    insert_file(repo.path(), "docs/io-edge.pdf", "docs", 100);
    let before = query_snapshot(repo.path());
    let classifier_path = repo.path().join(".areamatrix/classifier.yaml");
    if classifier_path.exists() {
        fs::remove_file(&classifier_path).expect("remove classifier file");
    }
    fs::create_dir(&classifier_path).expect("replace classifier with directory fixture");

    let error = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect_err("tree classifier read failure must surface");
    let mapping = error.to_error_mapping();

    assert_eq!(mapping.kind, ErrorKind::Io);
    assert_eq!(mapping.recoverability, ErrorRecoverability::Retryable);
    fs::remove_dir(&classifier_path).expect("remove classifier directory fixture");
    assert_repo_still_read_only(repo.path(), &before);
}

#[test]
fn desktop_main_query_failure_error_mapping_keeps_ui_actions_structured() {
    let cases = [
        (
            ErrorMappingInput {
                kind: ErrorKind::RepoNotInitialized,
                path: Some("/repo".to_owned()),
                reason: None,
                message: None,
            },
            ErrorKind::RepoNotInitialized,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Db,
                path: None,
                reason: None,
                message: Some("database is locked".to_owned()),
            },
            ErrorKind::Db,
            ErrorRecoverability::Retryable,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Db,
                path: None,
                reason: None,
                message: Some("file is not a database".to_owned()),
            },
            ErrorKind::Db,
            ErrorRecoverability::Fatal,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::PermissionDenied,
                path: Some("/repo/.areamatrix/index.db".to_owned()),
                reason: None,
                message: None,
            },
            ErrorKind::PermissionDenied,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Io,
                path: None,
                reason: None,
                message: Some("io edge".to_owned()),
            },
            ErrorKind::Io,
            ErrorRecoverability::Retryable,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Validation,
                path: None,
                reason: Some("pagination".to_owned()),
                message: None,
            },
            ErrorKind::Validation,
            ErrorRecoverability::UserActionRequired,
        ),
    ];

    for (input, expected_kind, expected_recoverability) in cases {
        let mapping = map_core_error(input);
        assert_eq!(mapping.kind, expected_kind);
        assert_eq!(mapping.recoverability, expected_recoverability);
        assert!(!mapping.user_message.is_empty());
        assert!(!mapping.suggested_action.is_empty());
        assert!(!mapping.raw_context.is_empty());
    }
}

#[test]
fn desktop_main_query_failure_has_no_remote_ai_or_secret_side_effects() {
    let repo = initialized_repo();
    insert_file(repo.path(), "docs/local-only.txt", "docs", 100);
    let before = query_snapshot(repo.path());

    let page = search_files(
        path_string(repo.path()),
        "local".to_owned(),
        default_search_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("desktop query stays local");

    assert_eq!(page.total_count, 1);
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_repo_still_read_only(repo.path(), &before);
}
