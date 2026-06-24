use area_matrix_core::{
    search_files, CoreError, CoreResult, FileEntry, FileOrigin, SearchDiagnosticKind,
    SearchDiagnosticSeverity, SearchFileResult, SearchFilter, SearchIndexStatus, SearchMatch,
    SearchMatchField, SearchMatchKind, SearchPagination, SearchQueryDiagnostic, SearchResultPage,
    SearchScope, SearchSort, SearchTagMatchMode, StorageMode,
};
use pretty_assertions::assert_eq;

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
        tag_match_mode: SearchTagMatchMode::All,
        imported_after: Some(100),
        imported_before: Some(200),
        modified_after: Some(120),
        modified_before: Some(220),
        storage_mode: Some(StorageMode::Copied),
        include_deleted: Some(false),
    };
    assert_eq!(filter.scope, SearchScope::CurrentNode);
    assert_eq!(filter.current_path.as_deref(), Some("docs/contracts"));
    assert_eq!(filter.tags, vec!["signed"]);
    assert_eq!(filter.tag_match_mode, SearchTagMatchMode::All);
    assert_eq!(filter.storage_mode, Some(StorageMode::Copied));

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

    let page = search_files(
        "/tmp/repo".to_owned(),
        "kindd:pdf".to_owned(),
        filter,
        SearchSort::NewestImported,
        pagination,
    )
    .expect("query parse diagnostics do not need repository IO");
    assert_eq!(page.query, "kindd:pdf");
    assert_eq!(page.total_count, 0);
    assert!(page.results.is_empty());
    assert_eq!(page.diagnostics[0].kind, SearchDiagnosticKind::UnknownField);
    assert_eq!(
        page.diagnostics[0].severity,
        SearchDiagnosticSeverity::Error
    );
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
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
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
        "SearchResultPage search_files(",
        "string repo_path,",
        "string query,",
        "SearchFilter filter,",
        "SearchSort sort,",
        "SearchPagination pagination",
        "dictionary SearchFilter",
        "SearchScope scope;",
        "sequence<string> tags;",
        "SearchTagMatchMode tag_match_mode;",
        "StorageMode? storage_mode;",
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
        "Searches files, paths, notes, categories, and change-log metadata.",
        "search query owns this read-only contract for search results and search sidebar empty",
        "search sidebar empty",
        "search empty state query diagnostics",
        "including tags with Any/All semantics",
        "optional storage mode",
        "does not include search facet counts",
        "saved search CRUD",
        "Smart List execution",
        "OCR, semantic search, remote AI",
        "must not modify tags, categories, notes, change log",
        "Returns `CoreError::InvalidPath { path }`",
        "`CoreError::Config { reason }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for fragment in [
        "Search scope for search queries.",
        "Structured query parser diagnostic kind.",
        "Search index readiness surfaced to search result and empty states.",
        "Filters and scope applied to a search query.",
        "Whether selected tags are matched with Any or All semantics.",
        "Optional storage-mode filter for copied, moved, or indexed entries.",
        "One page of search results.",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for error_name in ["Db", "Config", "InvalidPath"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
