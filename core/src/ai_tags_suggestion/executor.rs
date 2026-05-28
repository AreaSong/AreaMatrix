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

use super::{context::AiTagSuggestionContext, AiTagSuggestionInputField, AiTagSuggestionRoute};

const LOCAL_MODEL_ID: &str = "areamatrix-local-tags";
const LOCAL_RUNTIME_ENV: &str = "AREAMATRIX_AI_TAGS_LOCAL_RUNTIME";
const REMOTE_RUNTIME_ENV: &str = "AREAMATRIX_AI_TAGS_REMOTE_RUNTIME";
const MIN_CONFIDENCE: f32 = 0.05;
const MAX_CONFIDENCE: f32 = 0.99;
const MAX_REASON_CHARS: usize = 240;

#[derive(Clone, Debug)]
pub(super) struct AiTagRuntimeDraft {
    pub(super) suggestions: Vec<AiTagRuntimeSuggestion>,
    pub(super) route: AiTagSuggestionRoute,
    pub(super) model: String,
    pub(super) used_context: Vec<AiTagSuggestionInputField>,
}

#[derive(Clone, Debug)]
pub(super) struct AiTagRuntimeSuggestion {
    pub(super) slug: String,
    pub(super) display_name: Option<String>,
    pub(super) confidence: f32,
    pub(super) reason: String,
    pub(super) merge_target_slug: Option<String>,
}

pub(super) fn execute_local(context: &AiTagSuggestionContext) -> CoreResult<AiTagRuntimeDraft> {
    if let Some(runtime_path) = runtime_path(LOCAL_RUNTIME_ENV) {
        return execute_external_runtime(
            runtime_path,
            RuntimePayload::local(context),
            AiTagSuggestionRoute::Local,
            LOCAL_MODEL_ID.to_owned(),
            context.fields.clone(),
        );
    }
    Err(CoreError::internal("AI tags local runtime unavailable"))
}

pub(super) fn execute_remote(
    repo: &Path,
    context: &AiTagSuggestionContext,
) -> CoreResult<AiTagRuntimeDraft> {
    let config = crate::remote_provider_config::load_enabled_remote_provider_runtime(
        repo,
        AiFeatureKind::AutoTags,
    )?
    .ok_or_else(|| CoreError::config("AI tags remote provider is unavailable"))?;
    let model = config.model_id.clone();
    let Some(runtime_path) = runtime_path(REMOTE_RUNTIME_ENV) else {
        return Err(CoreError::internal("AI tags remote runtime unavailable"));
    };
    execute_external_runtime(
        runtime_path,
        RuntimePayload::remote(context, &config),
        AiTagSuggestionRoute::Remote,
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
    route: AiTagSuggestionRoute,
    model: String,
    used_context: Vec<AiTagSuggestionInputField>,
) -> CoreResult<AiTagRuntimeDraft> {
    let payload = serde_json::to_vec(&payload)
        .map_err(|_| CoreError::internal("AI tag request is invalid"))?;
    let mut child = Command::new(runtime_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| CoreError::internal("AI tags runtime unavailable"))?;
    let Some(mut stdin) = child.stdin.take() else {
        return Err(CoreError::internal("AI tags runtime unavailable"));
    };
    stdin
        .write_all(&payload)
        .map_err(|_| CoreError::internal("AI tags runtime failed"))?;
    drop(stdin);

    let output = child
        .wait_with_output()
        .map_err(|_| CoreError::internal("AI tags runtime failed"))?;
    if !output.status.success() {
        return Err(CoreError::internal("AI tags runtime failed"));
    }
    parse_runtime_response(&output.stdout, route, model, used_context)
}

fn parse_runtime_response(
    output: &[u8],
    route: AiTagSuggestionRoute,
    model: String,
    used_context: Vec<AiTagSuggestionInputField>,
) -> CoreResult<AiTagRuntimeDraft> {
    let value: RuntimeResponse = serde_json::from_slice(output)
        .map_err(|_| CoreError::internal("AI tag response is invalid"))?;
    let suggestions = value
        .suggestions
        .into_iter()
        .map(runtime_suggestion)
        .collect();
    Ok(AiTagRuntimeDraft {
        suggestions,
        route,
        model,
        used_context,
    })
}

fn runtime_suggestion(value: RuntimeSuggestion) -> AiTagRuntimeSuggestion {
    AiTagRuntimeSuggestion {
        slug: value.slug.trim().to_owned(),
        display_name: value
            .display_name
            .map(|name| sanitize_response_text(&name))
            .filter(|name| !name.is_empty()),
        confidence: value.confidence.clamp(MIN_CONFIDENCE, MAX_CONFIDENCE),
        reason: sanitize_response_text(
            value
                .reason
                .as_deref()
                .unwrap_or("AI tag suggestion completed"),
        ),
        merge_target_slug: value.merge_target_slug.map(|slug| slug.trim().to_owned()),
    }
}

fn sanitize_response_text(value: &str) -> String {
    let sanitized = value
        .split_whitespace()
        .filter(|part| !looks_sensitive(part))
        .collect::<Vec<_>>()
        .join(" ");
    if sanitized.is_empty() {
        "AI tag suggestion completed".to_owned()
    } else {
        sanitized.chars().take(MAX_REASON_CHARS).collect()
    }
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
    ai_summary: Option<&'a str>,
    existing_tags: &'a [String],
    tag_registry: &'a [String],
    #[serde(skip_serializing_if = "Option::is_none")]
    provider: Option<&'a RemoteAiProviderKind>,
    #[serde(skip_serializing_if = "Option::is_none")]
    endpoint_url: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    key_reference: Option<&'a str>,
}

impl<'a> RuntimePayload<'a> {
    fn local(context: &'a AiTagSuggestionContext) -> Self {
        Self {
            feature: "tags",
            route: "local",
            model: LOCAL_MODEL_ID,
            filename: &context.filename,
            repo_relative_path: context.repo_relative_path.as_deref(),
            ai_summary: context.ai_summary.as_deref(),
            existing_tags: &context.existing_tags,
            tag_registry: &context.tag_registry,
            provider: None,
            endpoint_url: None,
            key_reference: None,
        }
    }

    fn remote(context: &'a AiTagSuggestionContext, config: &'a StoredRemoteProviderConfig) -> Self {
        Self {
            feature: "tags",
            route: "remote",
            model: &config.model_id,
            filename: &context.filename,
            repo_relative_path: context.repo_relative_path.as_deref(),
            ai_summary: context.ai_summary.as_deref(),
            existing_tags: &context.existing_tags,
            tag_registry: &context.tag_registry,
            provider: Some(&config.provider),
            endpoint_url: config.endpoint_url.as_deref(),
            key_reference: Some(&config.key_reference),
        }
    }
}

#[derive(serde::Deserialize)]
struct RuntimeResponse {
    suggestions: Vec<RuntimeSuggestion>,
}

#[derive(serde::Deserialize)]
struct RuntimeSuggestion {
    slug: String,
    display_name: Option<String>,
    confidence: f32,
    reason: Option<String>,
    merge_target_slug: Option<String>,
}
