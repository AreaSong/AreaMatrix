use std::path::Path;

use crate::{db, CoreError, CoreResult};

use super::{
    fallback::{BuildFallback, SearchFallback},
    SemanticSearchFallbackReason, SemanticSearchRoute,
};

const FEATURE_NAME: &str = "semantic_search";
const LOCAL_PROVIDER: &str = "local_model";
pub(super) const LOCAL_MODEL: &str = "areamatrix-local-semantic-index";

pub(super) struct SearchLog<'a> {
    route: Option<&'a SemanticSearchRoute>,
    status: &'static str,
    sent_fields: Vec<&'static str>,
    result_summary: String,
    error_code: Option<&'static str>,
    privacy_rule_id: Option<&'a str>,
}

impl<'a> SearchLog<'a> {
    pub(super) fn success(route: &'a SemanticSearchRoute, candidate_count: usize) -> Self {
        Self {
            route: Some(route),
            status: "success",
            sent_fields: semantic_sent_fields(candidate_count),
            result_summary: format!("Returned {candidate_count} semantic search candidates"),
            error_code: None,
            privacy_rule_id: None,
        }
    }

    pub(super) fn skipped(fallback: &'a SearchFallback) -> Self {
        Self {
            route: None,
            status: "skipped",
            sent_fields: Vec::new(),
            result_summary: fallback.message.to_owned(),
            error_code: Some(reason_code(&fallback.reason)),
            privacy_rule_id: fallback.privacy_rule_id.as_deref(),
        }
    }

    pub(super) fn build_result(
        route: &'a SemanticSearchRoute,
        processed_count: i64,
        failed_count: i64,
        privacy_rule_id: Option<&'a str>,
    ) -> Self {
        let status = if processed_count == 0 && failed_count > 0 {
            "failed"
        } else {
            "success"
        };
        let error_code = (failed_count > 0).then_some("SemanticIndexBuildFailed");
        Self {
            route: Some(route),
            status,
            sent_fields: default_sent_fields(),
            result_summary: format!(
                "Built semantic index metadata for {processed_count} files; {failed_count} failed"
            ),
            error_code,
            privacy_rule_id,
        }
    }

    pub(super) fn build_fallback(fallback: &'a BuildFallback) -> Self {
        Self {
            route: fallback.route.as_ref(),
            status: "skipped",
            sent_fields: Vec::new(),
            result_summary: fallback.message.to_owned(),
            error_code: Some(reason_code(&fallback.reason)),
            privacy_rule_id: None,
        }
    }
}

pub(super) fn insert_call_log(repo: &Path, log: SearchLog<'_>) -> CoreResult<i64> {
    db::insert_ai_call_log_record(repo, log.into_record()?)
}

pub(super) fn insert_call_log_in_tx(
    tx: &rusqlite::Transaction<'_>,
    log: SearchLog<'_>,
) -> CoreResult<i64> {
    db::insert_ai_call_log_record_in_tx(tx, log.into_record()?)
}

impl SearchLog<'_> {
    fn into_record(self) -> CoreResult<db::AiCallLogInsertRecord> {
        let sent_fields_json = serde_json::to_string(&self.sent_fields)
            .map_err(|_| CoreError::internal("semantic search call log fields are invalid"))?;
        Ok(db::AiCallLogInsertRecord {
            feature: FEATURE_NAME.to_owned(),
            file_id: None,
            route: self.route.map(route_name),
            provider: self.route.map(provider_name),
            model: self.route.map(model_name),
            status: self.status.to_owned(),
            sent_fields_json,
            privacy_rule_id: self.privacy_rule_id.map(str::to_owned),
            result_summary: self.result_summary,
            error_code: self.error_code.map(str::to_owned),
        })
    }
}

fn semantic_sent_fields(candidate_count: usize) -> Vec<&'static str> {
    if candidate_count == 0 {
        Vec::new()
    } else {
        default_sent_fields()
    }
}

fn default_sent_fields() -> Vec<&'static str> {
    vec![
        "filename",
        "repo_relative_path",
        "note_summary",
        "tag_category_context",
    ]
}

fn route_name(route: &SemanticSearchRoute) -> String {
    match route {
        SemanticSearchRoute::Local => "local",
        SemanticSearchRoute::Remote => "remote",
    }
    .to_owned()
}

fn provider_name(route: &SemanticSearchRoute) -> String {
    match route {
        SemanticSearchRoute::Local => LOCAL_PROVIDER,
        SemanticSearchRoute::Remote => "remote_provider",
    }
    .to_owned()
}

fn model_name(route: &SemanticSearchRoute) -> String {
    match route {
        SemanticSearchRoute::Local => LOCAL_MODEL,
        SemanticSearchRoute::Remote => "configured-remote-provider",
    }
    .to_owned()
}

fn reason_code(reason: &SemanticSearchFallbackReason) -> &'static str {
    match reason {
        SemanticSearchFallbackReason::AiDisabled => "AiDisabled",
        SemanticSearchFallbackReason::FeatureDisabled => "FeatureDisabled",
        SemanticSearchFallbackReason::ProviderUnavailable => "ProviderUnavailable",
        SemanticSearchFallbackReason::PrivacyRule => "PrivacyRule",
        SemanticSearchFallbackReason::SemanticIndexNotReady => "SemanticIndexNotReady",
        SemanticSearchFallbackReason::CallLogUnavailable => "CallLogUnavailable",
        SemanticSearchFallbackReason::NoEligibleInput => "NoEligibleInput",
        SemanticSearchFallbackReason::NormalSearchUnavailable => "NormalSearchUnavailable",
        SemanticSearchFallbackReason::RateLimited => "RateLimited",
        SemanticSearchFallbackReason::Timeout => "Timeout",
    }
}
