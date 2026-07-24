use std::path::Path;

use uuid::Uuid;

use crate::{ContentLocale, CoreError, CoreResult, FileEntry};

use super::{
    super::{
        call_log::{insert_summary_call_log, SummaryCallLogDraft},
        context::AiSummaryContext,
        executor::AiSummaryRuntimeDraft,
        AiSummaryDraft, AiSummaryDraftStatus, AiSummaryInputField, AiSummaryRoute,
        AiSummarySkipReason,
    },
    common::{character_count, current_timestamp},
};

pub(super) struct SummaryDraftContext<'a> {
    pub(super) repo: &'a Path,
    pub(super) file: &'a FileEntry,
    pub(super) operation_id: &'a str,
    pub(super) content_locale: &'a ContentLocale,
    pub(super) format_contract_version: i64,
}

pub(super) fn draft_result(
    repo: &Path,
    file: &FileEntry,
    operation_id: &str,
    content_locale: &ContentLocale,
    format_contract_version: i64,
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
            privacy_rules_checked: true,
            privacy_rule_id: None,
            result_summary: &result_summary,
            error_code: None,
            model: Some(&draft.model),
        },
    )?;
    Ok(base_draft(
        file,
        operation_id,
        content_locale,
        format_contract_version,
        AiSummaryDraftStatus::Draft,
    )
    .with_draft_id(new_draft_id(file.id))
    .with_summary_text(draft.summary_text)
    .with_route(draft.route)
    .with_model(draft.model)
    .with_generated_at(current_timestamp())
    .with_context(draft.used_context)
    .with_call_log(call_log_id))
}

pub(super) fn skipped(
    draft_context: &SummaryDraftContext<'_>,
    reason: AiSummarySkipReason,
    message: &str,
    privacy_rules_checked: bool,
    privacy_rule_id: Option<String>,
) -> CoreResult<AiSummaryDraft> {
    let call_log_id = insert_summary_call_log(
        draft_context.repo,
        SummaryCallLogDraft {
            file_id: Some(draft_context.file.id),
            route: None,
            status: "skipped",
            sent_fields: &[],
            privacy_rules_checked,
            privacy_rule_id: privacy_rule_id.as_deref(),
            result_summary: message,
            error_code: None,
            model: None,
        },
    )?;
    Ok(base_draft(
        draft_context.file,
        draft_context.operation_id,
        draft_context.content_locale,
        draft_context.format_contract_version,
        AiSummaryDraftStatus::Skipped,
    )
    .with_skipped_reason(reason)
    .with_privacy_rule(privacy_rule_id)
    .with_call_log(call_log_id))
}

pub(super) fn unavailable_provider(
    repo: &Path,
    file: &FileEntry,
    operation_id: &str,
    content_locale: &ContentLocale,
    format_contract_version: i64,
) -> CoreResult<AiSummaryDraft> {
    let call_log_id = insert_summary_call_log(
        repo,
        SummaryCallLogDraft {
            file_id: Some(file.id),
            route: None,
            status: "unavailable",
            sent_fields: &[],
            privacy_rules_checked: true,
            privacy_rule_id: None,
            result_summary: "AI summary provider is unavailable",
            error_code: Some("ProviderUnavailable"),
            model: None,
        },
    )?;
    Ok(base_draft(
        file,
        operation_id,
        content_locale,
        format_contract_version,
        AiSummaryDraftStatus::Unavailable,
    )
    .with_skipped_reason(AiSummarySkipReason::ProviderUnavailable)
    .with_call_log(call_log_id))
}

pub(super) fn unavailable_after_runtime_error(
    draft_context: &SummaryDraftContext<'_>,
    route: AiSummaryRoute,
    context: &AiSummaryContext,
    error: CoreError,
) -> CoreResult<AiSummaryDraft> {
    let error_code = runtime_error_code(&error);
    let message = runtime_error_message(route.clone());
    let call_log_id = insert_summary_call_log(
        draft_context.repo,
        SummaryCallLogDraft {
            file_id: Some(draft_context.file.id),
            route: Some(&route),
            status: "failed",
            sent_fields: &context.fields,
            privacy_rules_checked: true,
            privacy_rule_id: None,
            result_summary: &message,
            error_code: Some(error_code),
            model: None,
        },
    )?;
    Ok(base_draft(
        draft_context.file,
        draft_context.operation_id,
        draft_context.content_locale,
        draft_context.format_contract_version,
        AiSummaryDraftStatus::Unavailable,
    )
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

fn base_draft(
    file: &FileEntry,
    operation_id: &str,
    content_locale: &ContentLocale,
    format_contract_version: i64,
    status: AiSummaryDraftStatus,
) -> AiSummaryDraft {
    AiSummaryDraft {
        operation_id: operation_id.to_owned(),
        content_locale: content_locale.clone(),
        format_contract_version,
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

fn new_draft_id(file_id: i64) -> String {
    format!("draft:summary:{file_id}:{}", Uuid::new_v4())
}
