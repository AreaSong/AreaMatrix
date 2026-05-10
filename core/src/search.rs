//! Search contract types for Stage 2 C2-01.

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult, FileEntry};

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
    /// Lower import timestamp bound.
    pub imported_after: Option<i64>,
    /// Upper import timestamp bound.
    pub imported_before: Option<i64>,
    /// Lower modified timestamp bound.
    pub modified_after: Option<i64>,
    /// Upper modified timestamp bound.
    pub modified_before: Option<i64>,
    /// Whether deleted entries should be included.
    pub include_deleted: Option<bool>,
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
/// current scope/filter state, sort mode, and pagination. The output echoes the
/// query, returns a total count, paginated file rows with highlightable match
/// metadata, parser diagnostics, and search index readiness so pages can
/// distinguish results, empty state, parse errors, API failures, and indexing
/// recovery without parsing strings.
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
    _repo_path: String,
    _query: String,
    _filter: SearchFilter,
    _sort: SearchSort,
    _pagination: SearchPagination,
) -> CoreResult<SearchResultPage> {
    Err(CoreError::config(
        "search_files implementation is owned by C2-01 implementation",
    ))
}
