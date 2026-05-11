use crate::{
    CoreResult, SearchFilter, SearchIndexStatus, SearchPagination, SearchResultPage, SearchSort,
};

use super::{
    parser::{has_error_diagnostic, parse_query},
    ranking::{page_results, rank_rows, sort_ranked_rows},
    repo::{query_rows, validate_current_path, validated_repo_path},
    validation::validate_request,
};

pub(super) fn search_files(
    repo_path: String,
    query: String,
    filter: SearchFilter,
    sort: SearchSort,
    pagination: SearchPagination,
) -> CoreResult<SearchResultPage> {
    let repo = validated_repo_path(&repo_path)?;
    validate_current_path(&filter)?;
    validate_request(&filter, &pagination)?;

    let parsed = parse_query(query);
    if has_error_diagnostic(&parsed.diagnostics) {
        return Ok(SearchResultPage {
            query: parsed.raw,
            total_count: 0,
            results: Vec::new(),
            diagnostics: parsed.diagnostics,
            index_status: SearchIndexStatus::Ready,
        });
    }

    let rows = query_rows(&repo, &filter)?;
    let mut ranked = rank_rows(rows, &parsed.terms, &filter)?;
    sort_ranked_rows(&mut ranked, &sort);

    let total_count =
        i64::try_from(ranked.len()).map_err(|error| crate::CoreError::db(error.to_string()))?;
    let results = page_results(ranked, pagination)?;

    Ok(SearchResultPage {
        query: parsed.raw,
        total_count,
        results,
        diagnostics: parsed.diagnostics,
        index_status: SearchIndexStatus::Ready,
    })
}
