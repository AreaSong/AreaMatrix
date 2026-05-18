//! C2-14 classifier rule impact-preview contract types and boundary.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{ClassifierRule, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_CATEGORY_SLUG_LEN: usize = 32;
const MAX_EXTENSION_LEN: usize = 16;
const MAX_KEYWORD_LEN: usize = 32;
const MIN_PRIORITY: i64 = -1000;
const MAX_PRIORITY: i64 = 1000;

/// Why an existing file is included in a classifier rule impact preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RuleImpactMatchReason {
    /// File name or path metadata matched a keyword rule basis.
    Keyword,
    /// File extension matched an extension rule basis.
    Extension,
}

/// Per-file status returned in a classifier rule impact preview sample.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RuleImpactStatus {
    /// Applying the rule would update the file category metadata.
    WillUpdate,
    /// The file already has the target category.
    AlreadyCorrect,
    /// The file requires user review before any bulk apply can proceed.
    NeedsReview,
    /// The preview found a conflict that blocks direct bulk apply.
    Conflict,
    /// The indexed file row no longer has a visible backing file.
    Missing,
    /// The file is index-only and must not be physically moved by this capability.
    IndexOnly,
}

/// Conflict class surfaced by a classifier rule impact preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RuleImpactConflictKind {
    /// A future move would collide with an existing target path.
    NameConflict,
    /// The indexed backing file is missing.
    MissingFile,
    /// The file cannot be moved or applied without review because of storage mode.
    UnsupportedStorage,
    /// Existing classifier state makes the proposed rule ambiguous.
    RuleConflict,
}

/// One file row shown in the S2-18 impact preview table.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RuleImpactSample {
    /// Stable file id for table selection and follow-up apply planning.
    pub file_id: i64,
    /// Current repository-relative or indexed path.
    pub path: String,
    /// Current category before the draft rule is applied.
    pub current_category: String,
    /// Category that the draft rule would assign.
    pub new_category: String,
    /// Matched rule basis values collapsed to stable reason classes.
    pub match_reasons: Vec<RuleImpactMatchReason>,
    /// Table status consumed by S2-18.
    pub status: RuleImpactStatus,
    /// Optional human-readable blocked or review reason.
    pub reason: Option<String>,
}

/// One conflict found while previewing a classifier rule draft.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RuleImpactConflict {
    /// File id that produced the conflict.
    pub file_id: i64,
    /// Current path when metadata can provide it.
    pub path: Option<String>,
    /// Optional conflicting target path for move-aware consumers.
    pub conflicting_path: Option<String>,
    /// Stable conflict class.
    pub kind: RuleImpactConflictKind,
    /// User-visible explanation for disabling direct bulk apply.
    pub reason: String,
}

/// Read-only classifier rule impact preview returned to S2-18.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RuleImpactReport {
    /// Draft rule used for the preview.
    pub rule: ClassifierRule,
    /// Existing files matched by the draft rule.
    pub affected_file_count: i64,
    /// Matched files whose category would change.
    pub will_update_count: i64,
    /// Matched files that already have the target category.
    pub already_correct_count: i64,
    /// Matched files requiring explicit review.
    pub needs_review_count: i64,
    /// Conflicts that block direct bulk apply.
    pub conflict_count: i64,
    /// Maximum number of sample rows included in this response.
    pub sample_limit: i64,
    /// Representative rows for the impact preview table.
    pub samples: Vec<RuleImpactSample>,
    /// Structured conflicts for disabled reasons and accessibility copy.
    pub conflicts: Vec<RuleImpactConflict>,
    /// True when any matched file requires review before apply.
    pub needs_review: bool,
    /// True when the affected count crosses the broad-impact warning threshold.
    pub warning_required: bool,
    /// Optional warning text for over-broad rules.
    pub warning: Option<String>,
    /// Whether a later apply task may proceed without additional user review.
    pub can_apply: bool,
    /// Stable disabled reason when `can_apply` is false.
    pub apply_blocked_reason: Option<String>,
}

/// Previews the impact of one classifier rule draft without saving or applying it.
///
/// C2-14 owns the read-only contract for S2-18. The function accepts the same
/// [`ClassifierRule`] draft used by rule save, validates the contract shape,
/// and returns a [`RuleImpactReport`] once the implementation task connects the
/// repository classifier matcher and file metadata reads. It must not save
/// classifier rules, apply category changes, move files, create categories,
/// write undo actions, call AI/network providers, or touch app-layer code.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths or rule
/// drafts. Returns `CoreError::Db { message }` when classifier impact metadata
/// cannot be read.
pub fn preview_classifier_rule_impact(
    repo_path: String,
    rule: ClassifierRule,
) -> CoreResult<RuleImpactReport> {
    validate_impact_request(&repo_path, &rule)?;
    Err(CoreError::db("classifier impact metadata is unavailable"))
}

fn validate_impact_request(repo_path: &str, rule: &ClassifierRule) -> CoreResult<()> {
    validate_repo_path(repo_path)?;
    validate_target_category(&rule.target_category)?;
    validate_rule_basis(rule)?;
    validate_priority(rule.priority)
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::config(
            "classifier impact repository path is required",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "classifier impact repository path is invalid",
        ));
    }
    Ok(repo)
}

fn validate_target_category(category: &str) -> CoreResult<()> {
    if !is_valid_category_slug(category) {
        return Err(CoreError::config(
            "classifier impact target category is invalid",
        ));
    }
    Ok(())
}

fn validate_rule_basis(rule: &ClassifierRule) -> CoreResult<()> {
    let mut has_basis = false;
    for keyword in &rule.keywords {
        validate_keyword(keyword)?;
        has_basis = true;
    }
    for extension in &rule.extensions {
        validate_extension(extension)?;
        has_basis = true;
    }
    if !has_basis {
        return Err(CoreError::config(
            "classifier impact rule basis is required",
        ));
    }
    ensure_unique(&rule.keywords, "classifier impact keywords must be unique")?;
    ensure_unique(
        &rule.extensions,
        "classifier impact extensions must be unique",
    )
}

fn validate_keyword(keyword: &str) -> CoreResult<()> {
    let trimmed = keyword.trim();
    if trimmed.is_empty()
        || trimmed != keyword
        || trimmed.chars().count() > MAX_KEYWORD_LEN
        || contains_forbidden_rule_character(trimmed)
    {
        return Err(CoreError::config("classifier impact keyword is invalid"));
    }
    Ok(())
}

fn validate_extension(extension: &str) -> CoreResult<()> {
    if extension.is_empty()
        || extension.chars().count() > MAX_EXTENSION_LEN
        || extension.starts_with('.')
        || !extension
            .chars()
            .all(|character| character.is_ascii_lowercase() || character.is_ascii_digit())
    {
        return Err(CoreError::config("classifier impact extension is invalid"));
    }
    Ok(())
}

fn validate_priority(priority: i64) -> CoreResult<()> {
    if (MIN_PRIORITY..=MAX_PRIORITY).contains(&priority) {
        Ok(())
    } else {
        Err(CoreError::config("classifier impact priority is invalid"))
    }
}

fn ensure_unique(values: &[String], message: &str) -> CoreResult<()> {
    let mut seen = std::collections::HashSet::new();
    for value in values {
        if !seen.insert(value.as_str()) {
            return Err(CoreError::config(message));
        }
    }
    Ok(())
}

fn is_valid_category_slug(category: &str) -> bool {
    let mut chars = category.chars();
    match chars.next() {
        Some(first) if first.is_ascii_lowercase() => {}
        _ => return false,
    }
    category.chars().count() <= MAX_CATEGORY_SLUG_LEN
        && chars.all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '-')
}

fn contains_forbidden_rule_character(value: &str) -> bool {
    value
        .chars()
        .any(|character| matches!(character, '/' | '\\' | ':' | '\0' | '\n' | '\r' | '\t'))
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
