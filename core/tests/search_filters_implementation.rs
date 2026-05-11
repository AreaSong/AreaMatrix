use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_filter_facets, CoreError, OverviewOutput, RepoInitMode, RepoInitOptions,
    SearchFacetQuery, SearchScope, SearchTagMatchMode, StorageMode,
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

fn insert_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    storage_mode: &str,
    imported_at: i64,
    updated_at: i64,
) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create parent directory");
    fs::write(&file_path, b"fixture bytes").expect("write file fixture");

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
                ?4, ?5, 'imported', NULL,
                ?6, ?7, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
                storage_mode,
                imported_at,
                updated_at,
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn insert_deleted_file(repo: &Path, relative_path: &str, category: &str) -> i64 {
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, deleted_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 13,
                ?4, 'indexed', 'imported', NULL,
                500, 520, 600, 'deleted'
             )",
            params![
                relative_path,
                relative_path
                    .rsplit('/')
                    .next()
                    .expect("fixture has filename"),
                category,
                format!("{:064x}", relative_path.len()),
            ],
        )
        .expect("insert deleted file row");
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

fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active files")
}

fn tag_row_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM tags", [], |row| row.get(0))
        .expect("count tag rows")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

#[test]
fn search_filters_implementation_returns_real_facets_for_combined_filters() {
    let repo = initialized_repo();
    let contract_id = insert_file(
        repo.path(),
        "docs/client-contract.pdf",
        "docs",
        "copied",
        100,
        300,
    );
    let spec_id = insert_file(repo.path(), "docs/api-spec.md", "docs", "indexed", 150, 250);
    let invoice_id = insert_file(
        repo.path(),
        "finance/invoice-contract.pdf",
        "finance",
        "moved",
        200,
        500,
    );
    insert_tag(repo.path(), contract_id, "finance");
    insert_tag(repo.path(), contract_id, "signed");
    insert_tag(repo.path(), spec_id, "signed");
    insert_tag(repo.path(), invoice_id, "finance");

    let mut query = default_query();
    query.query = "contract".to_owned();
    query.category = Some("docs".to_owned());
    query.file_kind = Some("pdf".to_owned());
    query.tags = vec!["finance".to_owned()];
    query.storage_mode = Some(StorageMode::Copied);
    query.imported_after = Some(50);
    query.imported_before = Some(180);
    query.modified_after = Some(250);
    query.modified_before = Some(350);

    let facets = list_filter_facets(path_string(repo.path()), query).expect("load facets");

    assert_eq!(facets.query, "contract");
    assert_eq!(facets.total_count, 1);
    assert_eq!(facets.active_filter_count, 6);
    assert_eq!(
        facets
            .categories
            .iter()
            .find(|facet| facet.value == "docs")
            .map(|facet| (facet.count, facet.selected, facet.disabled)),
        Some((1, true, false))
    );
    assert_eq!(
        facets
            .file_kinds
            .iter()
            .find(|facet| facet.value == "pdf")
            .map(|facet| (facet.count, facet.selected, facet.disabled)),
        Some((1, true, false))
    );
    assert_eq!(
        facets
            .tags
            .iter()
            .find(|facet| facet.value == "finance")
            .map(|facet| (facet.count, facet.selected, facet.disabled)),
        Some((1, true, false))
    );
    assert_eq!(
        facets
            .storage_modes
            .iter()
            .find(|facet| facet.value == StorageMode::Copied)
            .map(|facet| (facet.count, facet.selected, facet.disabled)),
        Some((1, true, false))
    );
    assert_eq!(facets.date_bounds.oldest_imported_at, Some(100));
    assert_eq!(facets.date_bounds.newest_imported_at, Some(100));
    assert_eq!(facets.date_bounds.oldest_modified_at, Some(300));
    assert_eq!(facets.date_bounds.newest_modified_at, Some(300));
}

#[test]
fn search_filters_implementation_supports_any_all_tags_scope_and_include_deleted() {
    let repo = initialized_repo();
    let signed_finance = insert_file(repo.path(), "docs/client.pdf", "docs", "copied", 100, 100);
    let signed_only = insert_file(repo.path(), "docs/handbook.pdf", "docs", "copied", 110, 110);
    let outside = insert_file(
        repo.path(),
        "finance/client.pdf",
        "finance",
        "copied",
        120,
        120,
    );
    let deleted = insert_deleted_file(repo.path(), "docs/deleted-client.pdf", "docs");
    insert_tag(repo.path(), signed_finance, "Finance");
    insert_tag(repo.path(), signed_finance, "Signed");
    insert_tag(repo.path(), signed_only, "Signed");
    insert_tag(repo.path(), outside, "Finance");
    insert_tag(repo.path(), deleted, "finance");

    let mut query = default_query();
    query.query = "client".to_owned();
    query.scope = SearchScope::CurrentNode;
    query.current_path = Some("docs".to_owned());
    query.tags = vec!["finance".to_owned(), "signed".to_owned()];
    query.tag_match_mode = SearchTagMatchMode::All;

    let all_facets =
        list_filter_facets(path_string(repo.path()), query.clone()).expect("load all tag facets");
    assert_eq!(all_facets.total_count, 1);

    query.tag_match_mode = SearchTagMatchMode::Any;
    let any_facets =
        list_filter_facets(path_string(repo.path()), query.clone()).expect("load any tag facets");
    assert_eq!(any_facets.total_count, 1);

    query.include_deleted = Some(true);
    let with_deleted =
        list_filter_facets(path_string(repo.path()), query).expect("load deleted facets");
    assert_eq!(with_deleted.total_count, 2);
    assert_eq!(with_deleted.active_filter_count, 2);
}

#[test]
fn search_filters_implementation_is_read_only_and_maps_failures() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/client.pdf", "docs", "copied", 100, 100);
    insert_tag(repo.path(), file_id, "finance");
    let files_before = active_file_count(repo.path());
    let tags_before = tag_row_count(repo.path());
    let changes_before = change_log_count(repo.path());

    let mut query = default_query();
    query.query = "after:2026-13-01".to_owned();
    let invalid_query = list_filter_facets(path_string(repo.path()), query);
    assert!(matches!(invalid_query, Err(CoreError::Config { .. })));

    let mut reversed_date = default_query();
    reversed_date.modified_after = Some(300);
    reversed_date.modified_before = Some(200);
    let invalid_filter = list_filter_facets(path_string(repo.path()), reversed_date);
    assert!(matches!(invalid_filter, Err(CoreError::Config { .. })));

    let uninitialized = tempfile::tempdir().expect("create uninitialized repo");
    let db_result = list_filter_facets(path_string(uninitialized.path()), default_query());
    assert!(matches!(db_result, Err(CoreError::Db { .. })));

    assert_eq!(active_file_count(repo.path()), files_before);
    assert_eq!(tag_row_count(repo.path()), tags_before);
    assert_eq!(change_log_count(repo.path()), changes_before);
}
