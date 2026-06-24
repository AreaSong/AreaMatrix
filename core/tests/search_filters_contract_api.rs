use area_matrix_core::{
    list_filter_facets, CoreError, CoreResult, SearchDateFacetBounds, SearchFacetCount,
    SearchFacetQuery, SearchFacets, SearchScope, SearchStorageModeFacetCount, SearchTagMatchMode,
    StorageMode,
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

fn facet_query() -> SearchFacetQuery {
    SearchFacetQuery {
        query: "contract".to_owned(),
        scope: SearchScope::CurrentNode,
        current_path: Some("docs/contracts".to_owned()),
        category: Some("docs".to_owned()),
        file_kind: Some("pdf".to_owned()),
        tags: vec!["signed".to_owned(), "finance".to_owned()],
        tag_match_mode: SearchTagMatchMode::All,
        imported_after: Some(100),
        imported_before: Some(200),
        modified_after: Some(120),
        modified_before: Some(220),
        storage_mode: Some(StorageMode::Copied),
        include_deleted: Some(false),
    }
}

#[test]
fn search_filters_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_facets(_: fn(String, SearchFacetQuery) -> CoreResult<SearchFacets>) {}
    assert_facets(list_filter_facets);

    let query = facet_query();
    assert_eq!(query.scope, SearchScope::CurrentNode);
    assert_eq!(query.current_path.as_deref(), Some("docs/contracts"));
    assert_eq!(query.tags, vec!["signed", "finance"]);
    assert_eq!(query.tag_match_mode, SearchTagMatchMode::All);
    assert_eq!(query.storage_mode, Some(StorageMode::Copied));
    assert_eq!(query.include_deleted, Some(false));

    let documented_errors = [
        CoreError::db("database error"),
        CoreError::config("filter state error"),
    ];
    assert_eq!(documented_errors.len(), 2);

    let mut invalid_date = query;
    invalid_date.imported_after = Some(300);
    invalid_date.imported_before = Some(200);
    let result = list_filter_facets("/tmp/repo".to_owned(), invalid_date);
    assert!(matches!(result, Err(CoreError::Config { .. })));

    let mut invalid_scope = facet_query();
    invalid_scope.current_path = Some("../outside".to_owned());
    let result = list_filter_facets("/tmp/repo".to_owned(), invalid_scope);
    assert!(matches!(result, Err(CoreError::Config { .. })));

    let db_result = list_filter_facets("/tmp/repo".to_owned(), facet_query());
    assert!(matches!(db_result, Err(CoreError::Db { .. })));
}

#[test]
fn search_filters_contract_result_carries_filter_popover_and_tag_state() {
    let facets = SearchFacets {
        query: "contract".to_owned(),
        total_count: 24,
        categories: vec![SearchFacetCount {
            value: "docs".to_owned(),
            label: "Documents".to_owned(),
            count: 12,
            selected: true,
            disabled: false,
        }],
        file_kinds: vec![SearchFacetCount {
            value: "pdf".to_owned(),
            label: "PDF".to_owned(),
            count: 8,
            selected: true,
            disabled: false,
        }],
        tags: vec![SearchFacetCount {
            value: "finance".to_owned(),
            label: "finance".to_owned(),
            count: 24,
            selected: true,
            disabled: false,
        }],
        storage_modes: vec![SearchStorageModeFacetCount {
            value: StorageMode::Copied,
            label: "Copied".to_owned(),
            count: 18,
            selected: true,
            disabled: false,
        }],
        date_bounds: SearchDateFacetBounds {
            oldest_imported_at: Some(100),
            newest_imported_at: Some(200),
            oldest_modified_at: Some(120),
            newest_modified_at: Some(220),
        },
        active_filter_count: 5,
    };

    assert_eq!(facets.query, "contract");
    assert_eq!(facets.total_count, 24);
    assert_eq!(facets.categories[0].value, "docs");
    assert_eq!(facets.file_kinds[0].value, "pdf");
    assert_eq!(facets.tags[0].count, 24);
    assert_eq!(facets.storage_modes[0].value, StorageMode::Copied);
    assert_eq!(facets.date_bounds.newest_modified_at, Some(220));
    assert_eq!(facets.active_filter_count, 5);
}

#[test]
fn search_filters_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "SearchFacets list_filter_facets(string repo_path, SearchFacetQuery query);",
        "dictionary SearchFilter",
        "dictionary SearchFacetQuery",
        "string query;",
        "SearchTagMatchMode tag_match_mode;",
        "StorageMode? storage_mode;",
        "dictionary SearchFacetCount",
        "dictionary SearchStorageModeFacetCount",
        "dictionary SearchDateFacetBounds",
        "dictionary SearchFacets",
        "sequence<SearchFacetCount> categories;",
        "sequence<SearchFacetCount> file_kinds;",
        "sequence<SearchFacetCount> tags;",
        "sequence<SearchStorageModeFacetCount> storage_modes;",
        "SearchDateFacetBounds date_bounds;",
        "i64 active_filter_count;",
        "enum SearchTagMatchMode { \"Any\", \"All\" };",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "SearchFacets list_filter_facets(string repo_path, SearchFacetQuery query);",
        "| `list_filter_facets(repo, query)` | search | √ | Db / Config |",
        "search query `search_files`、search facets `list_filter_facets` 和 saved search",
        "### `list_filter_facets(repoPath, query) throws -> SearchFacets`",
        "`search_files` 用同一份 filter 刷新真实结果",
        "search facets 的只读 filter/facet 入口",
        "和 `search results surface search-results` 中 search facets 负责的过滤器状态。",
        "tags、Any/All tag match mode",
        "storage mode 和 include deleted。",
        "`active_filter_count`",
        "CurrentNode 缺少合法 current path",
        "不创建、更新、删除或重命名标签。",
        "不保存搜索、不创建或执行 Smart List",
        "不实现 saved search CRUD",
        "Smart List execution",
        "不会移动、删除、重命名文件，也不会触发 AI/语义过滤。",
        "facet counts 仍由 search facets",
        "`list_filter_facets`",
        "保存搜索属于 saved searches",
        "Smart List 执行属于 Smart List execution",
        "| `search_files(repo, query, filter, sort, pagination)` | search | √ | Db / Config / InvalidPath |",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn search_filters_contract_documents_consumer_states_and_scope_boundaries() {
    for fragment in [
        "Loads search filter facet counts without mutating repository state.",
        "search filters and the search facets side",
        "tag filter surface",
        "category, file kind, tags with Any/All semantics",
        "optional storage mode",
        "active-filter count",
        "does not create, update, delete, or rename tags",
        "tag CRUD",
        "does not save searches or Smart Lists",
        "saved searches",
        "Smart List execution",
        "must not modify files, notes, categories, change log",
        "generated overviews",
        "Returns `CoreError::Config { reason }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for error_name in ["Db", "Config"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
