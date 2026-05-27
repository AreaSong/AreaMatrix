//! C3-04 AI classification suggestion contract types.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_POLICY_REF_LEN: usize = 128;

/// Context extraction policy allowed for AI category suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCategorySuggestionContextPolicy {
    /// Use only the current filename and extension.
    FileNameOnly,
    /// Use filename, extension, and repository-relative path.
    FileNameAndPath,
    /// Use filename, path, and a limited sanitized text summary when allowed.
    LimitedTextSummary,
}

/// Context fields reported back to the page and AI call log.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCategorySuggestionContextField {
    /// The current filename.
    FileName,
    /// The current file extension.
    Extension,
    /// The repository-relative path.
    RepoRelativePath,
    /// A limited sanitized text summary.
    LimitedTextSummary,
}

/// AI execution route that produced or attempted the suggestion.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCategorySuggestionRoute {
    /// A local model route.
    Local,
    /// A remote provider route after explicit gates.
    Remote,
}

/// Stable status for the classification suggestion panel.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCategorySuggestionStatus {
    /// A category suggestion is available and awaits user confirmation.
    Suggested,
    /// No AI suggestion should be shown for the current rule result.
    NoSuggestion,
    /// AI suggestion generation was skipped by a privacy or settings gate.
    Skipped,
    /// AI suggestion generation is unavailable until settings or provider state changes.
    Unavailable,
}

/// Stable skipped or unavailable reason for S3-04 and S3-10 consumers.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCategorySuggestionSkipReason {
    /// Master AI setting is off.
    AiDisabled,
    /// Classification suggestions feature is off.
    FeatureDisabled,
    /// Existing rule classification is confident enough.
    RuleResultConfident,
    /// The file or request did not provide enough safe context.
    NoEligibleContext,
    /// A privacy rule blocked all AI input fields.
    PrivacyRule,
    /// No local or remote provider route is currently available.
    ProviderUnavailable,
}

/// Request for generating an AI classification suggestion for one file.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiCategorySuggestionRequest {
    /// Active file id in repository metadata.
    pub file_id: i64,
    /// Maximum context extraction policy the caller allows.
    pub context_policy: AiCategorySuggestionContextPolicy,
    /// Optional privacy policy reference used to evaluate AI input gates.
    pub privacy_policy_ref: Option<String>,
}

/// AI classification suggestion result shown before any category write.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AiCategorySuggestion {
    /// Active file id this suggestion belongs to.
    pub file_id: i64,
    /// Suggestion status for S3-04 and fallback consumers.
    pub status: AiCategorySuggestionStatus,
    /// Current category before user confirmation, when known.
    pub current_category: Option<String>,
    /// Suggested target category. Empty unless `status` is `Suggested`.
    pub suggested_category: Option<String>,
    /// Confidence score from 0.0 to 1.0.
    pub confidence: f32,
    /// User-displayable reason without raw provider output.
    pub reason: Option<String>,
    /// Local or remote route that produced or attempted the suggestion.
    pub route: Option<AiCategorySuggestionRoute>,
    /// Context fields used or skipped by the AI gate.
    pub used_context: Vec<AiCategorySuggestionContextField>,
    /// Stable skipped or unavailable reason.
    pub skipped_reason: Option<AiCategorySuggestionSkipReason>,
    /// Matched privacy rule id, when the suggestion is skipped by privacy.
    pub privacy_rule_id: Option<String>,
    /// AI call log row id for traceability, when recorded by implementation.
    pub call_log_id: Option<i64>,
    /// Whether the caller must wait for explicit user confirmation before writing category.
    pub requires_user_confirmation: bool,
}

pub(crate) fn suggest_category_with_ai(
    repo_path: String,
    request: AiCategorySuggestionRequest,
) -> CoreResult<AiCategorySuggestion> {
    validate_repo_path(&repo_path)?;
    validate_request(&request)?;
    Err(CoreError::config(
        "AI classification suggestion implementation is pending",
    ))
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config(
            "AI classification suggestion repository path is invalid",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "AI classification suggestion repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn validate_request(request: &AiCategorySuggestionRequest) -> CoreResult<()> {
    if request.file_id <= 0 {
        return Err(CoreError::config(
            "AI classification suggestion file id is invalid",
        ));
    }
    if let Some(reference) = request.privacy_policy_ref.as_deref() {
        validate_policy_ref(reference)?;
    }
    Ok(())
}

fn validate_policy_ref(reference: &str) -> CoreResult<()> {
    if reference.trim() != reference
        || reference.is_empty()
        || reference.len() > MAX_POLICY_REF_LEN
        || reference.contains('\0')
        || reference.contains('/')
        || reference.contains('\\')
        || !reference.chars().all(is_policy_ref_char)
        || looks_sensitive(reference)
    {
        return Err(CoreError::config(
            "AI classification suggestion privacy policy reference is invalid",
        ));
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
