//! C3-07 AI tag suggestion contract types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{tags::TagSet, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_TAG_LEN: usize = 64;
const MAX_POLICY_REF_LEN: usize = 128;

/// AI route that produced or attempted tag suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiTagSuggestionRoute {
    /// Local model route.
    Local,
    /// Remote provider route after explicit settings and privacy gates.
    Remote,
}

/// Context fields that may be used for C3-07 tag suggestion generation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiTagSuggestionInputField {
    /// File name only.
    FileName,
    /// Repository-relative path category.
    RepoRelativePath,
    /// Limited extracted text excerpt category.
    ExtractedTextExcerpt,
    /// Existing AI summary metadata.
    AiSummary,
    /// User note summary category.
    NoteSummary,
    /// Existing tags attached to the file.
    ExistingTags,
    /// Repository tag registry candidates supplied to the AI gate.
    TagRegistry,
}

/// Stable lifecycle status for an AI tag suggestion report.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiTagSuggestionReportStatus {
    /// Suggestions are available and await explicit user review.
    Suggested,
    /// No useful tag suggestions were produced.
    NoSuggestion,
    /// Suggestion generation was skipped by settings or privacy gates.
    Skipped,
    /// No eligible provider, input, or call-log route is available.
    Unavailable,
}

/// Stable skipped or unavailable reason for S3-07 consumers.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiTagSuggestionSkipReason {
    /// Master AI setting is off.
    AiDisabled,
    /// Auto tags feature is off.
    FeatureDisabled,
    /// No local or remote provider route is currently available.
    ProviderUnavailable,
    /// A privacy rule blocked all AI input fields.
    PrivacyRule,
    /// The file has no eligible safe input fields for tag suggestion.
    NoEligibleInput,
    /// AI call log persistence is unavailable, so generation must not proceed.
    CallLogUnavailable,
}

/// Current state for one AI tag suggestion chip.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiTagSuggestionCandidateStatus {
    /// The tag can be selected and applied after review.
    Suggested,
    /// The tag is below the current high-confidence threshold.
    LowConfidence,
    /// The target file already has this tag.
    AlreadyApplied,
    /// The suggested or edited tag is invalid.
    Invalid,
    /// The suggestion is blocked by merge, privacy, or metadata preflight state.
    Blocked,
}

/// Suggested write action for one AI tag suggestion.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiTagSuggestionMergeAction {
    /// Applying the row would create a new tag registry entry.
    CreateTag,
    /// Applying the row would reuse an exact existing tag.
    UseExistingTag,
    /// The row should be merged with a similar existing tag before applying.
    MergeWithExistingTag,
}

/// Request for generating AI tag suggestions for one active file.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiTagSuggestionRequest {
    /// Active file whose metadata and allowed context should be inspected.
    pub file_id: i64,
    /// Existing or caller-provided tag candidates used to steer suggestions.
    pub candidate_tags: Vec<String>,
    /// Optional privacy policy reference used to evaluate AI input gates.
    pub privacy_policy_ref: Option<String>,
}

/// One AI tag suggestion row consumed by S3-07.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AiTagSuggestion {
    /// Stable client key for chip, edit, reject, and apply state.
    pub suggestion_id: String,
    /// Normalized tag slug to create, reuse, or merge.
    pub slug: String,
    /// Display label shown in the suggestion chip.
    pub display_name: String,
    /// Confidence score from 0.0 to 1.0.
    pub confidence: f32,
    /// User-displayable reason without raw provider output.
    pub reason: String,
    /// Row state used by S3-07 to disable invalid, low-confidence, or applied rows.
    pub status: AiTagSuggestionCandidateStatus,
    /// Whether applying this row creates, reuses, or merges a tag.
    pub merge_action: AiTagSuggestionMergeAction,
    /// Existing tag slug targeted by reuse or merge, when available.
    pub matched_existing_slug: Option<String>,
    /// Whether S3-07 may preselect the row by default.
    pub selected_by_default: bool,
    /// Optional user-facing blocked or validation reason.
    pub disabled_reason: Option<String>,
}

/// AI tag suggestion report returned before any tag write.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AiTagSuggestionReport {
    /// File whose metadata was inspected.
    pub file_id: i64,
    /// Report lifecycle state for loading, empty, skipped, and unavailable UI.
    pub status: AiTagSuggestionReportStatus,
    /// Suggested tag rows in display order.
    pub suggestions: Vec<AiTagSuggestion>,
    /// Local or remote route that produced or attempted the report.
    pub route: Option<AiTagSuggestionRoute>,
    /// Redacted model or provider display name.
    pub model_name: Option<String>,
    /// Unix timestamp when the suggestions were generated.
    pub generated_at: Option<i64>,
    /// Context fields used or allowed to be displayed.
    pub used_context: Vec<AiTagSuggestionInputField>,
    /// Stable skipped or unavailable reason.
    pub skipped_reason: Option<AiTagSuggestionSkipReason>,
    /// Matched privacy rule id, when generation is skipped by privacy.
    pub privacy_rule_id: Option<String>,
    /// AI call log row id for traceability, when recorded by implementation.
    pub call_log_id: Option<i64>,
    /// Whether the caller must explicitly review before writing tags.
    pub requires_user_confirmation: bool,
    /// Current threshold used by `Accept high confidence`.
    pub confidence_threshold: f32,
    /// Privacy boundary shown by S3-07: whether file contents were read.
    pub contents_read: bool,
    /// Privacy boundary shown by S3-07: whether AI was used.
    pub ai_used: bool,
    /// Privacy boundary shown by S3-07: whether network access was used.
    pub network_used: bool,
}

/// One reviewed or edited AI tag suggestion submitted for apply.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ApplyAiTagSuggestionItem {
    /// Suggestion identifier returned by `suggest_tags_with_ai`.
    pub suggestion_id: String,
    /// Final normalized tag slug after optional editing or merge.
    pub slug: String,
    /// Final display name after optional editing or merge.
    pub display_name: String,
    /// Confidence of the original AI suggestion, when known.
    pub confidence: f32,
    /// Whether the user edited the AI suggestion before applying it.
    pub edited_by_user: bool,
    /// Existing tag slug selected as a merge target, when applicable.
    pub merge_target_slug: Option<String>,
}

/// Request for applying reviewed C3-07 AI tag suggestions to one file.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ApplyAiTagSuggestionsRequest {
    /// Active file that receives the reviewed tags.
    pub file_id: i64,
    /// Selected or edited suggestions to apply in stable order.
    pub suggestions: Vec<ApplyAiTagSuggestionItem>,
    /// AI call log row id for provenance, when available.
    pub call_log_id: Option<i64>,
    /// Matched privacy rule id related to the source generation, when available.
    pub privacy_rule_id: Option<String>,
    /// Explicit confirmation from the caller's review or batch confirmation UI.
    pub confirmed: bool,
}

/// Status for one C3-07 apply result row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiTagSuggestionApplyStatus {
    /// The tag relation was newly applied.
    Applied,
    /// The file already had the tag relation.
    AlreadyAdded,
    /// The suggestion failed validation or persistence.
    Failed,
}

/// One C3-07 apply result row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiTagSuggestionApplyItemResult {
    /// Suggestion identifier from the apply request.
    pub suggestion_id: String,
    /// Final normalized tag slug attempted.
    pub slug: String,
    /// Per-row result status.
    pub status: AiTagSuggestionApplyStatus,
    /// Optional failure or skip detail for S3-07 recovery UI.
    pub error: Option<String>,
}

/// Report returned after applying reviewed C3-07 AI tag suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiTagSuggestionApplyReport {
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
    pub item_results: Vec<AiTagSuggestionApplyItemResult>,
    /// Refreshed tag state after the apply attempt.
    pub tag_set: TagSet,
    /// Undo token for C2-07 toast/history when at least one relation is newly added.
    pub undo_token: Option<String>,
    /// AI call log row id carried from generation or apply provenance.
    pub call_log_id: Option<i64>,
    /// Stable refresh hints for S3-07 and host detail/import-result surfaces.
    pub refresh_targets: Vec<String>,
}

pub(crate) fn suggest_tags_with_ai(
    repo_path: String,
    request: AiTagSuggestionRequest,
) -> CoreResult<AiTagSuggestionReport> {
    validate_repo_path(&repo_path)?;
    validate_suggestion_request(&request)?;
    Err(CoreError::db(
        "AI tag suggestion metadata is not available",
    ))
}

pub(crate) fn apply_ai_tag_suggestions(
    repo_path: String,
    request: ApplyAiTagSuggestionsRequest,
) -> CoreResult<AiTagSuggestionApplyReport> {
    validate_repo_path(&repo_path)?;
    validate_apply_request(&request)?;
    Err(CoreError::db("AI tag apply metadata is not available"))
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config("AI tag suggestion repository path is invalid"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "AI tag suggestion repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn validate_suggestion_request(request: &AiTagSuggestionRequest) -> CoreResult<()> {
    validate_file_id(request.file_id)?;
    validate_candidate_tags(&request.candidate_tags)?;
    if let Some(reference) = request.privacy_policy_ref.as_deref() {
        validate_identifier(reference, "AI tag suggestion privacy policy reference is invalid")?;
    }
    Ok(())
}

fn validate_apply_request(request: &ApplyAiTagSuggestionsRequest) -> CoreResult<()> {
    validate_file_id(request.file_id)?;
    if !request.confirmed {
        return Err(CoreError::config(
            "AI tag suggestion apply confirmation is required",
        ));
    }
    validate_apply_suggestions(&request.suggestions)?;
    validate_optional_positive_id(request.call_log_id, "AI tag suggestion call log id is invalid")?;
    if let Some(reference) = request.privacy_rule_id.as_deref() {
        validate_identifier(reference, "AI tag suggestion privacy rule id is invalid")?;
    }
    Ok(())
}

fn validate_file_id(file_id: i64) -> CoreResult<()> {
    if file_id > 0 {
        Ok(())
    } else {
        Err(CoreError::file_not_found(format!("file:{file_id}")))
    }
}

fn validate_candidate_tags(tags: &[String]) -> CoreResult<()> {
    let mut normalized: Vec<String> = Vec::new();
    for tag in tags {
        let slug = normalize_tag_slug(tag)?;
        if normalized.iter().any(|existing| existing == &slug) {
            return Err(CoreError::config(
                "AI tag suggestion candidate tags must be unique",
            ));
        }
        normalized.push(slug);
    }
    Ok(())
}

fn validate_apply_suggestions(suggestions: &[ApplyAiTagSuggestionItem]) -> CoreResult<()> {
    if suggestions.is_empty() {
        return Err(CoreError::config(
            "at least one AI tag suggestion must be selected",
        ));
    }
    let mut normalized: Vec<String> = Vec::new();
    for suggestion in suggestions {
        if suggestion.suggestion_id.trim().is_empty()
            || suggestion.suggestion_id.contains('\0')
            || looks_sensitive(&suggestion.suggestion_id)
        {
            return Err(CoreError::config("AI tag suggestion id is invalid"));
        }
        let slug = normalize_tag_slug(&suggestion.slug)?;
        validate_display_name(&suggestion.display_name)?;
        validate_confidence(suggestion.confidence)?;
        if let Some(target) = suggestion.merge_target_slug.as_deref() {
            normalize_tag_slug(target)?;
        }
        if normalized.iter().any(|existing| existing == &slug) {
            return Err(CoreError::config(
                "AI tag suggestion apply items must be unique",
            ));
        }
        normalized.push(slug);
    }
    Ok(())
}

fn normalize_tag_slug(value: &str) -> CoreResult<String> {
    let trimmed = value.trim();
    if trimmed.is_empty()
        || trimmed.chars().count() > MAX_TAG_LEN
        || trimmed.contains('/')
        || trimmed.contains('\\')
        || trimmed.contains(':')
        || trimmed.contains('\0')
        || trimmed.contains("://")
        || looks_sensitive(trimmed)
    {
        return Err(CoreError::config("AI tag suggestion tag is invalid"));
    }
    Ok(trimmed.to_lowercase())
}

fn validate_display_name(value: &str) -> CoreResult<()> {
    if value.trim().is_empty() || value.contains('\0') || value.chars().count() > MAX_TAG_LEN {
        return Err(CoreError::config(
            "AI tag suggestion display name is invalid",
        ));
    }
    Ok(())
}

fn validate_confidence(value: f32) -> CoreResult<()> {
    if (0.0..=1.0).contains(&value) {
        Ok(())
    } else {
        Err(CoreError::config(
            "AI tag suggestion confidence is invalid",
        ))
    }
}

fn validate_optional_positive_id(value: Option<i64>, message: &str) -> CoreResult<()> {
    match value {
        Some(id) if id <= 0 => Err(CoreError::config(message)),
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
}
