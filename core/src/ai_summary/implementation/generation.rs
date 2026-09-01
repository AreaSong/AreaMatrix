use std::path::{Path, PathBuf};

use serde_json::json;

use crate::{
    db, AiCapabilityState, AiFeatureKind, AiPrivacyEvaluationReport, AiPrivacyEvaluationRoute,
    AiPrivacyInputField, AiPrivacySkippedReason, CoreError, CoreResult,
    RecoverableOperationContext, RecoverableOperationStatus,
};

use super::{
    super::{
        call_log::ensure_summary_call_log_gate,
        context::{build_context, AiSummaryContext},
        executor::{execute_local, execute_remote, AiSummaryRuntimeDraft},
        validate_generation_request, validate_repo_path, AiSummaryDraft,
        AiSummaryGenerationRequest, AiSummaryInputField, AiSummaryRoute, AiSummarySkipReason,
    },
    common::map_file_lookup_error,
    draft::{
        draft_result, skipped, unavailable_after_runtime_error, unavailable_provider,
        SummaryDraftContext,
    },
    privacy::{matched_rule_id, privacy_blocks},
    route::select_route,
};

const AI_SUMMARY_FORMAT_VERSION: i64 = 1;

pub(in crate::ai_summary) fn generate_ai_summary(
    repo_path: String,
    request: AiSummaryGenerationRequest,
) -> CoreResult<AiSummaryDraft> {
    validate_repo_path(&repo_path)?;
    validate_generation_request(&request)?;
    let repo = PathBuf::from(&repo_path);
    let file = db::get_active_file_by_id(&repo, request.file_id).map_err(map_file_lookup_error)?;
    let ai_config = crate::ai_settings::load_ai_config(repo_path)?;
    let capability = summary_capability(&ai_config.capabilities)?;

    persist_operation_context(&repo, &request)?;
    let result = generate_after_context(&repo, &file, capability, &ai_config.config, &request);
    let (status, error_code) = match &result {
        Ok(_) => (RecoverableOperationStatus::Completed, None),
        Err(error) => (RecoverableOperationStatus::Failed, Some(error_code(error))),
    };
    db::update_recoverable_operation_status(&repo, &request.operation_id, status, error_code)?;
    result
}

fn generate_after_context(
    repo: &Path,
    file: &crate::FileEntry,
    capability: &AiCapabilityState,
    config: &crate::AiConfig,
    request: &AiSummaryGenerationRequest,
) -> CoreResult<AiSummaryDraft> {
    let draft_context = SummaryDraftContext {
        repo,
        file,
        operation_id: &request.operation_id,
        content_locale: &request.content_locale,
        format_contract_version: AI_SUMMARY_FORMAT_VERSION,
    };
    if !config.ai_enabled {
        return skipped(
            &draft_context,
            AiSummarySkipReason::AiDisabled,
            "AI summaries are off",
            false,
            None,
        );
    }
    if !capability.enabled {
        return skipped(
            &draft_context,
            AiSummarySkipReason::FeatureDisabled,
            "Auto summaries feature is off",
            false,
            None,
        );
    }
    let existing = db::load_ai_summary_metadata(repo, file.id)?
        .map(|row| row.summary_text)
        .filter(|summary| request.regenerate_existing || summary.trim().is_empty());
    let Some(route) = select_route(capability, &config.provider_preference, request, repo)? else {
        return unavailable_provider(
            repo,
            file,
            &request.operation_id,
            &request.content_locale,
            AI_SUMMARY_FORMAT_VERSION,
        );
    };
    let privacy = evaluate_privacy(repo, file, &route, request, existing.as_deref())?;
    if privacy_blocks(&privacy) {
        return skipped_by_privacy(&draft_context, privacy);
    }
    let context = build_context(
        repo,
        file,
        existing.as_deref(),
        &request.context_policy,
        &privacy.sent_fields,
    )?;
    if !has_eligible_input(&context) {
        return skipped(
            &draft_context,
            AiSummarySkipReason::NoEligibleInput,
            "No eligible AI summary input is available after privacy filtering",
            true,
            None,
        );
    }
    ensure_summary_call_log_gate(repo)?;
    let route_for_error = route.clone();
    let draft = match execute_summary(route, repo, &context, request.content_locale.as_str()) {
        Ok(draft) => draft,
        Err(error) => {
            return unavailable_after_runtime_error(
                &draft_context,
                route_for_error,
                &context,
                error,
            );
        }
    };
    draft_result(
        repo,
        file,
        &request.operation_id,
        &request.content_locale,
        AI_SUMMARY_FORMAT_VERSION,
        draft,
    )
}

fn evaluate_privacy(
    repo: &Path,
    file: &crate::FileEntry,
    route: &AiSummaryRoute,
    request: &AiSummaryGenerationRequest,
    existing_summary: Option<&str>,
) -> CoreResult<AiPrivacyEvaluationReport> {
    crate::ai_privacy_rules::evaluate_persisted_ai_privacy(
        repo,
        AiFeatureKind::AutoSummaries,
        match route {
            AiSummaryRoute::Local => AiPrivacyEvaluationRoute::Local,
            AiSummaryRoute::Remote => AiPrivacyEvaluationRoute::Remote,
        },
        requested_privacy_fields(request, existing_summary),
        crate::ai_privacy_rules::evaluation_context_for_file(repo, file)?,
    )
}

fn requested_privacy_fields(
    request: &AiSummaryGenerationRequest,
    existing_summary: Option<&str>,
) -> Vec<AiPrivacyInputField> {
    let mut fields = vec![
        AiPrivacyInputField::FileName,
        AiPrivacyInputField::RepoRelativePath,
    ];
    if existing_summary.is_some_and(|summary| !summary.trim().is_empty()) {
        fields.push(AiPrivacyInputField::AiSummary);
    }
    if matches!(
        request.context_policy,
        super::super::AiSummaryContextPolicy::MetadataAndExtractedText
            | super::super::AiSummaryContextPolicy::MetadataTextAndNotes
    ) {
        fields.push(AiPrivacyInputField::ExtractedTextExcerpt);
    }
    if matches!(
        request.context_policy,
        super::super::AiSummaryContextPolicy::MetadataTextAndNotes
    ) {
        fields.push(AiPrivacyInputField::NoteSummary);
        fields.push(AiPrivacyInputField::TagCategoryContext);
    }
    fields
}

fn skipped_by_privacy(
    context: &SummaryDraftContext<'_>,
    report: AiPrivacyEvaluationReport,
) -> CoreResult<AiSummaryDraft> {
    let rule_id = matched_rule_id(&report);
    let reason = if report.skipped_reason == Some(AiPrivacySkippedReason::NoEligibleInput) {
        AiSummarySkipReason::NoEligibleInput
    } else if report.provider_gate_reason.is_some() {
        AiSummarySkipReason::ProviderUnavailable
    } else {
        AiSummarySkipReason::PrivacyRule
    };
    skipped(context, reason, &report.message, true, rule_id)
}

fn persist_operation_context(repo: &Path, request: &AiSummaryGenerationRequest) -> CoreResult<()> {
    let payload = json!({
        "file_id": request.file_id,
        "provider_scope": format!("{:?}", request.provider_scope),
        "context_policy": format!("{:?}", request.context_policy),
        "regenerate_existing": request.regenerate_existing,
    });
    db::insert_recoverable_operation(
        repo,
        &RecoverableOperationContext {
            operation_id: request.operation_id.clone(),
            retry_of_operation_id: request.retry_of_operation_id.clone(),
            operation_code: "ai_summary_generation".to_owned(),
            operation_payload_json: serde_json::to_string(&payload)
                .map_err(|_| CoreError::internal("AI summary operation payload is invalid"))?,
            content_locale: Some(request.content_locale.clone()),
            repository_revision: db::load_repo_config_snapshot_or_default(
                repo.to_string_lossy().into_owned(),
            )?
            .revision,
            format_contract_version: AI_SUMMARY_FORMAT_VERSION,
            target_set_hash: None,
            run_sequence: 1,
        },
        RecoverableOperationStatus::Running,
    )?;
    Ok(())
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
    content_locale: &str,
) -> CoreResult<AiSummaryRuntimeDraft> {
    match route {
        AiSummaryRoute::Local => execute_local(context, content_locale),
        AiSummaryRoute::Remote => execute_remote(repo, context, content_locale),
    }
}

fn error_code(error: &CoreError) -> &'static str {
    match error {
        CoreError::Config { .. } => "config_error",
        CoreError::PermissionDenied { .. } => "permission_denied",
        CoreError::Db { .. } => "database_error",
        _ => "ai_summary_generation_failed",
    }
}
