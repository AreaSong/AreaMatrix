//! C3-03 remote provider configuration contract types and entry points.

use std::{
    collections::HashSet,
    path::{Component, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::{AiFeatureKind, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_MODEL_ID_LEN: usize = 128;
const MAX_ENDPOINT_URL_LEN: usize = 512;
const MAX_KEY_REFERENCE_LEN: usize = 256;
const MAX_VERIFICATION_TOKEN_LEN: usize = 256;

/// Supported remote AI provider families for Stage 3.
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

/// Persisted remote provider gate state consumed by S3-03 and S3-09.
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

/// Connection-test result for S3-03.
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

pub(crate) fn test_remote_ai_provider(
    repo_path: String,
    request: RemoteProviderTestRequest,
) -> CoreResult<RemoteProviderTestResult> {
    validate_repo_path(&repo_path)?;
    validate_connection_request(&request)?;
    Err(CoreError::internal(
        "remote provider connection test implementation unavailable",
    ))
}

pub(crate) fn enable_remote_ai_provider(
    repo_path: String,
    request: RemoteProviderEnableRequest,
) -> CoreResult<RemoteProviderConfigSnapshot> {
    validate_repo_path(&repo_path)?;
    validate_enable_request(&request)?;
    Err(CoreError::internal(
        "remote provider enable implementation unavailable",
    ))
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
        || !endpoint.starts_with("https://")
        || looks_sensitive(endpoint)
    {
        return Err(CoreError::config(
            "custom remote provider endpoint is invalid",
        ));
    }
    Ok(())
}

fn validate_key_reference(key_reference: &str) -> CoreResult<()> {
    if key_reference.trim() != key_reference
        || key_reference.is_empty()
        || key_reference.len() > MAX_KEY_REFERENCE_LEN
        || key_reference.contains('\0')
        || key_reference.chars().any(char::is_whitespace)
        || !key_reference.chars().all(is_key_reference_char)
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

fn is_key_reference_char(value: char) -> bool {
    value.is_ascii_alphanumeric() || matches!(value, ':' | '-' | '_' | '.' | '/')
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}

fn looks_sensitive(value: &str) -> bool {
    let normalized = value.to_ascii_lowercase();
    normalized.starts_with("sk-")
        || normalized.starts_with("sk_")
        || normalized.contains("bearer ")
        || normalized.contains("secret=")
        || normalized.contains("token=")
        || normalized.contains("api_key=")
        || normalized.contains("apikey=")
        || normalized.contains("-----begin")
}
