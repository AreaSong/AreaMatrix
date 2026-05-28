//! C3-10 AI fallback status contract types and entry point.

use serde::{Deserialize, Serialize};

use crate::{
    ai_call_log::{AiCallLogRoute, AiCallLogStatus},
    ai_classification_suggestion::AiCategorySuggestionSkipReason,
    ai_privacy_rules::{AiPrivacyDecision, AiPrivacySkippedReason},
    semantic_search::SemanticSearchFallbackReason,
    CoreResult,
};

mod validation;

/// AI operation whose failure or skipped state needs standard fallback UI.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiFallbackOperation {
    /// C3-04 AI category suggestion.
    ClassificationSuggestion,
    /// C3-08 semantic search request.
    SemanticSearch,
    /// C3-08 semantic embedding index build.
    EmbeddingIndexBuild,
}

/// Sanitized provider or runtime error category accepted by C3-10.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiFallbackProviderErrorKind {
    /// Local model is not installed, unreadable, loading, or unhealthy.
    LocalModelNotReady,
    /// Remote provider metadata or credential reference is missing.
    RemoteNotConfigured,
    /// Remote provider failed after a route was selected.
    RemoteFailed,
    /// No local or remote route can currently serve the operation.
    ProviderUnavailable,
    /// Provider rejected the request due to rate limiting.
    RateLimited,
    /// Provider or runtime exceeded the allowed execution window.
    Timeout,
    /// AI call-log persistence is unavailable for the operation.
    CallLogUnavailable,
    /// A sanitized internal runtime failure occurred.
    InternalFailure,
}

/// Stable fallback reason consumed by S3-10.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiFallbackKind {
    /// Master AI setting is disabled.
    AiDisabled,
    /// The specific AI feature is disabled.
    FeatureDisabled,
    /// Local model status prevents the operation.
    LocalModelNotReady,
    /// Remote provider is not configured or verified.
    RemoteNotConfigured,
    /// Remote provider failed after explicit route selection.
    RemoteFailed,
    /// No provider route is currently available.
    ProviderUnavailable,
    /// Privacy rules skipped the operation before sending content.
    PrivacySkipped,
    /// Semantic index is missing or not ready.
    SemanticIndexNotReady,
    /// No eligible AI input is available.
    NoEligibleInput,
    /// Normal search fallback could not be loaded.
    NormalSearchUnavailable,
    /// AI call-log persistence is unavailable.
    CallLogUnavailable,
    /// Provider rate limit is active.
    RateLimited,
    /// AI request timed out.
    Timeout,
    /// Sanitized internal fallback failure.
    InternalFailure,
}

/// Coarse display category used to distinguish skipped, disabled, and errors.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiFallbackCategory {
    /// Feature is disabled by configuration.
    Disabled,
    /// The operation was intentionally skipped.
    Skipped,
    /// Required provider, model, index, or input is unavailable.
    Unavailable,
    /// Provider or runtime failed.
    Error,
}

/// S3-10 action suggested by the fallback contract.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiFallbackAction {
    /// Retry the same operation after gates are checked again.
    Retry,
    /// Retry after the rate-limit window expires.
    RetryLater,
    /// Open AI settings.
    OpenAiSettings,
    /// Open local model status.
    OpenLocalModelStatus,
    /// Configure remote AI provider.
    ConfigureRemoteAi,
    /// Open the matched privacy rule.
    ViewPrivacyRule,
    /// Open the related AI call-log row.
    ViewCallLog,
    /// Build or refresh the semantic index.
    BuildSemanticIndex,
    /// Run ordinary search instead of semantic search.
    UseNormalSearch,
    /// Enter manual classification flow.
    ClassifyManually,
}

/// Input used to normalize AI fallback metadata for one operation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiFallbackStatusRequest {
    /// Operation that produced the fallback state.
    pub operation: AiFallbackOperation,
    /// Local or remote route that was attempted, when one was selected.
    pub route: Option<AiCallLogRoute>,
    /// Sanitized provider/runtime error category.
    pub provider_error: Option<AiFallbackProviderErrorKind>,
    /// Optional stable provider error code. It must not contain raw output or secrets.
    pub provider_error_code: Option<String>,
    /// C3-09 privacy decision available to the caller, when privacy was evaluated.
    pub privacy_decision: Option<AiPrivacyDecision>,
    /// C3-09 skipped reason available to the caller, when privacy was evaluated.
    pub privacy_skipped_reason: Option<AiPrivacySkippedReason>,
    /// C3-04 skipped reason, when the fallback came from category suggestion.
    pub category_skipped_reason: Option<AiCategorySuggestionSkipReason>,
    /// C3-08 fallback reason, when the fallback came from semantic search.
    pub semantic_fallback_reason: Option<SemanticSearchFallbackReason>,
    /// Related C3-05 log status, when the caller has a log row.
    pub call_log_status: Option<AiCallLogStatus>,
    /// Related C3-05 log row id for `View call log`.
    pub call_log_id: Option<i64>,
    /// Matched C3-09 rule id for `View privacy rule`.
    pub privacy_rule_id: Option<String>,
    /// Suggested unix timestamp before retrying rate-limited operations.
    pub retry_after: Option<i64>,
}

/// Standard AI fallback status returned to S3-10 consumers.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiFallbackStatus {
    /// Operation that produced the fallback state.
    pub operation: AiFallbackOperation,
    /// Stable fallback reason.
    pub kind: AiFallbackKind,
    /// Coarse display category.
    pub category: AiFallbackCategory,
    /// Display-safe title.
    pub title: String,
    /// Display-safe message without provider raw output, secrets, or file content.
    pub message: String,
    /// Whether retry can be offered immediately.
    pub retryable: bool,
    /// Display-safe reason when retry is disabled.
    pub retry_disabled_reason: Option<String>,
    /// Primary recovery action.
    pub primary_action: Option<AiFallbackAction>,
    /// Secondary recovery action.
    pub secondary_action: Option<AiFallbackAction>,
    /// Host-specific non-AI fallback action. Callers must render concrete labels.
    pub non_ai_fallback_action: AiFallbackAction,
    /// Local or remote route that was attempted, when one was selected.
    pub route: Option<AiCallLogRoute>,
    /// Related AI call-log id, when known.
    pub call_log_id: Option<i64>,
    /// Related privacy rule id, when known.
    pub privacy_rule_id: Option<String>,
    /// Suggested unix timestamp before retrying rate-limited operations.
    pub retry_after: Option<i64>,
}

pub(crate) fn get_ai_fallback_status(
    repo_path: String,
    request: AiFallbackStatusRequest,
) -> CoreResult<AiFallbackStatus> {
    validation::validate_repo_path(&repo_path)?;
    validation::validate_request(&request)?;
    Ok(status_from_request(request))
}

fn status_from_request(request: AiFallbackStatusRequest) -> AiFallbackStatus {
    let kind = fallback_kind(&request);
    let category = fallback_category(&kind);
    let retryable = retryable(&kind, request.retry_after);
    AiFallbackStatus {
        operation: request.operation.clone(),
        title: title(&kind).to_owned(),
        message: message(&kind).to_owned(),
        retry_disabled_reason: retry_disabled_reason(&kind, retryable).map(str::to_owned),
        primary_action: primary_action(&kind, request.privacy_rule_id.as_deref()),
        secondary_action: secondary_action(&kind, request.call_log_id),
        non_ai_fallback_action: non_ai_fallback_action(&request.operation),
        route: request.route,
        call_log_id: request.call_log_id,
        privacy_rule_id: request.privacy_rule_id,
        retry_after: request.retry_after,
        kind,
        category,
        retryable,
    }
}

fn fallback_kind(request: &AiFallbackStatusRequest) -> AiFallbackKind {
    if privacy_skipped(request) {
        return AiFallbackKind::PrivacySkipped;
    }
    if let Some(reason) = request.semantic_fallback_reason.as_ref() {
        return kind_from_semantic_reason(reason);
    }
    if let Some(reason) = request.category_skipped_reason.as_ref() {
        return kind_from_category_reason(reason);
    }
    if let Some(error) = request.provider_error.as_ref() {
        return kind_from_provider_error(error);
    }
    if matches!(request.call_log_status, Some(AiCallLogStatus::Failed)) {
        return AiFallbackKind::RemoteFailed;
    }
    if matches!(request.call_log_status, Some(AiCallLogStatus::Unavailable)) {
        return AiFallbackKind::ProviderUnavailable;
    }
    AiFallbackKind::InternalFailure
}

fn privacy_skipped(request: &AiFallbackStatusRequest) -> bool {
    matches!(
        request.privacy_decision,
        Some(AiPrivacyDecision::Denied | AiPrivacyDecision::Skipped)
    ) || matches!(
        request.privacy_skipped_reason,
        Some(AiPrivacySkippedReason::PrivacyRule | AiPrivacySkippedReason::FieldRule)
    )
}

fn kind_from_semantic_reason(reason: &SemanticSearchFallbackReason) -> AiFallbackKind {
    match reason {
        SemanticSearchFallbackReason::AiDisabled => AiFallbackKind::AiDisabled,
        SemanticSearchFallbackReason::FeatureDisabled => AiFallbackKind::FeatureDisabled,
        SemanticSearchFallbackReason::ProviderUnavailable => AiFallbackKind::ProviderUnavailable,
        SemanticSearchFallbackReason::PrivacyRule => AiFallbackKind::PrivacySkipped,
        SemanticSearchFallbackReason::SemanticIndexNotReady => {
            AiFallbackKind::SemanticIndexNotReady
        }
        SemanticSearchFallbackReason::CallLogUnavailable => AiFallbackKind::CallLogUnavailable,
        SemanticSearchFallbackReason::NoEligibleInput => AiFallbackKind::NoEligibleInput,
        SemanticSearchFallbackReason::NormalSearchUnavailable => {
            AiFallbackKind::NormalSearchUnavailable
        }
        SemanticSearchFallbackReason::RateLimited => AiFallbackKind::RateLimited,
        SemanticSearchFallbackReason::Timeout => AiFallbackKind::Timeout,
    }
}

fn kind_from_category_reason(reason: &AiCategorySuggestionSkipReason) -> AiFallbackKind {
    match reason {
        AiCategorySuggestionSkipReason::AiDisabled => AiFallbackKind::AiDisabled,
        AiCategorySuggestionSkipReason::FeatureDisabled => AiFallbackKind::FeatureDisabled,
        AiCategorySuggestionSkipReason::RuleResultConfident
        | AiCategorySuggestionSkipReason::NoEligibleContext => AiFallbackKind::NoEligibleInput,
        AiCategorySuggestionSkipReason::PrivacyRule => AiFallbackKind::PrivacySkipped,
        AiCategorySuggestionSkipReason::ProviderUnavailable => AiFallbackKind::ProviderUnavailable,
    }
}

fn kind_from_provider_error(error: &AiFallbackProviderErrorKind) -> AiFallbackKind {
    match error {
        AiFallbackProviderErrorKind::LocalModelNotReady => AiFallbackKind::LocalModelNotReady,
        AiFallbackProviderErrorKind::RemoteNotConfigured => AiFallbackKind::RemoteNotConfigured,
        AiFallbackProviderErrorKind::RemoteFailed => AiFallbackKind::RemoteFailed,
        AiFallbackProviderErrorKind::ProviderUnavailable => AiFallbackKind::ProviderUnavailable,
        AiFallbackProviderErrorKind::RateLimited => AiFallbackKind::RateLimited,
        AiFallbackProviderErrorKind::Timeout => AiFallbackKind::Timeout,
        AiFallbackProviderErrorKind::CallLogUnavailable => AiFallbackKind::CallLogUnavailable,
        AiFallbackProviderErrorKind::InternalFailure => AiFallbackKind::InternalFailure,
    }
}

fn fallback_category(kind: &AiFallbackKind) -> AiFallbackCategory {
    match kind {
        AiFallbackKind::AiDisabled | AiFallbackKind::FeatureDisabled => {
            AiFallbackCategory::Disabled
        }
        AiFallbackKind::PrivacySkipped => AiFallbackCategory::Skipped,
        AiFallbackKind::RemoteFailed
        | AiFallbackKind::RateLimited
        | AiFallbackKind::Timeout
        | AiFallbackKind::InternalFailure => AiFallbackCategory::Error,
        _ => AiFallbackCategory::Unavailable,
    }
}

fn retryable(kind: &AiFallbackKind, retry_after: Option<i64>) -> bool {
    matches!(kind, AiFallbackKind::RemoteFailed | AiFallbackKind::Timeout)
        || matches!(kind, AiFallbackKind::RateLimited if retry_after.is_some())
}

fn primary_action(
    kind: &AiFallbackKind,
    privacy_rule_id: Option<&str>,
) -> Option<AiFallbackAction> {
    match kind {
        AiFallbackKind::LocalModelNotReady => Some(AiFallbackAction::OpenLocalModelStatus),
        AiFallbackKind::RemoteNotConfigured => Some(AiFallbackAction::ConfigureRemoteAi),
        AiFallbackKind::PrivacySkipped if privacy_rule_id.is_some() => {
            Some(AiFallbackAction::ViewPrivacyRule)
        }
        AiFallbackKind::SemanticIndexNotReady => Some(AiFallbackAction::BuildSemanticIndex),
        AiFallbackKind::RateLimited => Some(AiFallbackAction::RetryLater),
        AiFallbackKind::RemoteFailed | AiFallbackKind::Timeout => Some(AiFallbackAction::Retry),
        AiFallbackKind::AiDisabled | AiFallbackKind::FeatureDisabled => {
            Some(AiFallbackAction::OpenAiSettings)
        }
        _ => None,
    }
}

fn secondary_action(kind: &AiFallbackKind, call_log_id: Option<i64>) -> Option<AiFallbackAction> {
    if call_log_id.is_some()
        && matches!(
            kind,
            AiFallbackKind::PrivacySkipped
                | AiFallbackKind::RemoteFailed
                | AiFallbackKind::RateLimited
                | AiFallbackKind::Timeout
                | AiFallbackKind::CallLogUnavailable
                | AiFallbackKind::InternalFailure
        )
    {
        return Some(AiFallbackAction::ViewCallLog);
    }
    match kind {
        AiFallbackKind::RemoteNotConfigured
        | AiFallbackKind::RemoteFailed
        | AiFallbackKind::ProviderUnavailable => Some(AiFallbackAction::OpenAiSettings),
        AiFallbackKind::SemanticIndexNotReady => Some(AiFallbackAction::UseNormalSearch),
        _ => None,
    }
}

fn non_ai_fallback_action(operation: &AiFallbackOperation) -> AiFallbackAction {
    match operation {
        AiFallbackOperation::ClassificationSuggestion => AiFallbackAction::ClassifyManually,
        AiFallbackOperation::SemanticSearch | AiFallbackOperation::EmbeddingIndexBuild => {
            AiFallbackAction::UseNormalSearch
        }
    }
}

fn title(kind: &AiFallbackKind) -> &'static str {
    match kind {
        AiFallbackKind::AiDisabled => "AI is off",
        AiFallbackKind::FeatureDisabled => "AI feature is off",
        AiFallbackKind::LocalModelNotReady => "Local model is not ready",
        AiFallbackKind::RemoteNotConfigured => "Remote AI is not configured",
        AiFallbackKind::RemoteFailed => "Remote AI could not be reached",
        AiFallbackKind::ProviderUnavailable => "AI provider is unavailable",
        AiFallbackKind::PrivacySkipped => "Skipped by privacy rule",
        AiFallbackKind::SemanticIndexNotReady => "Semantic index is not ready",
        AiFallbackKind::NoEligibleInput => "No eligible AI input",
        AiFallbackKind::NormalSearchUnavailable => "Normal search is unavailable",
        AiFallbackKind::CallLogUnavailable => "AI call log is unavailable",
        AiFallbackKind::RateLimited => "Provider rate limit reached",
        AiFallbackKind::Timeout => "AI request timed out",
        AiFallbackKind::InternalFailure => "AI fallback status is unavailable",
    }
}

fn message(kind: &AiFallbackKind) -> &'static str {
    match kind {
        AiFallbackKind::PrivacySkipped => {
            "This item matches a privacy rule, so no AI content was sent."
        }
        AiFallbackKind::SemanticIndexNotReady => "Semantic index is not ready yet.",
        AiFallbackKind::RemoteFailed => {
            "Remote AI could not be reached. Your files were not changed."
        }
        AiFallbackKind::LocalModelNotReady => "The local model is not installed or still loading.",
        AiFallbackKind::RateLimited => "The provider asked AreaMatrix to retry later.",
        AiFallbackKind::Timeout => "The AI request timed out. Your files were not changed.",
        AiFallbackKind::AiDisabled => "AI is disabled in repository settings.",
        AiFallbackKind::FeatureDisabled => "This AI feature is disabled in repository settings.",
        AiFallbackKind::RemoteNotConfigured => {
            "Remote AI must be configured before this route can run."
        }
        AiFallbackKind::ProviderUnavailable => "No AI provider route is currently available.",
        AiFallbackKind::NoEligibleInput => "There is no eligible safe input for this AI operation.",
        AiFallbackKind::NormalSearchUnavailable => "Normal search fallback could not be loaded.",
        AiFallbackKind::CallLogUnavailable => "AI fallback could not be recorded in the call log.",
        AiFallbackKind::InternalFailure => {
            "Fallback status could not be resolved from safe metadata."
        }
    }
}

fn retry_disabled_reason(kind: &AiFallbackKind, retryable: bool) -> Option<&'static str> {
    if retryable {
        return None;
    }
    match kind {
        AiFallbackKind::PrivacySkipped => {
            Some("Retry is disabled because privacy rules blocked the input")
        }
        AiFallbackKind::RateLimited => {
            Some("Retry is disabled until the provider allows another attempt")
        }
        AiFallbackKind::AiDisabled | AiFallbackKind::FeatureDisabled => {
            Some("Retry is disabled while AI is turned off")
        }
        AiFallbackKind::RemoteNotConfigured => {
            Some("Retry is disabled until remote AI is configured")
        }
        AiFallbackKind::SemanticIndexNotReady => {
            Some("Retry is disabled until the semantic index is ready")
        }
        _ => Some("Retry is unavailable for this fallback state"),
    }
}
