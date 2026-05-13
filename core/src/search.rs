//! Search contract types for Stage 2 search capabilities.

use serde::{Deserialize, Serialize};

use crate::{CoreResult, FileEntry, StorageMode};

mod engine;
mod facets;
mod parser;
mod pinyin;
mod ranking;
mod repo;
mod saved_search;
mod validation;

pub use saved_search::{
    create_saved_search, delete_saved_search, list_saved_searches, update_saved_search,
    CreateSavedSearchRequest, SavedSearch, SavedSearchQuery, UpdateSavedSearchRequest,
};

/// Search scope for C2-01 search queries.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SearchScope {
    /// Search every active file in the repository.
    AllRepo,
    /// Search within the caller-provided current tree node.
    CurrentNode,
}

/// Stable sort modes supported by the Stage 2 search results page.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SearchSort {
    /// Rank exact matches before fuzzy and pinyin matches, then keep a stable secondary order.
    Relevance,
    /// Newest imported files first.
    NewestImported,
    /// Newest modified files first.
    NewestModified,
    /// File names sorted ascending.
    NameAsc,
}

/// Match strategy that produced a search hit.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SearchMatchKind {
    /// Case-insensitive exact token or phrase match.
    Exact,
    /// Fuzzy keyword match.
    Fuzzy,
    /// Chinese pinyin-initials match.
    PinyinInitials,
}

/// File metadata field that matched the search query.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SearchMatchField {
    /// `FileEntry.current_name` or original file name.
    Name,
    /// Repository-relative or indexed source path.
    Path,
    /// Associated markdown note content.
    Note,
    /// Category slug or display name.
    Category,
    /// Change-log filename, action, or detail payload.
    ChangeLog,
}

/// Structured query parser diagnostic kind.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SearchDiagnosticKind {
    /// Query contains an unclosed quote.
    UnclosedQuote,
    /// Query references an unsupported field.
    UnknownField,
    /// Query contains an invalid date literal.
    InvalidDate,
    /// Query contains unmatched parentheses.
    UnbalancedParentheses,
    /// Query contains an invalid operator for a supported field.
    InvalidOperator,
}

/// Query parser diagnostic severity.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SearchDiagnosticSeverity {
    /// Informational diagnostic that does not block results.
    Info,
    /// Warning diagnostic that allows results but should be surfaced.
    Warning,
    /// Error diagnostic that prevents the search request from executing.
    Error,
}

/// Search index readiness surfaced to search result and empty states.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SearchIndexStatus {
    /// Search index is ready for normal queries.
    Ready,
    /// Search index is still building, so results can be incomplete.
    Indexing,
    /// Search index cannot currently serve results.
    Unavailable,
}

/// Filters and scope applied to a C2-01 search query.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchFilter {
    /// Whether the query runs against the full repository or current tree node.
    pub scope: SearchScope,
    /// Repository-relative tree node path when `scope` is `CurrentNode`.
    pub current_path: Option<String>,
    /// Optional category slug filter.
    pub category: Option<String>,
    /// Optional file kind or extension filter, such as `pdf`.
    pub file_kind: Option<String>,
    /// Optional tag slugs carried by the search query contract.
    pub tags: Vec<String>,
    /// Whether selected tags are matched with Any or All semantics.
    pub tag_match_mode: SearchTagMatchMode,
    /// Lower import timestamp bound.
    pub imported_after: Option<i64>,
    /// Upper import timestamp bound.
    pub imported_before: Option<i64>,
    /// Lower modified timestamp bound.
    pub modified_after: Option<i64>,
    /// Upper modified timestamp bound.
    pub modified_before: Option<i64>,
    /// Optional storage-mode filter for copied, moved, or indexed entries.
    pub storage_mode: Option<StorageMode>,
    /// Whether deleted entries should be included.
    pub include_deleted: Option<bool>,
}

/// Tag matching mode used by C2-02 tag filter UI.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SearchTagMatchMode {
    /// Match files containing any selected tag.
    Any,
    /// Match files containing every selected tag.
    All,
}

/// Full filter state used when loading C2-02 facet counts.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchFacetQuery {
    /// Raw search text associated with the current search state.
    pub query: String,
    /// Whether facets are calculated for the full repository or current node.
    pub scope: SearchScope,
    /// Repository-relative tree node path when `scope` is `CurrentNode`.
    pub current_path: Option<String>,
    /// Optional category slug filter.
    pub category: Option<String>,
    /// Optional file kind or extension filter, such as `pdf`.
    pub file_kind: Option<String>,
    /// Optional tag slugs selected by S2-02 or S2-08.
    pub tags: Vec<String>,
    /// Whether selected tags are matched with Any or All semantics.
    pub tag_match_mode: SearchTagMatchMode,
    /// Lower import timestamp bound.
    pub imported_after: Option<i64>,
    /// Upper import timestamp bound.
    pub imported_before: Option<i64>,
    /// Lower modified timestamp bound.
    pub modified_after: Option<i64>,
    /// Upper modified timestamp bound.
    pub modified_before: Option<i64>,
    /// Optional storage-mode filter for copied, moved, or indexed entries.
    pub storage_mode: Option<StorageMode>,
    /// Whether deleted entries should be included.
    pub include_deleted: Option<bool>,
}

/// One selectable string facet value and its current count.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchFacetCount {
    /// Stable value written back into the matching filter field.
    pub value: String,
    /// Display label for Swift UI controls.
    pub label: String,
    /// Number of files matching this facet under the current query state.
    pub count: i64,
    /// Whether this value is active in the current query state.
    pub selected: bool,
    /// Whether the row should be disabled while still visible.
    pub disabled: bool,
}

/// Storage-mode facet value and its current count.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchStorageModeFacetCount {
    /// Storage mode represented by this facet.
    pub value: StorageMode,
    /// Display label for Swift UI controls.
    pub label: String,
    /// Number of files matching this storage mode under the current query state.
    pub count: i64,
    /// Whether this storage mode is active in the current query state.
    pub selected: bool,
    /// Whether the row should be disabled while still visible.
    pub disabled: bool,
}

/// Date bounds available to the C2-02 date filter UI.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchDateFacetBounds {
    /// Earliest import timestamp available for the current query state.
    pub oldest_imported_at: Option<i64>,
    /// Newest import timestamp available for the current query state.
    pub newest_imported_at: Option<i64>,
    /// Earliest modified timestamp available for the current query state.
    pub oldest_modified_at: Option<i64>,
    /// Newest modified timestamp available for the current query state.
    pub newest_modified_at: Option<i64>,
}

/// Facet counts and UI state needed by C2-02 search filters.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchFacets {
    /// Echo of the query text used to calculate this facet snapshot.
    pub query: String,
    /// Number of files matching the current query and filter state.
    pub total_count: i64,
    /// Category facet counts.
    pub categories: Vec<SearchFacetCount>,
    /// File kind or extension facet counts.
    pub file_kinds: Vec<SearchFacetCount>,
    /// Tag facet counts used by S2-08 without creating or deleting tags.
    pub tags: Vec<SearchFacetCount>,
    /// Storage-mode facet counts.
    pub storage_modes: Vec<SearchStorageModeFacetCount>,
    /// Date bounds for custom date-range controls.
    pub date_bounds: SearchDateFacetBounds,
    /// Number of active filters, excluding the raw search query text.
    pub active_filter_count: i64,
}

/// Pagination controls for C2-01 search results.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchPagination {
    /// Maximum number of search results to return.
    pub limit: i64,
    /// Offset for paginated search reads.
    pub offset: i64,
}

/// One highlighted match within a search result.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchMatch {
    /// Field where the match was found.
    pub field: SearchMatchField,
    /// Match strategy that produced the hit.
    pub kind: SearchMatchKind,
    /// Display snippet containing the matched token.
    pub snippet: String,
    /// Optional UTF-8 byte start offset in the snippet.
    pub start: Option<i64>,
    /// Optional UTF-8 byte end offset in the snippet.
    pub end: Option<i64>,
}

/// One file row returned by C2-01 search.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchFileResult {
    /// File metadata row displayed by the existing file list table.
    pub entry: FileEntry,
    /// Search rank score; higher values sort first in relevance mode.
    pub score: f32,
    /// Highlightable match details for the result row.
    pub matches: Vec<SearchMatch>,
    /// Optional note snippet when a note matched the query.
    pub note_snippet: Option<String>,
}

/// Structured query parser diagnostic returned with a search page.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchQueryDiagnostic {
    /// Diagnostic category.
    pub kind: SearchDiagnosticKind,
    /// Diagnostic severity.
    pub severity: SearchDiagnosticSeverity,
    /// User-facing diagnostic message.
    pub message: String,
    /// Token that caused the diagnostic, when known.
    pub token: Option<String>,
    /// Optional UTF-8 byte start offset in the original query.
    pub start: Option<i64>,
    /// Optional UTF-8 byte end offset in the original query.
    pub end: Option<i64>,
    /// Safe replacement suggestion, when the parser can provide one.
    pub suggestion: Option<String>,
}

/// One page of C2-01 search results.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SearchResultPage {
    /// Echo of the query used for this result page.
    pub query: String,
    /// Total number of matching files before pagination.
    pub total_count: i64,
    /// Paginated result rows.
    pub results: Vec<SearchFileResult>,
    /// Query parser diagnostics for S2-05 and inline search errors.
    pub diagnostics: Vec<SearchQueryDiagnostic>,
    /// Current search index readiness.
    pub index_status: SearchIndexStatus,
}

/// Searches files, paths, notes, categories, and change-log metadata.
///
/// C2-01 owns this read-only contract for S2-01 search results, S2-04 empty
/// results, and S2-05 query diagnostics. The caller supplies the raw query,
/// current scope/filter state, sort mode, and pagination. Search results accept
/// the C2-02 portion of that state, including tags with Any/All semantics and
/// optional storage mode, so filter changes can refresh the real result list
/// and facet counts from the same state. The output echoes the query, returns a
/// total count, paginated file rows with highlightable match metadata, parser
/// diagnostics, and search index readiness so pages can distinguish results,
/// empty state, parse errors, API failures, and indexing recovery without
/// parsing strings.
///
/// This contract does not include C2-02 facet counts, C2-03 saved search CRUD,
/// C2-04 Smart List execution, OCR, semantic search, remote AI, or file content
/// full-text search. It must not modify tags, categories, notes, change log,
/// repository metadata, generated overviews, or user files.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for invalid repository or scope
/// paths, `CoreError::Config { reason }` when query/filter/sort configuration
/// cannot be parsed, and `CoreError::Db { message }` when repository search
/// metadata cannot be read.
pub fn search_files(
    repo_path: String,
    query: String,
    filter: SearchFilter,
    sort: SearchSort,
    pagination: SearchPagination,
) -> CoreResult<SearchResultPage> {
    engine::search_files(repo_path, query, filter, sort, pagination)
}

/// Loads C2-02 search filter facet counts without mutating repository state.
///
/// C2-02 owns this read-only contract for S2-02 search filters and the C2-02
/// side of S2-08 tag filtering. The caller supplies the current search text and
/// filter state, including category, file kind, tags with Any/All semantics,
/// date ranges, optional storage mode, scope, and deleted-row inclusion. The
/// output returns selectable facet counts, storage-mode counts, date bounds,
/// total count, and active-filter count so Swift can show loading, empty,
/// retry, disabled, and chip states without inventing local-only contract data.
///
/// This contract does not create, update, delete, or rename tags; that belongs
/// to C2-05. It does not save searches or Smart Lists; those belong to C2-03
/// and C2-04. It must not modify files, notes, categories, change log,
/// generated overviews, repository metadata, or user-authored files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when filter state is invalid, such as
/// an invalid repository path, missing current-node path, empty category,
/// invalid file kind, empty tag, parser diagnostic, or reversed date range.
/// Returns `CoreError::Db { message }` when repository metadata required for
/// facet counts cannot be read, including permission, lock, or schema failures
/// at the SQLite metadata boundary.
pub fn list_filter_facets(repo_path: String, query: SearchFacetQuery) -> CoreResult<SearchFacets> {
    facets::list_filter_facets(repo_path, query)
}
