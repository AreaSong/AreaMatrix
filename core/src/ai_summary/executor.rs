use std::{
    env,
    ffi::OsString,
    io::Write,
    path::Path,
    process::{Command, Stdio},
};

use serde::Serialize;

use crate::{
    remote_provider_config::{RemoteAiProviderKind, StoredRemoteProviderConfig},
    AiFeatureKind, CoreError, CoreResult,
};

use super::{context::AiSummaryContext, AiSummaryInputField, AiSummaryRoute};

const LOCAL_MODEL_ID: &str = "areamatrix-local-summary";
const LOCAL_RUNTIME_ENV: &str = "AREAMATRIX_AI_SUMMARY_LOCAL_RUNTIME";
const REMOTE_RUNTIME_ENV: &str = "AREAMATRIX_AI_SUMMARY_REMOTE_RUNTIME";
const MAX_SUMMARY_CHARS: usize = 1_200;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AiSummaryRuntimeDraft {
    pub(super) summary_text: String,
    pub(super) route: AiSummaryRoute,
    pub(super) model: String,
    pub(super) used_context: Vec<AiSummaryInputField>,
}

pub(super) fn execute_local(context: &AiSummaryContext) -> CoreResult<AiSummaryRuntimeDraft> {
    if let Some(runtime_path) = runtime_path(LOCAL_RUNTIME_ENV) {
        return execute_external_runtime(
            runtime_path,
            RuntimePayload::local(context),
            AiSummaryRoute::Local,
            LOCAL_MODEL_ID.to_owned(),
            context.fields.clone(),
        );
    }
    Err(CoreError::internal("AI summary local runtime unavailable"))
}

pub(super) fn execute_remote(
    repo: &Path,
    context: &AiSummaryContext,
) -> CoreResult<AiSummaryRuntimeDraft> {
    let config = crate::remote_provider_config::load_enabled_remote_provider_runtime(
        repo,
        AiFeatureKind::AutoSummaries,
    )?
    .ok_or_else(|| CoreError::config("AI summary remote provider is unavailable"))?;
    let model = config.model_id.clone();
    let Some(runtime_path) = runtime_path(REMOTE_RUNTIME_ENV) else {
        return Err(CoreError::internal("AI summary remote runtime unavailable"));
    };
    execute_external_runtime(
        runtime_path,
        RuntimePayload::remote(context, &config),
        AiSummaryRoute::Remote,
        model,
        context.fields.clone(),
    )
}

fn runtime_path(env_name: &str) -> Option<OsString> {
    env::var_os(env_name).filter(|value| !value.is_empty())
}

fn execute_external_runtime(
    runtime_path: OsString,
    payload: RuntimePayload<'_>,
    route: AiSummaryRoute,
    model: String,
    used_context: Vec<AiSummaryInputField>,
) -> CoreResult<AiSummaryRuntimeDraft> {
    let payload = serde_json::to_vec(&payload)
        .map_err(|_| CoreError::internal("AI summary request is invalid"))?;
    let mut child = Command::new(runtime_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| CoreError::internal("AI summary runtime unavailable"))?;
    let Some(mut stdin) = child.stdin.take() else {
        return Err(CoreError::internal("AI summary runtime unavailable"));
    };
    stdin
        .write_all(&payload)
        .map_err(|_| CoreError::internal("AI summary runtime failed"))?;
    drop(stdin);

    let output = child
        .wait_with_output()
        .map_err(|_| CoreError::internal("AI summary runtime failed"))?;
    if !output.status.success() {
        return Err(CoreError::internal("AI summary runtime failed"));
    }
    parse_runtime_response(&output.stdout, route, model, used_context)
}

fn parse_runtime_response(
    output: &[u8],
    route: AiSummaryRoute,
    model: String,
    used_context: Vec<AiSummaryInputField>,
) -> CoreResult<AiSummaryRuntimeDraft> {
    let value: RuntimeResponse = serde_json::from_slice(output)
        .map_err(|_| CoreError::internal("AI summary response is invalid"))?;
    let summary_text = sanitize_response_text(&value.summary_text);
    if summary_text.is_empty() {
        return Err(CoreError::internal("AI summary response is empty"));
    }
    Ok(AiSummaryRuntimeDraft {
        summary_text,
        route,
        model,
        used_context,
    })
}

fn sanitize_response_text(value: &str) -> String {
    value
        .split_whitespace()
        .filter(|part| !looks_sensitive(part))
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(MAX_SUMMARY_CHARS)
        .collect()
}

fn looks_sensitive(value: &str) -> bool {
    let normalized = value.to_ascii_lowercase();
    normalized.starts_with("sk-")
        || normalized.starts_with("sk_")
        || normalized.contains("bearer")
        || normalized.contains("api_key")
        || normalized.contains("apikey")
        || normalized.contains("secret=")
        || normalized.contains("token=")
        || normalized.contains("-----begin")
}

#[derive(Serialize)]
struct RuntimePayload<'a> {
    feature: &'static str,
    route: &'static str,
    model: &'a str,
    filename: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    repo_relative_path: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    extracted_text_excerpt: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    existing_ai_summary: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    note_summary: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tag_category_context: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    provider: Option<&'a RemoteAiProviderKind>,
    #[serde(skip_serializing_if = "Option::is_none")]
    endpoint_url: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    key_reference: Option<&'a str>,
}

impl<'a> RuntimePayload<'a> {
    fn local(context: &'a AiSummaryContext) -> Self {
        Self {
            feature: "summary",
            route: "local",
            model: LOCAL_MODEL_ID,
            filename: &context.filename,
            repo_relative_path: context.repo_relative_path.as_deref(),
            extracted_text_excerpt: context.extracted_text_excerpt.as_deref(),
            existing_ai_summary: context.existing_ai_summary.as_deref(),
            note_summary: context.note_summary.as_deref(),
            tag_category_context: context.tag_category_context.as_deref(),
            provider: None,
            endpoint_url: None,
            key_reference: None,
        }
    }

    fn remote(context: &'a AiSummaryContext, config: &'a StoredRemoteProviderConfig) -> Self {
        Self {
            feature: "summary",
            route: "remote",
            model: &config.model_id,
            filename: &context.filename,
            repo_relative_path: context.repo_relative_path.as_deref(),
            extracted_text_excerpt: context.extracted_text_excerpt.as_deref(),
            existing_ai_summary: context.existing_ai_summary.as_deref(),
            note_summary: context.note_summary.as_deref(),
            tag_category_context: context.tag_category_context.as_deref(),
            provider: Some(&config.provider),
            endpoint_url: config.endpoint_url.as_deref(),
            key_reference: Some(&config.key_reference),
        }
    }
}

#[derive(serde::Deserialize)]
struct RuntimeResponse {
    summary_text: String,
}
