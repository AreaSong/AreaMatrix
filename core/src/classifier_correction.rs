//! C2-12 classifier correction contract types and entry point.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult, FileEntry};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_CATEGORY_SLUG_LEN: usize = 32;

/// Rule draft handed off from S2-16 to classifier rule confirmation pages.
///
/// This draft is only a proposed rule basis. C2-12 must not persist it; saving
/// and impact preview stay with C2-13 and C2-14.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClassifierRuleDraft {
    /// File that produced the correction suggestion.
    pub source_file_id: i64,
    /// Target category selected in the correction sheet.
    pub target_category: String,
    /// Safe keyword candidates derived from filename or path context.
    pub keyword_candidates: Vec<String>,
    /// Safe extension candidates without leading dots.
    pub extension_candidates: Vec<String>,
    /// Suggested classifier priority for later confirmation.
    pub priority: i64,
}

/// Result returned after applying one C2-12 classifier correction.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ClassifierCorrectionResult {
    /// Updated file row after the correction is committed.
    pub updated_file: FileEntry,
    /// Optional rule draft for S2-17/S2-18 handoff; it is not saved by C2-12.
    pub rule_draft: Option<ClassifierRuleDraft>,
    /// Whether the caller requested a physical move when the entry is repo-managed.
    pub move_file_requested: bool,
    /// Whether the caller requested a future-rule handoff.
    pub remember_requested: bool,
    /// Whether the returned draft still requires explicit rule confirmation.
    pub rule_confirmation_required: bool,
}

/// Applies one classifier correction contract request.
///
/// C2-12 is the quick-correction boundary for S2-16. The contract accepts the
/// target category, an explicit move preference, and a remember flag for rule
/// draft handoff. It must not save classifier rules, preview broad rule impact,
/// create categories, call AI or network providers, or touch app-layer code.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` for invalid target categories.
/// Returns `CoreError::Db { message }` until the C2-12 implementation task
/// wires the contract to repository metadata. Later implementation tasks may
/// also return the documented `Conflict`, `Io`, and `Db` variants for safe
/// move, metadata, and change-log failures.
pub fn correct_file_category(
    repo_path: String,
    file_id: i64,
    category: String,
    move_file: bool,
    remember: bool,
) -> CoreResult<ClassifierCorrectionResult> {
    let _repo = validate_correction_repo_path(&repo_path)?;
    validate_correction_file_id(file_id)?;
    validate_category_slug(&category)?;
    let _contract_flags = (move_file, remember);
    Err(CoreError::db(
        "classifier correction implementation is not available yet",
    ))
}

fn validate_correction_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::db(
            "classifier correction metadata is unavailable",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::db(
            "classifier correction metadata is unavailable",
        ));
    }
    Ok(repo)
}

fn validate_correction_file_id(file_id: i64) -> CoreResult<()> {
    if file_id <= 0 {
        return Err(CoreError::db(
            "classifier correction file metadata is unavailable",
        ));
    }
    Ok(())
}

fn validate_category_slug(category: &str) -> CoreResult<()> {
    let trimmed = category.trim();
    if trimmed.is_empty()
        || trimmed.chars().count() > MAX_CATEGORY_SLUG_LEN
        || !is_valid_category_slug(trimmed)
    {
        return Err(CoreError::classify("target category is invalid"));
    }
    Ok(())
}

fn is_valid_category_slug(category: &str) -> bool {
    let mut chars = category.chars();
    match chars.next() {
        Some(first) if first.is_ascii_lowercase() => {}
        _ => return false,
    }
    chars.all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '-')
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
