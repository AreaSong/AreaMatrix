//! remote provider configuration contract types and entry points.

mod probe;
mod state;

use std::{
    collections::HashSet,
    path::{Component, Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use state::{serialize_stored_config, snapshot_from_stored_config};
use uuid::Uuid;

use crate::{db, AiFeatureKind, CoreError, CoreResult};

pub(crate) use state::{
    disable_remote_ai_provider, load_enabled_remote_provider_runtime,
    load_remote_ai_provider_config,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_MODEL_ID_LEN: usize = 128;
const MAX_ENDPOINT_URL_LEN: usize = 512;
const MAX_KEY_REFERENCE_LEN: usize = 256;
const MAX_PROBE_TOKEN_LEN: usize = 256;
const MAX_VERIFICATION_TOKEN_LEN: usize = 256;
const VERIFIED_MESSAGE: &str = "Remote provider metadata verified";

/// Supported remote AI provider families.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RemoteAiProviderKind {
    /// OpenAI-compatible managed provider.
    OpenAi,
    /// Anthropic-compatible managed provider.
    Anthropic,
    /// User-supplied provider endpoint.
    Other,
}

/// Sanitized outcome of a remote provider connection test.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RemoteProviderTestStatus {
    /// Provider accepted the minimal connection test.
    Succeeded,
    /// Provider rejected the credential or model without exposing secret text.
    ProviderRejected,
    /// Network or endpoint connectivity failed.
    ConnectionFailed,
    /// Provider shape is valid but not supported by the current runtime.
    UnsupportedProvider,
}

/// Request for testing a remote AI provider without sending user file content.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RemoteProviderTestRequest {
    /// Provider family to test.
    pub provider: RemoteAiProviderKind,
    /// Provider model id selected by the user.
    pub model_id: String,
    /// Custom HTTPS endpoint. Only `Other` providers may set it.
    pub endpoint_url: Option<String>,
    /// Platform secure-storage reference for the API key.
    pub key_reference: String,
}

/// HTTP method selected by Core for a platform-executed provider probe.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RemoteProviderProbeMethod {
    /// Read provider model metadata without sending user content.
    Get,
}

/// Authentication header shape that the platform layer must assemble from secure storage.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RemoteProviderProbeAuthorization {
    /// `Authorization: Bearer <credential>`.
    Bearer,
    /// `x-api-key: <credential>`.
    AnthropicApiKey,
}

/// Sanitized non-secret header included in a provider probe plan.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RemoteProviderProbeHeader {
    /// Header name fixed by Core policy.
    pub name: String,
    /// Non-secret header value fixed by Core policy.
    pub value: String,
}

/// Platform-neutral plan for the macOS layer to execute with Keychain and URLSession.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RemoteProviderProbePlan {
    /// Provider family being tested.
    pub provider: RemoteAiProviderKind,
    /// Model id being tested.
    pub model_id: String,
    /// Custom endpoint being tested, when present.
    pub endpoint_url: Option<String>,
    /// Platform secure-storage reference. This is never raw credential material.
    pub key_reference: String,
    /// Opaque token binding the observation to the current probe preparation.
    pub probe_token: String,
    /// HTTP method selected by Core.
    pub method: RemoteProviderProbeMethod,
    /// Fully rendered provider metadata URL.
    pub url: String,
    /// Non-secret provider headers.
    pub headers: Vec<RemoteProviderProbeHeader>,
    /// Authentication header shape for the platform layer.
    pub authorization: RemoteProviderProbeAuthorization,
    /// Request and resource timeout required from the platform transport.
    pub timeout_millis: u32,
    /// Maximum response body bytes. Zero means headers-only observation.
    pub maximum_response_body_bytes: u64,
    /// Whether redirects may be followed.
    pub follow_redirects: bool,
}

/// Sanitized platform observation returned after executing a provider probe plan.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RemoteProviderProbeObservation {
    /// Opaque token from the prepared plan.
    pub probe_token: String,
    /// Sanitized transport outcome.
    pub outcome: RemoteProviderProbeOutcome,
    /// HTTP status when an HTTP response was observed.
    pub http_status: Option<u32>,
}

/// Allowed sanitized outcomes from the platform transport.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RemoteProviderProbeOutcome {
    /// An HTTP response status was observed.
    HttpResponse,
    /// DNS, TLS, timeout, refusal, or another transport failure occurred.
    ConnectionFailed,
    /// The secure credential reference could not be resolved.
    CredentialUnavailable,
}

/// Request for enabling a tested remote provider after explicit consent.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RemoteProviderEnableRequest {
    /// Provider family to enable.
    pub provider: RemoteAiProviderKind,
    /// Provider model id selected by the user.
    pub model_id: String,
    /// Custom HTTPS endpoint. Only `Other` providers may set it.
    pub endpoint_url: Option<String>,
    /// Platform secure-storage reference for the API key.
    pub key_reference: String,
    /// AI features allowed to use this remote provider after later gates pass.
    pub feature_scope: Vec<AiFeatureKind>,
    /// Opaque token returned by a successful provider connection test.
    pub verification_token: String,
    /// Explicit user confirmation that allowed content may leave the device.
    pub data_flow_confirmed: bool,
}

/// Request for disabling the current remote provider gate.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RemoteProviderDisableRequest {
    /// Whether Core should forget the stored secure-credential reference.
    pub remove_stored_credential: bool,
}

/// Persisted remote provider gate state consumed by remote provider settings surface and AI privacy rules surface.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RemoteProviderConfigSnapshot {
    /// Whether provider, model, endpoint, and credential metadata are configured.
    pub provider_configured: bool,
    /// Whether the current provider/model/key combination has been tested.
    pub provider_verified: bool,
    /// Whether the user explicitly enabled remote provider calls.
    pub remote_provider_enabled: bool,
    /// Configured provider family, when present.
    pub provider: Option<RemoteAiProviderKind>,
    /// Configured model id, when present.
    pub model_id: Option<String>,
    /// Configured custom endpoint, when present.
    pub endpoint_url: Option<String>,
    /// Whether a secure credential reference exists. API keys are never returned.
    pub credential_configured: bool,
    /// Features allowed by the provider scope gate.
    pub feature_scope: Vec<AiFeatureKind>,
    /// Last persisted update timestamp, when implementation storage provides one.
    pub updated_at: Option<i64>,
    /// Stable reason explaining why remote calls are currently disabled.
    pub disabled_reason: Option<String>,
}

/// Connection-test result for remote provider settings surface.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RemoteProviderTestResult {
    /// Provider family that was tested.
    pub provider: RemoteAiProviderKind,
    /// Model id that was tested.
    pub model_id: String,
    /// Custom endpoint that was tested, when present.
    pub endpoint_url: Option<String>,
    /// Sanitized provider test status.
    pub status: RemoteProviderTestStatus,
    /// Whether this test verifies the current provider/model/key combination.
    pub provider_verified: bool,
    /// Opaque enable token. It must never contain API key material.
    pub verification_token: Option<String>,
    /// User-displayable sanitized message.
    pub sanitized_message: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct PendingRemoteProviderVerification {
    provider: RemoteAiProviderKind,
    model_id: String,
    endpoint_url: Option<String>,
    key_reference: String,
    verification_token: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct PendingRemoteProviderProbe {
    request: RemoteProviderTestRequest,
    probe_token: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value")]
enum PendingRemoteProviderTestRecord {
    Probe(PendingRemoteProviderProbe),
    Verification(PendingRemoteProviderVerification),
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(crate) struct StoredRemoteProviderConfig {
    pub(crate) provider: RemoteAiProviderKind,
    pub(crate) model_id: String,
    pub(crate) endpoint_url: Option<String>,
    pub(crate) key_reference: String,
    pub(crate) feature_scope: Vec<AiFeatureKind>,
    pub(crate) provider_verified: bool,
    pub(crate) remote_provider_enabled: bool,
}

pub(crate) fn prepare_remote_ai_provider_probe(
    repo_path: String,
    request: RemoteProviderTestRequest,
) -> CoreResult<RemoteProviderProbePlan> {
    validate_repo_path(&repo_path)?;
    validate_connection_request(&request)?;
    let probe_token = new_probe_token();
    let plan = probe::build_probe_plan(&request, probe_token.clone())?;
    let pending = PendingRemoteProviderTestRecord::Probe(PendingRemoteProviderProbe {
        request,
        probe_token,
    });
    let repo = PathBuf::from(&repo_path);
    let serialized = serialize_pending_test_record(&pending)?;
    db::save_remote_provider_test_record(&repo, &serialized).map_err(map_storage_error)?;
    Ok(plan)
}

pub(crate) fn complete_remote_ai_provider_probe(
    repo_path: String,
    observation: RemoteProviderProbeObservation,
) -> CoreResult<RemoteProviderTestResult> {
    validate_repo_path(&repo_path)?;
    validate_probe_token(&observation.probe_token)?;
    let repo = PathBuf::from(&repo_path);
    let pending = load_pending_probe(&repo)?;
    if pending.probe_token != observation.probe_token {
        return Err(CoreError::config("remote provider probe token is invalid"));
    }

    let status = match probe::status_from_observation(
        &pending.request.provider,
        &observation.outcome,
        observation.http_status,
    ) {
        Ok(status) => status,
        Err(error) => {
            db::delete_remote_provider_test_record(&repo).map_err(map_storage_error)?;
            return Err(error);
        }
    };
    if status != RemoteProviderTestStatus::Succeeded {
        db::delete_remote_provider_test_record(&repo).map_err(map_storage_error)?;
        return Ok(unverified_test_result(pending.request, status));
    }

    let verification = pending_verification(pending.request, new_verification_token());
    let serialized = serialize_pending_test_record(
        &PendingRemoteProviderTestRecord::Verification(verification.clone()),
    )?;
    db::save_remote_provider_test_record(&repo, &serialized).map_err(map_storage_error)?;
    Ok(RemoteProviderTestResult {
        provider: verification.provider,
        model_id: verification.model_id,
        endpoint_url: verification.endpoint_url,
        status: RemoteProviderTestStatus::Succeeded,
        provider_verified: true,
        verification_token: Some(verification.verification_token),
        sanitized_message: VERIFIED_MESSAGE.to_owned(),
    })
}

fn unverified_test_result(
    request: RemoteProviderTestRequest,
    status: RemoteProviderTestStatus,
) -> RemoteProviderTestResult {
    RemoteProviderTestResult {
        provider: request.provider,
        model_id: request.model_id,
        endpoint_url: request.endpoint_url,
        sanitized_message: probe::sanitized_probe_message(&status).to_owned(),
        status,
        provider_verified: false,
        verification_token: None,
    }
}

pub(crate) fn enable_remote_ai_provider(
    repo_path: String,
    request: RemoteProviderEnableRequest,
) -> CoreResult<RemoteProviderConfigSnapshot> {
    validate_repo_path(&repo_path)?;
    validate_enable_request(&request)?;
    let repo = PathBuf::from(&repo_path);
    let pending = load_pending_verification(&repo)?;
    ensure_pending_matches_request(&pending, &request)?;

    let config = StoredRemoteProviderConfig {
        provider: request.provider,
        model_id: request.model_id,
        endpoint_url: request.endpoint_url,
        key_reference: request.key_reference,
        feature_scope: request.feature_scope,
        provider_verified: true,
        remote_provider_enabled: true,
    };
    let serialized = serialize_stored_config(&config)?;
    let updated_at =
        db::update_remote_provider_config_record(&repo, &serialized).map_err(map_storage_error)?;
    Ok(snapshot_from_stored_config(config, Some(updated_at)))
}

fn pending_verification(
    request: RemoteProviderTestRequest,
    verification_token: String,
) -> PendingRemoteProviderVerification {
    PendingRemoteProviderVerification {
        provider: request.provider,
        model_id: request.model_id,
        endpoint_url: request.endpoint_url,
        key_reference: request.key_reference,
        verification_token,
    }
}

fn new_verification_token() -> String {
    format!("verify:remote-provider:{}", Uuid::new_v4())
}

fn new_probe_token() -> String {
    format!("probe:remote-provider:{}", Uuid::new_v4())
}

fn load_pending_verification(repo_path: &Path) -> CoreResult<PendingRemoteProviderVerification> {
    let Some((serialized, _)) =
        db::load_remote_provider_test_record(repo_path).map_err(map_storage_error)?
    else {
        return Err(CoreError::config(
            "remote provider must be tested before enabling",
        ));
    };
    match deserialize_pending_test_record(&serialized)? {
        PendingRemoteProviderTestRecord::Verification(pending) => Ok(pending),
        PendingRemoteProviderTestRecord::Probe(_) => Err(CoreError::config(
            "remote provider probe must be completed before enabling",
        )),
    }
}

fn load_pending_probe(repo_path: &Path) -> CoreResult<PendingRemoteProviderProbe> {
    let Some((serialized, _)) =
        db::load_remote_provider_test_record(repo_path).map_err(map_storage_error)?
    else {
        return Err(CoreError::config(
            "remote provider probe must be prepared before completion",
        ));
    };
    match deserialize_pending_test_record(&serialized)? {
        PendingRemoteProviderTestRecord::Probe(pending) => Ok(pending),
        PendingRemoteProviderTestRecord::Verification(_) => Err(CoreError::config(
            "remote provider probe has already been completed",
        )),
    }
}

fn ensure_pending_matches_request(
    pending: &PendingRemoteProviderVerification,
    request: &RemoteProviderEnableRequest,
) -> CoreResult<()> {
    if pending.provider != request.provider
        || pending.model_id != request.model_id
        || pending.endpoint_url != request.endpoint_url
        || pending.key_reference != request.key_reference
        || pending.verification_token != request.verification_token
    {
        return Err(CoreError::config(
            "remote provider verification token is invalid",
        ));
    }
    Ok(())
}

fn validate_connection_request(request: &RemoteProviderTestRequest) -> CoreResult<()> {
    validate_provider_fields(
        &request.provider,
        &request.model_id,
        request.endpoint_url.as_deref(),
        &request.key_reference,
    )
}

fn validate_enable_request(request: &RemoteProviderEnableRequest) -> CoreResult<()> {
    validate_provider_fields(
        &request.provider,
        &request.model_id,
        request.endpoint_url.as_deref(),
        &request.key_reference,
    )?;
    validate_feature_scope(&request.feature_scope)?;
    validate_verification_token(&request.verification_token)?;
    if !request.data_flow_confirmed {
        return Err(CoreError::config(
            "remote provider data flow consent is required",
        ));
    }
    Ok(())
}

fn validate_provider_fields(
    provider: &RemoteAiProviderKind,
    model_id: &str,
    endpoint_url: Option<&str>,
    key_reference: &str,
) -> CoreResult<()> {
    validate_model_id(model_id)?;
    validate_endpoint(provider, endpoint_url)?;
    validate_key_reference(key_reference)
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config(
            "remote provider repository path is invalid",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "remote provider repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn validate_model_id(model_id: &str) -> CoreResult<()> {
    if model_id.trim() != model_id
        || model_id.is_empty()
        || model_id.len() > MAX_MODEL_ID_LEN
        || model_id.contains('\0')
        || model_id.chars().any(char::is_control)
    {
        return Err(CoreError::config("remote provider model id is invalid"));
    }
    Ok(())
}

fn validate_endpoint(
    provider: &RemoteAiProviderKind,
    endpoint_url: Option<&str>,
) -> CoreResult<()> {
    match (provider, endpoint_url) {
        (RemoteAiProviderKind::Other, Some(endpoint)) => validate_custom_endpoint(endpoint),
        (RemoteAiProviderKind::Other, None) => Err(CoreError::config(
            "custom remote provider endpoint is required",
        )),
        (_, Some(_)) => Err(CoreError::config(
            "managed remote providers must not override endpoint",
        )),
        (_, None) => Ok(()),
    }
}

fn validate_custom_endpoint(endpoint: &str) -> CoreResult<()> {
    if endpoint.trim() != endpoint
        || endpoint.is_empty()
        || endpoint.len() > MAX_ENDPOINT_URL_LEN
        || endpoint.contains('\0')
        || endpoint.chars().any(char::is_whitespace)
        || !probe::custom_endpoint_scheme_allowed(endpoint)
        || custom_endpoint_has_userinfo(endpoint)
        || looks_sensitive(endpoint)
    {
        return Err(CoreError::config(
            "custom remote provider endpoint is invalid",
        ));
    }
    Ok(())
}

fn custom_endpoint_has_userinfo(endpoint: &str) -> bool {
    endpoint
        .split_once("://")
        .map(|(_, remainder)| {
            remainder
                .split('/')
                .next()
                .unwrap_or(remainder)
                .contains('@')
        })
        .unwrap_or(false)
}

fn validate_key_reference(key_reference: &str) -> CoreResult<()> {
    if key_reference.trim() != key_reference
        || key_reference.is_empty()
        || key_reference.len() > MAX_KEY_REFERENCE_LEN
        || key_reference.contains('\0')
        || key_reference.chars().any(char::is_whitespace)
        || !key_reference.chars().all(is_key_reference_char)
        || !is_secure_storage_reference(key_reference)
        || looks_sensitive(key_reference)
    {
        return Err(CoreError::config(
            "remote provider key reference is invalid",
        ));
    }
    Ok(())
}

fn validate_feature_scope(feature_scope: &[AiFeatureKind]) -> CoreResult<()> {
    if feature_scope.is_empty() {
        return Err(CoreError::config(
            "remote provider feature scope is required",
        ));
    }
    let mut seen = HashSet::new();
    for feature in feature_scope {
        if !seen.insert(feature.clone()) {
            return Err(CoreError::config(
                "remote provider feature scope must be unique",
            ));
        }
    }
    Ok(())
}

fn validate_verification_token(token: &str) -> CoreResult<()> {
    if token.trim() != token
        || token.is_empty()
        || token.len() > MAX_VERIFICATION_TOKEN_LEN
        || token.contains('\0')
        || token.chars().any(char::is_whitespace)
        || looks_sensitive(token)
    {
        return Err(CoreError::config(
            "remote provider verification token is invalid",
        ));
    }
    Ok(())
}

fn validate_probe_token(token: &str) -> CoreResult<()> {
    if token.trim() != token
        || token.is_empty()
        || token.len() > MAX_PROBE_TOKEN_LEN
        || token.contains('\0')
        || token.chars().any(char::is_whitespace)
        || looks_sensitive(token)
    {
        return Err(CoreError::config("remote provider probe token is invalid"));
    }
    Ok(())
}

fn serialize_pending_test_record(pending: &PendingRemoteProviderTestRecord) -> CoreResult<String> {
    serde_json::to_string(pending)
        .map_err(|_| CoreError::internal("remote provider verification metadata is invalid"))
}

fn deserialize_pending_test_record(
    serialized: &str,
) -> CoreResult<PendingRemoteProviderTestRecord> {
    serde_json::from_str(serialized)
        .map_err(|_| CoreError::config("remote provider verification metadata is invalid"))
}

fn map_storage_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Db { .. } | CoreError::Io { .. } => {
            CoreError::internal("remote provider metadata persistence failed")
        }
        CoreError::InvalidPath { .. } => {
            CoreError::config("remote provider repository path is invalid")
        }
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("remote provider requires initialized repository metadata")
        }
        other => other,
    }
}

fn is_key_reference_char(value: char) -> bool {
    value.is_ascii_alphanumeric() || matches!(value, ':' | '-' | '_' | '.' | '/')
}

fn is_secure_storage_reference(value: &str) -> bool {
    value.starts_with("keychain:")
        || value.starts_with("secure-store:")
        || value.starts_with("secure-storage:")
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}

fn looks_sensitive(value: &str) -> bool {
    let normalized = value.to_ascii_lowercase();
    normalized.starts_with("sk-")
        || normalized.starts_with("sk_")
        || normalized.contains(":sk-")
        || normalized.contains(":sk_")
        || normalized.contains("bearer ")
        || normalized.contains("secret=")
        || normalized.contains("token=")
        || normalized.contains("api_key=")
        || normalized.contains("apikey=")
        || normalized.contains("-----begin")
}
