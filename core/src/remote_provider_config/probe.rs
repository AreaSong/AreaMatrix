//! Provider probe policy for C3-03 remote provider tests.

use std::{
    env,
    ffi::OsString,
    io::{Read, Write},
    net::{TcpStream, ToSocketAddrs},
    process::{Command, Stdio},
    time::Duration,
};

use serde::Serialize;

use crate::{
    remote_provider_config::{
        RemoteAiProviderKind, RemoteProviderTestRequest, RemoteProviderTestStatus,
    },
    CoreError, CoreResult,
};

const VERIFIED_MESSAGE: &str = "Remote provider metadata verified";
const REJECTED_MESSAGE: &str = "Remote provider rejected the credential or model";
const CONNECTION_FAILED_MESSAGE: &str = "Remote provider connection failed";
const UNSUPPORTED_MESSAGE: &str = "Remote provider is not supported by this runtime";
const INVALID_KEY_REFERENCE_MESSAGE: &str = "remote provider key reference is invalid";
const SECURE_STORAGE_ENV_PREFIX: &str = "secure-storage:env:";
const SECURE_STORE_ENV_PREFIX: &str = "secure-store:env:";
const KEYCHAIN_PREFIX: &str = "keychain:";
const OPENAI_MODELS_ENDPOINT: &str = "https://api.openai.com/v1/models";
const ANTHROPIC_MODELS_ENDPOINT: &str = "https://api.anthropic.com/v1/models";
const PROBE_RUNTIME_ENV: &str = "AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME";
const HTTP_TIMEOUT: Duration = Duration::from_secs(5);

pub(super) struct RemoteProviderProbeResult {
    pub(super) status: RemoteProviderTestStatus,
    pub(super) sanitized_message: String,
}

struct CredentialSecret {
    value: String,
}

enum ProbeCredential {
    Secret(CredentialSecret),
    PlatformReference(String),
}

struct ProbeHttpRequest {
    provider: RemoteAiProviderKind,
    method: &'static str,
    url: String,
    headers: Vec<(&'static str, String)>,
    key_reference: Option<String>,
}

struct ProbeUrl {
    scheme: String,
    host: String,
    port: u16,
    path: String,
}

#[derive(Serialize)]
struct RuntimeProbePayload<'a> {
    provider: &'a RemoteAiProviderKind,
    method: &'a str,
    url: &'a str,
    headers: Vec<RuntimeProbeHeader<'a>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    key_reference: Option<&'a str>,
}

#[derive(Serialize)]
struct RuntimeProbeHeader<'a> {
    name: &'a str,
    value: &'a str,
}

/// Performs the C3-03 minimal probe without accepting raw API key material.
pub(super) fn probe_remote_provider(
    request: &RemoteProviderTestRequest,
) -> CoreResult<RemoteProviderProbeResult> {
    let credential = inspect_credential_reference(&request.key_reference)?;
    let probe_request = build_probe_request(request, &credential)?;
    let status = execute_probe_request(&probe_request)?;
    Ok(RemoteProviderProbeResult {
        sanitized_message: sanitized_probe_message(&status).to_owned(),
        status,
    })
}

pub(super) fn custom_endpoint_scheme_allowed(endpoint: &str) -> bool {
    endpoint.starts_with("https://") || is_loopback_http_endpoint(endpoint)
}

fn inspect_credential_reference(key_reference: &str) -> CoreResult<ProbeCredential> {
    if key_reference.starts_with(KEYCHAIN_PREFIX) {
        return keychain_reference(key_reference);
    }
    let Some(env_name) = credential_env_name(key_reference)? else {
        return Err(CoreError::permission_denied("remote provider credential"));
    };
    let value = env::var(env_name)
        .map_err(|_| CoreError::permission_denied("remote provider credential"))?;
    if value.trim().is_empty() || value.contains('\0') || value.chars().any(char::is_control) {
        return Err(CoreError::permission_denied("remote provider credential"));
    }
    Ok(ProbeCredential::Secret(CredentialSecret { value }))
}

fn keychain_reference(key_reference: &str) -> CoreResult<ProbeCredential> {
    let name = key_reference
        .strip_prefix(KEYCHAIN_PREFIX)
        .expect("keychain prefix was checked before parsing");
    if name.is_empty() {
        return Err(CoreError::config(INVALID_KEY_REFERENCE_MESSAGE));
    }
    Ok(ProbeCredential::PlatformReference(key_reference.to_owned()))
}

fn credential_env_name(key_reference: &str) -> CoreResult<Option<&str>> {
    let env_name = key_reference
        .strip_prefix(SECURE_STORAGE_ENV_PREFIX)
        .or_else(|| key_reference.strip_prefix(SECURE_STORE_ENV_PREFIX));
    let Some(env_name) = env_name else {
        return Ok(None);
    };
    if env_name.is_empty()
        || env_name.len() > 128
        || !env_name
            .chars()
            .all(|value| value.is_ascii_alphanumeric() || value == '_')
    {
        return Err(CoreError::config(INVALID_KEY_REFERENCE_MESSAGE));
    }
    Ok(Some(env_name))
}

fn build_probe_request(
    request: &RemoteProviderTestRequest,
    credential: &ProbeCredential,
) -> CoreResult<ProbeHttpRequest> {
    let (headers, key_reference) = match credential {
        ProbeCredential::Secret(secret) => {
            (provider_headers(&request.provider, &secret.value), None)
        }
        ProbeCredential::PlatformReference(reference) => (Vec::new(), Some(reference.clone())),
    };
    let url = match request.provider {
        RemoteAiProviderKind::OpenAi => {
            model_metadata_url(OPENAI_MODELS_ENDPOINT, &request.model_id)
        }
        RemoteAiProviderKind::Anthropic => {
            model_metadata_url(ANTHROPIC_MODELS_ENDPOINT, &request.model_id)
        }
        RemoteAiProviderKind::Other => custom_probe_url(request)?,
    };
    Ok(ProbeHttpRequest {
        provider: request.provider.clone(),
        method: "GET",
        url,
        headers,
        key_reference,
    })
}

fn provider_headers(
    provider: &RemoteAiProviderKind,
    credential: &str,
) -> Vec<(&'static str, String)> {
    match provider {
        RemoteAiProviderKind::Anthropic => vec![
            ("x-api-key", credential.to_owned()),
            ("anthropic-version", "2023-06-01".to_owned()),
        ],
        RemoteAiProviderKind::OpenAi | RemoteAiProviderKind::Other => {
            vec![("Authorization", format!("Bearer {credential}"))]
        }
    }
}

fn model_metadata_url(base: &str, model_id: &str) -> String {
    format!("{base}/{}", percent_encode(model_id))
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

fn execute_probe_request(request: &ProbeHttpRequest) -> CoreResult<RemoteProviderTestStatus> {
    if request.key_reference.is_some() {
        return execute_external_probe_runtime(request)?
            .ok_or_else(|| CoreError::permission_denied("remote provider credential"));
    }
    if let Some(status) = execute_external_probe_runtime(request)? {
        return Ok(status);
    }

    let url = parse_probe_url(&request.url)?;
    match url.scheme.as_str() {
        "http" => execute_plain_http_probe(request, &url),
        "https" => execute_curl_probe(request),
        _ => Ok(RemoteProviderTestStatus::UnsupportedProvider),
    }
}

fn execute_external_probe_runtime(
    request: &ProbeHttpRequest,
) -> CoreResult<Option<RemoteProviderTestStatus>> {
    let Some(runtime_path) = external_probe_runtime_path() else {
        return Ok(None);
    };
    let payload = runtime_probe_payload(request)?;
    let mut child = Command::new(runtime_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| CoreError::internal("remote provider runtime unavailable"))?;
    let Some(mut stdin) = child.stdin.take() else {
        return Err(CoreError::internal("remote provider runtime unavailable"));
    };
    stdin
        .write_all(&payload)
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;
    drop(stdin);

    let output = child
        .wait_with_output()
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;
    if !output.status.success() {
        return Err(CoreError::internal("remote provider runtime unavailable"));
    }
    Ok(Some(parse_runtime_status(
        &request.provider,
        &output.stdout,
    )?))
}

fn execute_plain_http_probe(
    request: &ProbeHttpRequest,
    url: &ProbeUrl,
) -> CoreResult<RemoteProviderTestStatus> {
    let address = (url.host.as_str(), url.port)
        .to_socket_addrs()
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?
        .next()
        .ok_or_else(|| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;
    let mut stream = TcpStream::connect_timeout(&address, HTTP_TIMEOUT)
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;
    stream
        .set_read_timeout(Some(HTTP_TIMEOUT))
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;
    stream
        .write_all(render_http_request(request, url).as_bytes())
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;

    let mut response = Vec::new();
    stream
        .read_to_end(&mut response)
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;
    let status = parse_http_status(&response)?;
    Ok(map_http_status(&request.provider, status))
}

fn external_probe_runtime_path() -> Option<OsString> {
    env::var_os(PROBE_RUNTIME_ENV).filter(|value| !value.is_empty())
}

fn runtime_probe_payload(request: &ProbeHttpRequest) -> CoreResult<Vec<u8>> {
    let headers = request
        .headers
        .iter()
        .map(|(name, value)| RuntimeProbeHeader { name, value })
        .collect();
    serde_json::to_vec(&RuntimeProbePayload {
        provider: &request.provider,
        method: request.method,
        url: &request.url,
        headers,
        key_reference: request.key_reference.as_deref(),
    })
    .map_err(|_| CoreError::internal("remote provider probe metadata is invalid"))
}

fn parse_runtime_status(
    provider: &RemoteAiProviderKind,
    output: &[u8],
) -> CoreResult<RemoteProviderTestStatus> {
    let output = String::from_utf8_lossy(output);
    let status = output.trim();
    match status {
        "Succeeded" => Ok(RemoteProviderTestStatus::Succeeded),
        "ProviderRejected" => Ok(RemoteProviderTestStatus::ProviderRejected),
        "ConnectionFailed" => Ok(RemoteProviderTestStatus::ConnectionFailed),
        "UnsupportedProvider" => Ok(RemoteProviderTestStatus::UnsupportedProvider),
        _ => status
            .parse::<u16>()
            .map(|code| map_http_status(provider, code))
            .map_err(|_| CoreError::internal("remote provider runtime unavailable")),
    }
}

fn execute_curl_probe(request: &ProbeHttpRequest) -> CoreResult<RemoteProviderTestStatus> {
    let mut child = Command::new("curl")
        .arg("--config")
        .arg("-")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| CoreError::internal("remote provider runtime unavailable"))?;
    let Some(mut stdin) = child.stdin.take() else {
        return Err(CoreError::internal("remote provider runtime unavailable"));
    };
    stdin
        .write_all(curl_config(request).as_bytes())
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;
    drop(stdin);

    let output = child
        .wait_with_output()
        .map_err(|_| CoreError::internal(CONNECTION_FAILED_MESSAGE))?;
    if !output.status.success() {
        return Ok(RemoteProviderTestStatus::ConnectionFailed);
    }
    let status = parse_curl_status(&output.stdout)?;
    Ok(map_http_status(&request.provider, status))
}

fn render_http_request(request: &ProbeHttpRequest, url: &ProbeUrl) -> String {
    let mut rendered = format!(
        "{} {} HTTP/1.1\r\nHost: {}\r\nUser-Agent: AreaMatrix\r\nConnection: close\r\n",
        request.method, url.path, url.host
    );
    for (name, value) in &request.headers {
        rendered.push_str(name);
        rendered.push_str(": ");
        rendered.push_str(value);
        rendered.push_str("\r\n");
    }
    rendered.push_str("\r\n");
    rendered
}

fn curl_config(request: &ProbeHttpRequest) -> String {
    let mut config = format!(
        "silent\nshow-error\noutput = \"/dev/null\"\nwrite-out = \"%{{http_code}}\"\n\
         request = \"{}\"\nmax-time = \"10\"\nurl = \"{}\"\n",
        request.method,
        curl_config_value(&request.url)
    );
    for (name, value) in &request.headers {
        config.push_str("header = \"");
        config.push_str(&curl_config_value(&format!("{name}: {value}")));
        config.push_str("\"\n");
    }
    config
}

fn parse_probe_url(url: &str) -> CoreResult<ProbeUrl> {
    let (scheme, rest) = url
        .split_once("://")
        .ok_or_else(|| CoreError::config("remote provider endpoint is invalid"))?;
    let authority_end = rest.find('/').unwrap_or(rest.len());
    let authority = &rest[..authority_end];
    if authority.is_empty() || authority.contains('@') {
        return Err(CoreError::config("remote provider endpoint is invalid"));
    }
    let path = if authority_end < rest.len() {
        &rest[authority_end..]
    } else {
        "/"
    };
    let (host, port) = parse_authority(authority, scheme)?;
    Ok(ProbeUrl {
        scheme: scheme.to_owned(),
        host,
        port,
        path: path.to_owned(),
    })
}

fn parse_authority(authority: &str, scheme: &str) -> CoreResult<(String, u16)> {
    let default_port = if scheme == "https" { 443 } else { 80 };
    if let Some(rest) = authority.strip_prefix('[') {
        let (host, suffix) = rest
            .split_once(']')
            .ok_or_else(|| CoreError::config("remote provider endpoint is invalid"))?;
        return Ok((host.to_owned(), parse_optional_port(suffix, default_port)?));
    }
    let Some((host, port)) = authority.rsplit_once(':') else {
        return Ok((authority.to_owned(), default_port));
    };
    if port.chars().all(|value| value.is_ascii_digit()) {
        Ok((host.to_owned(), parse_port(port)?))
    } else {
        Ok((authority.to_owned(), default_port))
    }
}

fn parse_optional_port(suffix: &str, default_port: u16) -> CoreResult<u16> {
    if suffix.is_empty() {
        return Ok(default_port);
    }
    let port = suffix
        .strip_prefix(':')
        .ok_or_else(|| CoreError::config("remote provider endpoint is invalid"))?;
    parse_port(port)
}

fn parse_port(port: &str) -> CoreResult<u16> {
    port.parse()
        .map_err(|_| CoreError::config("remote provider endpoint is invalid"))
}

fn parse_http_status(response: &[u8]) -> CoreResult<u16> {
    let response = String::from_utf8_lossy(response);
    let Some(status) = response
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
    else {
        return Err(CoreError::internal(CONNECTION_FAILED_MESSAGE));
    };
    parse_port(status)
}

fn parse_curl_status(output: &[u8]) -> CoreResult<u16> {
    let output = String::from_utf8_lossy(output);
    let status = output.trim();
    if status.len() != 3 || !status.chars().all(|value| value.is_ascii_digit()) {
        return Err(CoreError::internal(CONNECTION_FAILED_MESSAGE));
    }
    parse_port(status)
}

fn map_http_status(provider: &RemoteAiProviderKind, status: u16) -> RemoteProviderTestStatus {
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

fn sanitized_probe_message(status: &RemoteProviderTestStatus) -> &'static str {
    match status {
        RemoteProviderTestStatus::Succeeded => VERIFIED_MESSAGE,
        RemoteProviderTestStatus::ProviderRejected => REJECTED_MESSAGE,
        RemoteProviderTestStatus::ConnectionFailed => CONNECTION_FAILED_MESSAGE,
        RemoteProviderTestStatus::UnsupportedProvider => UNSUPPORTED_MESSAGE,
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

fn curl_config_value(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn is_loopback_http_endpoint(endpoint: &str) -> bool {
    endpoint.starts_with("http://127.0.0.1:")
        || endpoint.starts_with("http://localhost:")
        || endpoint.starts_with("http://[::1]:")
}
