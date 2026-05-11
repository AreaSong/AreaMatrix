use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, search_files, write_note, CoreError, CoreResult, OverviewOutput, RepoInitMode,
    RepoInitOptions, SearchDiagnosticKind, SearchFilter, SearchIndexStatus, SearchMatchField,
    SearchPagination, SearchResultPage, SearchScope, SearchSort,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-01-search-query-files.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const SEARCH_RS: &str = include_str!("../src/search.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

#[derive(Debug, Eq, PartialEq)]
struct RepoSnapshot {
    files: Vec<(i64, String, String, String)>,
    change_log_count: i64,
    note_count: i64,
    tag_count: i64,
    visible_paths: Vec<String>,
    staging_count: usize,
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn default_filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: None,
        file_kind: None,
        tags: Vec::new(),
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        include_deleted: Some(false),
    }
}

fn first_page() -> SearchPagination {
    SearchPagination {
        limit: 50,
        offset: 0,
    }
}

fn insert_file(
    repo: &Path,
    relative_path: &str,
    category: &str,
    imported_at: i64,
    updated_at: i64,
) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create parent directory");
    fs::write(&file_path, b"search validation fixture").expect("write file fixture");

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
                ?1, ?2, ?2, ?3, 25,
                ?4, 'copied', 'imported', NULL,
                ?5, ?6, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                format!("{:064x}", relative_path.len()),
                imported_at,
                updated_at,
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn insert_change(repo: &Path, file_id: i64, action: &str, detail: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, 200)",
            params![file_id, action, detail],
        )
        .expect("insert change-log row");
}

fn snapshot(repo: &Path) -> RepoSnapshot {
    RepoSnapshot {
        files: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        note_count: table_count(repo, "notes"),
        tag_count: table_count(repo, "tags"),
        visible_paths: user_visible_paths(repo),
        staging_count: directory_entry_count(&repo.join(".areamatrix/staging")),
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
            .expect("path is inside repo")
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

fn directory_entry_count(path: &Path) -> usize {
    let mut count = 0;
    for entry in fs::read_dir(path).expect("read metadata directory") {
        entry.expect("read metadata entry");
        count += 1;
    }
    count
}

fn relative_directory_entries(repo: &Path, path: &Path) -> Vec<String> {
    let mut entries: Vec<String> = fs::read_dir(path)
        .expect("read generated directory")
        .map(|entry| {
            entry
                .expect("read generated entry")
                .path()
                .strip_prefix(repo)
                .expect("generated path is inside repo")
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    entries.sort();
    entries
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn search_query_files_validation_covers_success_empty_and_query_error_states() {
    let repo = initialized_repo();
    let note_id = insert_file(repo.path(), "docs/contracts/client-a.pdf", "docs", 100, 120);
    let change_id = insert_file(repo.path(), "finance/invoice-2026.pdf", "finance", 200, 220);
    write_note(
        path_string(repo.path()),
        note_id,
        "等待客户回签合同扫描件".to_owned(),
    )
    .expect("write searchable note");
    insert_change(
        repo.path(),
        change_id,
        "renamed",
        r#"{"from":"draft","to":"付款合同"}"#,
    );
    let before = snapshot(repo.path());

    let success = search_files(
        path_string(repo.path()),
        "合同".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("search succeeds");
    assert_eq!(success.query, "合同");
    assert_eq!(success.total_count, 2);
    assert_eq!(success.index_status, SearchIndexStatus::Ready);
    assert!(success.diagnostics.is_empty());
    assert!(success
        .results
        .iter()
        .any(|result| result.entry.id == note_id
            && result
                .matches
                .iter()
                .any(|matched| matched.field == SearchMatchField::Note)));
    assert!(success
        .results
        .iter()
        .any(|result| result.entry.id == change_id
            && result
                .matches
                .iter()
                .any(|matched| matched.field == SearchMatchField::ChangeLog)));

    let empty = search_files(
        path_string(repo.path()),
        "missing-keyword".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("empty search succeeds");
    assert_eq!(empty.total_count, 0);
    assert!(empty.results.is_empty());
    assert!(empty.diagnostics.is_empty());

    let query_error = search_files(
        path_string(repo.path()),
        "kindd:pdf after:2026-13-01 (".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    )
    .expect("query diagnostics return as a result page");
    assert_eq!(query_error.total_count, 0);
    assert!(query_error.results.is_empty());
    assert!(query_error
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::UnknownField));
    assert!(query_error
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::InvalidDate));
    assert!(query_error
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == SearchDiagnosticKind::UnbalancedParentheses));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn search_query_files_validation_covers_structured_failure_paths() {
    let repo = initialized_repo();
    insert_file(repo.path(), "docs/report.pdf", "docs", 100, 100);
    let before = snapshot(repo.path());

    let mut invalid_scope = default_filter();
    invalid_scope.scope = SearchScope::CurrentNode;
    invalid_scope.current_path = Some("../outside".to_owned());
    let invalid_scope_result = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        invalid_scope,
        SearchSort::Relevance,
        first_page(),
    );
    assert!(matches!(
        invalid_scope_result,
        Err(CoreError::InvalidPath { .. })
    ));

    let mut invalid_filter = default_filter();
    invalid_filter.category = Some("   ".to_owned());
    let invalid_filter_result = search_files(
        path_string(repo.path()),
        "report".to_owned(),
        invalid_filter,
        SearchSort::Relevance,
        first_page(),
    );
    assert!(matches!(
        invalid_filter_result,
        Err(CoreError::Config { .. })
    ));

    let uninitialized = tempfile::tempdir().expect("create uninitialized repository directory");
    let db_result = search_files(
        path_string(uninitialized.path()),
        "report".to_owned(),
        default_filter(),
        SearchSort::Relevance,
        first_page(),
    );
    assert!(matches!(db_result, Err(CoreError::Db { .. })));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn search_query_files_validation_locks_core_api_udl_and_rust_contract() {
    fn assert_signature(
        _: fn(
            String,
            String,
            SearchFilter,
            SearchSort,
            SearchPagination,
        ) -> CoreResult<SearchResultPage>,
    ) {
    }
    assert_signature(search_files);

    for fragment in [
        "# C2-01 search-query-files",
        "`search_files(repo_path, query, filter, sort, pagination) -> SearchResultPage`",
        "文件名、相对路径、笔记、分类、change log 可搜索。",
        "0 结果和 query parse error 可区分。",
        "搜索不修改标签、分类或文件。",
        "- `Db`",
        "- `Config`",
        "- `InvalidPath`",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-01 | search-results | C2-01, C2-02 | `search_files`",
        "| S2-04 | search-empty | C2-01 | empty result state | 只读",
        "| S2-05 | query-error | C2-01 | query diagnostics | 只读",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "SearchResultPage search_files(",
        "string repo_path,",
        "string query,",
        "SearchFilter filter,",
        "SearchSort sort,",
        "SearchPagination pagination",
        "dictionary SearchFilter",
        "SearchScope scope;",
        "sequence<string> tags;",
        "dictionary SearchResultPage",
        "i64 total_count;",
        "sequence<SearchFileResult> results;",
        "sequence<SearchQueryDiagnostic> diagnostics;",
        "SearchIndexStatus index_status;",
        "enum SearchScope { \"AllRepo\", \"CurrentNode\" };",
        "enum SearchDiagnosticKind",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub fn search_files(",
        "Searches files, paths, notes, categories, and change-log metadata.",
        "must not modify tags, categories, notes, change log",
        "Returns `CoreError::InvalidPath { path }`",
        "`CoreError::Config { reason }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }
    assert_contains(LIB_RS, "pub use search::*;");
}
