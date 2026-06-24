use std::path::{Path, PathBuf};

use crate::{db, AiCapabilityState, AiFeatureKind, CoreError, CoreResult};

use super::{
    super::{
        call_log::ensure_summary_call_log_gate,
        context::{build_context, AiSummaryContext},
        executor::{execute_local, execute_remote, AiSummaryRuntimeDraft},
        validate_generation_request, validate_repo_path, AiSummaryDraft,
        AiSummaryGenerationRequest, AiSummaryInputField, AiSummaryRoute, AiSummarySkipReason,
    },
    common::map_file_lookup_error,
    draft::{draft_result, skipped, unavailable_after_runtime_error, unavailable_provider},
    privacy::{privacy_blocks, privacy_rule_id},
    route::select_route,
};

pub(in crate::ai_summary) fn generate_ai_summary(
    repo_path: String,
    request: AiSummaryGenerationRequest,
) -> CoreResult<AiSummaryDraft> {
    validate_repo_path(&repo_path)?;
    validate_generation_request(&request)?;

    let repo = PathBuf::from(&repo_path);
    let file = db::get_active_file_by_id(&repo, request.file_id).map_err(map_file_lookup_error)?;
    let ai_config = crate::ai_settings::load_ai_config(repo_path.clone())?;
    let capability = summary_capability(&ai_config.capabilities)?;

    if !ai_config.config.ai_enabled {
        return skipped(
            &repo,
            &file,
            AiSummarySkipReason::AiDisabled,
            "AI summaries are off",
            None,
        );
    }
    if !capability.enabled {
        return skipped(
            &repo,
            &file,
            AiSummarySkipReason::FeatureDisabled,
            "Auto summaries feature is off",
            None,
        );
    }
    if privacy_blocks(&ai_config.config.privacy_policy_ref, &request) {
        return skipped(
            &repo,
            &file,
            AiSummarySkipReason::PrivacyRule,
            "Skipped by privacy rule",
            privacy_rule_id(&request),
        );
    }

    let existing_summary = db::load_ai_summary_metadata(&repo, file.id)?
        .map(|row| row.summary_text)
        .filter(|summary| request.regenerate_existing || summary.trim().is_empty());
    let context = build_context(
        &repo,
        &file,
        existing_summary.as_deref(),
        &request.context_policy,
    )?;
    if !has_eligible_input(&context) {
        return skipped(
            &repo,
            &file,
            AiSummarySkipReason::NoEligibleInput,
            "No eligible AI summary input is available",
            None,
        );
    }

    let Some(route) = select_route(
        capability,
        &ai_config.config.provider_preference,
        &request,
        &repo,
    )?
    else {
        return unavailable_provider(&repo, &file);
    };
    ensure_summary_call_log_gate(&repo)?;
    let route_for_error = route.clone();
    let draft = match execute_summary(route, &repo, &context) {
        Ok(draft) => draft,
        Err(error) => {
            return unavailable_after_runtime_error(&repo, &file, route_for_error, &context, error);
        }
    };
    draft_result(&repo, &file, draft)
}

fn summary_capability(capabilities: &[AiCapabilityState]) -> CoreResult<&AiCapabilityState> {
    capabilities
        .iter()
        .find(|state| state.feature == AiFeatureKind::AutoSummaries)
        .ok_or_else(|| CoreError::config("AI summary capability is not configured"))
}

fn has_eligible_input(context: &AiSummaryContext) -> bool {
    context.fields.iter().any(|field| {
        matches!(
            field,
            AiSummaryInputField::FileName
                | AiSummaryInputField::RepoRelativePath
                | AiSummaryInputField::ExtractedTextExcerpt
                | AiSummaryInputField::NoteSummary
                | AiSummaryInputField::TagCategoryContext
        )
    })
}

fn execute_summary(
    route: AiSummaryRoute,
    repo: &Path,
    context: &AiSummaryContext,
) -> CoreResult<AiSummaryRuntimeDraft> {
    match route {
        AiSummaryRoute::Local => execute_local(context),
        AiSummaryRoute::Remote => execute_remote(repo, context),
    }
}
