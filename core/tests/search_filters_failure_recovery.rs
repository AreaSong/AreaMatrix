use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_filter_facets, CoreError, ErrorKind, OverviewOutput, RepoInitMode,
    RepoInitOptions, SearchFacetQuery, SearchScope, SearchTagMatchMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

#[derive(Debug, Eq, PartialEq)]
struct RepoSnapshot {
    files: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    tag_count: i64,
    staging_count: usize,
    user_visible_paths: Vec<String>,
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
    .expect("initialize repository");
    repo
}

fn default_query() -> SearchFacetQuery {
    SearchFacetQuery {
        query: String::new(),
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create parent directory");
    fs::write(&file_path, b"search filter fixture").expect("write file fixture");

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
                ?1, ?2, ?2, ?3, 21,
                ?4, 'copied', 'imported', NULL,
                100, 120, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 100)",
            params![file_id, tag],
        )
        .expect("insert tag row");
}

fn snapshot(repo: &Path) -> RepoSnapshot {
    RepoSnapshot {
        files: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        tag_count: table_count(repo, "tags"),
        staging_count: directory_entry_count(&repo.join(".areamatrix/staging")),
        user_visible_paths: user_visible_paths(repo),
        generated_paths: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count metadata rows")
}

fn directory_entry_count(path: &Path) -> usize {
    fs::read_dir(path).map_or(0, Iterator::count)
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

fn collect_relative_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let entry = entry.expect("read directory entry");
        let path = entry.path();
        paths.push(
            path.strip_prefix(repo)
                .expect("path is inside repository")
                .to_string_lossy()
                .into_owned(),
        );
        if path.is_dir() {
            collect_relative_paths(repo, &path, paths);
        }
    }
}

fn assert_config_error(result: Result<area_matrix_core::SearchFacets, CoreError>) {
    let error = result.expect_err("facet query should fail with Config");
    assert!(matches!(error, CoreError::Config { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Config);
}

fn assert_db_error(result: Result<area_matrix_core::SearchFacets, CoreError>) {
    let error = result.expect_err("facet query should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
}

#[test]
fn search_filters_failure_recovery_empty_repo_returns_empty_facets_without_writes() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    let facets =
        list_filter_facets(path_string(repo.path()), default_query()).expect("load empty facets");

    assert_eq!(facets.query, "");
    assert_eq!(facets.total_count, 0);
    assert!(facets.categories.is_empty());
    assert!(facets.file_kinds.is_empty());
    assert!(facets.tags.is_empty());
    assert_eq!(facets.storage_modes.len(), 3);
    assert!(facets.storage_modes.iter().all(|facet| facet.count == 0));
    assert!(facets.date_bounds.oldest_imported_at.is_none());
    assert_eq!(facets.active_filter_count, 0);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn search_filters_failure_recovery_invalid_inputs_map_to_config_without_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/client.pdf", "docs");
    insert_tag(repo.path(), file_id, "finance");
    let before = snapshot(repo.path());

    let mut empty_category = default_query();
    empty_category.category = Some("  ".to_owned());
    assert_config_error(list_filter_facets(path_string(repo.path()), empty_category));

    let mut invalid_kind = default_query();
    invalid_kind.file_kind = Some(".pdf".to_owned());
    assert_config_error(list_filter_facets(path_string(repo.path()), invalid_kind));

    let mut empty_tag = default_query();
    empty_tag.tags = vec!["finance".to_owned(), " ".to_owned()];
    assert_config_error(list_filter_facets(path_string(repo.path()), empty_tag));

    let mut reversed_date = default_query();
    reversed_date.imported_after = Some(200);
    reversed_date.imported_before = Some(100);
    assert_config_error(list_filter_facets(path_string(repo.path()), reversed_date));

    let mut invalid_scope = default_query();
    invalid_scope.scope = SearchScope::CurrentNode;
    invalid_scope.current_path = Some("../outside".to_owned());
    assert_config_error(list_filter_facets(path_string(repo.path()), invalid_scope));

    let mut invalid_query = default_query();
    invalid_query.query = "after:2026-13-01".to_owned();
    assert_config_error(list_filter_facets(path_string(repo.path()), invalid_query));

    assert_config_error(list_filter_facets(String::new(), default_query()));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn search_filters_failure_recovery_db_error_preserves_user_files_and_no_staging() {
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

    assert_db_error(list_filter_facets(
        path_string(repo.path()),
        default_query(),
    ));
    assert_eq!(
        fs::read(&user_file).expect("read user file"),
        b"user file bytes"
    );
    assert_eq!(
        directory_entry_count(&repo.path().join(".areamatrix/staging")),
        0
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        Vec::<String>::new()
    );
}

#[cfg(unix)]
#[test]
fn search_filters_failure_recovery_db_permission_denied_maps_to_db_without_writes() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    insert_file(repo.path(), "docs/locked.pdf", "docs");
    let before = snapshot(repo.path());
    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read db permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&db_path, denied_permissions).expect("remove db read permissions");

    if fs::File::open(&db_path).is_ok() {
        fs::set_permissions(&db_path, original_permissions).expect("restore db permissions");
        return;
    }

    let result = list_filter_facets(path_string(repo.path()), default_query());

    fs::set_permissions(&db_path, original_permissions).expect("restore db permissions");

    assert_db_error(result);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn search_filters_failure_recovery_has_no_ai_remote_or_secret_side_effects() {
    let repo = initialized_repo();
    insert_file(repo.path(), "docs/local-only.txt", "docs");
    let before = snapshot(repo.path());

    let facets = list_filter_facets(path_string(repo.path()), default_query())
        .expect("local facet query succeeds");

    assert_eq!(facets.total_count, 1);
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_eq!(snapshot(repo.path()), before);
}
