use std::path::Path;

use crate::{
    AiCapabilityState, AiFeatureKind, AiProviderPreference, CoreResult,
    RemoteProviderConfigSnapshot,
};

use super::super::{AiSummaryGenerationRequest, AiSummaryProviderScope, AiSummaryRoute};

pub(super) fn select_route(
    capability: &AiCapabilityState,
    preference: &AiProviderPreference,
    request: &AiSummaryGenerationRequest,
    repo: &Path,
) -> CoreResult<Option<AiSummaryRoute>> {
    match request.provider_scope {
        AiSummaryProviderScope::LocalOnly => {
            return Ok(capability.local_allowed.then_some(AiSummaryRoute::Local));
        }
        AiSummaryProviderScope::RemoteAllowed
            if matches!(preference, AiProviderPreference::RemoteFirst)
                && capability.remote_allowed =>
        {
            return remote_route(repo);
        }
        _ => {}
    }
    if capability.local_allowed {
        return Ok(Some(AiSummaryRoute::Local));
    }
    if matches!(
        request.provider_scope,
        AiSummaryProviderScope::RemoteAllowed
    ) && capability.remote_allowed
    {
        return remote_route(repo);
    }
    Ok(None)
}

fn remote_route(repo: &Path) -> CoreResult<Option<AiSummaryRoute>> {
    let snapshot = crate::remote_provider_config::load_remote_ai_provider_config(
        repo.to_string_lossy().into_owned(),
    )?;
    if remote_provider_allows_summary(&snapshot) {
        Ok(Some(AiSummaryRoute::Remote))
    } else {
        Ok(None)
    }
}

fn remote_provider_allows_summary(snapshot: &RemoteProviderConfigSnapshot) -> bool {
    snapshot.provider_configured
        && snapshot.provider_verified
        && snapshot.remote_provider_enabled
        && snapshot.credential_configured
        && snapshot
            .feature_scope
            .contains(&AiFeatureKind::AutoSummaries)
}
