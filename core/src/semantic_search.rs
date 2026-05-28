//! C3-08 semantic search contract types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult, SearchFileResult, SearchFilter, SearchPagination, SearchScope};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_QUERY_LEN: usize = 512;
const MAX_POLICY_REF_LEN: usize = 128;
const MAX_PROVIDER_LEN: usize = 128;
const MAX_REASON_LEN: usize = 512;

/// Local or remote route selected for a semantic search or embedding build.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SemanticSearchRoute {
    /// Local embedding and semantic index route.
    Local,
    /// Remote embedding route after explicit provider and privacy gates.
    Remote,
}

/// Field category used for semantic matching or embedding input.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SemanticSearchInputField {
    /// File name only.
    FileName,
    /// Repository-relative path category.
    RepoRelativePath,
    /// File category metadata.
    Category,
    /// User note summary or note excerpt.
    NoteSummary,
    /// AreaMatrix-owned AI summary metadata.
    AiSummary,
    /// Limited extracted text excerpt category.
    ExtractedTextExcerpt,
}

/// Semantic index lifecycle state surfaced to S3-08 and S3-10.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SemanticIndexStatus {
    /// Semantic index is ready for semantic queries.
    Ready,
    /// No semantic index exists for the requested scope.
    NotReady,
    /// Index build is currently processing.
    Building,
    /// Index build is paused by the user.
    Paused,
    /// Last index build was canceled.
    Canceled,
    /// Last index build failed.
    Failed,
    /// Some index fragments are usable, but failures or skipped files remain.
    Partial,
}

/// Stable fallback reason consumed by S3-08 and S3-10.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SemanticSearchFallbackReason {
    /// Master AI setting is off.
    AiDisabled,
    /// Semantic search feature toggle is off.
    FeatureDisabled,
    /// No local or remote provider route is currently available.
    ProviderUnavailable,
    /// Privacy rules blocked all eligible semantic input.
    PrivacyRule,
    /// Semantic index is missing or cannot serve this scope.
    SemanticIndexNotReady,
    /// AI call log persistence is unavailable.
    CallLogUnavailable,
    /// No searchable semantic input exists for this request.
    NoEligibleInput,
    /// Normal search fallback could not be loaded.
    NormalSearchUnavailable,
    /// Provider reported a stable rate limit for the selected route.
    RateLimited,
    /// Semantic search or embedding request exceeded the allowed runtime window.
    Timeout,
}

/// One semantic search match row for S3-08.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SemanticSearchMatch {
    /// File row and ordinary search match details reused by the result table.
    pub result: SearchFileResult,
    /// Semantic relevance score from 0.0 to 1.0.
    pub relevance: f32,
    /// Display-safe explanation for why this file matched.
    pub matched_reason: String,
    /// Context fields used to produce the semantic match.
    pub used_fields: Vec<SemanticSearchInputField>,
    /// Route that produced the match.
    pub route: SemanticSearchRoute,
    /// Whether the same file was also present in the normal-search group.
    pub also_matched_normal_search: bool,
    /// AI call log row id for traceability, when recorded by implementation.
    pub call_log_id: Option<i64>,
    /// Matched privacy rule id, when a skipped or redacted field affects the row.
    pub privacy_rule_id: Option<String>,
}

/// Normal-search fallback row grouped with semantic results.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SemanticNormalSearchMatch {
    /// Normal C2-01 search result for the same query and compatible filters.
    pub result: SearchFileResult,
    /// Whether S3-08 should hide this duplicate until the user expands it.
    pub deduped_by_semantic: bool,
}

/// One page of C3-08 semantic and normal search groups.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SemanticSearchResultPage {
    /// Echo of the natural-language query used for this semantic search.
    pub query: String,
    /// Semantic group total before pagination.
    pub semantic_total_count: i64,
    /// Normal-search group total before pagination and dedupe rendering.
    pub normal_total_count: i64,
    /// Semantic matches shown in the first S3-08 group.
    pub semantic_matches: Vec<SemanticSearchMatch>,
    /// Normal search matches shown in the second S3-08 group.
    pub normal_matches: Vec<SemanticNormalSearchMatch>,
    /// Number of normal rows hidden because the same file appears in semantic matches.
    pub deduped_normal_count: i64,
    /// Semantic index state for the requested scope.
    pub index_status: SemanticIndexStatus,
    /// Local or remote route used or attempted.
    pub route: Option<SemanticSearchRoute>,
    /// Stable fallback reason for S3-08 and S3-10, when semantic results are unavailable.
    pub fallback_reason: Option<SemanticSearchFallbackReason>,
    /// User-facing fallback detail without provider raw output or file contents.
    pub fallback_message: Option<String>,
    /// AI call log row id for the search attempt, when recorded by implementation.
    pub call_log_id: Option<i64>,
    /// Matched privacy rule id, when semantic search was skipped by privacy.
    pub privacy_rule_id: Option<String>,
    /// Whether any semantic result is below the high-confidence threshold.
    pub low_confidence: bool,
}

/// Scope used to build or refresh a semantic embedding index.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SemanticIndexScope {
    /// Search-compatible scope and filters for files eligible for embedding.
    pub filter: SearchFilter,
    /// Preferred route for the build. `None` lets implementation choose from AI settings.
    pub route: Option<SemanticSearchRoute>,
    /// Optional privacy policy reference used to evaluate embedding input gates.
    pub privacy_policy_ref: Option<String>,
    /// Explicit confirmation from the S3-08 build-index confirmation sheet.
    pub confirmed: bool,
}

/// Report for starting or resuming an embedding index build.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SemanticIndexBuildReport {
    /// Semantic index state after the request.
    pub status: SemanticIndexStatus,
    /// Route selected for embedding, when one is available.
    pub route: Option<SemanticSearchRoute>,
    /// Number of files in scope for this build.
    pub total_count: i64,
    /// Number of files already processed.
    pub processed_count: i64,
    /// Number of files skipped by privacy, unsupported type, or missing content.
    pub skipped_count: i64,
    /// Number of files failed with retryable or permanent errors.
    pub failed_count: i64,
    /// Number of files skipped specifically by privacy rules.
    pub privacy_skipped_count: i64,
    /// Redacted provider or model display name.
    pub provider_name: Option<String>,
    /// AI call log row id for the build attempt, when recorded by implementation.
    pub call_log_id: Option<i64>,
    /// Stable fallback or blocking reason, when the build cannot start.
    pub fallback_reason: Option<SemanticSearchFallbackReason>,
    /// User-displayable detail without raw provider output or file content.
    pub message: Option<String>,
}

/// Searches semantic index matches and normal fallback results for S3-08.
///
/// The C3-08 contract accepts the natural-language query, shared Stage 2
/// filters, and pagination state. It returns separate semantic and normal
/// groups so the UI can explain source, relevance, dedupe, and fallback state
/// without creating a mixed opaque score.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, query,
/// filters, pagination, or unsafe privacy metadata. Later implementation may
/// return `CoreError::PermissionDenied { path }` for blocked metadata or
/// content inspection, `CoreError::Db { message }` for semantic index or
/// normal search metadata failures, and `CoreError::Internal { message }` for
/// sanitized provider/runtime failures.
pub fn semantic_search(
    repo_path: String,
    query: String,
    filter: SearchFilter,
    pagination: SearchPagination,
) -> CoreResult<SemanticSearchResultPage> {
    validate_repo_path(&repo_path)?;
    validate_query(&query)?;
    validate_filter(&filter)?;
    validate_pagination(&pagination)?;
    Err(CoreError::db("semantic search index metadata unavailable"))
}

/// Starts a C3-08 semantic embedding index build after explicit confirmation.
///
/// The contract defines the build request and report shape only. A successful
/// implementation may later write AreaMatrix-owned embedding metadata and AI
/// call-log rows, but it must keep user files read-only and must not send
/// remote content unless C3-01, C3-03, C3-09, and call-log gates pass.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, scope,
/// privacy references, or missing confirmation. Later implementation may
/// return `CoreError::PermissionDenied { path }` for blocked metadata/content
/// inspection, `CoreError::Db { message }` for index metadata persistence
/// failures, and `CoreError::Internal { message }` for sanitized provider or
/// runtime failures.
pub fn build_embedding_index(
    repo_path: String,
    scope: SemanticIndexScope,
) -> CoreResult<SemanticIndexBuildReport> {
    validate_repo_path(&repo_path)?;
    validate_index_scope(&scope)?;
    Err(CoreError::db(
        "semantic embedding index metadata unavailable",
    ))
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config(
            "semantic search repository path is invalid",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "semantic search repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn validate_query(query: &str) -> CoreResult<()> {
    if query.trim().is_empty() || query.contains('\0') || query.chars().count() > MAX_QUERY_LEN {
        return Err(CoreError::config("semantic search query is invalid"));
    }
    Ok(())
}

fn validate_index_scope(scope: &SemanticIndexScope) -> CoreResult<()> {
    if !scope.confirmed {
        return Err(CoreError::config(
            "semantic index build confirmation is required",
        ));
    }
    validate_filter(&scope.filter)?;
    if let Some(reference) = scope.privacy_policy_ref.as_deref() {
        validate_identifier(
            reference,
            "semantic search privacy policy reference is invalid",
        )?;
    }
    Ok(())
}

fn validate_filter(filter: &SearchFilter) -> CoreResult<()> {
    if matches!(filter.scope, SearchScope::CurrentNode)
        && filter
            .current_path
            .as_deref()
            .is_none_or(|path| path.trim().is_empty() || path.contains('\0'))
    {
        return Err(CoreError::config(
            "semantic search current path is required for current-node scope",
        ));
    }
    if let Some(path) = filter.current_path.as_deref() {
        validate_relative_path(path, "semantic search current path is invalid")?;
    }
    validate_optional_label(&filter.category, "semantic search category is invalid")?;
    validate_optional_label(&filter.file_kind, "semantic search file kind is invalid")?;
    validate_labels(&filter.tags, "semantic search tag is invalid")?;
    validate_date_range(filter.imported_after, filter.imported_before)?;
    validate_date_range(filter.modified_after, filter.modified_before)
}

fn validate_pagination(pagination: &SearchPagination) -> CoreResult<()> {
    if (1..=200).contains(&pagination.limit) && pagination.offset >= 0 {
        Ok(())
    } else {
        Err(CoreError::config("semantic search pagination is invalid"))
    }
}

fn validate_relative_path(value: &str, message: &str) -> CoreResult<()> {
    if value.trim() != value
        || value.is_empty()
        || value.starts_with('/')
        || value.contains('\\')
        || value.contains('\0')
        || value.split('/').any(|part| part.is_empty() || part == "..")
    {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn validate_optional_label(value: &Option<String>, message: &str) -> CoreResult<()> {
    match value.as_deref() {
        Some(label) => validate_label(label, message),
        None => Ok(()),
    }
}

fn validate_labels(values: &[String], message: &str) -> CoreResult<()> {
    for value in values {
        validate_label(value, message)?;
    }
    Ok(())
}

fn validate_label(value: &str, message: &str) -> CoreResult<()> {
    if value.trim() != value
        || value.is_empty()
        || value.len() > MAX_PROVIDER_LEN
        || value.contains('\0')
        || looks_sensitive(value)
    {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn validate_date_range(after: Option<i64>, before: Option<i64>) -> CoreResult<()> {
    match (after, before) {
        (Some(start), Some(end)) if start > end => {
            Err(CoreError::config("semantic search date range is invalid"))
        }
        _ => Ok(()),
    }
}

fn validate_identifier(value: &str, message: &str) -> CoreResult<()> {
    if value.trim() != value
        || value.is_empty()
        || value.len() > MAX_POLICY_REF_LEN
        || value.contains('\0')
        || value.contains('/')
        || value.contains('\\')
        || !value.chars().all(is_identifier_char)
        || looks_sensitive(value)
    {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn is_identifier_char(value: char) -> bool {
    value.is_ascii_alphanumeric() || matches!(value, '-' | '_' | '.' | ':')
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}

fn looks_sensitive(value: &str) -> bool {
    let normalized = value.to_ascii_lowercase();
    normalized.starts_with("sk-")
        || normalized.starts_with("sk_")
        || normalized.contains("api_key")
        || normalized.contains("apikey")
        || normalized.contains("bearer")
        || normalized.contains("secret=")
        || normalized.contains("token=")
        || normalized.contains("-----begin")
        || value.chars().count() > MAX_REASON_LEN
}
