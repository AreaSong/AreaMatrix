use std::path::Path;

use crate::{db, CoreError, CoreResult};

use super::{AiCategorySuggestionContextField, AiCategorySuggestionRoute};

const FEATURE_NAME: &str = "classification";

pub(super) struct CallLogDraft<'a> {
    pub(super) file_id: Option<i64>,
    pub(super) route: Option<&'a AiCategorySuggestionRoute>,
    pub(super) status: &'a str,
    pub(super) sent_fields: &'a [AiCategorySuggestionContextField],
    pub(super) privacy_rule_id: Option<&'a str>,
    pub(super) result_summary: &'a str,
    pub(super) error_code: Option<&'a str>,
    pub(super) model: Option<&'a str>,
}

pub(super) fn insert_call_log(repo: &Path, draft: CallLogDraft<'_>) -> CoreResult<Option<i64>> {
    let sent_fields_json = serde_json::to_string(&field_names(draft.sent_fields))
        .map_err(|_| CoreError::internal("AI call log fields are invalid"))?;
    let id = db::insert_ai_call_log_record(
        repo,
        db::AiCallLogRecord {
            feature: FEATURE_NAME.to_owned(),
            file_id: draft.file_id,
            route: draft.route.map(route_name),
            provider: draft.route.map(provider_name),
            model: draft
                .model
                .map(str::to_owned)
                .or_else(|| draft.route.map(model_name)),
            status: draft.status.to_owned(),
            sent_fields_json,
            privacy_rule_id: draft.privacy_rule_id.map(str::to_owned),
            result_summary: draft.result_summary.to_owned(),
            error_code: draft.error_code.map(str::to_owned),
        },
    )
    .map_err(map_call_log_error)?;
    Ok(Some(id))
}

fn field_names(fields: &[AiCategorySuggestionContextField]) -> Vec<&'static str> {
    fields
        .iter()
        .map(|field| match field {
            AiCategorySuggestionContextField::FileName => "filename",
            AiCategorySuggestionContextField::Extension => "extension",
            AiCategorySuggestionContextField::RepoRelativePath => "repo_relative_path",
            AiCategorySuggestionContextField::LimitedTextSummary => "limited_text_summary",
        })
        .collect()
}

fn route_name(route: &AiCategorySuggestionRoute) -> String {
    match route {
        AiCategorySuggestionRoute::Local => "local",
        AiCategorySuggestionRoute::Remote => "remote",
    }
    .to_owned()
}

fn provider_name(route: &AiCategorySuggestionRoute) -> String {
    match route {
        AiCategorySuggestionRoute::Local => "local_model",
        AiCategorySuggestionRoute::Remote => "remote_provider",
    }
    .to_owned()
}

fn model_name(route: &AiCategorySuggestionRoute) -> String {
    match route {
        AiCategorySuggestionRoute::Local => "areamatrix-local-classifier",
        AiCategorySuggestionRoute::Remote => "configured-remote-provider",
    }
    .to_owned()
}

fn map_call_log_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Db { .. } | CoreError::Io { .. } => {
            CoreError::internal("AI call log persistence failed")
        }
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI classification requires initialized repository metadata")
        }
        other => other,
    }
}
