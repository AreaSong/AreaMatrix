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

use super::{
    context::AiSuggestionContext, AiCategorySuggestionContextField, AiCategorySuggestionRoute,
};

const LOCAL_MODEL_ID: &str = "areamatrix-local-classifier";
const LOCAL_RUNTIME_ENV: &str = "AREAMATRIX_AI_CLASSIFICATION_LOCAL_RUNTIME";
const REMOTE_RUNTIME_ENV: &str = "AREAMATRIX_AI_CLASSIFICATION_REMOTE_RUNTIME";
const MIN_CONFIDENCE: f32 = 0.1;
const MAX_CONFIDENCE: f32 = 0.99;

#[derive(Clone, Debug)]
pub(super) struct AiSuggestionDraft {
    pub(super) category: Option<String>,
    pub(super) confidence: f32,
    pub(super) reason: String,
    pub(super) route: AiCategorySuggestionRoute,
    pub(super) model: String,
    pub(super) used_context: Vec<AiCategorySuggestionContextField>,
}

pub(super) fn execute_local(context: &AiSuggestionContext) -> CoreResult<AiSuggestionDraft> {
    if let Some(runtime_path) = runtime_path(LOCAL_RUNTIME_ENV) {
        return execute_external_runtime(
            runtime_path,
            RuntimePayload::local(context),
            AiCategorySuggestionRoute::Local,
            LOCAL_MODEL_ID.to_owned(),
            context.fields.clone(),
        );
    }
    Err(CoreError::internal(
        "AI classification local runtime unavailable",
    ))
}

pub(super) fn execute_remote(
    repo: &Path,
    context: &AiSuggestionContext,
) -> CoreResult<AiSuggestionDraft> {
    let config = crate::remote_provider_config::load_enabled_remote_provider_runtime(
        repo,
        AiFeatureKind::ClassificationSuggestions,
    )?
    .ok_or_else(|| CoreError::config("AI classification remote provider is unavailable"))?;
    let model = config.model_id.clone();
    let Some(runtime_path) = runtime_path(REMOTE_RUNTIME_ENV) else {
        return Err(CoreError::internal(
            "AI classification remote runtime unavailable",
        ));
    };
    execute_external_runtime(
        runtime_path,
        RuntimePayload::remote(context, &config),
        AiCategorySuggestionRoute::Remote,
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
    route: AiCategorySuggestionRoute,
    model: String,
    used_context: Vec<AiCategorySuggestionContextField>,
) -> CoreResult<AiSuggestionDraft> {
    let payload =
        serde_json::to_vec(&payload).map_err(|_| CoreError::internal("AI request is invalid"))?;
    let mut child = Command::new(runtime_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| CoreError::internal("AI classification runtime unavailable"))?;
    let Some(mut stdin) = child.stdin.take() else {
        return Err(CoreError::internal("AI classification runtime unavailable"));
    };
    stdin
        .write_all(&payload)
        .map_err(|_| CoreError::internal("AI classification runtime failed"))?;
    drop(stdin);

    let output = child
        .wait_with_output()
        .map_err(|_| CoreError::internal("AI classification runtime failed"))?;
    if !output.status.success() {
        return Err(CoreError::internal("AI classification runtime failed"));
    }
    parse_runtime_response(&output.stdout, route, model, used_context)
}

fn parse_runtime_response(
    output: &[u8],
    route: AiCategorySuggestionRoute,
    model: String,
    used_context: Vec<AiCategorySuggestionContextField>,
) -> CoreResult<AiSuggestionDraft> {
    let value: RuntimeResponse = serde_json::from_slice(output)
        .map_err(|_| CoreError::internal("AI classification response is invalid"))?;
    let category = value
        .category
        .filter(|category| !category.trim().is_empty())
        .map(|category| category.trim().to_owned());
    let reason = sanitize_response_text(
        value
            .reason
            .as_deref()
            .unwrap_or("AI classification completed"),
    );
    Ok(AiSuggestionDraft {
        category,
        confidence: value.confidence.clamp(MIN_CONFIDENCE, MAX_CONFIDENCE),
        reason,
        route,
        model,
        used_context,
    })
}

fn sanitize_response_text(value: &str) -> String {
    let sanitized = value
        .split_whitespace()
        .filter(|part| !looks_sensitive(part))
        .collect::<Vec<_>>()
        .join(" ");
    if sanitized.is_empty() {
        "AI classification completed".to_owned()
    } else {
        sanitized.chars().take(240).collect()
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
    extension: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    repo_relative_path: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    limited_text_summary: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    provider: Option<&'a RemoteAiProviderKind>,
    #[serde(skip_serializing_if = "Option::is_none")]
    endpoint_url: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    key_reference: Option<&'a str>,
}

impl<'a> RuntimePayload<'a> {
    fn local(context: &'a AiSuggestionContext) -> Self {
        Self {
            feature: "classification",
            route: "local",
            model: LOCAL_MODEL_ID,
            filename: &context.filename,
            extension: context.extension.as_deref(),
            repo_relative_path: context.repo_relative_path.as_deref(),
            limited_text_summary: context.limited_text_summary.as_deref(),
            provider: None,
            endpoint_url: None,
            key_reference: None,
        }
    }

    fn remote(context: &'a AiSuggestionContext, config: &'a StoredRemoteProviderConfig) -> Self {
        Self {
            feature: "classification",
            route: "remote",
            model: &config.model_id,
            filename: &context.filename,
            extension: context.extension.as_deref(),
            repo_relative_path: context.repo_relative_path.as_deref(),
            limited_text_summary: context.limited_text_summary.as_deref(),
            provider: Some(&config.provider),
            endpoint_url: config.endpoint_url.as_deref(),
            key_reference: Some(&config.key_reference),
        }
    }
}

#[derive(serde::Deserialize)]
struct RuntimeResponse {
    category: Option<String>,
    confidence: f32,
    reason: Option<String>,
}
