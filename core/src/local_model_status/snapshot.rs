//! Local model status snapshot construction helpers.

use crate::{
    AiFeatureKind, LocalModelAvailability, LocalModelFeatureStatus, LocalModelRecommendedAction,
    LocalModelStatusRequest, LocalModelStatusSnapshot,
};

pub(super) struct SnapshotDraft<'a> {
    pub(super) request: &'a LocalModelStatusRequest,
    pub(super) availability: LocalModelAvailability,
    pub(super) version: Option<String>,
    pub(super) size_bytes: Option<i64>,
    pub(super) last_error: Option<String>,
    pub(super) checked_at: i64,
    pub(super) diagnostics_summary: String,
    pub(super) feature_statuses: Option<Vec<LocalModelFeatureStatus>>,
}

pub(super) fn snapshot(draft: SnapshotDraft<'_>) -> LocalModelStatusSnapshot {
    LocalModelStatusSnapshot {
        model_id: draft.request.model_id.clone(),
        storage_location: draft.request.storage_location.clone(),
        recommended_action: recommended_action(&draft.availability),
        feature_statuses: draft
            .feature_statuses
            .unwrap_or_else(|| default_feature_statuses(&draft.availability)),
        availability: draft.availability,
        version: draft.version,
        size_bytes: draft.size_bytes,
        last_error: draft.last_error,
        last_checked_at: Some(draft.checked_at),
        diagnostics_summary: draft.diagnostics_summary,
    }
}

pub(super) fn default_feature_statuses(
    availability: &LocalModelAvailability,
) -> Vec<LocalModelFeatureStatus> {
    let available = matches!(availability, LocalModelAvailability::Ready);
    all_features()
        .into_iter()
        .map(|feature| LocalModelFeatureStatus {
            feature,
            available,
            unavailable_reason: if available {
                None
            } else {
                Some(unavailable_reason(availability))
            },
        })
        .collect()
}

pub(super) fn unavailable_reason(availability: &LocalModelAvailability) -> String {
    match availability {
        LocalModelAvailability::Unknown => "Local model status is unknown",
        LocalModelAvailability::NotInstalled => "Local model is not installed",
        LocalModelAvailability::PathUnreadable => "Local model path cannot be read",
        LocalModelAvailability::VersionIncompatible => "Local model version is incompatible",
        LocalModelAvailability::Checking => "Local model status check is running",
        LocalModelAvailability::Verifying => "Local model manifest verification is running",
        LocalModelAvailability::Loading => "Local model runtime is loading",
        LocalModelAvailability::Corrupted => "Local model metadata is corrupted",
        LocalModelAvailability::RuntimeFailed => "Local model runtime failed",
        LocalModelAvailability::Error => "Local model status check failed",
        LocalModelAvailability::Ready => "Local model is ready",
    }
    .to_owned()
}

fn recommended_action(availability: &LocalModelAvailability) -> LocalModelRecommendedAction {
    match availability {
        LocalModelAvailability::Unknown => LocalModelRecommendedAction::CheckStatus,
        LocalModelAvailability::Ready => LocalModelRecommendedAction::None,
        LocalModelAvailability::NotInstalled => LocalModelRecommendedAction::OpenInstallHelp,
        LocalModelAvailability::PathUnreadable => LocalModelRecommendedAction::OpenModelLocation,
        LocalModelAvailability::VersionIncompatible => LocalModelRecommendedAction::OpenInstallHelp,
        LocalModelAvailability::Checking
        | LocalModelAvailability::Verifying
        | LocalModelAvailability::Loading => LocalModelRecommendedAction::OpenDiagnostics,
        LocalModelAvailability::Corrupted => LocalModelRecommendedAction::RepairMetadata,
        LocalModelAvailability::RuntimeFailed => LocalModelRecommendedAction::RunHealthCheck,
        LocalModelAvailability::Error => LocalModelRecommendedAction::RetryStatusCheck,
    }
}

fn all_features() -> Vec<AiFeatureKind> {
    vec![
        AiFeatureKind::ClassificationSuggestions,
        AiFeatureKind::AutoTags,
        AiFeatureKind::SemanticSearch,
    ]
}

pub(super) fn feature_kind(value: &str) -> Option<AiFeatureKind> {
    match value {
        "ClassificationSuggestions" | "classification_suggestions" => {
            Some(AiFeatureKind::ClassificationSuggestions)
        }
        "AutoSummaries" | "auto_summaries" => Some(AiFeatureKind::AutoSummaries),
        "AutoTags" | "auto_tags" => Some(AiFeatureKind::AutoTags),
        "SemanticSearch" | "semantic_search" => Some(AiFeatureKind::SemanticSearch),
        _ => None,
    }
}
