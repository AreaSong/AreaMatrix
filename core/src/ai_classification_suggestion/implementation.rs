use std::path::{Path, PathBuf};

use crate::{
    classify, db, AiCapabilityState, AiFeatureKind, AiProviderPreference, ClassifyReason,
    ClassifyResult, CoreError, CoreResult, FileEntry, RemoteProviderConfigSnapshot,
};

use super::{
    AiCategorySuggestion, AiCategorySuggestionContextField, AiCategorySuggestionContextPolicy,
    AiCategorySuggestionRequest, AiCategorySuggestionRoute, AiCategorySuggestionSkipReason,
    AiCategorySuggestionStatus,
};

const HIGH_RULE_CONFIDENCE: f32 = 0.8;
const LOCAL_SUGGESTION_CONFIDENCE: f32 = 0.72;
const FEATURE_NAME: &str = "classification";

pub(super) fn suggest_category_with_ai(
    repo_path: String,
    request: AiCategorySuggestionRequest,
) -> CoreResult<AiCategorySuggestion> {
    let repo = PathBuf::from(&repo_path);
    let file = db::get_active_file_by_id(&repo, request.file_id).map_err(map_file_lookup_error)?;
    let ai_config = crate::ai_settings::load_ai_config(repo_path.clone())?;
    let capability = classification_capability(&ai_config.capabilities)?;

    if !ai_config.config.ai_enabled {
        return skipped(
            &repo,
            &file,
            AiCategorySuggestionSkipReason::AiDisabled,
            "AI classification suggestions are off",
            None,
        );
    }
    if !capability.enabled {
        return skipped(
            &repo,
            &file,
            AiCategorySuggestionSkipReason::FeatureDisabled,
            "AI classification suggestions feature is off",
            None,
        );
    }
    if privacy_blocks(&ai_config.config.privacy_policy_ref, &request) {
        return skipped(
            &repo,
            &file,
            AiCategorySuggestionSkipReason::PrivacyRule,
            "Skipped by privacy rule",
            privacy_rule_id(&request),
        );
    }

    let rule_result =
        classify::predict_category(repo_path, file.current_name.clone()).map_err(map_rule_error)?;
    if rule_result_is_confident(&rule_result, &file.category) {
        return no_suggestion_for_confident_rule(&repo, &file);
    }

    let Some(route) = select_route(capability, &ai_config.config.provider_preference, &repo)?
    else {
        return unavailable_provider(&repo, &file);
    };
    let used_context = used_context_fields(&file, &request);
    if used_context.is_empty() {
        return skipped(
            &repo,
            &file,
            AiCategorySuggestionSkipReason::NoEligibleContext,
            "No eligible AI context is available",
            None,
        );
    }

    let Some(suggested_category) = suggestion_category(&rule_result, &file) else {
        return no_suggestion(&repo, &file, route, used_context);
    };
    suggested(&repo, &file, suggested_category, route, used_context)
}

fn classification_capability(capabilities: &[AiCapabilityState]) -> CoreResult<&AiCapabilityState> {
    capabilities
        .iter()
        .find(|state| state.feature == AiFeatureKind::ClassificationSuggestions)
        .ok_or_else(|| CoreError::config("AI classification capability is not configured"))
}

fn privacy_blocks(config_ref: &Option<String>, request: &AiCategorySuggestionRequest) -> bool {
    let reference = request.privacy_policy_ref.as_ref().or(config_ref.as_ref());
    reference.is_some_and(|value| {
        let normalized = value.to_ascii_lowercase();
        normalized.contains("block")
            || normalized.contains("deny")
            || normalized.contains("private")
    })
}

fn privacy_rule_id(request: &AiCategorySuggestionRequest) -> Option<String> {
    request
        .privacy_policy_ref
        .as_ref()
        .map(|value| format!("rule:{value}"))
}

fn rule_result_is_confident(rule_result: &ClassifyResult, current_category: &str) -> bool {
    rule_result.confidence >= HIGH_RULE_CONFIDENCE && rule_result.category == current_category
}

fn select_route(
    capability: &AiCapabilityState,
    preference: &AiProviderPreference,
    repo: &Path,
) -> CoreResult<Option<AiCategorySuggestionRoute>> {
    if matches!(preference, AiProviderPreference::RemoteFirst) && capability.remote_allowed {
        return remote_route(repo);
    }
    if capability.local_allowed {
        return Ok(Some(AiCategorySuggestionRoute::Local));
    }
    if capability.remote_allowed {
        return remote_route(repo);
    }
    Ok(None)
}

fn remote_route(repo: &Path) -> CoreResult<Option<AiCategorySuggestionRoute>> {
    let snapshot = crate::remote_provider_config::load_remote_ai_provider_config(
        repo.to_string_lossy().into_owned(),
    )?;
    if remote_provider_allows_classification(&snapshot) {
        Ok(Some(AiCategorySuggestionRoute::Remote))
    } else {
        Ok(None)
    }
}

fn remote_provider_allows_classification(snapshot: &RemoteProviderConfigSnapshot) -> bool {
    snapshot.provider_configured
        && snapshot.provider_verified
        && snapshot.remote_provider_enabled
        && snapshot.credential_configured
        && snapshot
            .feature_scope
            .contains(&AiFeatureKind::ClassificationSuggestions)
}

fn used_context_fields(
    file: &FileEntry,
    request: &AiCategorySuggestionRequest,
) -> Vec<AiCategorySuggestionContextField> {
    let mut fields = vec![AiCategorySuggestionContextField::FileName];
    if Path::new(&file.current_name).extension().is_some() {
        fields.push(AiCategorySuggestionContextField::Extension);
    }
    match request.context_policy {
        AiCategorySuggestionContextPolicy::FileNameOnly => {}
        AiCategorySuggestionContextPolicy::FileNameAndPath
        | AiCategorySuggestionContextPolicy::LimitedTextSummary => {
            fields.push(AiCategorySuggestionContextField::RepoRelativePath);
        }
    }
    fields
}

fn suggestion_category(rule_result: &ClassifyResult, file: &FileEntry) -> Option<String> {
    if rule_result.category == file.category {
        return None;
    }
    if matches!(rule_result.reason, ClassifyReason::Default) && rule_result.category == "inbox" {
        return None;
    }
    Some(rule_result.category.clone())
}

fn suggested(
    repo: &Path,
    file: &FileEntry,
    suggested_category: String,
    route: AiCategorySuggestionRoute,
    used_context: Vec<AiCategorySuggestionContextField>,
) -> CoreResult<AiCategorySuggestion> {
    let reason = format!(
        "Local classification context suggests `{suggested_category}`; confirm before applying."
    );
    let result_summary = format!("Suggested category: {suggested_category}");
    let call_log_id = insert_call_log(
        repo,
        CallLogDraft {
            file_id: Some(file.id),
            route: Some(&route),
            status: "success",
            sent_fields: &used_context,
            privacy_rule_id: None,
            result_summary: &result_summary,
            error_code: None,
        },
    )?;
    Ok(base_result(file, AiCategorySuggestionStatus::Suggested)
        .with_suggestion(
            suggested_category,
            LOCAL_SUGGESTION_CONFIDENCE,
            reason,
            route,
        )
        .with_context(used_context)
        .with_call_log(call_log_id))
}

fn no_suggestion_for_confident_rule(
    repo: &Path,
    file: &FileEntry,
) -> CoreResult<AiCategorySuggestion> {
    let call_log_id = insert_call_log(
        repo,
        CallLogDraft {
            file_id: Some(file.id),
            route: None,
            status: "skipped",
            sent_fields: &[],
            privacy_rule_id: None,
            result_summary: "Rule classification is already confident",
            error_code: None,
        },
    )?;
    Ok(base_result(file, AiCategorySuggestionStatus::NoSuggestion)
        .with_reason("Rule classification is already confident")
        .with_skipped_reason(AiCategorySuggestionSkipReason::RuleResultConfident)
        .with_call_log(call_log_id))
}

fn no_suggestion(
    repo: &Path,
    file: &FileEntry,
    route: AiCategorySuggestionRoute,
    used_context: Vec<AiCategorySuggestionContextField>,
) -> CoreResult<AiCategorySuggestion> {
    let call_log_id = insert_call_log(
        repo,
        CallLogDraft {
            file_id: Some(file.id),
            route: Some(&route),
            status: "success",
            sent_fields: &used_context,
            privacy_rule_id: None,
            result_summary: "No category suggestion is available",
            error_code: None,
        },
    )?;
    Ok(base_result(file, AiCategorySuggestionStatus::NoSuggestion)
        .with_reason("No AI category suggestion is available")
        .with_route(route)
        .with_context(used_context)
        .with_call_log(call_log_id))
}

fn skipped(
    repo: &Path,
    file: &FileEntry,
    reason: AiCategorySuggestionSkipReason,
    message: &str,
    privacy_rule_id: Option<String>,
) -> CoreResult<AiCategorySuggestion> {
    let call_log_id = insert_call_log(
        repo,
        CallLogDraft {
            file_id: Some(file.id),
            route: None,
            status: "skipped",
            sent_fields: &[],
            privacy_rule_id: privacy_rule_id.as_deref(),
            result_summary: message,
            error_code: None,
        },
    )?;
    Ok(base_result(file, AiCategorySuggestionStatus::Skipped)
        .with_reason(message)
        .with_skipped_reason(reason)
        .with_privacy_rule(privacy_rule_id)
        .with_call_log(call_log_id))
}

fn unavailable_provider(repo: &Path, file: &FileEntry) -> CoreResult<AiCategorySuggestion> {
    let call_log_id = insert_call_log(
        repo,
        CallLogDraft {
            file_id: Some(file.id),
            route: None,
            status: "unavailable",
            sent_fields: &[],
            privacy_rule_id: None,
            result_summary: "AI classification provider is unavailable",
            error_code: Some("ProviderUnavailable"),
        },
    )?;
    Ok(base_result(file, AiCategorySuggestionStatus::Unavailable)
        .with_reason("AI classification provider is unavailable")
        .with_skipped_reason(AiCategorySuggestionSkipReason::ProviderUnavailable)
        .with_call_log(call_log_id))
}

fn base_result(file: &FileEntry, status: AiCategorySuggestionStatus) -> AiCategorySuggestion {
    AiCategorySuggestion {
        file_id: file.id,
        status,
        current_category: Some(file.category.clone()),
        suggested_category: None,
        confidence: 0.0,
        reason: None,
        route: None,
        used_context: Vec::new(),
        skipped_reason: None,
        privacy_rule_id: None,
        call_log_id: None,
        requires_user_confirmation: true,
    }
}

trait SuggestionBuilder {
    fn with_suggestion(
        self,
        category: String,
        confidence: f32,
        reason: String,
        route: AiCategorySuggestionRoute,
    ) -> Self;
    fn with_reason(self, reason: &str) -> Self;
    fn with_route(self, route: AiCategorySuggestionRoute) -> Self;
    fn with_context(self, context: Vec<AiCategorySuggestionContextField>) -> Self;
    fn with_skipped_reason(self, reason: AiCategorySuggestionSkipReason) -> Self;
    fn with_privacy_rule(self, rule_id: Option<String>) -> Self;
    fn with_call_log(self, call_log_id: Option<i64>) -> Self;
}

impl SuggestionBuilder for AiCategorySuggestion {
    fn with_suggestion(
        mut self,
        category: String,
        confidence: f32,
        reason: String,
        route: AiCategorySuggestionRoute,
    ) -> Self {
        self.suggested_category = Some(category);
        self.confidence = confidence;
        self.reason = Some(reason);
        self.route = Some(route);
        self
    }

    fn with_reason(mut self, reason: &str) -> Self {
        self.reason = Some(reason.to_owned());
        self
    }

    fn with_route(mut self, route: AiCategorySuggestionRoute) -> Self {
        self.route = Some(route);
        self
    }

    fn with_context(mut self, context: Vec<AiCategorySuggestionContextField>) -> Self {
        self.used_context = context;
        self
    }

    fn with_skipped_reason(mut self, reason: AiCategorySuggestionSkipReason) -> Self {
        self.skipped_reason = Some(reason);
        self
    }

    fn with_privacy_rule(mut self, rule_id: Option<String>) -> Self {
        self.privacy_rule_id = rule_id;
        self
    }

    fn with_call_log(mut self, call_log_id: Option<i64>) -> Self {
        self.call_log_id = call_log_id;
        self
    }
}

struct CallLogDraft<'a> {
    file_id: Option<i64>,
    route: Option<&'a AiCategorySuggestionRoute>,
    status: &'a str,
    sent_fields: &'a [AiCategorySuggestionContextField],
    privacy_rule_id: Option<&'a str>,
    result_summary: &'a str,
    error_code: Option<&'a str>,
}

fn insert_call_log(repo: &Path, draft: CallLogDraft<'_>) -> CoreResult<Option<i64>> {
    let sent_fields_json = serde_json::to_string(&field_names(draft.sent_fields))
        .map_err(|_| CoreError::internal("AI call log fields are invalid"))?;
    let id = db::insert_ai_call_log_record(
        repo,
        db::AiCallLogRecord {
            feature: FEATURE_NAME.to_owned(),
            file_id: draft.file_id,
            route: draft.route.map(route_name),
            provider: draft.route.map(provider_name),
            model: draft.route.map(model_name),
            status: draft.status.to_owned(),
            sent_fields_json,
            privacy_rule_id: draft.privacy_rule_id.map(str::to_owned),
            result_summary: draft.result_summary.to_owned(),
            error_code: draft.error_code.map(str::to_owned),
        },
    )
    .map_err(map_call_log_error)?;
    Ok(Some(id))
}

fn field_names(fields: &[AiCategorySuggestionContextField]) -> Vec<&'static str> {
    fields
        .iter()
        .map(|field| match field {
            AiCategorySuggestionContextField::FileName => "filename",
            AiCategorySuggestionContextField::Extension => "extension",
            AiCategorySuggestionContextField::RepoRelativePath => "repo_relative_path",
            AiCategorySuggestionContextField::LimitedTextSummary => "limited_text_summary",
        })
        .collect()
}

fn route_name(route: &AiCategorySuggestionRoute) -> String {
    match route {
        AiCategorySuggestionRoute::Local => "local",
        AiCategorySuggestionRoute::Remote => "remote",
    }
    .to_owned()
}

fn provider_name(route: &AiCategorySuggestionRoute) -> String {
    match route {
        AiCategorySuggestionRoute::Local => "local_model",
        AiCategorySuggestionRoute::Remote => "remote_provider",
    }
    .to_owned()
}

fn model_name(route: &AiCategorySuggestionRoute) -> String {
    match route {
        AiCategorySuggestionRoute::Local => "local-classifier-v1",
        AiCategorySuggestionRoute::Remote => "configured-remote-provider",
    }
    .to_owned()
}

fn map_file_lookup_error(error: CoreError) -> CoreError {
    match error {
        CoreError::FileNotFound { .. } => {
            CoreError::config("AI classification suggestion requires an active file id")
        }
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI classification requires initialized repository metadata")
        }
        CoreError::Db { .. } | CoreError::Io { .. } => {
            CoreError::internal("AI classification file lookup failed")
        }
        other => other,
    }
}

fn map_rule_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Config { .. } => {
            CoreError::config("AI classification rule configuration is invalid")
        }
        CoreError::Classify { .. } | CoreError::Db { .. } | CoreError::Io { .. } => {
            CoreError::internal("AI classification rule precheck failed")
        }
        CoreError::FileNotFound { .. }
        | CoreError::InvalidPath { .. }
        | CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI classification rule precheck input is invalid")
        }
        other => other,
    }
}

fn map_call_log_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Db { .. } | CoreError::Io { .. } => {
            CoreError::internal("AI call log persistence failed")
        }
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI classification requires initialized repository metadata")
        }
        other => other,
    }
}
