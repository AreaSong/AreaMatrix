use area_matrix_core::{
    create_saved_search, run_smart_list, search_files, CoreError, CoreResult, ErrorKind,
    ErrorRecoverability, SavedSearchQuery, SearchFilter, SearchPagination, SearchResultPage,
    SearchScope, SearchSort, SearchTagMatchMode, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::params;

#[path = "support/smart_list_failure.rs"]
mod smart_list_support;

use smart_list_support::{
    assert_config_error, assert_db_error, assert_snapshot_unchanged, create_request, first_page,
    initialized_repo, insert_change, insert_file, insert_note, insert_tag, open_db, path_string,
    smart_list_query, snapshot,
};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-04-smart-lists.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const SEARCH_RS: &str = include_str!("../src/search.rs");
const SAVED_SEARCH_RS: &str = include_str!("../src/search/saved_search.rs");
const DB_SAVED_SEARCH_RS: &str = include_str!("../src/db/saved_search.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

fn validation_filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: Some("finance".to_owned()),
        file_kind: Some("pdf".to_owned()),
        tags: vec!["tax".to_owned()],
        tag_match_mode: SearchTagMatchMode::All,
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: Some(StorageMode::Copied),
        include_deleted: Some(false),
    }
}

fn validation_query() -> SavedSearchQuery {
    SavedSearchQuery {
        query: "report".to_owned(),
        filter: validation_filter(),
        sort: SearchSort::NameAsc,
    }
}

fn small_page() -> SearchPagination {
    SearchPagination {
        limit: 1,
        offset: 0,
    }
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn smart_lists_validation_matches_saved_query_to_search_files_without_writes() {
    let repo = initialized_repo();
    let matching = insert_file(repo.path(), "finance/report-alpha.pdf", "finance");
    let second_match = insert_file(repo.path(), "finance/report-beta.pdf", "finance");
    let wrong_category = insert_file(repo.path(), "docs/report-alpha.pdf", "docs");
    insert_tag(repo.path(), matching, "tax");
    insert_tag(repo.path(), second_match, "tax");
    insert_tag(repo.path(), wrong_category, "tax");
    insert_note(repo.path(), matching, "smart list report note");
    insert_change(repo.path(), matching);

    let query = validation_query();
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Finance Reports", query.clone()),
    )
    .expect("create smart list");
    let before = snapshot(repo.path());

    let smart_list_page =
        run_smart_list(path_string(repo.path()), saved.id, small_page()).expect("run smart list");
    let direct_page = search_files(
        path_string(repo.path()),
        query.query,
        query.filter,
        query.sort,
        small_page(),
    )
    .expect("run equivalent search");

    assert_eq!(smart_list_page, direct_page);
    assert_eq!(smart_list_page.query, "report");
    assert_eq!(smart_list_page.total_count, 2);
    assert_eq!(smart_list_page.results.len(), 1);
    assert_eq!(smart_list_page.results[0].entry.id, matching);
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_lists_validation_covers_structured_failure_paths_without_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report-alpha.pdf", "finance");
    insert_tag(repo.path(), file_id, "tax");
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Finance Reports", smart_list_query()),
    )
    .expect("create smart list");
    let before = snapshot(repo.path());

    assert_config_error(run_smart_list(String::new(), saved.id, first_page()));
    assert_config_error(run_smart_list(path_string(repo.path()), 0, first_page()));
    assert_config_error(run_smart_list(
        path_string(repo.path()),
        saved.id,
        SearchPagination {
            limit: 0,
            offset: 0,
        },
    ));

    let missing = run_smart_list(path_string(repo.path()), 404, first_page())
        .expect_err("missing smart list should fail");
    assert!(matches!(missing, CoreError::FileNotFound { .. }));
    assert_eq!(missing.to_error_mapping().kind, ErrorKind::FileNotFound);
    assert_eq!(
        missing.to_error_mapping().recoverability,
        ErrorRecoverability::RefreshRequired
    );

    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_lists_validation_rejects_corrupted_saved_query_without_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report-alpha.pdf", "finance");
    insert_tag(repo.path(), file_id, "tax");
    let saved = create_saved_search(
        path_string(repo.path()),
        create_request("Finance Reports", validation_query()),
    )
    .expect("create smart list");
    open_db(repo.path())
        .execute(
            "UPDATE saved_searches SET query_json = '{' WHERE id = ?1",
            params![saved.id],
        )
        .expect("corrupt saved search query json");
    let before = snapshot(repo.path());

    let error = assert_db_error(run_smart_list(
        path_string(repo.path()),
        saved.id,
        first_page(),
    ));

    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
    assert_snapshot_unchanged(repo.path(), &before);
}

#[test]
fn smart_lists_validation_locks_core_api_udl_and_rust_alignment() {
    fn assert_signature(_: fn(String, i64, SearchPagination) -> CoreResult<SearchResultPage>) {}
    assert_signature(run_smart_list);

    for fragment in [
        "# C2-04 smart-lists",
        "`list_saved_searches`",
        "`search_files`",
        "`run_smart_list(repo_path, saved_search_id, pagination) -> SearchResultPage`",
        "读取 saved searches；无文件写入。",
        "打开 Smart List 只运行查询，不改变文件。",
        "Command palette 能发现 smart list。",
        "智能推荐列表属于 Stage 3。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-06 | smart-lists | C2-03, C2-04 | run/list smart lists | saved_searches",
        "| S2-15 | command-palette | C2-04, C2-11 | command index | 只读 / recent command",
        "搜索、filter、Smart List 不得移动、删除或改名文件。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "SearchResultPage run_smart_list(",
        "string repo_path,",
        "i64 saved_search_id,",
        "SearchPagination pagination",
        "dictionary SearchResultPage",
        "sequence<SearchFileResult> results;",
        "sequence<SearchQueryDiagnostic> diagnostics;",
        "SearchIndexStatus index_status;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "测试金字塔",
        "`core/storage`",
        "集成测试目录",
        "`core/tests/`，每个文件独立编译",
        "关键测试场景",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
}

#[test]
fn smart_lists_validation_locks_rust_read_only_execution_path() {
    for fragment in [
        "pub use saved_search::{",
        "run_smart_list",
        "SearchResultPage",
        "pub use search::*;",
    ] {
        assert!(SEARCH_RS.contains(fragment) || LIB_RS.contains(fragment));
    }

    for fragment in [
        "pub fn run_smart_list(",
        "db::get_saved_search_row",
        "super::search_files(",
        "validate_saved_search_id(saved_search_id)",
        "validate_smart_list_pagination(&pagination)",
        "validate_smart_list_query_state(&saved.query)",
        "must not rename, move, delete, trash",
        "Returns `CoreError::Config { reason }`",
        "Returns `CoreError::Db { message }`",
        "`CoreError::FileNotFound { path }`",
    ] {
        assert_contains(SAVED_SEARCH_RS, fragment);
    }

    for fragment in [
        "SELECT id, name, query_json, icon, color, pinned",
        "FROM saved_searches",
        "WHERE id = ?1",
        "ok_or_else(|| CoreError::file_not_found",
        "open_saved_search_read_connection",
    ] {
        assert_contains(DB_SAVED_SEARCH_RS, fragment);
    }
}
