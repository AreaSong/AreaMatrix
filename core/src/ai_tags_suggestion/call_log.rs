use std::path::Path;

use crate::{db, CoreError, CoreResult};

use super::{AiTagSuggestionInputField, AiTagSuggestionRoute};

const FEATURE_NAME: &str = "tags";

pub(super) struct TagCallLogDraft<'a> {
    pub(super) file_id: Option<i64>,
    pub(super) route: Option<&'a AiTagSuggestionRoute>,
    pub(super) status: &'a str,
    pub(super) sent_fields: &'a [AiTagSuggestionInputField],
    pub(super) privacy_rule_id: Option<&'a str>,
    pub(super) result_summary: &'a str,
    pub(super) error_code: Option<&'a str>,
    pub(super) model: Option<&'a str>,
}

pub(super) fn insert_tag_call_log(repo: &Path, draft: TagCallLogDraft<'_>) -> CoreResult<i64> {
    let sent_fields_json = serde_json::to_string(&field_names(draft.sent_fields))
        .map_err(|_| CoreError::internal("AI tag call log fields are invalid"))?;
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

pub(super) fn ensure_tag_call_log_gate(repo: &Path) -> CoreResult<()> {
    db::ensure_ai_call_log_record_insertable(repo, tag_call_log_gate_record())
        .map_err(map_call_log_error)
}

fn tag_call_log_gate_record() -> db::AiCallLogInsertRecord {
    db::AiCallLogInsertRecord {
        feature: FEATURE_NAME.to_owned(),
        file_id: None,
        route: None,
        provider: None,
        model: None,
        status: "unavailable".to_owned(),
        sent_fields_json: "[]".to_owned(),
        privacy_rule_id: None,
        result_summary: "AI tag call log gate".to_owned(),
        error_code: Some("CallLogGate".to_owned()),
    }
}

fn field_names(fields: &[AiTagSuggestionInputField]) -> Vec<&'static str> {
    fields
        .iter()
        .map(|field| match field {
            AiTagSuggestionInputField::FileName => "filename",
            AiTagSuggestionInputField::RepoRelativePath => "repo_relative_path",
            AiTagSuggestionInputField::ExtractedTextExcerpt => "extracted_text_excerpt",
            AiTagSuggestionInputField::AiSummary => "ai_summary",
            AiTagSuggestionInputField::NoteSummary => "note_summary",
            AiTagSuggestionInputField::ExistingTags => "existing_tags",
            AiTagSuggestionInputField::TagRegistry => "tag_registry",
        })
        .collect()
}

fn route_name(route: &AiTagSuggestionRoute) -> String {
    match route {
        AiTagSuggestionRoute::Local => "local",
        AiTagSuggestionRoute::Remote => "remote",
    }
    .to_owned()
}

fn provider_name(route: &AiTagSuggestionRoute) -> String {
    match route {
        AiTagSuggestionRoute::Local => "local_model",
        AiTagSuggestionRoute::Remote => "remote_provider",
    }
    .to_owned()
}

fn model_name(route: &AiTagSuggestionRoute) -> String {
    match route {
        AiTagSuggestionRoute::Local => "areamatrix-local-tags",
        AiTagSuggestionRoute::Remote => "configured-remote-provider",
    }
    .to_owned()
}

fn map_call_log_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Db { .. } | CoreError::Io { .. } => CoreError::db("AI call log unavailable"),
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI tags require initialized repository metadata")
        }
        other => other,
    }
}
