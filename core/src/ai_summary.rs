//! C3-06 AI summary contract types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_POLICY_REF_LEN: usize = 128;
const MAX_DRAFT_ID_LEN: usize = 128;
const MAX_MODEL_NAME_LEN: usize = 128;
const MAX_SUMMARY_TEXT_LEN: usize = 8_000;

/// Provider route scope allowed for one AI summary generation request.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiSummaryProviderScope {
    /// Use only local models.
    LocalOnly,
    /// Prefer local models but allow later gates to choose remote.
    LocalPreferred,
    /// Allow remote provider consideration after explicit gates pass.
    RemoteAllowed,
}

/// Maximum context extraction policy for summary generation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiSummaryContextPolicy {
    /// Use only file metadata such as name and path.
    MetadataOnly,
    /// Use metadata plus allowed extracted text excerpts.
    MetadataAndExtractedText,
    /// Use metadata, extracted text, and note/tag/category summaries.
    MetadataTextAndNotes,
}

/// AI summary input field categories that may be shown and logged.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiSummaryInputField {
    /// File name only.
    FileName,
    /// Repository-relative path category.
    RepoRelativePath,
    /// Limited extracted text excerpt category.
    ExtractedTextExcerpt,
    /// Existing AI summary category used for regeneration context.
    ExistingAiSummary,
    /// User note summary category.
    NoteSummary,
    /// Tag or category context category.
    TagCategoryContext,
}

/// AI route that produced or attempted a summary draft.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiSummaryRoute {
    /// Local model route.
    Local,
    /// Remote provider route after explicit gates.
    Remote,
}

/// Stable status for a generated AI summary draft.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiSummaryDraftStatus {
    /// A draft is available and still requires explicit save.
    Draft,
    /// Summary generation was skipped by settings or privacy gates.
    Skipped,
    /// No eligible provider, input, or call-log route is available.
    Unavailable,
}

/// Stable skipped or unavailable reason for S3-06 and fallback consumers.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiSummarySkipReason {
    /// Master AI setting is off.
    AiDisabled,
    /// Auto summaries feature is off.
    FeatureDisabled,
    /// No local or remote provider route is currently available.
    ProviderUnavailable,
    /// A privacy rule blocked all AI input fields.
    PrivacyRule,
    /// The file has no eligible safe input fields for summary generation.
    NoEligibleInput,
    /// AI call log persistence is unavailable, so generation must not proceed.
    CallLogUnavailable,
}

/// Request for generating an AI summary draft for one file.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSummaryGenerationRequest {
    /// Active file id in repository metadata.
    pub file_id: i64,
    /// Provider route scope requested by the page.
    pub provider_scope: AiSummaryProviderScope,
    /// Maximum context policy allowed by the page and privacy gate.
    pub context_policy: AiSummaryContextPolicy,
    /// Optional privacy policy reference used to evaluate AI input gates.
    pub privacy_policy_ref: Option<String>,
    /// Whether this request may replace an existing draft after confirmation.
    pub regenerate_existing: bool,
}

/// AI summary draft returned before any durable summary write.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSummaryDraft {
    /// Active file id this draft belongs to.
    pub file_id: i64,
    /// Opaque draft id for later save, when generation produced one.
    pub draft_id: Option<String>,
    /// Draft lifecycle status for S3-06 and fallback consumers.
    pub status: AiSummaryDraftStatus,
    /// Generated summary text. Empty unless `status` is `Draft`.
    pub summary_text: Option<String>,
    /// Local or remote route that produced or attempted the draft.
    pub route: Option<AiSummaryRoute>,
    /// Redacted model or provider display name.
    pub model_name: Option<String>,
    /// Unix timestamp when the draft was generated.
    pub generated_at: Option<i64>,
    /// Context fields used or allowed to be displayed.
    pub used_context: Vec<AiSummaryInputField>,
    /// Stable skipped or unavailable reason.
    pub skipped_reason: Option<AiSummarySkipReason>,
    /// Matched privacy rule id, when generation is skipped by privacy.
    pub privacy_rule_id: Option<String>,
    /// AI call log row id for traceability, when recorded by implementation.
    pub call_log_id: Option<i64>,
    /// Whether the caller must explicitly save before persisting the summary.
    pub requires_user_save: bool,
    /// Summary length in Unicode scalar count for UI counters.
    pub character_count: i64,
}

/// Request for saving a generated or user-edited AI summary draft.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSummarySaveRequest {
    /// Active file id in repository metadata.
    pub file_id: i64,
    /// Summary text to persist as AreaMatrix-owned derived metadata.
    pub summary_text: String,
    /// Opaque draft id returned by generation, when available.
    pub draft_id: Option<String>,
    /// Local or remote route that produced the original draft.
    pub route: Option<AiSummaryRoute>,
    /// Redacted model or provider display name.
    pub model_name: Option<String>,
    /// Unix timestamp when the source draft was generated.
    pub generated_at: Option<i64>,
    /// Context fields used or allowed to be displayed.
    pub used_context: Vec<AiSummaryInputField>,
    /// Matched privacy rule id, when the source draft was privacy related.
    pub privacy_rule_id: Option<String>,
    /// AI call log row id for traceability, when recorded by generation.
    pub call_log_id: Option<i64>,
    /// Whether the user edited the generated draft before saving.
    pub edited_by_user: bool,
}

/// Result of saving AI summary metadata.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSummarySaveReport {
    /// Active file id whose summary was saved.
    pub file_id: i64,
    /// Persisted summary text.
    pub saved_summary: String,
    /// Unix timestamp when the save completed.
    pub saved_at: i64,
    /// Local or remote route that produced the original draft.
    pub route: Option<AiSummaryRoute>,
    /// Redacted model or provider display name.
    pub model_name: Option<String>,
    /// Unix timestamp when the source draft was generated.
    pub generated_at: Option<i64>,
    /// Context fields used or allowed to be displayed.
    pub used_context: Vec<AiSummaryInputField>,
    /// Matched privacy rule id, when available.
    pub privacy_rule_id: Option<String>,
    /// AI call log row id for traceability, when available.
    pub call_log_id: Option<i64>,
    /// Whether the user edited the generated draft before saving.
    pub edited_by_user: bool,
    /// Summary length in Unicode scalar count for UI counters.
    pub character_count: i64,
}

/// Request for clearing AreaMatrix-owned AI summary metadata.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSummaryClearRequest {
    /// Active file id whose summary should be cleared.
    pub file_id: i64,
    /// Explicit confirmation from the caller's clear-summary sheet.
    pub confirmed: bool,
}

/// Result of clearing AI summary metadata.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSummaryClearReport {
    /// Active file id whose summary was cleared.
    pub file_id: i64,
    /// Whether a saved summary row was cleared.
    pub cleared: bool,
    /// Unix timestamp when the clear completed.
    pub cleared_at: i64,
}

pub(crate) fn generate_ai_summary(
    repo_path: String,
    request: AiSummaryGenerationRequest,
) -> CoreResult<AiSummaryDraft> {
    validate_repo_path(&repo_path)?;
    validate_generation_request(&request)?;
    Err(CoreError::db("AI summary metadata unavailable"))
}

pub(crate) fn save_ai_summary(
    repo_path: String,
    request: AiSummarySaveRequest,
) -> CoreResult<AiSummarySaveReport> {
    validate_repo_path(&repo_path)?;
    validate_save_request(&request)?;
    Err(CoreError::db("AI summary metadata unavailable"))
}

pub(crate) fn clear_ai_summary(
    repo_path: String,
    request: AiSummaryClearRequest,
) -> CoreResult<AiSummaryClearReport> {
    validate_repo_path(&repo_path)?;
    validate_clear_request(&request)?;
    Err(CoreError::db("AI summary metadata unavailable"))
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config("AI summary repository path is invalid"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "AI summary repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn validate_generation_request(request: &AiSummaryGenerationRequest) -> CoreResult<()> {
    validate_file_id(request.file_id)?;
    if let Some(reference) = request.privacy_policy_ref.as_deref() {
        validate_policy_ref(reference, "AI summary privacy policy reference is invalid")?;
    }
    Ok(())
}

fn validate_save_request(request: &AiSummarySaveRequest) -> CoreResult<()> {
    validate_file_id(request.file_id)?;
    validate_summary_text(&request.summary_text)?;
    validate_optional_identifier(&request.draft_id, "AI summary draft id is invalid")?;
    validate_optional_model_name(&request.model_name)?;
    validate_timestamp(
        request.generated_at,
        "AI summary generated timestamp is invalid",
    )?;
    validate_optional_identifier(
        &request.privacy_rule_id,
        "AI summary privacy rule id is invalid",
    )?;
    validate_optional_positive_id(request.call_log_id, "AI summary call log id is invalid")?;
    validate_unique_context(&request.used_context)
}

fn validate_clear_request(request: &AiSummaryClearRequest) -> CoreResult<()> {
    validate_file_id(request.file_id)?;
    if request.confirmed {
        Ok(())
    } else {
        Err(CoreError::config(
            "AI summary clear confirmation is required",
        ))
    }
}

fn validate_file_id(file_id: i64) -> CoreResult<()> {
    if file_id > 0 {
        Ok(())
    } else {
        Err(CoreError::config("AI summary file id is invalid"))
    }
}

fn validate_summary_text(summary: &str) -> CoreResult<()> {
    let length = summary.chars().count();
    if summary.trim().is_empty() || length > MAX_SUMMARY_TEXT_LEN || summary.contains('\0') {
        return Err(CoreError::config("AI summary text is invalid"));
    }
    Ok(())
}

fn validate_optional_identifier(value: &Option<String>, message: &str) -> CoreResult<()> {
    if let Some(identifier) = value.as_deref() {
        validate_policy_ref(identifier, message)?;
    }
    Ok(())
}

fn validate_optional_model_name(value: &Option<String>) -> CoreResult<()> {
    if let Some(name) = value.as_deref() {
        if name.trim() != name
            || name.is_empty()
            || name.len() > MAX_MODEL_NAME_LEN
            || name.contains('\0')
            || looks_sensitive(name)
        {
            return Err(CoreError::config("AI summary model name is invalid"));
        }
    }
    Ok(())
}

fn validate_timestamp(value: Option<i64>, message: &str) -> CoreResult<()> {
    match value {
        Some(timestamp) if timestamp < 0 => Err(CoreError::config(message)),
        _ => Ok(()),
    }
}

fn validate_optional_positive_id(value: Option<i64>, message: &str) -> CoreResult<()> {
    match value {
        Some(id) if id <= 0 => Err(CoreError::config(message)),
        _ => Ok(()),
    }
}

fn validate_unique_context(fields: &[AiSummaryInputField]) -> CoreResult<()> {
    for (index, field) in fields.iter().enumerate() {
        if fields[..index].contains(field) {
            return Err(CoreError::config(
                "AI summary context fields must be unique",
            ));
        }
    }
    Ok(())
}

fn validate_policy_ref(reference: &str, message: &str) -> CoreResult<()> {
    if reference.trim() != reference
        || reference.is_empty()
        || reference.len() > MAX_POLICY_REF_LEN
        || reference.len() > MAX_DRAFT_ID_LEN
        || reference.contains('\0')
        || reference.contains('/')
        || reference.contains('\\')
        || !reference.chars().all(is_policy_ref_char)
        || looks_sensitive(reference)
    {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn is_policy_ref_char(value: char) -> bool {
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
