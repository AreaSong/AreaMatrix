//! Platform-neutral remote provider probe planning and observation mapping.

use crate::{
    remote_provider_config::{
        RemoteAiProviderKind, RemoteProviderProbeAuthorization, RemoteProviderProbeHeader,
        RemoteProviderProbeMethod, RemoteProviderProbeOutcome, RemoteProviderProbePlan,
        RemoteProviderTestRequest, RemoteProviderTestStatus,
    },
    CoreError, CoreResult,
};

const VERIFIED_MESSAGE: &str = "Remote provider metadata verified";
const REJECTED_MESSAGE: &str = "Remote provider rejected the credential or model";
const CONNECTION_FAILED_MESSAGE: &str = "Remote provider connection failed";
const UNSUPPORTED_MESSAGE: &str = "Remote provider is not supported by this runtime";
const OPENAI_MODELS_ENDPOINT: &str = "https://api.openai.com/v1/models";
const ANTHROPIC_MODELS_ENDPOINT: &str = "https://api.anthropic.com/v1/models";
const PROBE_TIMEOUT_MILLIS: u32 = 10_000;

pub(super) fn build_probe_plan(
    request: &RemoteProviderTestRequest,
    probe_token: String,
) -> CoreResult<RemoteProviderProbePlan> {
    let (url, headers, authorization) = match request.provider {
        RemoteAiProviderKind::OpenAi => (
            model_metadata_url(OPENAI_MODELS_ENDPOINT, &request.model_id),
            Vec::new(),
            RemoteProviderProbeAuthorization::Bearer,
        ),
        RemoteAiProviderKind::Anthropic => (
            model_metadata_url(ANTHROPIC_MODELS_ENDPOINT, &request.model_id),
            vec![RemoteProviderProbeHeader {
                name: "anthropic-version".to_owned(),
                value: "2023-06-01".to_owned(),
            }],
            RemoteProviderProbeAuthorization::AnthropicApiKey,
        ),
        RemoteAiProviderKind::Other => (
            custom_probe_url(request)?,
            Vec::new(),
            RemoteProviderProbeAuthorization::Bearer,
        ),
    };

    Ok(RemoteProviderProbePlan {
        provider: request.provider.clone(),
        model_id: request.model_id.clone(),
        endpoint_url: request.endpoint_url.clone(),
        key_reference: request.key_reference.clone(),
        probe_token,
        method: RemoteProviderProbeMethod::Get,
        url,
        headers,
        authorization,
        timeout_millis: PROBE_TIMEOUT_MILLIS,
        maximum_response_body_bytes: 0,
        follow_redirects: false,
    })
}

pub(super) fn status_from_observation(
    provider: &RemoteAiProviderKind,
    outcome: &RemoteProviderProbeOutcome,
    http_status: Option<u32>,
) -> CoreResult<RemoteProviderTestStatus> {
    match (outcome, http_status) {
        (RemoteProviderProbeOutcome::HttpResponse, Some(status))
            if (100..=599).contains(&status) =>
        {
            Ok(map_http_status(provider, status))
        }
        (RemoteProviderProbeOutcome::ConnectionFailed, None) => {
            Ok(RemoteProviderTestStatus::ConnectionFailed)
        }
        (RemoteProviderProbeOutcome::CredentialUnavailable, None) => {
            Err(CoreError::permission_denied("remote provider credential"))
        }
        _ => Err(CoreError::config(
            "remote provider probe observation is invalid",
        )),
    }
}

pub(super) fn custom_endpoint_scheme_allowed(endpoint: &str) -> bool {
    endpoint.starts_with("https://") || is_loopback_http_endpoint(endpoint)
}

pub(super) fn sanitized_probe_message(status: &RemoteProviderTestStatus) -> &'static str {
    match status {
        RemoteProviderTestStatus::Succeeded => VERIFIED_MESSAGE,
        RemoteProviderTestStatus::ProviderRejected => REJECTED_MESSAGE,
        RemoteProviderTestStatus::ConnectionFailed => CONNECTION_FAILED_MESSAGE,
        RemoteProviderTestStatus::UnsupportedProvider => UNSUPPORTED_MESSAGE,
    }
}

fn custom_probe_url(request: &RemoteProviderTestRequest) -> CoreResult<String> {
    let endpoint = request
        .endpoint_url
        .as_deref()
        .ok_or_else(|| CoreError::config("custom remote provider endpoint is required"))?;
    Ok(append_query(
        endpoint,
        &[
            ("model_id", request.model_id.as_str()),
            ("probe", "provider_metadata"),
        ],
    ))
}

fn model_metadata_url(base: &str, model_id: &str) -> String {
    format!("{base}/{}", percent_encode(model_id))
}

fn map_http_status(provider: &RemoteAiProviderKind, status: u32) -> RemoteProviderTestStatus {
    match status {
        200..=299 => RemoteProviderTestStatus::Succeeded,
        400 | 401 | 403 | 422 => RemoteProviderTestStatus::ProviderRejected,
        404 if matches!(provider, RemoteAiProviderKind::Other) => {
            RemoteProviderTestStatus::UnsupportedProvider
        }
        404 => RemoteProviderTestStatus::ProviderRejected,
        408 | 425 | 429 | 500..=599 => RemoteProviderTestStatus::ConnectionFailed,
        _ => RemoteProviderTestStatus::UnsupportedProvider,
    }
}

fn append_query(endpoint: &str, pairs: &[(&str, &str)]) -> String {
    let separator = if endpoint.contains('?') { '&' } else { '?' };
    let query = pairs
        .iter()
        .map(|(key, value)| format!("{}={}", percent_encode(key), percent_encode(value)))
        .collect::<Vec<_>>()
        .join("&");
    format!("{endpoint}{separator}{query}")
}

fn percent_encode(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            encoded.push(byte as char);
        } else {
            encoded.push_str(&format!("%{byte:02X}"));
        }
    }
    encoded
}

fn is_loopback_http_endpoint(endpoint: &str) -> bool {
    endpoint.starts_with("http://127.0.0.1:")
        || endpoint.starts_with("http://localhost:")
        || endpoint.starts_with("http://[::1]:")
}
