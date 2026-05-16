//! C2-05 tag CRUD contract types and validation.

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

/// Adds one normalized tag relation to an active file and returns the refreshed tag set.
///
/// C2-05 owns this single-file tag mutation contract for S2-07. The operation
/// is idempotent for duplicate tags, must write only tag metadata and a
/// change-log entry once implemented, and must never rename, move, delete,
/// trash, reclassify, reindex, or edit notes or generated overview files.
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
    validate_tag_value(&tag)?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;
    Err(CoreError::db("tag CRUD persistence is not implemented"))
}

/// Removes one tag relation from an active file and returns the refreshed tag set.
///
/// S2-07 chip deletion uses this contract to remove only the relation between
/// the current file and the tag. It does not delete the tag definition from the
/// repository registry and must not affect other files that carry the same tag.
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
    validate_tag_value(&tag)?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;
    Err(CoreError::db("tag CRUD persistence is not implemented"))
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
    Err(CoreError::db("tag CRUD persistence is not implemented"))
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

fn validate_tag_value(tag: &str) -> CoreResult<()> {
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
    Ok(())
}

fn normalize_tag_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => CoreError::db("tag metadata is unavailable"),
        other => other,
    }
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
