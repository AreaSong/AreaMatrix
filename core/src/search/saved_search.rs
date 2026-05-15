use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::{
    db, CoreError, CoreResult, SearchFilter, SearchPagination, SearchResultPage, SearchSort,
};

use super::{parser, repo, validation};

const MAX_SAVED_SEARCH_NAME_LEN: usize = 64;
const MAX_SAVED_SEARCH_ICON_LEN: usize = 64;
const MAX_SAVED_SEARCH_COLOR_LEN: usize = 64;

/// Stable sort and filter payload saved by C2-03 Smart List CRUD.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SavedSearchQuery {
    /// Raw search text to restore when opening a saved search.
    pub query: String,
    /// Search and filter state saved with the Smart List.
    pub filter: SearchFilter,
    /// Sort mode restored with the saved search.
    pub sort: SearchSort,
}

/// Input used to create a C2-03 saved search record.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CreateSavedSearchRequest {
    /// User-visible Smart List name.
    pub name: String,
    /// Query, filter, scope, and sort state to persist.
    pub query: SavedSearchQuery,
    /// Optional icon identifier chosen by the UI.
    pub icon: Option<String>,
    /// Optional color token chosen by the UI.
    pub color: Option<String>,
    /// Whether the Smart List is pinned in the sidebar.
    pub pinned: bool,
}

/// Input used to update an existing C2-03 saved search record.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct UpdateSavedSearchRequest {
    /// Stable saved search identifier.
    pub id: i64,
    /// Replacement user-visible Smart List name.
    pub name: String,
    /// Replacement query, filter, scope, and sort state.
    pub query: SavedSearchQuery,
    /// Replacement icon identifier.
    pub icon: Option<String>,
    /// Replacement color token.
    pub color: Option<String>,
    /// Replacement sidebar pin state.
    pub pinned: bool,
}

/// Saved search record returned to S2-03 and S2-06 consumers.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SavedSearch {
    /// Stable saved search identifier.
    pub id: i64,
    /// User-visible Smart List name.
    pub name: String,
    /// Persisted query, filter, scope, and sort state.
    pub query: SavedSearchQuery,
    /// Optional icon identifier.
    pub icon: Option<String>,
    /// Optional color token.
    pub color: Option<String>,
    /// Whether the Smart List is pinned in the sidebar.
    pub pinned: bool,
    /// Creation timestamp used for sidebar ordering and audit UI.
    pub created_at: i64,
    /// Last update timestamp used for edit recovery and sorting.
    pub updated_at: i64,
}

/// Creates a C2-03 saved search record without touching user files.
///
/// S2-03 uses this contract to persist the current query/filter/sort/scope
/// state as a sidebar Smart List. The returned [`SavedSearch`] carries enough
/// state for S2-06 to insert and select the new row without inventing local
/// fields. Implementations must enforce unique names, persist only saved-search
/// metadata, and never move, duplicate, rename, delete, retag, reclassify, or
/// reindex repository files.
///
/// This API does not execute Smart Lists or return search results; that belongs
/// to C2-04 Smart List execution.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the repository path or saved
/// search payload is invalid, including empty or duplicate names, names over 64
/// characters, query parser diagnostics, invalid filter state, or invalid
/// display metadata. Returns `CoreError::Db { message }` when saved-search
/// metadata cannot be read or persisted.
pub fn create_saved_search(
    repo_path: String,
    request: CreateSavedSearchRequest,
) -> CoreResult<SavedSearch> {
    let repo = validate_saved_search_repo_path(&repo_path)?;
    validate_create_saved_search_request(&request)?;
    db::create_saved_search_row(&repo, &request)
}

/// Updates a C2-03 saved search record without executing it.
///
/// S2-06 uses this contract for rename, pin, icon/color, and edit-query
/// management flows. A successful implementation updates only the matching
/// saved-search row and leaves SearchState execution to the consumer after the
/// update has committed.
///
/// This API must not create a second Smart List, mutate tags/categories/files,
/// update `change_log`, or run the saved search query.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the id, repository path, name,
/// query, filter, sort, or display metadata is invalid. Returns
/// `CoreError::Db { message }` when the saved search is missing, the name is
/// duplicated, or metadata cannot be persisted.
pub fn update_saved_search(
    repo_path: String,
    request: UpdateSavedSearchRequest,
) -> CoreResult<SavedSearch> {
    let repo = validate_saved_search_repo_path(&repo_path)?;
    validate_update_saved_search_request(&request)?;
    db::update_saved_search_row(&repo, &request)
}

/// Deletes one C2-03 saved search record.
///
/// S2-06 uses this destructive-looking action only to remove the saved query
/// metadata. It must not delete, move, rename, trash, retag, reclassify, or
/// reindex any file, even when the Smart List currently has matching results.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the repository path or id is
/// invalid. Returns `CoreError::Db { message }` when the saved search is
/// missing or metadata deletion cannot be persisted.
pub fn delete_saved_search(repo_path: String, saved_search_id: i64) -> CoreResult<()> {
    let repo = validate_saved_search_repo_path(&repo_path)?;
    validate_saved_search_id(saved_search_id)?;
    db::delete_saved_search_row(&repo, saved_search_id)
}

/// Lists C2-03 saved search metadata for sidebar Smart Lists.
///
/// S2-06 uses this read-only contract to render the Smart Lists section,
/// management menus, pin state, query recovery warnings, and empty/list-error
/// states. Implementations should return pinned records first and remaining
/// records by name using the Stage 2 ordering rule.
///
/// This API only reads saved-search metadata. Smart List execution and result
/// pages belong to C2-04 and must call search execution explicitly.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the repository path is invalid.
/// Returns `CoreError::Db { message }` when saved-search metadata cannot be
/// read.
pub fn list_saved_searches(repo_path: String) -> CoreResult<Vec<SavedSearch>> {
    let repo = validate_saved_search_repo_path(&repo_path)?;
    db::list_saved_search_rows(&repo)
}

/// Runs one C2-04 Smart List and returns its search result page.
///
/// C2-04 owns this read-only contract for S2-06 Smart List selection and
/// S2-15 command-palette Smart List navigation. The caller supplies a saved
/// search id and pagination; Core loads the saved `query`, `filter`, and `sort`
/// state, then returns the same [`SearchResultPage`] shape as `search_files` so
/// consumers can render results, empty state, query diagnostics, index status,
/// and API errors without inventing local-only state.
///
/// Implementations must only read saved-search metadata and repository search
/// rows. Running a Smart List must not rename, move, delete, trash, retag,
/// reclassify, reindex, duplicate, write `change_log`, update generated
/// overviews, call AI/semantic search, or modify user files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the repository path, saved
/// search id, or pagination is invalid. Returns `CoreError::Db { message }`
/// when saved-search metadata or search rows cannot be read. Returns
/// `CoreError::FileNotFound { path }` when the saved search id has no matching
/// row.
pub fn run_smart_list(
    repo_path: String,
    saved_search_id: i64,
    pagination: SearchPagination,
) -> CoreResult<SearchResultPage> {
    validate_saved_search_repo_path(&repo_path)?;
    validate_saved_search_id(saved_search_id)?;
    validate_smart_list_pagination(&pagination)?;
    Err(CoreError::db("smart list execution is not implemented"))
}

pub(crate) fn validate_saved_search_id(id: i64) -> CoreResult<()> {
    if id <= 0 {
        return Err(CoreError::config(
            "saved search id must be a positive integer",
        ));
    }
    Ok(())
}

pub(crate) fn validate_create_saved_search_request(
    request: &CreateSavedSearchRequest,
) -> CoreResult<()> {
    validate_saved_search_name(&request.name)?;
    validate_saved_search_query(&request.query)?;
    validate_saved_search_optional_text(request.icon.as_deref(), MAX_SAVED_SEARCH_ICON_LEN)?;
    validate_saved_search_optional_text(request.color.as_deref(), MAX_SAVED_SEARCH_COLOR_LEN)
}

pub(crate) fn validate_update_saved_search_request(
    request: &UpdateSavedSearchRequest,
) -> CoreResult<()> {
    validate_saved_search_id(request.id)?;
    validate_saved_search_name(&request.name)?;
    validate_saved_search_query(&request.query)?;
    validate_saved_search_optional_text(request.icon.as_deref(), MAX_SAVED_SEARCH_ICON_LEN)?;
    validate_saved_search_optional_text(request.color.as_deref(), MAX_SAVED_SEARCH_COLOR_LEN)
}

fn validate_saved_search_name(name: &str) -> CoreResult<()> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err(CoreError::config("saved search name is required"));
    }
    if trimmed.chars().count() > MAX_SAVED_SEARCH_NAME_LEN {
        return Err(CoreError::config(
            "saved search name must be at most 64 characters",
        ));
    }
    Ok(())
}

fn validate_saved_search_query(query: &SavedSearchQuery) -> CoreResult<()> {
    if parser::has_error_diagnostic(&parser::parse_query(query.query.clone()).diagnostics) {
        return Err(CoreError::config(
            "saved search query contains parser diagnostics",
        ));
    }
    repo::validate_current_path(&query.filter)
        .map_err(|_| CoreError::config("saved search filter state is invalid"))?;
    validation::validate_filter(&query.filter)
}

fn validate_saved_search_optional_text(value: Option<&str>, max_len: usize) -> CoreResult<()> {
    let Some(value) = value else {
        return Ok(());
    };
    if value.trim().is_empty() || value.chars().count() > max_len {
        return Err(CoreError::config(
            "saved search display metadata is invalid",
        ));
    }
    Ok(())
}

fn validate_saved_search_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::config(
            "saved search repository path is required",
        ));
    }
    Ok(PathBuf::from(repo_path))
}

fn validate_smart_list_pagination(pagination: &SearchPagination) -> CoreResult<()> {
    if pagination.limit <= 0 || pagination.limit > 1000 || pagination.offset < 0 {
        return Err(CoreError::config("smart list pagination is invalid"));
    }
    Ok(())
}
