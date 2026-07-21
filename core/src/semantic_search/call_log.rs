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
    privacy_rules_checked: bool,
    privacy_rule_id: Option<&'a str>,
    model: Option<&'a str>,
}

impl<'a> SearchLog<'a> {
    pub(super) fn success(route: &'a SemanticSearchRoute, candidate_count: usize) -> Self {
        Self::success_with_model(route, candidate_count, None)
    }

    pub(super) fn success_with_model(
        route: &'a SemanticSearchRoute,
        candidate_count: usize,
        model: Option<&'a str>,
    ) -> Self {
        Self {
            route: Some(route),
            status: "success",
            sent_fields: semantic_sent_fields(candidate_count),
            result_summary: format!("Returned {candidate_count} semantic search candidates"),
            error_code: None,
            privacy_rules_checked: true,
            privacy_rule_id: None,
            model,
        }
    }

    pub(super) fn skipped(fallback: &'a SearchFallback) -> Self {
        Self {
            route: None,
            status: "skipped",
            sent_fields: Vec::new(),
            result_summary: fallback.message.to_owned(),
            error_code: Some(reason_code(&fallback.reason)),
            privacy_rules_checked: fallback.privacy_rules_checked,
            privacy_rule_id: fallback.privacy_rule_id.as_deref(),
            model: None,
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
            privacy_rules_checked: true,
            privacy_rule_id,
            model: None,
        }
    }

    pub(super) fn build_result_with_model(
        route: &'a SemanticSearchRoute,
        processed_count: i64,
        failed_count: i64,
        privacy_rule_id: Option<&'a str>,
        model: Option<&'a str>,
    ) -> Self {
        let mut log = Self::build_result(route, processed_count, failed_count, privacy_rule_id);
        log.model = model;
        log
    }

    pub(super) fn build_fallback(fallback: &'a BuildFallback) -> Self {
        Self {
            route: fallback.route.as_ref(),
            status: "skipped",
            sent_fields: Vec::new(),
            result_summary: fallback.message.to_owned(),
            error_code: Some(reason_code(&fallback.reason)),
            privacy_rules_checked: fallback.privacy_rules_checked,
            privacy_rule_id: None,
            model: None,
        }
    }
}

pub(super) fn ensure_semantic_call_log_gate(repo: &Path) -> CoreResult<()> {
    db::ensure_ai_call_log_record_insertable(repo, semantic_call_log_gate_record())
        .map_err(map_gate_error)
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
            model: self
                .model
                .map(str::to_owned)
                .or_else(|| self.route.map(model_name)),
            status: self.status.to_owned(),
            sent_fields_json,
            privacy_rules_checked: self.privacy_rules_checked,
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

fn semantic_call_log_gate_record() -> db::AiCallLogInsertRecord {
    db::AiCallLogInsertRecord {
        feature: FEATURE_NAME.to_owned(),
        file_id: None,
        route: None,
        provider: None,
        model: None,
        status: "unavailable".to_owned(),
        sent_fields_json: "[]".to_owned(),
        privacy_rules_checked: true,
        privacy_rule_id: None,
        result_summary: "Semantic search call log gate".to_owned(),
        error_code: Some("CallLogGate".to_owned()),
    }
}

fn map_gate_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Db { .. } | CoreError::Io { .. } => CoreError::db("AI call log unavailable"),
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("Semantic search requires initialized repository metadata")
        }
        other => other,
    }
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
