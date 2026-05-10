use area_matrix_core::{
    search_files, CoreError, CoreResult, FileEntry, FileOrigin, SearchDiagnosticKind,
    SearchDiagnosticSeverity, SearchFileResult, SearchFilter, SearchIndexStatus, SearchMatch,
    SearchMatchField, SearchMatchKind, SearchPagination, SearchQueryDiagnostic, SearchResultPage,
    SearchScope, SearchSort, StorageMode,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-01-search-query-files.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const SEARCH_RESULTS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-01-search-results.md");
const SEARCH_EMPTY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-04-search-empty.md");
const QUERY_ERROR_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-05-query-error.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const SEARCH_RS: &str = include_str!("../src/search.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn search_query_files_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_search(
        _: fn(
            String,
            String,
            SearchFilter,
            SearchSort,
            SearchPagination,
        ) -> CoreResult<SearchResultPage>,
    ) {
    }

    assert_search(search_files);

    let filter = SearchFilter {
        scope: SearchScope::CurrentNode,
        current_path: Some("docs/contracts".to_owned()),
        category: Some("docs".to_owned()),
        file_kind: Some("pdf".to_owned()),
        tags: vec!["signed".to_owned()],
        imported_after: Some(100),
        imported_before: Some(200),
        modified_after: Some(120),
        modified_before: Some(220),
        include_deleted: Some(false),
    };
    assert_eq!(filter.scope, SearchScope::CurrentNode);
    assert_eq!(filter.current_path.as_deref(), Some("docs/contracts"));
    assert_eq!(filter.tags, vec!["signed"]);

    let pagination = SearchPagination {
        limit: 50,
        offset: 10,
    };
    assert_eq!(pagination.limit, 50);
    assert_eq!(pagination.offset, 10);

    let documented_errors = [
        CoreError::db("database error"),
        CoreError::config("query parser error"),
        CoreError::invalid_path("invalid scope path"),
    ];
    assert_eq!(documented_errors.len(), 3);

    let not_yet_implemented = search_files(
        "/tmp/repo".to_owned(),
        "合同".to_owned(),
        filter,
        SearchSort::NewestImported,
        pagination,
    );
    assert!(matches!(not_yet_implemented, Err(CoreError::Config { .. })));
}

#[test]
fn search_query_files_contract_result_page_carries_consumer_state() {
    let entry = FileEntry {
        id: 1,
        path: "docs/contracts/client-a.pdf".to_owned(),
        original_name: "client-a.pdf".to_owned(),
        current_name: "client-a.pdf".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 128,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: None,
        imported_at: 100,
        updated_at: 120,
    };
    let result = SearchFileResult {
        entry,
        score: 10.0,
        matches: vec![SearchMatch {
            field: SearchMatchField::Name,
            kind: SearchMatchKind::Exact,
            snippet: "client-a.pdf".to_owned(),
            start: Some(0),
            end: Some(6),
        }],
        note_snippet: Some("等待客户回签合同扫描件".to_owned()),
    };
    let diagnostic = SearchQueryDiagnostic {
        kind: SearchDiagnosticKind::UnknownField,
        severity: SearchDiagnosticSeverity::Error,
        message: "Unknown field `kindd`".to_owned(),
        token: Some("kindd".to_owned()),
        start: Some(0),
        end: Some(5),
        suggestion: Some("kind".to_owned()),
    };
    let page = SearchResultPage {
        query: "合同".to_owned(),
        total_count: 1,
        results: vec![result],
        diagnostics: vec![diagnostic],
        index_status: SearchIndexStatus::Ready,
    };

    assert_eq!(page.query, "合同");
    assert_eq!(page.total_count, 1);
    assert_eq!(page.results[0].matches[0].field, SearchMatchField::Name);
    assert_eq!(page.results[0].matches[0].kind, SearchMatchKind::Exact);
    assert_eq!(
        page.results[0].note_snippet.as_deref(),
        Some("等待客户回签合同扫描件")
    );
    assert_eq!(page.diagnostics[0].kind, SearchDiagnosticKind::UnknownField);
    assert_eq!(page.diagnostics[0].suggestion.as_deref(), Some("kind"));
    assert_eq!(page.index_status, SearchIndexStatus::Ready);
}

#[test]
fn search_query_files_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-01 search-query-files",
        "- S2-01 search-results",
        "- S2-04 search-empty",
        "- S2-05 query-error",
        "`search_files(repo_path, query, filter, sort, pagination) -> SearchResultPage`",
        "搜索结果、总数、query parse diagnostics。",
        "- `Db`",
        "- `Config`",
        "- `InvalidPath`",
        "文件名、相对路径、笔记、分类、change log 可搜索。",
        "0 结果和 query parse error 可区分。",
        "搜索不修改标签、分类或文件。",
        "OCR、语义搜索和远程 AI 属于 Stage 3。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-01 | search-results | C2-01, C2-02 | `search_files`",
        "| S2-04 | search-empty | C2-01 | empty result state | 只读",
        "| S2-05 | query-error | C2-01 | query diagnostics | 只读",
        "搜索、filter、Smart List 不得移动、删除或改名文件。",
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
        "enum SearchSort { \"Relevance\", \"NewestImported\", \"NewestModified\", \"NameAsc\" };",
        "enum SearchMatchKind { \"Exact\", \"Fuzzy\", \"PinyinInitials\" };",
        "enum SearchDiagnosticKind",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn search_query_files_contract_documents_consumer_states_and_scope_boundaries() {
    for fragment in [
        "聚焦并显示搜索 query。",
        "展示搜索 banner、结果数量、清除和保存入口。",
        "高亮命中片段，笔记命中时显示摘要。",
        "支持排序：Relevance、Newest imported、Newest modified、Name A-Z。",
        "加载中、0 结果、查询错误、Search API 失败、索引不可用五类状态可区分。",
    ] {
        assert_contains(SEARCH_RESULTS_PAGE, fragment);
    }

    for fragment in [
        "用户执行搜索后没有匹配文件。",
        "默认态：搜索成功且结果为 0",
        "no result、indexing、empty repo、backend error 四类状态不会混淆。",
    ] {
        assert_contains(SEARCH_EMPTY_PAGE, fragment);
    }

    for fragment in [
        "Query parser error type",
        "Unknown field",
        "错误查询不能保存为 Smart List。",
        "解析错误时不执行搜索请求。",
    ] {
        assert_contains(QUERY_ERROR_PAGE, fragment);
    }

    for fragment in [
        "Searches files, paths, notes, categories, and change-log metadata.",
        "C2-01 owns this read-only contract for S2-01 search results",
        "S2-04 empty",
        "S2-05 query diagnostics",
        "does not include C2-02 facet counts",
        "C2-03 saved search CRUD",
        "C2-04 Smart List execution",
        "OCR, semantic search, remote AI",
        "must not modify tags, categories, notes, change log",
        "Returns `CoreError::InvalidPath { path }`",
        "`CoreError::Config { reason }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for fragment in [
        "Search scope for C2-01 search queries.",
        "Structured query parser diagnostic kind.",
        "Search index readiness surfaced to search result and empty states.",
        "Filters and scope applied to a C2-01 search query.",
        "One page of C2-01 search results.",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for error_name in ["Db", "Config", "InvalidPath"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
    }
}
