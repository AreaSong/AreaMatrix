use std::path::Path;

use crate::{db, CoreError, CoreResult};

use super::{AiSummaryInputField, AiSummaryRoute};

const FEATURE_NAME: &str = "summary";

pub(super) struct SummaryCallLogDraft<'a> {
    pub(super) file_id: Option<i64>,
    pub(super) route: Option<&'a AiSummaryRoute>,
    pub(super) status: &'a str,
    pub(super) sent_fields: &'a [AiSummaryInputField],
    pub(super) privacy_rule_id: Option<&'a str>,
    pub(super) result_summary: &'a str,
    pub(super) error_code: Option<&'a str>,
    pub(super) model: Option<&'a str>,
}

pub(super) fn insert_summary_call_log(
    repo: &Path,
    draft: SummaryCallLogDraft<'_>,
) -> CoreResult<i64> {
    let sent_fields_json = serde_json::to_string(&field_names(draft.sent_fields))
        .map_err(|_| CoreError::internal("AI summary call log fields are invalid"))?;
    db::insert_ai_call_log_record(
        repo,
        db::AiCallLogInsertRecord {
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
    .map_err(map_call_log_error)
}

fn field_names(fields: &[AiSummaryInputField]) -> Vec<&'static str> {
    fields
        .iter()
        .map(|field| match field {
            AiSummaryInputField::FileName => "filename",
            AiSummaryInputField::RepoRelativePath => "repo_relative_path",
            AiSummaryInputField::ExtractedTextExcerpt => "extracted_text_excerpt",
            AiSummaryInputField::ExistingAiSummary => "ai_summary",
            AiSummaryInputField::NoteSummary => "note_summary",
            AiSummaryInputField::TagCategoryContext => "tag_category_context",
        })
        .collect()
}

fn route_name(route: &AiSummaryRoute) -> String {
    match route {
        AiSummaryRoute::Local => "local",
        AiSummaryRoute::Remote => "remote",
    }
    .to_owned()
}

fn provider_name(route: &AiSummaryRoute) -> String {
    match route {
        AiSummaryRoute::Local => "local_model",
        AiSummaryRoute::Remote => "remote_provider",
    }
    .to_owned()
}

fn model_name(route: &AiSummaryRoute) -> String {
    match route {
        AiSummaryRoute::Local => "areamatrix-local-summary",
        AiSummaryRoute::Remote => "configured-remote-provider",
    }
    .to_owned()
}

fn map_call_log_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Db { .. } | CoreError::Io { .. } => CoreError::db("AI call log unavailable"),
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI summary requires initialized repository metadata")
        }
        other => other,
    }
}
