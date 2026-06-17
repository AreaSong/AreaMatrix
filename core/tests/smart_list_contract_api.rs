use area_matrix_core::{run_smart_list, CoreError, CoreResult, SearchPagination, SearchResultPage};

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

#[test]
fn smart_list_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_run(_: fn(String, i64, SearchPagination) -> CoreResult<SearchResultPage>) {}
    assert_run(run_smart_list);

    let pagination = SearchPagination {
        limit: 50,
        offset: 0,
    };
    assert_eq!(pagination.limit, 50);
    assert_eq!(pagination.offset, 0);

    let documented_errors = [
        CoreError::db("saved search metadata read failed"),
        CoreError::config("invalid smart list pagination"),
        CoreError::file_not_found("saved search not found"),
    ];
    assert_eq!(documented_errors.len(), 3);

    assert!(matches!(
        run_smart_list("/tmp/repo".to_owned(), 0, pagination.clone()),
        Err(CoreError::Config { .. })
    ));

    let invalid_pagination = SearchPagination {
        limit: 0,
        offset: 0,
    };
    assert!(matches!(
        run_smart_list("/tmp/repo".to_owned(), 1, invalid_pagination),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        run_smart_list("/tmp/repo".to_owned(), 1, pagination),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn smart_list_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "SearchResultPage run_smart_list(",
        "string repo_path,",
        "i64 saved_search_id,",
        "SearchPagination pagination",
        "dictionary SearchPagination",
        "dictionary SearchResultPage",
        "sequence<SearchFileResult> results;",
        "sequence<SearchQueryDiagnostic> diagnostics;",
        "SearchIndexStatus index_status;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `run_smart_list(repo, saved_search_id, pagination)` | search | √ | Db / Config / FileNotFound |",
        "### `run_smart_list(repoPath, savedSearchId, pagination) throws -> SearchResultPage`",
        "C2-04 的 Smart List 执行入口",
        "`S2-06 smart-lists`",
        "`S2-15 command-palette`",
        "Core 从 saved search 记录读取已保存的 query、完整",
        "返回与 `search_files` 相同的 `SearchResultPage`",
        "该 API 只读，不创建、更新、重命名、复制、pin 或删除 saved search 记录",
        "不写 `change_log`",
        "智能推荐、语义搜索、OCR 和远程 AI",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn smart_list_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "run_smart_list",
        "C2-04 Smart List execution",
        "SearchResultPage",
    ] {
        assert_contains(SEARCH_RS, fragment);
    }

    for fragment in [
        "Runs one C2-04 Smart List",
        "S2-06 Smart List selection",
        "S2-15 command-palette Smart List navigation",
        "must not rename, move, delete, trash",
        "Returns `CoreError::Config { reason }`",
        "Returns `CoreError::Db { message }`",
        "`CoreError::FileNotFound { path }`",
    ] {
        assert_contains(SAVED_SEARCH_RS, fragment);
    }

    for error_name in ["Db", "Config", "FileNotFound"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
