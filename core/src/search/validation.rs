use std::path::{Component, Path};

use crate::{CoreError, CoreResult, SearchFacetQuery, SearchFilter, SearchPagination, SearchScope};

const AREA_MATRIX_DIR: &str = ".areamatrix";

const MAX_LIMIT: i64 = 1000;

pub(super) fn validate_request(
    filter: &SearchFilter,
    pagination: &SearchPagination,
) -> CoreResult<()> {
    validate_optional_text(filter.category.as_deref())?;
    validate_file_kind(filter.file_kind.as_deref())?;
    validate_tags(&filter.tags)?;
    validate_time_range(filter.imported_after, filter.imported_before)?;
    validate_time_range(filter.modified_after, filter.modified_before)?;
    validate_pagination(pagination)
}

pub(super) fn validate_facet_query(query: &SearchFacetQuery) -> CoreResult<()> {
    validate_facet_scope(query)?;
    validate_optional_text(query.category.as_deref())?;
    validate_file_kind(query.file_kind.as_deref())?;
    validate_tags(&query.tags)?;
    validate_time_range(query.imported_after, query.imported_before)?;
    validate_time_range(query.modified_after, query.modified_before)
}

fn validate_facet_scope(query: &SearchFacetQuery) -> CoreResult<()> {
    match query.scope {
        SearchScope::AllRepo => Ok(()),
        SearchScope::CurrentNode => validate_facet_current_path(query.current_path.as_deref()),
    }
}

fn validate_facet_current_path(current_path: Option<&str>) -> CoreResult<()> {
    let Some(current_path) = current_path else {
        return Err(CoreError::config(
            "current path is required for current-node facets",
        ));
    };
    if current_path.trim().is_empty() || current_path.starts_with('~') {
        return Err(CoreError::config("current path is invalid"));
    }
    let path = Path::new(current_path);
    if path.is_absolute() {
        return Err(CoreError::config(
            "current path must be repository-relative",
        ));
    }
    for component in path.components() {
        match component {
            Component::Normal(part) if part != AREA_MATRIX_DIR => {}
            _ => return Err(CoreError::config("current path escapes repository scope")),
        }
    }
    Ok(())
}

fn validate_optional_text(value: Option<&str>) -> CoreResult<()> {
    if value.is_some_and(|text| text.trim().is_empty()) {
        return Err(CoreError::config("facet text filters cannot be empty"));
    }
    Ok(())
}

fn validate_file_kind(value: Option<&str>) -> CoreResult<()> {
    let Some(kind) = value else {
        return Ok(());
    };
    if kind.trim().is_empty()
        || kind.contains('/')
        || kind.contains('\\')
        || kind.contains(':')
        || kind.starts_with('.')
    {
        return Err(CoreError::config("file kind filter is invalid"));
    }
    Ok(())
}

fn validate_tags(tags: &[String]) -> CoreResult<()> {
    if tags.iter().any(|tag| tag.trim().is_empty()) {
        return Err(CoreError::config("tag filters cannot be empty"));
    }
    Ok(())
}

fn validate_time_range(after: Option<i64>, before: Option<i64>) -> CoreResult<()> {
    match (after, before) {
        (Some(after), Some(before)) if after > before => Err(CoreError::config(
            "date range lower bound must not be after upper bound",
        )),
        _ => Ok(()),
    }
}

fn validate_pagination(pagination: &SearchPagination) -> CoreResult<()> {
    if pagination.limit <= 0 || pagination.limit > MAX_LIMIT || pagination.offset < 0 {
        return Err(CoreError::config("configuration error"));
    }
    Ok(())
}
