//! Public FFI AI settings entry points.

use crate::{
    ai_settings, local_model_status, remote_provider_config, AiConfig, AiConfigSnapshot,
    CoreResult, LocalModelFolderLocation, LocalModelFolderRequest, LocalModelStatusRequest,
    LocalModelStatusSnapshot, RemoteProviderConfigSnapshot, RemoteProviderDisableRequest,
    RemoteProviderEnableRequest, RemoteProviderProbeObservation, RemoteProviderProbePlan,
    RemoteProviderTestRequest, RemoteProviderTestResult,
};

/// Loads the AI settings snapshot without starting any AI provider.
///
/// The contract is for AI settings surface and the AI privacy rules privacy gate summary.
/// It exposes the master AI switch, provider preference, local/remote route
/// toggles, privacy gate reference, and per-feature switches. Loading settings
/// must never call local models, contact remote providers, read user file
/// contents, write logs, or store API keys.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the repository path is invalid.
pub fn load_ai_config(repo_path: String) -> CoreResult<AiConfigSnapshot> {
    ai_settings::load_ai_config(repo_path)
}

/// Validates an AI settings update payload.
///
/// This contract accepts only settings metadata. API keys, provider connection
/// tests, remote enablement, privacy rule CRUD/evaluation, AI call logs,
/// pending suggestion cleanup, and actual model execution remain owned by
/// their dedicated AI capability contracts.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths,
/// mismatched payloads, incomplete feature toggles, or unavailable AI settings
/// persistence. Returns `CoreError::PermissionDenied { path }` when repository
/// metadata cannot be inspected and `CoreError::Io { message }` for metadata
/// inspection failures.
pub fn update_ai_config(repo_path: String, new_config: AiConfig) -> CoreResult<AiConfigSnapshot> {
    ai_settings::update_ai_config(repo_path, new_config)
}

/// Reads the local model status without enabling remote fallback.
///
/// The contract is for local model status surface. It accepts a model id, a
/// configured storage location, and an optional cached status snapshot so the
/// page can render first-load, failure-entry, and manual refresh states from a
/// stable shape. A status check may inspect only local model manifest,
/// directory metadata, disk usage, cached status, and runtime health metadata.
///
/// This API must not download, install, delete, train, rewrite model weights,
/// read user file contents, contact remote providers, enable remote fallback,
/// write AI call logs, or expose API keys/provider config through diagnostics.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid request shape or
/// unavailable local-model metadata, `CoreError::PermissionDenied { path }` for
/// unreadable model metadata or runtime state, and `CoreError::Io { message }`
/// for model manifest, directory metadata, or runtime inspection failures.
pub fn get_local_model_status(
    repo_path: String,
    request: LocalModelStatusRequest,
) -> CoreResult<LocalModelStatusSnapshot> {
    local_model_status::get_local_model_status(repo_path, request)
}

/// Locates the configured local model folder without mutating it.
///
/// local model status surface uses this read-only contract for `Open model location`. The result
/// tells the platform layer which folder can be revealed and why revealing is
/// unavailable. Core must not create missing folders, download models, repair
/// metadata, delete caches, or touch user-authored files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid request shape,
/// `CoreError::PermissionDenied { path }` when the folder cannot be inspected,
/// and `CoreError::Io { message }` for filesystem metadata failures.
pub fn locate_local_model_folder(
    repo_path: String,
    request: LocalModelFolderRequest,
) -> CoreResult<LocalModelFolderLocation> {
    local_model_status::locate_local_model_folder(repo_path, request)
}

/// Prepares a platform-executed remote provider probe without sending user file content.
///
/// remote provider settings surface uses this contract before enabling remote AI. Core validates the
/// provider metadata, persists an opaque in-flight probe token, and returns a
/// non-secret HTTP plan for the platform layer. Core does not read Keychain,
/// start a process, or access the network.
///
/// The plan must never contain raw API keys, user file paths, file content,
/// prompts, notes, summaries, tags, or provider raw responses.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid provider, model,
/// endpoint, or key-reference shape, and `CoreError::Internal { message }`
/// when the in-flight probe record cannot be persisted.
pub fn prepare_remote_ai_provider_probe(
    repo_path: String,
    request: RemoteProviderTestRequest,
) -> CoreResult<RemoteProviderProbePlan> {
    remote_provider_config::prepare_remote_ai_provider_probe(repo_path, request)
}

/// Completes a prepared remote provider probe from a sanitized platform observation.
///
/// The platform layer executes the plan with Keychain and URLSession, then
/// returns only the probe token, transport outcome, and optional HTTP status.
/// Core maps that observation to the stable test result and creates an enable
/// verification token only after a successful status.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for malformed, stale, or mismatched
/// observations; `CoreError::PermissionDenied { path }` when the platform
/// reports an unavailable credential; and `CoreError::Internal { message }`
/// when pending probe metadata cannot be read, updated, or cleared.
pub fn complete_remote_ai_provider_probe(
    repo_path: String,
    observation: RemoteProviderProbeObservation,
) -> CoreResult<RemoteProviderTestResult> {
    remote_provider_config::complete_remote_ai_provider_probe(repo_path, observation)
}

/// Loads the persisted remote provider gate snapshot.
///
/// remote provider settings surface calls this when opening the remote model configuration sheet, and
/// AI privacy rules surface reads it as provider-consent state. The snapshot reports configured,
/// verified, enabled, credential-present, scope, and disabled-reason state
/// without returning API key material or contacting a provider.
///
/// This contract does not mutate provider settings, enable privacy gates,
/// inspect user files, execute AI calls, or delete credentials.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths or
/// invalid persisted metadata, and `CoreError::Internal { message }` when
/// provider metadata cannot be read from initialized repository storage.
pub fn load_remote_ai_provider_config(
    repo_path: String,
) -> CoreResult<RemoteProviderConfigSnapshot> {
    remote_provider_config::load_remote_ai_provider_config(repo_path)
}

/// Enables a remote AI provider after successful test and consent.
///
/// remote provider settings surface uses this contract after the user selects usage scope and confirms
/// that allowed content may leave the device. The returned snapshot exposes the
/// five provider gate fields consumed by remote provider settings surface and AI privacy rules surface:
/// `provider_configured`, `provider_verified`, `remote_provider_enabled`,
/// `feature_scope`, and credential presence without API key material.
///
/// This contract does not execute AI calls, evaluate privacy rules, edit
/// privacy field filters, generate suggestions, write user files, or disable
/// remote calls through AI privacy rules surface's privacy gate. AI privacy rules remains responsible for
/// `privacy_gate_enabled` and field/rule evaluation.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid provider settings,
/// missing feature scope, missing verification token, or missing data-flow
/// consent; `CoreError::PermissionDenied { path }` when secure credential or
/// provider metadata cannot be inspected; and `CoreError::Internal { message }`
/// when provider metadata persistence or sanitized enablement state fails.
pub fn enable_remote_ai_provider(
    repo_path: String,
    request: RemoteProviderEnableRequest,
) -> CoreResult<RemoteProviderConfigSnapshot> {
    remote_provider_config::enable_remote_ai_provider(repo_path, request)
}

/// Disables the remote provider gate without touching AI privacy rules.
///
/// remote provider settings surface uses this for `Disable remote AI`. The call sets
/// `remote_provider_enabled` to false and may forget the stored credential
/// reference when the user explicitly chooses `Also remove stored API key`.
/// It preserves provider metadata and feature scope unless the credential
/// reference is removed, in which case verification is reset because the
/// tested provider/key combination no longer exists in Core metadata.
///
/// This contract does not delete user files, execute AI calls, change local AI
/// settings, modify privacy rules, clear call logs, or implement AI privacy rules surface's
/// `privacy_gate_enabled` persistence.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths or
/// invalid persisted metadata, and `CoreError::Internal { message }` when
/// provider metadata cannot be read or updated atomically.
pub fn disable_remote_ai_provider(
    repo_path: String,
    request: RemoteProviderDisableRequest,
) -> CoreResult<RemoteProviderConfigSnapshot> {
    remote_provider_config::disable_remote_ai_provider(repo_path, request)
}
