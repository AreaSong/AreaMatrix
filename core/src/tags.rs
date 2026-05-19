//! C2-05, C2-06, and C2-19 tag contract behavior and types.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{db, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_TAG_LEN: usize = 64;

/// One tag visible to Stage 2 tag editing and filtering surfaces.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagRecord {
    /// Normalized stable tag value used in search filters and DB rows.
    pub value: String,
    /// Display label shown by Swift tag chips and rows.
    pub label: String,
    /// Number of active files currently carrying this tag.
    pub file_count: i64,
    /// Whether the target file already has this tag.
    pub selected: bool,
    /// Whether UI should show the row but prevent adding/removing it.
    pub disabled: bool,
    /// Last known mutation timestamp for sorting recent tags.
    pub updated_at: i64,
}

/// Tag state returned by C2-05 tag CRUD operations.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSet {
    /// File whose tag relation is being edited or inspected.
    pub file_id: i64,
    /// Tags currently attached to the file after the requested operation.
    pub file_tags: Vec<TagRecord>,
    /// Repository tag registry candidates for S2-07 and S2-08.
    pub available_tags: Vec<TagRecord>,
    /// Recently used tags for the S2-07 empty-input state.
    pub recent_tags: Vec<TagRecord>,
    /// Unix timestamp for the latest tag relation change visible in this snapshot.
    pub updated_at: i64,
}

/// Per file/tag status returned by C2-06 batch tag mutation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchMutationStatus {
    /// The tag relation was newly added for this file.
    Added,
    /// The file already had the tag relation, so no duplicate row was written.
    AlreadyHadTag,
    /// The mutation failed for this file/tag pair.
    Failed,
}

/// Per file/tag result row returned by C2-06 batch tag mutation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BatchMutationItemResult {
    /// File id from the request.
    pub file_id: i64,
    /// Normalized tag value attempted for this file.
    pub tag: String,
    /// Stable status used by S2-09 to separate added, skipped, and failed rows.
    pub status: BatchMutationStatus,
    /// Optional failure detail for result summaries and retry UI.
    pub error: Option<String>,
}

/// Batch mutation report returned to S2-09 and Undo toast consumers.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BatchMutationReport {
    /// Number of unique file ids accepted by the contract.
    pub requested_file_count: i64,
    /// Number of unique normalized tags accepted by the contract.
    pub requested_tag_count: i64,
    /// Number of newly added file/tag relations.
    pub added_count: i64,
    /// Number of already-existing relations skipped without duplicate writes.
    pub skipped_count: i64,
    /// Number of failed file/tag relation attempts.
    pub failed_count: i64,
    /// Detailed per item results for partial failure summaries.
    pub item_results: Vec<BatchMutationItemResult>,
    /// Undo token for C2-07 toast/history when the implementation creates one.
    pub undo_token: Option<String>,
}

/// Source that produced one deterministic C2-19 tag suggestion.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum TagSuggestionSource {
    /// The suggestion came from the current file name.
    FileName,
    /// The suggestion came from the repository-relative path.
    Path,
    /// The suggestion came from the imported source directory.
    SourceFolder,
    /// The suggestion reused or mirrored an existing tag pattern.
    ExistingTagPattern,
}

/// Deterministic match strength for one C2-19 tag suggestion.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum TagSuggestionMatch {
    /// Exact normalized token match and safe to preselect.
    Strong,
    /// Partial or inferred deterministic match that needs explicit selection.
    Weak,
}

/// Current write/readiness state for one C2-19 suggestion row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum TagSuggestionStatus {
    /// The suggested tag can be applied.
    NewTag,
    /// The target file already has this tag.
    AlreadyAdded,
    /// The suggested or edited tag is invalid.
    Invalid,
    /// The suggestion is blocked by read-only metadata or another preflight issue.
    Blocked,
}

/// Optional context used when generating deterministic C2-19 suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionContext {
    /// Optional source directory captured by import flows.
    pub source_folder: Option<String>,
    /// Optional importer-provided keywords that already passed privacy review.
    pub source_keywords: Vec<String>,
}

/// Request for deterministic C2-19 tag suggestions for one active file.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionRequest {
    /// Active file whose metadata should be inspected.
    pub file_id: i64,
    /// Optional source context from import-result consumers.
    pub context: Option<TagSuggestionContext>,
    /// Maximum number of suggestions to return after normalization and dedupe.
    pub limit: i64,
}

/// One C2-19 tag suggestion row consumed by S2-23.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestion {
    /// Stable client key for checkbox/edit state.
    pub suggestion_id: String,
    /// Normalized tag slug to create or reuse.
    pub slug: String,
    /// Display label shown in the suggestion row.
    pub display_name: String,
    /// Human-readable explanation for the suggestion.
    pub reason: String,
    /// Source metadata bucket used for deterministic generation.
    pub source: TagSuggestionSource,
    /// Strong suggestions can be preselected; weak suggestions require user choice.
    pub match_strength: TagSuggestionMatch,
    /// Whether an equivalent tag already exists in the repository registry.
    pub already_exists: bool,
    /// Whether applying this row would create a new tag registry entry.
    pub needs_create: bool,
    /// Row state for disabled/error UI.
    pub status: TagSuggestionStatus,
    /// Whether S2-23 may preselect this suggestion by default.
    pub selected_by_default: bool,
    /// Optional user-facing blocked or validation reason.
    pub disabled_reason: Option<String>,
}

/// Result returned when S2-23 asks Core for C2-19 suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionReport {
    /// File whose metadata was inspected.
    pub file_id: i64,
    /// Deterministic suggestions in display order.
    pub suggestions: Vec<TagSuggestion>,
    /// Current tag state, so S2-23 can show already-added rows and avoid duplicate writes.
    pub tag_set: TagSet,
    /// Privacy boundary shown by S2-23: no file content read.
    pub contents_read: bool,
    /// Privacy boundary shown by S2-23: no AI or remote provider called.
    pub ai_used: bool,
    /// Privacy boundary shown by S2-23: no network access.
    pub network_used: bool,
}

/// One selected or edited suggestion submitted for C2-19 apply.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ApplyTagSuggestionItem {
    /// Suggestion identifier returned by `suggest_tags_for_file`.
    pub suggestion_id: String,
    /// Final normalized tag slug after optional editing.
    pub slug: String,
    /// Final display name after optional editing.
    pub display_name: String,
}

/// Request for applying selected C2-19 tag suggestions to one file.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ApplyTagSuggestionsRequest {
    /// Active file that receives the selected tags.
    pub file_id: i64,
    /// Selected or edited suggestions to apply in stable order.
    pub suggestions: Vec<ApplyTagSuggestionItem>,
}

/// Status for one C2-19 apply result row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum TagSuggestionApplyStatus {
    /// The tag relation was newly applied.
    Applied,
    /// The file already had the tag relation.
    AlreadyAdded,
    /// The suggestion failed validation or persistence.
    Failed,
}

/// One C2-19 apply result row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionApplyItemResult {
    /// Suggestion identifier from the apply request.
    pub suggestion_id: String,
    /// Final normalized tag slug attempted.
    pub slug: String,
    /// Per-row result status.
    pub status: TagSuggestionApplyStatus,
    /// Optional failure or skip detail for S2-23 recovery UI.
    pub error: Option<String>,
}

/// Report returned after applying C2-19 selected tag suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionApplyReport {
    /// File whose tags were mutated.
    pub file_id: i64,
    /// Number of selected suggestions accepted by the contract.
    pub requested_count: i64,
    /// Number of newly applied tag relations.
    pub applied_count: i64,
    /// Number of already-present relations skipped without duplicate writes.
    pub skipped_count: i64,
    /// Number of failed suggestion rows.
    pub failed_count: i64,
    /// Detailed per-suggestion results for partial failure UI.
    pub item_results: Vec<TagSuggestionApplyItemResult>,
    /// Refreshed tag state after the apply attempt.
    pub tag_set: TagSet,
    /// Undo token for C2-07 toast/history when at least one relation was newly added.
    pub undo_token: Option<String>,
    /// Stable refresh hints for S2-23 and host detail/import-result surfaces.
    pub refresh_targets: Vec<String>,
}

/// Adds one normalized tag relation to an active file and returns the refreshed tag set.
///
/// C2-05 owns this single-file tag mutation contract for S2-07. The operation
/// is idempotent for duplicate tags, must write only tag metadata and a
/// change-log entry with `kind = tag_added` when the relation changes, and
/// must never rename, move, delete, trash, reclassify, reindex, or edit notes
/// or generated overview files.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` when the repository path or tag is
/// invalid, `CoreError::FileNotFound { path }` when the file id is not an
/// active file, and `CoreError::Db { message }` when tag metadata cannot be
/// read or persisted.
pub fn add_tag(repo_path: String, file_id: i64, tag: String) -> CoreResult<TagSet> {
    let repo = validate_tag_repo_path(&repo_path)?;
    validate_file_id(file_id)?;
    let normalized = normalize_tag_value(&tag)?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;
    db::add_tag_row(&repo, file_id, &normalized).map_err(normalize_tag_metadata_error)
}

/// Removes one tag relation from an active file and returns the refreshed tag set.
///
/// S2-07 chip deletion uses this contract to remove only the relation between
/// the current file and the tag. It does not delete the tag definition from the
/// repository registry and must not affect other files that carry the same tag.
/// The change-log detail uses `kind = tag_removed` when the relation changes.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` when the repository path or tag is
/// invalid, `CoreError::FileNotFound { path }` when the file id is not an
/// active file, and `CoreError::Db { message }` when tag metadata cannot be
/// read or persisted.
pub fn remove_tag(repo_path: String, file_id: i64, tag: String) -> CoreResult<TagSet> {
    let repo = validate_tag_repo_path(&repo_path)?;
    validate_file_id(file_id)?;
    let normalized = normalize_tag_value(&tag)?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;
    db::remove_tag_row(&repo, file_id, &normalized).map_err(normalize_tag_metadata_error)
}

/// Lists the tag registry and the selected file tag state without mutating metadata.
///
/// S2-07 uses this contract for current chips, existing candidates, recent
/// tags, loading, empty, and retry states. S2-08 may use the same registry
/// snapshot as a complement to C2-02 facet counts. The query is read-only: it
/// must not create, update, remove, rename, or suggest tags.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` when the repository path is
/// invalid, `CoreError::FileNotFound { path }` when the file id is not an
/// active file, and `CoreError::Db { message }` when tag metadata cannot be
/// read.
pub fn list_tags(repo_path: String, file_id: i64) -> CoreResult<TagSet> {
    let repo = validate_tag_repo_path(&repo_path)?;
    validate_file_id(file_id)?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;
    db::list_tag_set(&repo, file_id).map_err(normalize_tag_metadata_error)
}

/// Adds normalized tags to multiple active files and returns a mutation report.
///
/// C2-06 batch tag mutation contract.
///
/// S2-09 uses this API to add one or more normalized tags to a multi-selection
/// and S2-10 consumes the returned undo token after successful writes. The
/// report shape carries added, already-present, and failed item counts so UI
/// can render partial failure summaries without treating skipped or failed
/// files as successful writes.
///
/// The implementation performs real writes to `tags`, `change_log`, and the C2-07 undo action
/// store. It must never move, rename, delete, trash, reclassify, reindex, edit notes, update
/// generated overviews, call AI/network providers, or touch user file contents.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when no valid target file id is
/// supplied. Returns `CoreError::Db { message }` when repository tag metadata is
/// unavailable, tag input cannot be normalized for the batch contract, or the
/// batch mutation cannot be persisted.
pub fn batch_add_tags(
    repo_path: String,
    file_ids: Vec<i64>,
    tags: Vec<String>,
) -> CoreResult<BatchMutationReport> {
    let repo = validate_tag_repo_path(&repo_path)
        .map_err(|_| CoreError::db("batch tag metadata is unavailable for this repository path"))?;
    let normalized_file_ids = normalize_batch_file_ids(&file_ids)?;
    let normalized_tags = normalize_batch_tags(&tags)?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;
    db::batch_add_tags_rows(&repo, &normalized_file_ids, &normalized_tags)
        .map_err(normalize_tag_metadata_error)
}

/// Suggests deterministic non-AI tags for one active file.
///
/// C2-19 owns the Stage 2 tag-suggestion contract for S2-23. Suggestions may
/// inspect file metadata, repository-relative path, optional import source
/// context, and existing tag registry state. They must not read file contents,
/// call AI or remote providers, access the network, write metadata, mutate
/// files, change filters, or touch app-layer code.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when `file_id` is invalid or the
/// active file cannot be found, `CoreError::Validation { reason }` when the
/// request limit or context is invalid, `CoreError::Conflict { path }` when
/// metadata cannot produce a deterministic suggestion state, and
/// `CoreError::Db { message }` when tag or file metadata cannot be read.
pub fn suggest_tags_for_file(
    repo_path: String,
    request: TagSuggestionRequest,
) -> CoreResult<TagSuggestionReport> {
    let repo = validate_tag_repo_path(&repo_path)?;
    validate_file_id(request.file_id)?;
    validate_suggestion_limit(request.limit)?;
    validate_suggestion_context(request.context.as_ref())?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;
    Err(CoreError::db(
        "tag suggestion metadata is not implemented until C2-19 implementation",
    ))
}

/// Applies selected C2-19 tag suggestions to one active file.
///
/// The apply contract creates or reuses normalized tags, writes file/tag
/// relations, emits change-log rows, and returns an undo token for C2-07 when
/// at least one new relation is written. It must never apply unselected
/// suggestions, update search filters, move/rename/delete files, read file
/// contents, call AI/network providers, or modify app-layer code.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when the file id is invalid or
/// absent, `CoreError::Validation { reason }` when selected/edited suggestions
/// are empty or invalid, `CoreError::Conflict { path }` when duplicate edited
/// suggestions cannot be applied deterministically, and `CoreError::Db {
/// message }` when tag metadata, change-log, or undo writes fail.
pub fn apply_tag_suggestions(
    repo_path: String,
    request: ApplyTagSuggestionsRequest,
) -> CoreResult<TagSuggestionApplyReport> {
    let repo = validate_tag_repo_path(&repo_path)?;
    validate_file_id(request.file_id)?;
    validate_apply_suggestions(&request.suggestions)?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;
    Err(CoreError::db(
        "tag suggestion apply is not implemented until C2-19 implementation",
    ))
}

fn validate_tag_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("repository path is required"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::invalid_path("repository path is invalid"));
    }
    Ok(repo)
}

fn validate_suggestion_limit(limit: i64) -> CoreResult<()> {
    if !(1..=50).contains(&limit) {
        return Err(CoreError::validation("tag suggestion limit must be 1..50"));
    }
    Ok(())
}

fn validate_suggestion_context(context: Option<&TagSuggestionContext>) -> CoreResult<()> {
    let Some(context) = context else {
        return Ok(());
    };
    if let Some(source_folder) = context.source_folder.as_deref() {
        validate_context_text(source_folder, "source folder")?;
    }
    for keyword in &context.source_keywords {
        validate_context_text(keyword, "source keyword")?;
    }
    Ok(())
}

fn validate_context_text(value: &str, label: &str) -> CoreResult<()> {
    let trimmed = value.trim();
    if trimmed.is_empty()
        || trimmed.chars().count() > 128
        || trimmed.contains('\0')
        || trimmed.contains("://")
    {
        return Err(CoreError::validation(format!(
            "tag suggestion {label} is invalid"
        )));
    }
    Ok(())
}

fn validate_apply_suggestions(suggestions: &[ApplyTagSuggestionItem]) -> CoreResult<Vec<String>> {
    if suggestions.is_empty() {
        return Err(CoreError::validation(
            "at least one tag suggestion must be selected",
        ));
    }
    let mut slugs = Vec::new();
    for suggestion in suggestions {
        if suggestion.suggestion_id.trim().is_empty() {
            return Err(CoreError::validation("suggestion id is required"));
        }
        let slug = normalize_suggestion_slug(&suggestion.slug)?;
        if suggestion.display_name.trim().is_empty() || suggestion.display_name.contains('\0') {
            return Err(CoreError::validation(
                "tag suggestion display name is invalid",
            ));
        }
        if slugs.iter().any(|existing| existing == &slug) {
            return Err(CoreError::conflict(format!("tag:{slug}")));
        }
        slugs.push(slug);
    }
    Ok(slugs)
}

fn normalize_suggestion_slug(slug: &str) -> CoreResult<String> {
    normalize_tag_value(slug).map_err(|_| CoreError::validation("tag suggestion slug is invalid"))
}

fn validate_file_id(file_id: i64) -> CoreResult<()> {
    if file_id <= 0 {
        return Err(CoreError::file_not_found(format!("file:{file_id}")));
    }
    Ok(())
}

fn normalize_tag_value(tag: &str) -> CoreResult<String> {
    let trimmed = tag.trim();
    if trimmed.is_empty()
        || trimmed.chars().count() > MAX_TAG_LEN
        || trimmed.contains('/')
        || trimmed.contains('\\')
        || trimmed.contains(':')
        || trimmed.contains('\0')
    {
        return Err(CoreError::invalid_path("tag name is invalid"));
    }
    Ok(trimmed.to_lowercase())
}

fn normalize_batch_file_ids(file_ids: &[i64]) -> CoreResult<Vec<i64>> {
    let mut normalized = Vec::new();
    for file_id in file_ids {
        validate_file_id(*file_id)?;
        if !normalized.iter().any(|existing| existing == file_id) {
            normalized.push(*file_id);
        }
    }
    if normalized.is_empty() {
        return Err(CoreError::file_not_found("file:empty"));
    }
    Ok(normalized)
}

fn normalize_batch_tags(tags: &[String]) -> CoreResult<Vec<String>> {
    let mut normalized = Vec::new();
    for tag in tags {
        let value =
            normalize_tag_value(tag).map_err(|_| CoreError::db("batch tag input is invalid"))?;
        if !normalized.iter().any(|existing| existing == &value) {
            normalized.push(value);
        }
    }
    if normalized.is_empty() {
        return Err(CoreError::db("batch tag input is empty"));
    }
    Ok(normalized)
}

fn normalize_tag_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => CoreError::db("tag metadata is unavailable"),
        CoreError::PermissionDenied { .. } => CoreError::db("tag metadata permission denied"),
        CoreError::Io { .. } => CoreError::db("tag metadata io unavailable"),
        other => other,
    }
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
