use std::path::Path;

use crate::{ai_call_log::AiCallLogRoute, db, CoreError, CoreResult};

use super::{AiFallbackCategory, AiFallbackKind, AiFallbackOperation, AiFallbackStatus};

pub(super) fn ensure_metadata_readable(repo: &Path) -> CoreResult<()> {
    db::ensure_initialized_readable(repo).map_err(map_metadata_error)
}

pub(super) fn insert_fallback_call_log(
    repo: &Path,
    status: &AiFallbackStatus,
    provider_error_code: Option<&str>,
) -> CoreResult<i64> {
    db::insert_ai_call_log_record(
        repo,
        db::AiCallLogInsertRecord {
            feature: feature_name(&status.operation).to_owned(),
            file_id: None,
            route: status.route.as_ref().map(route_name),
            provider: status.route.as_ref().map(provider_name),
            model: status.route.as_ref().map(model_name),
            status: log_status(status).to_owned(),
            sent_fields_json: "[]".to_owned(),
            privacy_rule_id: status.privacy_rule_id.clone(),
            result_summary: status.message.clone(),
            error_code: Some(
                provider_error_code
                    .map(str::to_owned)
                    .unwrap_or_else(|| error_code(status).to_owned()),
            ),
        },
    )
    .map_err(map_metadata_error)
}

fn map_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Config { .. } | CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI fallback requires initialized repository metadata")
        }
        CoreError::InvalidPath { path } => CoreError::Config { reason: path },
        CoreError::PermissionDenied { .. } => {
            CoreError::permission_denied("AI fallback metadata unavailable")
        }
        CoreError::Db { .. } | CoreError::Io { .. } => {
            CoreError::internal("AI fallback metadata unavailable")
        }
        other => other,
    }
}

fn feature_name(operation: &AiFallbackOperation) -> &'static str {
    match operation {
        AiFallbackOperation::ClassificationSuggestion => "classification",
        AiFallbackOperation::SemanticSearch | AiFallbackOperation::EmbeddingIndexBuild => {
            "semantic_search"
        }
    }
}

fn route_name(route: &AiCallLogRoute) -> String {
    match route {
        AiCallLogRoute::Local => "local",
        AiCallLogRoute::Remote => "remote",
    }
    .to_owned()
}

fn provider_name(route: &AiCallLogRoute) -> String {
    match route {
        AiCallLogRoute::Local => "local_model",
        AiCallLogRoute::Remote => "remote_provider",
    }
    .to_owned()
}

fn model_name(route: &AiCallLogRoute) -> String {
    match route {
        AiCallLogRoute::Local => "configured-local-model",
        AiCallLogRoute::Remote => "configured-remote-provider",
    }
    .to_owned()
}

fn log_status(status: &AiFallbackStatus) -> &'static str {
    match status.category {
        AiFallbackCategory::Disabled | AiFallbackCategory::Skipped => "skipped",
        AiFallbackCategory::Unavailable => "unavailable",
        AiFallbackCategory::Error => "failed",
    }
}

fn error_code(status: &AiFallbackStatus) -> &'static str {
    match status.kind {
        AiFallbackKind::AiDisabled => "AiDisabled",
        AiFallbackKind::FeatureDisabled => "FeatureDisabled",
        AiFallbackKind::LocalModelNotReady => "LocalModelNotReady",
        AiFallbackKind::RemoteNotConfigured => "RemoteNotConfigured",
        AiFallbackKind::RemoteFailed => "RemoteFailed",
        AiFallbackKind::ProviderUnavailable => "ProviderUnavailable",
        AiFallbackKind::PrivacySkipped => "PrivacySkipped",
        AiFallbackKind::SemanticIndexNotReady => "SemanticIndexNotReady",
        AiFallbackKind::NoEligibleInput => "NoEligibleInput",
        AiFallbackKind::NormalSearchUnavailable => "NormalSearchUnavailable",
        AiFallbackKind::CallLogUnavailable => "CallLogUnavailable",
        AiFallbackKind::RateLimited => "RateLimited",
        AiFallbackKind::Timeout => "Timeout",
        AiFallbackKind::InternalFailure => "InternalFailure",
    }
}
