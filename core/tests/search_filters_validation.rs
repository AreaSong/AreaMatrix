#[path = "support/search_filters_validation.rs"]
mod validation_support;

use area_matrix_core::{
    list_filter_facets, search_files, CoreError, CoreResult, SearchFacetQuery, SearchFacets,
    SearchScope, SearchSort, StorageMode,
};
use pretty_assertions::assert_eq;
use validation_support::{
    assert_capability_spec_alignment, assert_combined_facets, assert_config_error,
    assert_consumer_docs_alignment, assert_control_map_alignment,
    assert_core_api_and_udl_alignment, assert_rust_contract_alignment, assert_search_config_error,
    combined_query, default_query, first_page, initialized_repo, insert_file, insert_tag,
    path_string, search_filter_from_query, seed_combined_facets, snapshot,
};

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
fn search_filters_validation_proves_same_c2_02_state_drives_results_and_facets() {
    let repo = initialized_repo();
    seed_combined_facets(repo.path());
    let mut query = combined_query();
    query.storage_mode = Some(StorageMode::Copied);
    let filter = search_filter_from_query(&query);

    let facets = list_filter_facets(path_string(repo.path()), query.clone()).expect("load facets");
    let page = search_files(
        path_string(repo.path()),
        query.query,
        filter,
        SearchSort::NewestImported,
        first_page(),
    )
    .expect("search files with full C2-02 filter state");

    assert_eq!(facets.total_count, 1);
    assert_eq!(page.total_count, facets.total_count);
    assert_eq!(page.results[0].entry.current_name, "client-contract.pdf");
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
    assert_config_error(list_filter_facets(
        path_string(repo.path()),
        reversed_date.clone(),
    ));
    assert_search_config_error(search_files(
        path_string(repo.path()),
        reversed_date.query.clone(),
        search_filter_from_query(&reversed_date),
        SearchSort::Relevance,
        first_page(),
    ));

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
