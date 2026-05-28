use std::path::{Path, PathBuf};

use uuid::Uuid;

use crate::{
    db, AiCapabilityState, AiFeatureKind, AiProviderPreference, CoreError, CoreResult, FileEntry,
    RemoteProviderConfigSnapshot,
};

use super::{
    call_log::{ensure_summary_call_log_gate, insert_summary_call_log, SummaryCallLogDraft},
    context::{build_context, AiSummaryContext},
    executor::{execute_local, execute_remote, AiSummaryRuntimeDraft},
    validate_clear_request, validate_generation_request, validate_repo_path, validate_save_request,
    AiSummaryClearReport, AiSummaryClearRequest, AiSummaryDraft, AiSummaryDraftStatus,
    AiSummaryGenerationRequest, AiSummaryInputField, AiSummaryProviderScope, AiSummaryRoute,
    AiSummarySaveReport, AiSummarySaveRequest, AiSummarySkipReason,
};

pub(super) fn generate_ai_summary(
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

pub(super) fn save_ai_summary(
    repo_path: String,
    request: AiSummarySaveRequest,
) -> CoreResult<AiSummarySaveReport> {
    validate_repo_path(&repo_path)?;
    validate_save_request(&request)?;
    let repo = PathBuf::from(&repo_path);
    db::get_active_file_by_id(&repo, request.file_id).map_err(map_file_lookup_error)?;

    let used_context_json = used_context_json(&request.used_context)?;
    let stats = db::upsert_ai_summary_metadata(
        &repo,
        db::AiSummaryUpsert {
            file_id: request.file_id,
            summary_text: request.summary_text.clone(),
            draft_id: request.draft_id.clone(),
            route: request.route.as_ref().map(summary_route_to_db),
            model_name: request.model_name.clone(),
            generated_at: request.generated_at,
            used_context_json,
            privacy_rule_id: request.privacy_rule_id.clone(),
            call_log_id: request.call_log_id,
            edited_by_user: request.edited_by_user,
        },
    )?;
    Ok(AiSummarySaveReport {
        file_id: request.file_id,
        saved_summary: request.summary_text.clone(),
        saved_at: stats.saved_at,
        route: request.route,
        model_name: request.model_name,
        generated_at: request.generated_at,
        used_context: request.used_context,
        privacy_rule_id: request.privacy_rule_id,
        call_log_id: request.call_log_id,
        edited_by_user: request.edited_by_user,
        character_count: character_count(&request.summary_text),
    })
}

pub(super) fn clear_ai_summary(
    repo_path: String,
    request: AiSummaryClearRequest,
) -> CoreResult<AiSummaryClearReport> {
    validate_repo_path(&repo_path)?;
    validate_clear_request(&request)?;
    let repo = PathBuf::from(&repo_path);
    db::get_active_file_by_id(&repo, request.file_id).map_err(map_file_lookup_error)?;
    let stats = db::clear_ai_summary_metadata(&repo, request.file_id)?;
    Ok(AiSummaryClearReport {
        file_id: request.file_id,
        cleared: stats.cleared,
        cleared_at: stats.cleared_at,
    })
}

fn summary_capability(capabilities: &[AiCapabilityState]) -> CoreResult<&AiCapabilityState> {
    capabilities
        .iter()
        .find(|state| state.feature == AiFeatureKind::AutoSummaries)
        .ok_or_else(|| CoreError::config("AI summary capability is not configured"))
}

fn privacy_blocks(config_ref: &Option<String>, request: &AiSummaryGenerationRequest) -> bool {
    let reference = request.privacy_policy_ref.as_ref().or(config_ref.as_ref());
    reference.is_some_and(|value| {
        let normalized = value.to_ascii_lowercase();
        normalized.contains("block")
            || normalized.contains("deny")
            || normalized.contains("private")
    })
}

fn privacy_rule_id(request: &AiSummaryGenerationRequest) -> Option<String> {
    request
        .privacy_policy_ref
        .as_ref()
        .map(|value| format!("rule:{value}"))
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

fn select_route(
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

fn draft_result(
    repo: &Path,
    file: &FileEntry,
    draft: AiSummaryRuntimeDraft,
) -> CoreResult<AiSummaryDraft> {
    let result_summary = format!(
        "Generated {} character summary",
        draft.summary_text.chars().count()
    );
    let call_log_id = insert_summary_call_log(
        repo,
        SummaryCallLogDraft {
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
    Ok(base_draft(file, AiSummaryDraftStatus::Draft)
        .with_draft_id(new_draft_id(file.id))
        .with_summary_text(draft.summary_text)
        .with_route(draft.route)
        .with_model(draft.model)
        .with_generated_at(current_timestamp())
        .with_context(draft.used_context)
        .with_call_log(call_log_id))
}

fn skipped(
    repo: &Path,
    file: &FileEntry,
    reason: AiSummarySkipReason,
    message: &str,
    privacy_rule_id: Option<String>,
) -> CoreResult<AiSummaryDraft> {
    let call_log_id = insert_summary_call_log(
        repo,
        SummaryCallLogDraft {
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
    Ok(base_draft(file, AiSummaryDraftStatus::Skipped)
        .with_skipped_reason(reason)
        .with_privacy_rule(privacy_rule_id)
        .with_call_log(call_log_id))
}

fn unavailable_provider(repo: &Path, file: &FileEntry) -> CoreResult<AiSummaryDraft> {
    let call_log_id = insert_summary_call_log(
        repo,
        SummaryCallLogDraft {
            file_id: Some(file.id),
            route: None,
            status: "unavailable",
            sent_fields: &[],
            privacy_rule_id: None,
            result_summary: "AI summary provider is unavailable",
            error_code: Some("ProviderUnavailable"),
            model: None,
        },
    )?;
    Ok(base_draft(file, AiSummaryDraftStatus::Unavailable)
        .with_skipped_reason(AiSummarySkipReason::ProviderUnavailable)
        .with_call_log(call_log_id))
}

fn unavailable_after_runtime_error(
    repo: &Path,
    file: &FileEntry,
    route: AiSummaryRoute,
    context: &AiSummaryContext,
    error: CoreError,
) -> CoreResult<AiSummaryDraft> {
    let error_code = runtime_error_code(&error);
    let message = runtime_error_message(route.clone());
    let call_log_id = insert_summary_call_log(
        repo,
        SummaryCallLogDraft {
            file_id: Some(file.id),
            route: Some(&route),
            status: "failed",
            sent_fields: &context.fields,
            privacy_rule_id: None,
            result_summary: &message,
            error_code: Some(error_code),
            model: None,
        },
    )?;
    Ok(base_draft(file, AiSummaryDraftStatus::Unavailable)
        .with_route(route)
        .with_context(context.fields.clone())
        .with_skipped_reason(AiSummarySkipReason::ProviderUnavailable)
        .with_call_log(call_log_id))
}

fn runtime_error_code(error: &CoreError) -> &'static str {
    match error {
        CoreError::Config { .. } => "ProviderUnavailable",
        CoreError::PermissionDenied { .. } => "PermissionDenied",
        _ => "RuntimeFailed",
    }
}

fn runtime_error_message(route: AiSummaryRoute) -> String {
    match route {
        AiSummaryRoute::Local => "AI summary local runtime is unavailable",
        AiSummaryRoute::Remote => "AI summary remote provider failed",
    }
    .to_owned()
}

fn base_draft(file: &FileEntry, status: AiSummaryDraftStatus) -> AiSummaryDraft {
    AiSummaryDraft {
        file_id: file.id,
        draft_id: None,
        status,
        summary_text: None,
        route: None,
        model_name: None,
        generated_at: None,
        used_context: Vec::new(),
        skipped_reason: None,
        privacy_rule_id: None,
        call_log_id: None,
        requires_user_save: true,
        character_count: 0,
    }
}

trait SummaryDraftBuilder {
    fn with_draft_id(self, draft_id: String) -> Self;
    fn with_summary_text(self, summary_text: String) -> Self;
    fn with_route(self, route: AiSummaryRoute) -> Self;
    fn with_model(self, model: String) -> Self;
    fn with_generated_at(self, generated_at: i64) -> Self;
    fn with_context(self, context: Vec<AiSummaryInputField>) -> Self;
    fn with_skipped_reason(self, reason: AiSummarySkipReason) -> Self;
    fn with_privacy_rule(self, rule_id: Option<String>) -> Self;
    fn with_call_log(self, call_log_id: i64) -> Self;
}

impl SummaryDraftBuilder for AiSummaryDraft {
    fn with_draft_id(mut self, draft_id: String) -> Self {
        self.draft_id = Some(draft_id);
        self
    }

    fn with_summary_text(mut self, summary_text: String) -> Self {
        self.character_count = character_count(&summary_text);
        self.summary_text = Some(summary_text);
        self
    }

    fn with_route(mut self, route: AiSummaryRoute) -> Self {
        self.route = Some(route);
        self
    }

    fn with_model(mut self, model: String) -> Self {
        self.model_name = Some(model);
        self
    }

    fn with_generated_at(mut self, generated_at: i64) -> Self {
        self.generated_at = Some(generated_at);
        self
    }

    fn with_context(mut self, context: Vec<AiSummaryInputField>) -> Self {
        self.used_context = context;
        self
    }

    fn with_skipped_reason(mut self, reason: AiSummarySkipReason) -> Self {
        self.skipped_reason = Some(reason);
        self
    }

    fn with_privacy_rule(mut self, rule_id: Option<String>) -> Self {
        self.privacy_rule_id = rule_id;
        self
    }

    fn with_call_log(mut self, call_log_id: i64) -> Self {
        self.call_log_id = Some(call_log_id);
        self
    }
}

fn used_context_json(fields: &[AiSummaryInputField]) -> CoreResult<String> {
    serde_json::to_string(&field_names(fields))
        .map_err(|_| CoreError::internal("AI summary context metadata is invalid"))
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

fn summary_route_to_db(route: &AiSummaryRoute) -> String {
    match route {
        AiSummaryRoute::Local => "local",
        AiSummaryRoute::Remote => "remote",
    }
    .to_owned()
}

fn new_draft_id(file_id: i64) -> String {
    format!("draft:summary:{file_id}:{}", Uuid::new_v4())
}

fn current_timestamp() -> i64 {
    chrono::Utc::now().timestamp()
}

fn character_count(value: &str) -> i64 {
    value.chars().count() as i64
}

fn map_file_lookup_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI summary requires initialized repository metadata")
        }
        other => other,
    }
}
