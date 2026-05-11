use area_matrix_core::{
    create_saved_search, delete_saved_search, list_saved_searches, update_saved_search, CoreError,
    CoreResult, CreateSavedSearchRequest, SavedSearch, SavedSearchQuery, SearchFilter, SearchScope,
    SearchSort, SearchTagMatchMode, StorageMode, UpdateSavedSearchRequest,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-03-saved-search-crud.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const SAVED_SEARCH_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-03-saved-search-sheet.md");
const SMART_LISTS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-06-smart-lists.md");
const C2_04_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-04-smart-lists.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const SEARCH_RS: &str = include_str!("../src/search.rs");
const SAVED_SEARCH_RS: &str = include_str!("../src/search/saved_search.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::CurrentNode,
        current_path: Some("docs/contracts".to_owned()),
        category: Some("docs".to_owned()),
        file_kind: Some("pdf".to_owned()),
        tags: vec!["finance".to_owned()],
        tag_match_mode: SearchTagMatchMode::Any,
        imported_after: Some(100),
        imported_before: Some(200),
        modified_after: Some(120),
        modified_before: Some(220),
        storage_mode: Some(StorageMode::Copied),
        include_deleted: Some(false),
    }
}

fn saved_query() -> SavedSearchQuery {
    SavedSearchQuery {
        query: "invoice OR receipt".to_owned(),
        filter: filter(),
        sort: SearchSort::NewestModified,
    }
}

fn create_request() -> CreateSavedSearchRequest {
    CreateSavedSearchRequest {
        name: "Finance PDFs".to_owned(),
        query: saved_query(),
        icon: Some("magnifyingglass".to_owned()),
        color: Some("blue".to_owned()),
        pinned: true,
    }
}

#[test]
fn saved_search_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_create(_: fn(String, CreateSavedSearchRequest) -> CoreResult<SavedSearch>) {}
    fn assert_update(_: fn(String, UpdateSavedSearchRequest) -> CoreResult<SavedSearch>) {}
    fn assert_delete(_: fn(String, i64) -> CoreResult<()>) {}
    fn assert_list(_: fn(String) -> CoreResult<Vec<SavedSearch>>) {}

    assert_create(create_saved_search);
    assert_update(update_saved_search);
    assert_delete(delete_saved_search);
    assert_list(list_saved_searches);

    let request = create_request();
    assert_eq!(request.name, "Finance PDFs");
    assert_eq!(request.query.query, "invoice OR receipt");
    assert_eq!(request.query.filter.scope, SearchScope::CurrentNode);
    assert_eq!(request.query.filter.tags, vec!["finance"]);
    assert_eq!(request.query.sort, SearchSort::NewestModified);
    assert_eq!(request.icon.as_deref(), Some("magnifyingglass"));
    assert!(request.pinned);

    let saved = SavedSearch {
        id: 42,
        name: request.name.clone(),
        query: request.query.clone(),
        icon: request.icon.clone(),
        color: request.color.clone(),
        pinned: request.pinned,
        created_at: 1_000,
        updated_at: 1_200,
    };
    assert_eq!(saved.id, 42);
    assert_eq!(
        saved.query.filter.current_path.as_deref(),
        Some("docs/contracts")
    );
    assert_eq!(saved.query.sort, SearchSort::NewestModified);
    assert_eq!(saved.created_at, 1_000);
    assert_eq!(saved.updated_at, 1_200);

    let documented_errors = [
        CoreError::db("saved search persistence failed"),
        CoreError::config("duplicate saved search name"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn saved_search_contract_validates_without_fake_success() {
    let valid = create_saved_search("/tmp/repo".to_owned(), create_request());
    assert!(matches!(valid, Err(CoreError::Db { .. })));

    let mut empty_name = create_request();
    empty_name.name = " ".to_owned();
    assert!(matches!(
        create_saved_search("/tmp/repo".to_owned(), empty_name),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_query = create_request();
    invalid_query.query.query = "kindd:pdf".to_owned();
    assert!(matches!(
        create_saved_search("/tmp/repo".to_owned(), invalid_query),
        Err(CoreError::Config { .. })
    ));

    let update = UpdateSavedSearchRequest {
        id: 0,
        name: "Finance PDFs".to_owned(),
        query: saved_query(),
        icon: None,
        color: None,
        pinned: false,
    };
    assert!(matches!(
        update_saved_search("/tmp/repo".to_owned(), update),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        delete_saved_search("/tmp/repo".to_owned(), -1),
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        list_saved_searches(String::new()),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn saved_search_contract_mentions_real_persistence_after_implementation() {
    assert_contains(SAVED_SEARCH_RS, "db::create_saved_search_row");
    assert_contains(SAVED_SEARCH_RS, "db::update_saved_search_row");
    assert_contains(SAVED_SEARCH_RS, "db::delete_saved_search_row");
    assert_contains(SAVED_SEARCH_RS, "db::list_saved_search_rows");
    assert!(!SAVED_SEARCH_RS.contains("saved search persistence is not implemented"));
}

#[test]
fn saved_search_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-03 saved-search-crud",
        "- S2-03 saved-search-sheet",
        "- S2-06 smart-lists",
        "`create_saved_search`",
        "`update_saved_search`",
        "`delete_saved_search`",
        "`list_saved_searches`",
        "名称、query、filters、sort、scope。",
        "SavedSearch 记录。",
        "- `Db`",
        "- `Config`",
        "删除 Smart List 只删除保存查询，不删除任何文件。",
        "名称重复、非法 query、保存失败都有结构化错误。",
        "保存后可在 sidebar 恢复同一搜索条件。",
        "共享 Smart List 和跨端同步属于 Stage 4。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-03 | saved-search-sheet | C2-03 | saved search CRUD | saved_searches",
        "| S2-06 | smart-lists | C2-03, C2-04 | run/list smart lists | saved_searches",
        "搜索、filter、Smart List 不得移动、删除或改名文件。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "SavedSearch create_saved_search(string repo_path, CreateSavedSearchRequest request);",
        "SavedSearch update_saved_search(string repo_path, UpdateSavedSearchRequest request);",
        "void delete_saved_search(string repo_path, i64 saved_search_id);",
        "sequence<SavedSearch> list_saved_searches(string repo_path);",
        "dictionary SavedSearchQuery",
        "SearchFilter filter;",
        "SearchSort sort;",
        "dictionary CreateSavedSearchRequest",
        "dictionary UpdateSavedSearchRequest",
        "dictionary SavedSearch",
        "boolean pinned;",
        "i64 created_at;",
        "i64 updated_at;",
    ] {
        assert_contains(UDL, fragment);
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "| `create_saved_search(repo, request)` | search | √ | Db / Config |",
        "| `update_saved_search(repo, request)` | search | √ | Db / Config |",
        "| `delete_saved_search(repo, saved_search_id)` | search | √ | Db / Config |",
        "| `list_saved_searches(repo)` | search | √ | Db / Config |",
        "C2-03 saved search",
        "0 结果的有效搜索可以保存",
        "query 无效时必须返回结构化 `Config`",
        "该 API 不执行 Smart List、不返回 `SearchResultPage`、不实现 C2-04 `run_smart_list`",
        "Stage 2 不支持拖拽排序",
        "Smart List 打开执行属于 C2-04",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn saved_search_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "Save the current query as a Smart List. Files are not moved or duplicated.",
        "当前 `SearchQuery`、filter state、sort state。",
        "Smart List persistence API。",
        "Smart List name uniqueness check。",
        "保存成功后 Smart List 出现在 sidebar 并可点击复现查询。",
        "result count 失败不阻止保存有效查询。",
        "Edit filters 回到过滤器 draft，不直接保存 Smart List。",
    ] {
        assert_contains(SAVED_SEARCH_PAGE, fragment);
    }

    for fragment in [
        "删除 Smart List 不删除文件。",
        "Rename、Duplicate、Delete、Edit query",
        "它只是查询条件的命名入口。",
        "SavedSearchStore。",
        "SavedSearch update API。",
        "Edit query 可以修改 query、scope、filters 和 sort",
        "S2-02 在 Smart List draft context 中只改 draft",
        "Stage 2 不注册超出普通搜索字段的 Smart List",
    ] {
        assert_contains(SMART_LISTS_PAGE, fragment);
    }

    for fragment in [
        "计划新增：`run_smart_list(repo_path, saved_search_id) -> SearchResultPage`",
        "打开 Smart List 只运行查询，不改变文件。",
    ] {
        assert_contains(C2_04_SPEC, fragment);
    }

    for fragment in [
        "pub use saved_search::{",
        "create_saved_search",
        "UpdateSavedSearchRequest",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for fragment in [
        "C2-03 saved search record",
        "This API does not execute Smart Lists",
        "must not delete, move, rename, trash",
        "list_saved_searches",
    ] {
        assert_contains(SAVED_SEARCH_RS, fragment);
    }

    for error_name in ["Db", "Config"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
    }
}
