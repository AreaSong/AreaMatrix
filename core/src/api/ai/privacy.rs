//! Public FFI AI privacy entry points.

use crate::{
    ai_privacy_rules, AiPrivacyEvaluationReport, AiPrivacyEvaluationRequest,
    AiPrivacyRulesSnapshot, AiPrivacyRulesUpdateRequest, CoreResult,
};

/// Lists AI privacy rules, remote field filters, and provider gate state.
///
/// AI privacy rules surface uses this contract to render the privacy rules table, global
/// `privacy_gate_enabled` state, remote allowed field controls, and read-only
/// remote provider scope. AI fallback surface can use matched rule ids from other AI
/// contracts to route `View privacy rule` back to this snapshot.
///
/// This API is read-only. It must not create recommended templates
/// automatically, enable or disable remote providers, delete credentials,
/// inspect or send user file contents, write AI call logs, delete AI results,
/// or touch user files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths or
/// malformed privacy metadata, and `CoreError::Db { message }` when privacy
/// rules or provider gate metadata cannot be read.
pub fn list_ai_privacy_rules(repo_path: String) -> CoreResult<AiPrivacyRulesSnapshot> {
    ai_privacy_rules::list_ai_privacy_rules(repo_path)
}

/// Updates AI privacy rules and remote privacy gate metadata.
///
/// The request replaces the AI privacy rules surface-owned privacy rule set, remote field filter
/// settings, and global `privacy_gate_enabled` value after explicit user
/// confirmation. Enabling the privacy gate requires the read-only provider
/// snapshot to show configured, verified, enabled provider state and non-empty
/// feature scope; this prevents the privacy page from replacing the provider
/// configuration flow.
///
/// The contract must not enable or disable remote provider metadata,
/// remove Keychain keys, execute AI calls, write suggestions, clear logs,
/// regenerate summaries/tags, or modify user files. Disabling
/// `privacy_gate_enabled` blocks future remote calls only.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid rules, duplicate rule
/// ids, incomplete field settings, invalid provider gate state, or missing
/// confirmation. Returns `CoreError::Db { message }` when privacy metadata
/// cannot be written atomically.
pub fn update_ai_privacy_rules(
    repo_path: String,
    request: AiPrivacyRulesUpdateRequest,
) -> CoreResult<AiPrivacyRulesSnapshot> {
    ai_privacy_rules::update_ai_privacy_rules(repo_path, request)
}

/// Evaluates AI privacy rules before an AI feature uses candidate fields.
///
/// AI classification, summary, tag, and semantic search implementations use
/// this contract before local or remote input is prepared. The returned report
/// gives pages a stable allow/deny/skipped decision, provider-gate reason,
/// matched rule, matched field type, sent field categories, and display-safe
/// message. Privacy skips must keep `sent_fields` empty so AI call log surface can log
/// `No AI call was made`.
///
/// This contract evaluates gate state only. It must not execute providers,
/// retry models, persist call logs, read full user note text, write AI results,
/// or mutate files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid evaluation input,
/// duplicate fields, invalid rules, or unsafe path/context values. Returns
/// `CoreError::Db { message }` when privacy metadata required for evaluation
/// cannot be loaded.
pub fn evaluate_ai_privacy(
    repo_path: String,
    request: AiPrivacyEvaluationRequest,
) -> CoreResult<AiPrivacyEvaluationReport> {
    ai_privacy_rules::evaluate_ai_privacy(repo_path, request)
}
