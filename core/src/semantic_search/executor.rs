use std::{env, ffi::OsString, path::Path, process::Command, time::Duration};

use serde::Serialize;

use crate::{
    db,
    external_runtime::{ExternalRuntimeError, ExternalRuntimeLimits},
    remote_provider_config::{RemoteAiProviderKind, StoredRemoteProviderConfig},
    AiFeatureKind, CoreResult, SearchFilter, SearchPagination,
};

const REMOTE_RUNTIME_ENV: &str = "AREAMATRIX_AI_SEMANTIC_REMOTE_RUNTIME";
const MAX_REASON_CHARS: usize = 512;
const RUNTIME_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_RUNTIME_OUTPUT_BYTES: usize = 1024 * 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum SemanticRemoteError {
    RateLimited,
    Timeout,
    Unavailable,
}

#[derive(Clone, Debug)]
pub(super) struct RemoteSearchMatchDraft {
    pub(super) file_id: i64,
    pub(super) relevance: f32,
    pub(super) reason: String,
}

#[derive(Clone, Debug)]
pub(super) struct RemoteSearchDraft {
    pub(super) matches: Vec<RemoteSearchMatchDraft>,
    pub(super) model: String,
}

#[derive(Clone, Debug)]
pub(super) struct RemoteBuildDraft {
    pub(super) model: String,
}

pub(super) fn execute_remote_search(
    repo: &Path,
    query: &str,
    filter: &SearchFilter,
    pagination: &SearchPagination,
) -> Result<RemoteSearchDraft, SemanticRemoteError> {
    let config = load_remote_config(repo)?;
    let runtime_path = runtime_path(REMOTE_RUNTIME_ENV).ok_or(SemanticRemoteError::Unavailable)?;
    let payload = SearchRuntimePayload::remote(query, filter, pagination, &config);
    let output = run_runtime(runtime_path, &payload)?;
    parse_search_response(&output, &config.model_id)
}

pub(super) fn execute_remote_build(
    repo: &Path,
    filter: &SearchFilter,
) -> Result<RemoteBuildDraft, SemanticRemoteError> {
    let config = load_remote_config(repo)?;
    let runtime_path = runtime_path(REMOTE_RUNTIME_ENV).ok_or(SemanticRemoteError::Unavailable)?;
    let payload = BuildRuntimePayload::remote(filter, &config);
    let output = run_runtime(runtime_path, &payload)?;
    parse_build_response(&output, &config.model_id)
}

pub(super) fn hydrate_remote_matches(
    repo: &Path,
    drafts: Vec<RemoteSearchMatchDraft>,
) -> CoreResult<Vec<RemoteSearchMatchDraft>> {
    let mut hydrated = Vec::new();
    for draft in drafts {
        if db::get_active_file_by_id(repo, draft.file_id).is_ok() {
            hydrated.push(draft);
        }
    }
    Ok(hydrated)
}

fn load_remote_config(repo: &Path) -> Result<StoredRemoteProviderConfig, SemanticRemoteError> {
    crate::remote_provider_config::load_enabled_remote_provider_runtime(
        repo,
        AiFeatureKind::SemanticSearch,
    )
    .map_err(|_| SemanticRemoteError::Unavailable)?
    .ok_or(SemanticRemoteError::Unavailable)
}

fn runtime_path(env_name: &str) -> Option<OsString> {
    env::var_os(env_name).filter(|value| !value.is_empty())
}

fn run_runtime(
    runtime_path: OsString,
    payload: &impl Serialize,
) -> Result<Vec<u8>, SemanticRemoteError> {
    let payload = serde_json::to_vec(payload).map_err(|_| SemanticRemoteError::Unavailable)?;
    let mut command = Command::new(runtime_path);
    let output = crate::external_runtime::run(
        &mut command,
        &payload,
        ExternalRuntimeLimits {
            timeout: RUNTIME_TIMEOUT,
            max_stdout_bytes: MAX_RUNTIME_OUTPUT_BYTES,
            preserved_environment: &[],
        },
    )
    .map_err(map_runtime_error)?;
    if output.status.success() {
        return Ok(output.stdout);
    }
    if is_rate_limited(&output) {
        return Err(SemanticRemoteError::RateLimited);
    }
    Err(SemanticRemoteError::Unavailable)
}

fn map_runtime_error(error: ExternalRuntimeError) -> SemanticRemoteError {
    match error {
        ExternalRuntimeError::TimedOut => SemanticRemoteError::Timeout,
        _ => SemanticRemoteError::Unavailable,
    }
}

fn is_rate_limited(output: &crate::external_runtime::ExternalRuntimeOutput) -> bool {
    output.status.code() == Some(429)
        || String::from_utf8_lossy(&output.stdout)
            .to_ascii_lowercase()
            .contains("rate_limited")
}

fn parse_search_response(
    output: &[u8],
    model: &str,
) -> Result<RemoteSearchDraft, SemanticRemoteError> {
    let value: SearchRuntimeResponse =
        serde_json::from_slice(output).map_err(|_| SemanticRemoteError::Unavailable)?;
    let matches = value
        .matches
        .into_iter()
        .map(|matched| RemoteSearchMatchDraft {
            file_id: matched.file_id,
            relevance: matched.relevance.clamp(0.0, 1.0),
            reason: crate::ai_runtime::sanitize_response_text(
                &matched.reason,
                "Semantic search match",
                MAX_REASON_CHARS,
            ),
        })
        .collect();
    Ok(RemoteSearchDraft {
        matches,
        model: model.to_owned(),
    })
}

fn parse_build_response(
    output: &[u8],
    model: &str,
) -> Result<RemoteBuildDraft, SemanticRemoteError> {
    let value: serde_json::Value =
        serde_json::from_slice(output).map_err(|_| SemanticRemoteError::Unavailable)?;
    if !value.is_object() {
        return Err(SemanticRemoteError::Unavailable);
    }
    Ok(RemoteBuildDraft {
        model: model.to_owned(),
    })
}

#[derive(Serialize)]
struct SearchRuntimePayload<'a> {
    feature: &'static str,
    operation: &'static str,
    route: &'static str,
    model: &'a str,
    query: &'a str,
    filter: &'a SearchFilter,
    pagination: &'a SearchPagination,
    #[serde(skip_serializing_if = "Option::is_none")]
    provider: Option<&'a RemoteAiProviderKind>,
    #[serde(skip_serializing_if = "Option::is_none")]
    endpoint_url: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    key_reference: Option<&'a str>,
}

impl<'a> SearchRuntimePayload<'a> {
    fn remote(
        query: &'a str,
        filter: &'a SearchFilter,
        pagination: &'a SearchPagination,
        config: &'a StoredRemoteProviderConfig,
    ) -> Self {
        Self {
            feature: "semantic_search",
            operation: "search",
            route: "remote",
            model: &config.model_id,
            query,
            filter,
            pagination,
            provider: Some(&config.provider),
            endpoint_url: config.endpoint_url.as_deref(),
            key_reference: Some(&config.key_reference),
        }
    }
}

#[derive(Serialize)]
struct BuildRuntimePayload<'a> {
    feature: &'static str,
    operation: &'static str,
    route: &'static str,
    model: &'a str,
    filter: &'a SearchFilter,
    #[serde(skip_serializing_if = "Option::is_none")]
    provider: Option<&'a RemoteAiProviderKind>,
    #[serde(skip_serializing_if = "Option::is_none")]
    endpoint_url: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    key_reference: Option<&'a str>,
}

impl<'a> BuildRuntimePayload<'a> {
    fn remote(filter: &'a SearchFilter, config: &'a StoredRemoteProviderConfig) -> Self {
        Self {
            feature: "semantic_search",
            operation: "build",
            route: "remote",
            model: &config.model_id,
            filter,
            provider: Some(&config.provider),
            endpoint_url: config.endpoint_url.as_deref(),
            key_reference: Some(&config.key_reference),
        }
    }
}

#[derive(serde::Deserialize)]
struct SearchRuntimeResponse {
    matches: Vec<SearchRuntimeMatch>,
}

#[derive(serde::Deserialize)]
struct SearchRuntimeMatch {
    file_id: i64,
    relevance: f32,
    reason: String,
}
