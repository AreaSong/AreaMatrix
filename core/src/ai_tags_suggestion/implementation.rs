use std::path::{Path, PathBuf};

use crate::{
    db, AiCapabilityState, AiFeatureKind, AiProviderPreference, CoreError, CoreResult, FileEntry,
    RemoteProviderConfigSnapshot,
};

use super::{
    call_log::{ensure_tag_call_log_gate, insert_tag_call_log, TagCallLogDraft},
    context::{build_context, has_eligible_input, AiTagSuggestionContext},
    executor::{execute_local, execute_remote, AiTagRuntimeDraft},
    normalize_tag_slug,
    report::{base_report, build_suggestions, TagReportBuilder},
    validate_apply_request, validate_repo_path, validate_suggestion_request,
    AiTagSuggestionApplyReport, AiTagSuggestionReport, AiTagSuggestionReportStatus,
    AiTagSuggestionRequest, AiTagSuggestionRoute, AiTagSuggestionSkipReason,
    ApplyAiTagSuggestionsRequest,
};

const CONFIDENCE_THRESHOLD: f32 = 0.8;

pub(super) fn suggest_tags_with_ai(
    repo_path: String,
    request: AiTagSuggestionRequest,
) -> CoreResult<AiTagSuggestionReport> {
    validate_repo_path(&repo_path)?;
    validate_suggestion_request(&request)?;

    let repo = PathBuf::from(&repo_path);
    let file = db::get_active_file_by_id(&repo, request.file_id).map_err(map_metadata_error)?;
    let ai_config = crate::ai_settings::load_ai_config(repo_path)?;
    let capability = tag_capability(&ai_config.capabilities)?;

    if !ai_config.config.ai_enabled {
        return skipped(
            &repo,
            &file,
            AiTagSuggestionSkipReason::AiDisabled,
            "AI tags are off",
            None,
        );
    }
    if !capability.enabled {
        return skipped(
            &repo,
            &file,
            AiTagSuggestionSkipReason::FeatureDisabled,
            "Auto tags feature is off",
            None,
        );
    }
    if privacy_blocks(&ai_config.config.privacy_policy_ref, &request) {
        return skipped(
            &repo,
            &file,
            AiTagSuggestionSkipReason::PrivacyRule,
            "Skipped by privacy rule",
            privacy_rule_id(&request),
        );
    }

    let context =
        build_context(&repo, &file, &request.candidate_tags).map_err(map_metadata_error)?;
    if !has_eligible_input(&context) {
        return skipped(
            &repo,
            &file,
            AiTagSuggestionSkipReason::NoEligibleInput,
            "No eligible AI tag input is available",
            None,
        );
    }

    let Some(route) = select_route(capability, &ai_config.config.provider_preference, &repo)?
    else {
        return unavailable_provider(&repo, &file);
    };
    ensure_tag_call_log_gate(&repo)?;
    let route_for_error = route.clone();
    let draft = match execute_tags(route, &repo, &context) {
        Ok(draft) => draft,
        Err(error) => {
            return unavailable_after_runtime_error(&repo, &file, route_for_error, &context, error);
        }
    };
    draft_result(&repo, &file, &context, draft)
}

pub(super) fn apply_ai_tag_suggestions(
    repo_path: String,
    request: ApplyAiTagSuggestionsRequest,
) -> CoreResult<AiTagSuggestionApplyReport> {
    validate_repo_path(&repo_path)?;
    validate_apply_request(&request)?;
    let rows = apply_rows(&request)?;
    let repo = PathBuf::from(&repo_path);
    db::apply_ai_tag_suggestion_rows(
        &repo,
        request.file_id,
        &rows,
        db::AiTagSuggestionApplyProvenance {
            source_call_log_id: request.call_log_id,
            privacy_rule_id: request.privacy_rule_id.clone(),
        },
    )
    .map_err(map_metadata_error)
}

fn tag_capability(capabilities: &[AiCapabilityState]) -> CoreResult<&AiCapabilityState> {
    capabilities
        .iter()
        .find(|state| state.feature == AiFeatureKind::AutoTags)
        .ok_or_else(|| CoreError::config("AI tag capability is not configured"))
}

fn privacy_blocks(config_ref: &Option<String>, request: &AiTagSuggestionRequest) -> bool {
    let reference = request.privacy_policy_ref.as_ref().or(config_ref.as_ref());
    reference.is_some_and(|value| {
        let normalized = value.to_ascii_lowercase();
        normalized.contains("block")
            || normalized.contains("deny")
            || normalized.contains("private")
    })
}

fn privacy_rule_id(request: &AiTagSuggestionRequest) -> Option<String> {
    request
        .privacy_policy_ref
        .as_ref()
        .map(|value| format!("rule:{value}"))
}

fn select_route(
    capability: &AiCapabilityState,
    preference: &AiProviderPreference,
    repo: &Path,
) -> CoreResult<Option<AiTagSuggestionRoute>> {
    if matches!(preference, AiProviderPreference::RemoteFirst) && capability.remote_allowed {
        return remote_route(repo);
    }
    if capability.local_allowed {
        return Ok(Some(AiTagSuggestionRoute::Local));
    }
    if capability.remote_allowed {
        return remote_route(repo);
    }
    Ok(None)
}

fn remote_route(repo: &Path) -> CoreResult<Option<AiTagSuggestionRoute>> {
    let snapshot = crate::remote_provider_config::load_remote_ai_provider_config(
        repo.to_string_lossy().into_owned(),
    )?;
    if remote_provider_allows_tags(&snapshot) {
        Ok(Some(AiTagSuggestionRoute::Remote))
    } else {
        Ok(None)
    }
}

fn remote_provider_allows_tags(snapshot: &RemoteProviderConfigSnapshot) -> bool {
    snapshot.provider_configured
        && snapshot.provider_verified
        && snapshot.remote_provider_enabled
        && snapshot.credential_configured
        && snapshot.feature_scope.contains(&AiFeatureKind::AutoTags)
}

fn execute_tags(
    route: AiTagSuggestionRoute,
    repo: &Path,
    context: &AiTagSuggestionContext,
) -> CoreResult<AiTagRuntimeDraft> {
    match route {
        AiTagSuggestionRoute::Local => execute_local(context),
        AiTagSuggestionRoute::Remote => execute_remote(repo, context),
    }
}

fn draft_result(
    repo: &Path,
    file: &FileEntry,
    context: &AiTagSuggestionContext,
    draft: AiTagRuntimeDraft,
) -> CoreResult<AiTagSuggestionReport> {
    let suggestions = build_suggestions(file.id, context, &draft.suggestions, CONFIDENCE_THRESHOLD);
    let status = if suggestions.is_empty() {
        AiTagSuggestionReportStatus::NoSuggestion
    } else {
        AiTagSuggestionReportStatus::Suggested
    };
    let result_summary = if suggestions.is_empty() {
        "No AI tag suggestion is available".to_owned()
    } else {
        format!("Suggested {} AI tags", suggestions.len())
    };
    let call_log_id = insert_tag_call_log(
        repo,
        TagCallLogDraft {
            file_id: Some(file.id),
            route: Some(&draft.route),
            status: "success",
            sent_fields: &draft.used_context,
            privacy_rule_id: None,
            result_summary: &result_summary,
            error_code: None,
            model: Some(&draft.model),
        },
    )?;
    Ok(base_report(file, status, CONFIDENCE_THRESHOLD)
        .with_suggestions(suggestions)
        .with_route(draft.route)
        .with_model(draft.model)
        .with_generated_at(current_timestamp())
        .with_context(draft.used_context)
        .with_call_log(call_log_id)
        .with_ai_boundary(true))
}

fn skipped(
    repo: &Path,
    file: &FileEntry,
    reason: AiTagSuggestionSkipReason,
    message: &str,
    privacy_rule_id: Option<String>,
) -> CoreResult<AiTagSuggestionReport> {
    let call_log_id = insert_tag_call_log(
        repo,
        TagCallLogDraft {
            file_id: Some(file.id),
            route: None,
            status: "skipped",
            sent_fields: &[],
            privacy_rule_id: privacy_rule_id.as_deref(),
            result_summary: message,
            error_code: None,
            model: None,
        },
    )?;
    Ok(base_report(
        file,
        AiTagSuggestionReportStatus::Skipped,
        CONFIDENCE_THRESHOLD,
    )
    .with_skipped_reason(reason)
    .with_privacy_rule(privacy_rule_id)
    .with_call_log(call_log_id))
}

fn unavailable_provider(repo: &Path, file: &FileEntry) -> CoreResult<AiTagSuggestionReport> {
    let call_log_id = insert_tag_call_log(
        repo,
        TagCallLogDraft {
            file_id: Some(file.id),
            route: None,
            status: "unavailable",
            sent_fields: &[],
            privacy_rule_id: None,
            result_summary: "AI tag provider is unavailable",
            error_code: Some("ProviderUnavailable"),
            model: None,
        },
    )?;
    Ok(base_report(
        file,
        AiTagSuggestionReportStatus::Unavailable,
        CONFIDENCE_THRESHOLD,
    )
    .with_skipped_reason(AiTagSuggestionSkipReason::ProviderUnavailable)
    .with_call_log(call_log_id))
}

fn unavailable_after_runtime_error(
    repo: &Path,
    file: &FileEntry,
    route: AiTagSuggestionRoute,
    context: &AiTagSuggestionContext,
    error: CoreError,
) -> CoreResult<AiTagSuggestionReport> {
    let message = runtime_error_message(route.clone());
    let call_log_id = insert_tag_call_log(
        repo,
        TagCallLogDraft {
            file_id: Some(file.id),
            route: Some(&route),
            status: "failed",
            sent_fields: &context.fields,
            privacy_rule_id: None,
            result_summary: &message,
            error_code: Some(runtime_error_code(&error)),
            model: None,
        },
    )?;
    Ok(base_report(
        file,
        AiTagSuggestionReportStatus::Unavailable,
        CONFIDENCE_THRESHOLD,
    )
    .with_route(route.clone())
    .with_context(context.fields.clone())
    .with_skipped_reason(AiTagSuggestionSkipReason::ProviderUnavailable)
    .with_call_log(call_log_id)
    .with_network(route == AiTagSuggestionRoute::Remote)
    .with_ai_boundary(true))
}

fn runtime_error_code(error: &CoreError) -> &'static str {
    match error {
        CoreError::Config { .. } => "ProviderUnavailable",
        CoreError::PermissionDenied { .. } => "PermissionDenied",
        _ => "RuntimeFailed",
    }
}

fn runtime_error_message(route: AiTagSuggestionRoute) -> String {
    match route {
        AiTagSuggestionRoute::Local => "AI tags local runtime is unavailable",
        AiTagSuggestionRoute::Remote => "AI tags remote provider failed",
    }
    .to_owned()
}

fn apply_rows(
    request: &ApplyAiTagSuggestionsRequest,
) -> CoreResult<Vec<db::AiTagSuggestionApplyRow>> {
    request
        .suggestions
        .iter()
        .map(|item| {
            let slug = match item.merge_target_slug.as_deref() {
                Some(target) => normalize_tag_slug(target)?,
                None => normalize_tag_slug(&item.slug)?,
            };
            Ok(db::AiTagSuggestionApplyRow {
                suggestion_id: item.suggestion_id.trim().to_owned(),
                slug,
                display_name: item.display_name.trim().to_owned(),
                confidence: item.confidence,
                edited_by_user: item.edited_by_user,
                merge_target_slug: item.merge_target_slug.clone(),
            })
        })
        .collect()
}

fn current_timestamp() -> i64 {
    chrono::Utc::now().timestamp()
}

fn map_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::PermissionDenied { .. } | CoreError::Io { .. } => error,
        CoreError::RepoNotInitialized { .. }
        | CoreError::InvalidPath { .. }
        | CoreError::Config { .. } => CoreError::db("AI tag metadata is unavailable"),
        other => other,
    }
}
