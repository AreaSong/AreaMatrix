use std::{env, ffi::OsString, path::Path, process::Command, time::Duration};

use serde::Serialize;

use crate::{
    external_runtime::{ExternalRuntimeError, ExternalRuntimeLimits},
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
const MAX_REASON_CHARS: usize = 240;
const RUNTIME_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_RUNTIME_OUTPUT_BYTES: usize = 1024 * 1024;

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
    if !output.status.success() {
        return Err(CoreError::internal("AI classification runtime failed"));
    }
    parse_runtime_response(&output.stdout, route, model, used_context)
}

fn map_runtime_error(error: ExternalRuntimeError) -> CoreError {
    match error {
        ExternalRuntimeError::Spawn => CoreError::internal("AI classification runtime unavailable"),
        _ => CoreError::internal("AI classification runtime failed"),
    }
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
    let reason = crate::ai_runtime::sanitize_response_text(
        value
            .reason
            .as_deref()
            .unwrap_or("AI classification completed"),
        "AI classification completed",
        MAX_REASON_CHARS,
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
