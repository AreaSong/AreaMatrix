//! C2-05 and C2-06 tag contract behavior and types.

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

/// Defines the C2-06 batch tag mutation contract without performing batch writes yet.
///
/// S2-09 uses this API to add one or more normalized tags to a multi-selection
/// and S2-10 consumes the returned undo token when a later implementation
/// persists undo metadata. The report shape carries added, already-present, and
/// failed item counts so UI can render partial failure summaries without
/// treating skipped or failed files as successful writes.
///
/// This contract intentionally stops before DB mutation in the contract/API
/// task. The C2-06 implementation task must replace the final persistence
/// boundary with real writes to `tags`, `change_log`, and the C2-07 undo action
/// store. The contract must never move, rename, delete, trash, reclassify,
/// reindex, edit notes, update generated overviews, call AI/network providers,
/// or touch user file contents.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when no valid target file id is
/// supplied. Returns `CoreError::Db { message }` when repository tag metadata is
/// unavailable, tag input cannot be normalized for the batch contract, or the
/// C2-06 persistence task has not yet connected real batch writes.
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

    let _contract_shape = BatchMutationReport {
        requested_file_count: normalized_file_ids.len() as i64,
        requested_tag_count: normalized_tags.len() as i64,
        added_count: 0,
        skipped_count: 0,
        failed_count: 0,
        item_results: Vec::new(),
        undo_token: None,
    };
    Err(CoreError::db(
        "batch tag mutation persistence is defined by C2-06 implementation task",
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
