use crate::{CoreError, CoreResult, SearchFilter, SearchPagination};

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

fn validate_optional_text(value: Option<&str>) -> CoreResult<()> {
    if value.is_some_and(|text| text.trim().is_empty()) {
        return Err(CoreError::config("configuration error"));
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
        return Err(CoreError::config("configuration error"));
    }
    Ok(())
}

fn validate_tags(tags: &[String]) -> CoreResult<()> {
    if tags.iter().any(|tag| tag.trim().is_empty()) {
        return Err(CoreError::config("configuration error"));
    }
    Ok(())
}

fn validate_time_range(after: Option<i64>, before: Option<i64>) -> CoreResult<()> {
    match (after, before) {
        (Some(after), Some(before)) if after > before => {
            Err(CoreError::config("configuration error"))
        }
        _ => Ok(()),
    }
}

fn validate_pagination(pagination: &SearchPagination) -> CoreResult<()> {
    if pagination.limit <= 0 || pagination.limit > MAX_LIMIT || pagination.offset < 0 {
        return Err(CoreError::config("configuration error"));
    }
    Ok(())
}
