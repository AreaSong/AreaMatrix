//! C3-09 AI privacy rules contract types and entry points.

mod evaluation;
mod persistence;
mod validation;

use serde::{Deserialize, Serialize};

use crate::{AiFeatureKind, CoreResult};
use validation::{validate_evaluation_request, validate_repo_path, validate_update_request};

/// Privacy rule matcher kind supported by C3-09.
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum AiPrivacyRuleKind {
    /// Repository-relative folder prefix.
    Folder,
    /// Existing classifier category.
    Category,
    /// Keyword checked against allowed metadata or derived text fields.
    Keyword,
    /// File extension such as `.key`.
    Extension,
    /// Existing tag registry item.
    Tag,
}

/// Route scope affected by one privacy rule.
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum AiPrivacyRuleAppliesTo {
    /// Rule blocks only remote AI input.
    #[serde(rename = "Remote AI", alias = "RemoteAi", alias = "remote")]
    RemoteAi,
    /// Rule blocks both local and remote AI input.
    #[serde(
        rename = "Local and remote AI",
        alias = "LocalAndRemoteAi",
        alias = "local_and_remote"
    )]
    LocalAndRemoteAi,
}

/// Local or remote route being evaluated by C3-09.
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum AiPrivacyEvaluationRoute {
    /// Local model route.
    Local,
    /// Remote provider route after provider and privacy gates.
    Remote,
}

/// AI input field category controlled by remote field filtering.
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum AiPrivacyInputField {
    /// File name only.
    FileName,
    /// Repository-relative path.
    RepoRelativePath,
    /// File extension.
    Extension,
    /// Limited extracted text excerpt.
    ExtractedTextExcerpt,
    /// AreaMatrix-owned AI summary metadata.
    AiSummary,
    /// Derived note summary. Full note text is not part of this contract.
    NoteSummary,
    /// Tag and category context.
    TagCategoryContext,
}

/// Final privacy decision for one AI attempt.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiPrivacyDecision {
    /// AI may use the returned `sent_fields`.
    Allowed,
    /// A privacy rule or field filter blocked this attempt.
    Denied,
    /// Provider or privacy gate state skipped the attempt before content use.
    Skipped,
}

/// Stable skip or deny reason shown by AI pages and fallback surfaces.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiPrivacySkippedReason {
    /// Global remote privacy gate is off.
    PrivacyGateDisabled,
    /// Requested feature is outside the remote provider feature scope.
    ScopeNotAllowed,
    /// Remote provider metadata is absent.
    ProviderNotConfigured,
    /// Remote provider exists but has not passed verification.
    ProviderNotVerified,
    /// Remote provider gate is disabled.
    ProviderDisabled,
    /// A directory, category, keyword, extension, or tag rule matched.
    PrivacyRule,
    /// A requested remote input field is blocked.
    FieldRule,
    /// No requested AI input field remains eligible.
    NoEligibleInput,
}

/// Provider-gate reason reported separately from rule matching.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiPrivacyProviderGateReason {
    /// Global remote privacy gate is off.
    PrivacyGateDisabled,
    /// Requested feature is outside the remote provider feature scope.
    ScopeNotAllowed,
    /// Remote provider metadata is absent.
    ProviderNotConfigured,
    /// Remote provider exists but has not passed verification.
    ProviderNotVerified,
    /// Remote provider gate is disabled.
    ProviderDisabled,
}

/// Editable privacy rule payload accepted by S3-09.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyRuleInput {
    /// Stable rule id. New rules may omit it until persistence assigns one.
    pub rule_id: Option<String>,
    /// User-visible rule name.
    pub name: String,
    /// Matcher kind.
    pub kind: AiPrivacyRuleKind,
    /// Rule pattern interpreted by `kind`.
    pub pattern: String,
    /// Route scope affected by this rule.
    pub applies_to: AiPrivacyRuleAppliesTo,
    /// Whether the rule currently participates in evaluation.
    pub enabled: bool,
    /// Optional user-visible description.
    pub description: Option<String>,
}

/// Persisted rule row returned by `list_ai_privacy_rules`.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyRuleRecord {
    /// Stable persisted rule id.
    #[serde(rename = "id", alias = "rule_id")]
    pub rule_id: String,
    /// User-visible rule name.
    pub name: String,
    /// Matcher kind.
    pub kind: AiPrivacyRuleKind,
    /// Rule pattern interpreted by `kind`.
    pub pattern: String,
    /// Route scope affected by this rule.
    pub applies_to: AiPrivacyRuleAppliesTo,
    /// Whether the rule currently participates in evaluation.
    pub enabled: bool,
    /// Optional user-visible description.
    pub description: Option<String>,
    /// Estimated matching file count for S3-09 list rows.
    pub match_count: i64,
    /// Last matched timestamp, when known.
    pub last_matched_at: Option<i64>,
}

/// Remote field setting submitted by S3-09.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyFieldRule {
    /// Field controlled by this setting.
    pub field: AiPrivacyInputField,
    /// Whether remote AI may receive this field after all other gates pass.
    pub allow_remote: bool,
}

/// Remote field state returned by S3-09 list snapshots.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyFieldState {
    /// Field controlled by this setting.
    pub field: AiPrivacyInputField,
    /// Whether remote AI may receive this field after all other gates pass.
    pub allow_remote: bool,
    /// Number of recent attempts blocked by this field setting.
    pub last_matched_count: i64,
}

/// Read-only C3-03 provider scope consumed by C3-09.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyProviderScopeSnapshot {
    /// Whether provider metadata is configured.
    pub provider_configured: bool,
    /// Whether provider metadata has passed connection verification.
    pub provider_verified: bool,
    /// Whether the remote provider gate is enabled.
    pub remote_provider_enabled: bool,
    /// AI feature scope allowed to use the remote provider.
    pub feature_scope: Vec<AiFeatureKind>,
}

/// Privacy rules snapshot consumed by S3-09.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyRulesSnapshot {
    /// Global remote privacy gate.
    pub privacy_gate_enabled: bool,
    /// Persisted privacy rules.
    pub rules: Vec<AiPrivacyRuleRecord>,
    /// Remote input-field controls.
    pub remote_allowed_fields: Vec<AiPrivacyFieldState>,
    /// Read-only provider gate snapshot from C3-03.
    pub provider_scope: AiPrivacyProviderScopeSnapshot,
    /// Last update timestamp, when persistence provides one.
    pub updated_at: Option<i64>,
    /// Whether the default policy blocks remote AI until explicit consent.
    pub remote_blocked_by_default: bool,
}

/// Replace-style update request for the C3-09 rules contract.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyRulesUpdateRequest {
    /// Desired global remote privacy gate state.
    pub privacy_gate_enabled: bool,
    /// Complete editable rule set.
    pub rules: Vec<AiPrivacyRuleInput>,
    /// Complete remote field settings.
    pub remote_allowed_fields: Vec<AiPrivacyFieldRule>,
    /// Read-only provider state used to validate gate enablement.
    pub provider_scope: AiPrivacyProviderScopeSnapshot,
    /// Explicit confirmation from the save or block-remote action.
    pub confirmed: bool,
}

/// File or metadata context for one privacy evaluation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyEvaluationContext {
    /// Active file id, when the evaluation is tied to one file row.
    pub file_id: Option<i64>,
    /// Repository-relative path, when already known to the caller.
    pub repo_relative_path: Option<String>,
    /// File display name, when already known to the caller.
    pub file_name: Option<String>,
    /// Category slug, when already known to the caller.
    pub category: Option<String>,
    /// File extension, when already known to the caller.
    pub extension: Option<String>,
    /// Existing tags, when already known to the caller.
    pub tags: Vec<String>,
}

/// Request for evaluating whether one AI attempt may use candidate fields.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyEvaluationRequest {
    /// AI feature requesting input.
    pub feature: AiFeatureKind,
    /// Local or remote route to evaluate.
    pub route: AiPrivacyEvaluationRoute,
    /// Candidate input fields requested by the AI feature.
    pub requested_fields: Vec<AiPrivacyInputField>,
    /// Global remote privacy gate at the time of evaluation.
    pub privacy_gate_enabled: bool,
    /// Read-only provider scope at the time of evaluation.
    pub provider_scope: AiPrivacyProviderScopeSnapshot,
    /// Rule set to evaluate.
    pub rules: Vec<AiPrivacyRuleInput>,
    /// Remote input-field controls to evaluate.
    pub remote_allowed_fields: Vec<AiPrivacyFieldRule>,
    /// File or metadata context used by later implementation matching.
    pub context: AiPrivacyEvaluationContext,
}

/// Matched privacy rule summary returned by evaluation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyRuleMatch {
    /// Stable rule id.
    pub rule_id: String,
    /// User-visible rule name.
    pub name: String,
    /// Matcher kind.
    pub kind: AiPrivacyRuleKind,
    /// Rule pattern that matched.
    pub pattern: String,
    /// Route scope affected by the rule.
    pub applies_to: AiPrivacyRuleAppliesTo,
    /// Field that caused the match, when known.
    pub matched_field: Option<AiPrivacyInputField>,
}

/// Evaluation report consumed by AI pages, S3-09 tests, and S3-10 fallback.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiPrivacyEvaluationReport {
    /// Final privacy decision.
    pub decision: AiPrivacyDecision,
    /// Stable skip or deny reason.
    pub skipped_reason: Option<AiPrivacySkippedReason>,
    /// Provider-gate reason, when provider state skipped the request.
    pub provider_gate_reason: Option<AiPrivacyProviderGateReason>,
    /// Matched privacy rules.
    pub matched_rules: Vec<AiPrivacyRuleMatch>,
    /// Field that blocked the attempt, when known.
    pub matched_field_type: Option<AiPrivacyInputField>,
    /// Fields allowed by rule and field filters.
    pub allowed_fields: Vec<AiPrivacyInputField>,
    /// Fields blocked by rule or field filters.
    pub blocked_fields: Vec<AiPrivacyInputField>,
    /// Fields that may be sent to AI. Privacy skips must leave this empty.
    pub sent_fields: Vec<AiPrivacyInputField>,
    /// Display-safe status message.
    pub message: String,
}

/// Lists C3-09 AI privacy rules and remote field-filter state.
///
/// This read-only contract gives S3-09 enough state to render rules, remote
/// field settings, default remote-blocked policy, and read-only provider gate
/// state without enabling providers, touching user files, or executing AI.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths and
/// later implementation metadata-shape failures. Returns `CoreError::Db {
/// message }` when persisted privacy metadata cannot be read.
pub fn list_ai_privacy_rules(repo_path: String) -> CoreResult<AiPrivacyRulesSnapshot> {
    validate_repo_path(&repo_path)?;
    persistence::load_snapshot(&repo_path)
}

/// Updates C3-09 privacy rules, remote field filters, and the remote privacy gate.
///
/// The request is replace-style and requires explicit confirmation. Enabling
/// `privacy_gate_enabled` requires provider scope state that is configured,
/// verified, enabled, and non-empty, so the privacy page cannot replace S3-03
/// provider enablement. The contract must not delete Keychain credentials,
/// disable remote providers, clear logs, edit AI results, or touch user files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid rules, field settings,
/// provider scope, or missing confirmation. Returns `CoreError::Db { message
/// }` when persisted privacy metadata cannot be written.
pub fn update_ai_privacy_rules(
    repo_path: String,
    request: AiPrivacyRulesUpdateRequest,
) -> CoreResult<AiPrivacyRulesSnapshot> {
    validate_repo_path(&repo_path)?;
    validate_update_request(&request)?;
    persistence::store_update(
        &repo_path,
        request.privacy_gate_enabled,
        request.rules,
        request.remote_allowed_fields,
        request.provider_scope,
    )
}

/// Evaluates C3-09 privacy gates for one AI attempt.
///
/// The evaluation report shape lets AI feature pages and S3-10 render
/// allow/deny/skipped state, provider-gate reasons, matched rule ids, matched
/// field types, and sent-field categories. Privacy skips must keep
/// `sent_fields` empty so call-log records can show that no AI call was made.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid evaluation input,
/// duplicate fields, invalid rules, or unsafe context values. Returns
/// `CoreError::Db { message }` when required privacy metadata cannot be loaded.
pub fn evaluate_ai_privacy(
    repo_path: String,
    request: AiPrivacyEvaluationRequest,
) -> CoreResult<AiPrivacyEvaluationReport> {
    validate_repo_path(&repo_path)?;
    validate_evaluation_request(&request)?;
    Ok(evaluation::evaluate(request))
}
