use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_filter_facets, CoreError, CoreResult, OverviewOutput, RepoInitMode,
    RepoInitOptions, SearchFacetCount, SearchFacetQuery, SearchFacets, SearchScope,
    SearchStorageModeFacetCount, SearchTagMatchMode, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-02-search-filters.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const SEARCH_FILTERS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-02-search-filters.md");
const TAGS_FILTER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-08-tags-filter.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const SEARCH_RS: &str = include_str!("../src/search.rs");

#[derive(Debug, Eq, PartialEq)]
struct RepoSnapshot {
    files: Vec<(i64, String, String, String)>,
    tag_count: i64,
    change_log_count: i64,
    visible_paths: Vec<String>,
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

fn insert_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    storage_mode: &str,
    imported_at: i64,
    updated_at: i64,
    status: &str,
) -> i64 {
    if status == "active" {
        let file_path = repo.join(relative_path);
        fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
            .expect("create parent directory");
        fs::write(&file_path, b"search filters validation fixture")
            .expect("write user-visible fixture");
    }

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture has filename");
    let seed = imported_at as u64 + updated_at as u64 + relative_path.len() as u64;
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 33,
                ?4, ?5, 'imported', NULL,
                ?6, ?7, ?8
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{seed:064x}"),
                storage_mode,
                imported_at,
                updated_at,
                status,
            ],
        )
        .expect("insert file row");
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

fn insert_docs_file(
    repo: &Path,
    relative_path: &str,
    storage_mode: &str,
    imported_at: i64,
    updated_at: i64,
    status: &str,
) -> i64 {
    insert_file(
        repo,
        relative_path,
        "docs",
        storage_mode,
        imported_at,
        updated_at,
        status,
    )
}

fn seed_combined_facets(repo: &Path) {
    let client = insert_docs_file(
        repo,
        "docs/contracts/client-contract.pdf",
        "copied",
        100,
        300,
        "active",
    );
    let vendor = insert_docs_file(
        repo,
        "docs/contracts/vendor-contract.pdf",
        "moved",
        120,
        320,
        "active",
    );
    let spec = insert_docs_file(repo, "docs/spec/api.md", "indexed", 140, 280, "active");
    let deleted = insert_docs_file(
        repo,
        "docs/contracts/deleted-contract.pdf",
        "indexed",
        150,
        350,
        "deleted",
    );
    insert_tag(repo, client, "Finance");
    insert_tag(repo, client, "Signed");
    insert_tag(repo, vendor, "Finance");
    insert_tag(repo, spec, "Signed");
    insert_tag(repo, deleted, "finance");
    insert_tag(repo, deleted, "signed");
}

fn combined_query() -> SearchFacetQuery {
    let mut query = default_query();
    query.query = "contract".to_owned();
    query.scope = SearchScope::CurrentNode;
    query.current_path = Some("docs/contracts".to_owned());
    query.category = Some("docs".to_owned());
    query.file_kind = Some("pdf".to_owned());
    query.tags = vec!["finance".to_owned(), "signed".to_owned()];
    query.tag_match_mode = SearchTagMatchMode::All;
    query.imported_after = Some(90);
    query.imported_before = Some(160);
    query.modified_after = Some(250);
    query.modified_before = Some(360);
    query.include_deleted = Some(true);
    query
}

fn snapshot(repo: &Path) -> RepoSnapshot {
    RepoSnapshot {
        files: file_rows(repo),
        tag_count: table_count(repo, "tags"),
        change_log_count: table_count(repo, "change_log"),
        visible_paths: visible_paths(repo),
        staging_paths: relative_entries(repo, &repo.join(".areamatrix/staging")),
        generated_paths: relative_entries(repo, &repo.join(".areamatrix/generated")),
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
            collect_visible_paths(repo, &path, paths);
        }
    }
}

fn relative_entries(repo: &Path, root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    if root.exists() {
        collect_relative_entries(repo, root, &mut entries);
    }
    entries.sort();
    entries
}

fn collect_relative_entries(repo: &Path, current: &Path, entries: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read directory") {
        let entry = entry.expect("read directory entry");
        let path = entry.path();
        entries.push(
            path.strip_prefix(repo)
                .expect("path is inside repository")
                .to_string_lossy()
                .into_owned(),
        );
        if path.is_dir() {
            collect_relative_entries(repo, &path, entries);
        }
    }
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn string_facet_state(facets: &[SearchFacetCount], value: &str) -> Option<(i64, bool, bool)> {
    facets
        .iter()
        .find(|facet| facet.value == value)
        .map(|facet| (facet.count, facet.selected, facet.disabled))
}

fn storage_facet_state(
    facets: &[SearchStorageModeFacetCount],
    value: StorageMode,
) -> Option<(i64, bool, bool)> {
    facets
        .iter()
        .find(|facet| facet.value == value)
        .map(|facet| (facet.count, facet.selected, facet.disabled))
}

fn assert_combined_facets(facets: &SearchFacets) {
    assert_eq!(facets.query, "contract");
    assert_eq!(facets.total_count, 2);
    assert_eq!(facets.active_filter_count, 6);
    assert_eq!(
        string_facet_state(&facets.categories, "docs"),
        Some((2, true, false))
    );
    assert_eq!(
        string_facet_state(&facets.file_kinds, "pdf"),
        Some((2, true, false))
    );
    assert_eq!(
        string_facet_state(&facets.tags, "finance"),
        Some((3, true, false))
    );
    assert_eq!(
        storage_facet_state(&facets.storage_modes, StorageMode::Copied),
        Some((1, false, false))
    );
    assert_eq!(
        storage_facet_state(&facets.storage_modes, StorageMode::Moved),
        Some((0, false, true))
    );
    assert_eq!(facets.date_bounds.oldest_imported_at, Some(100));
    assert_eq!(facets.date_bounds.newest_imported_at, Some(150));
    assert_eq!(facets.date_bounds.oldest_modified_at, Some(300));
    assert_eq!(facets.date_bounds.newest_modified_at, Some(350));
}

fn assert_config_error(result: Result<SearchFacets, CoreError>) {
    assert!(matches!(result, Err(CoreError::Config { .. })));
}

fn assert_capability_spec_alignment() {
    for fragment in [
        "# C2-02 search-filters",
        "- S2-02 search-filters",
        "- S2-08 tags-filter",
        "`list_filter_facets(repo_path, query) -> SearchFacets`",
        "category、tags、date range、storage mode、include deleted。",
        "过滤后的搜索结果和 facet counts。",
        "- `Db`",
        "- `Config`",
        "标签筛选只改变搜索条件，不创建或删除标签。",
        "日期非法返回结构化 query error。",
        "Smart List 编辑场景可保存 draft filter。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_control_map_alignment() {
    for fragment in [
        "| S2-02 | search-filters | C2-02 | filter/facet query | 只读",
        "| S2-08 | tags-filter | C2-02, C2-05 | tag filter | tags 只读",
        "搜索、filter、Smart List 不得移动、删除或改名文件。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
}

fn assert_core_api_and_udl_alignment() {
    for fragment in [
        "SearchFacets list_filter_facets(string repo_path, SearchFacetQuery query);",
        "dictionary SearchFacetQuery",
        "string query;",
        "SearchScope scope;",
        "sequence<string> tags;",
        "SearchTagMatchMode tag_match_mode;",
        "StorageMode? storage_mode;",
        "boolean? include_deleted;",
        "dictionary SearchFacets",
        "sequence<SearchFacetCount> categories;",
        "sequence<SearchFacetCount> file_kinds;",
        "sequence<SearchFacetCount> tags;",
        "sequence<SearchStorageModeFacetCount> storage_modes;",
        "SearchDateFacetBounds date_bounds;",
        "i64 active_filter_count;",
        "enum SearchTagMatchMode { \"Any\", \"All\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_rust_contract_alignment() {
    for fragment in [
        "pub fn list_filter_facets(repo_path: String, query: SearchFacetQuery)",
        "Loads C2-02 search filter facet counts without mutating repository state.",
        "tags with Any/All semantics",
        "optional storage mode",
        "does not create, update, delete, or rename tags",
        "must not modify files, notes, categories, change log",
        "Returns `CoreError::Config { reason }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }
}

fn assert_consumer_docs_alignment() {
    for fragment in [
        "Reset filters 不清空 query。",
        "自定义日期错误能提示且不污染结果状态。",
        "Smart List 编辑场景中，filter 变化更新编辑草稿，不立即保存 Smart List。",
    ] {
        assert_contains(SEARCH_FILTERS_PAGE, fragment);
    }

    for fragment in [
        "本页只负责筛选，不负责生成标签。",
        "移除筛选不会删除标签。",
        "可选择多个标签并清楚显示 Any/All 模式。",
        "标签搜索大小写不敏感；拼音匹配不作为本页 Stage 2 必做能力。",
    ] {
        assert_contains(TAGS_FILTER_PAGE, fragment);
    }
}

#[test]
fn search_filters_validation_covers_combined_success_path_without_side_effects() {
    let repo = initialized_repo();
    seed_combined_facets(repo.path());
    let before = snapshot(repo.path());

    let facets =
        list_filter_facets(path_string(repo.path()), combined_query()).expect("load facets");

    assert_combined_facets(&facets);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn search_filters_validation_covers_structured_failure_paths_without_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(
        repo.path(),
        "docs/contracts/client-contract.pdf",
        "docs",
        "copied",
        100,
        300,
        "active",
    );
    insert_tag(repo.path(), file_id, "finance");
    let before = snapshot(repo.path());

    let mut reversed_date = default_query();
    reversed_date.imported_after = Some(300);
    reversed_date.imported_before = Some(200);
    assert_config_error(list_filter_facets(path_string(repo.path()), reversed_date));

    let mut invalid_query = default_query();
    invalid_query.query = "after:2026-13-01".to_owned();
    assert_config_error(list_filter_facets(path_string(repo.path()), invalid_query));

    let mut invalid_scope = default_query();
    invalid_scope.scope = SearchScope::CurrentNode;
    assert_config_error(list_filter_facets(path_string(repo.path()), invalid_scope));

    let uninitialized = tempfile::tempdir().expect("create uninitialized repository directory");
    assert!(matches!(
        list_filter_facets(path_string(uninitialized.path()), default_query()),
        Err(CoreError::Db { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn search_filters_validation_locks_core_api_udl_rust_and_consumer_contract() {
    fn assert_signature(_: fn(String, SearchFacetQuery) -> CoreResult<SearchFacets>) {}
    assert_signature(list_filter_facets);

    assert_capability_spec_alignment();
    assert_control_map_alignment();
    assert_core_api_and_udl_alignment();
    assert_rust_contract_alignment();
    assert_consumer_docs_alignment();
}
