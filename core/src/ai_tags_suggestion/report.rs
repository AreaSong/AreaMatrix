use std::collections::HashSet;

use crate::FileEntry;

use super::{
    context::AiTagSuggestionContext, executor::AiTagRuntimeSuggestion, normalize_tag_slug,
    validate_display_name, AiTagSuggestion, AiTagSuggestionCandidateStatus,
    AiTagSuggestionInputField, AiTagSuggestionMergeAction, AiTagSuggestionReport,
    AiTagSuggestionReportStatus, AiTagSuggestionRoute, AiTagSuggestionSkipReason,
};

pub(super) fn build_suggestions(
    file_id: i64,
    context: &AiTagSuggestionContext,
    runtime_suggestions: &[AiTagRuntimeSuggestion],
    confidence_threshold: f32,
) -> Vec<AiTagSuggestion> {
    let mut seen = HashSet::new();
    let mut suggestions = Vec::new();
    for (index, runtime) in runtime_suggestions.iter().enumerate() {
        let Ok(slug) = normalize_tag_slug(&runtime.slug) else {
            continue;
        };
        if !seen.insert(comparable_tag(&slug)) {
            continue;
        }
        suggestions.push(suggestion_from_runtime(
            file_id,
            index,
            context,
            runtime,
            slug,
            confidence_threshold,
        ));
    }
    suggestions
}

pub(super) fn base_report(
    file: &FileEntry,
    status: AiTagSuggestionReportStatus,
    confidence_threshold: f32,
) -> AiTagSuggestionReport {
    AiTagSuggestionReport {
        file_id: file.id,
        status,
        suggestions: Vec::new(),
        route: None,
        model_name: None,
        generated_at: None,
        used_context: Vec::new(),
        skipped_reason: None,
        privacy_rule_id: None,
        call_log_id: None,
        requires_user_confirmation: true,
        confidence_threshold,
        contents_read: false,
        ai_used: false,
        network_used: false,
    }
}

pub(super) trait TagReportBuilder {
    fn with_suggestions(self, suggestions: Vec<AiTagSuggestion>) -> Self;
    fn with_route(self, route: AiTagSuggestionRoute) -> Self;
    fn with_model(self, model: String) -> Self;
    fn with_generated_at(self, generated_at: i64) -> Self;
    fn with_context(self, context: Vec<AiTagSuggestionInputField>) -> Self;
    fn with_skipped_reason(self, reason: AiTagSuggestionSkipReason) -> Self;
    fn with_privacy_rule(self, rule_id: Option<String>) -> Self;
    fn with_call_log(self, call_log_id: i64) -> Self;
    fn with_ai_boundary(self, ai_used: bool) -> Self;
    fn with_network(self, network_used: bool) -> Self;
}

impl TagReportBuilder for AiTagSuggestionReport {
    fn with_suggestions(mut self, suggestions: Vec<AiTagSuggestion>) -> Self {
        self.suggestions = suggestions;
        self
    }

    fn with_route(mut self, route: AiTagSuggestionRoute) -> Self {
        self.network_used = route == AiTagSuggestionRoute::Remote;
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

    fn with_context(mut self, context: Vec<AiTagSuggestionInputField>) -> Self {
        self.used_context = context;
        self
    }

    fn with_skipped_reason(mut self, reason: AiTagSuggestionSkipReason) -> Self {
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

    fn with_ai_boundary(mut self, ai_used: bool) -> Self {
        self.ai_used = ai_used;
        self
    }

    fn with_network(mut self, network_used: bool) -> Self {
        self.network_used = network_used;
        self
    }
}

fn suggestion_from_runtime(
    file_id: i64,
    index: usize,
    context: &AiTagSuggestionContext,
    runtime: &AiTagRuntimeSuggestion,
    slug: String,
    confidence_threshold: f32,
) -> AiTagSuggestion {
    let matched_existing_slug = matched_existing_slug(context, runtime, &slug);
    let already_applied = has_existing(&context.existing_tags, &slug);
    let low_confidence = runtime.confidence < confidence_threshold;
    let status = candidate_status(already_applied, low_confidence);
    AiTagSuggestion {
        suggestion_id: format!("ai-tag:{file_id}:{index}:{slug}"),
        display_name: display_name(runtime.display_name.as_deref(), &slug),
        merge_action: merge_action(runtime, matched_existing_slug.as_deref(), &slug),
        matched_existing_slug,
        selected_by_default: !already_applied && !low_confidence,
        disabled_reason: already_applied.then(|| "Already added".to_owned()),
        slug,
        confidence: runtime.confidence,
        reason: runtime.reason.clone(),
        status,
    }
}

fn candidate_status(already_applied: bool, low_confidence: bool) -> AiTagSuggestionCandidateStatus {
    if already_applied {
        AiTagSuggestionCandidateStatus::AlreadyApplied
    } else if low_confidence {
        AiTagSuggestionCandidateStatus::LowConfidence
    } else {
        AiTagSuggestionCandidateStatus::Suggested
    }
}

fn matched_existing_slug(
    context: &AiTagSuggestionContext,
    runtime: &AiTagRuntimeSuggestion,
    slug: &str,
) -> Option<String> {
    runtime
        .merge_target_slug
        .as_deref()
        .and_then(|target| existing_tag(context, target))
        .or_else(|| existing_tag(context, slug))
}

fn existing_tag(context: &AiTagSuggestionContext, slug: &str) -> Option<String> {
    context
        .tag_registry
        .iter()
        .chain(context.existing_tags.iter())
        .find(|tag| comparable_tag(tag) == comparable_tag(slug))
        .cloned()
}

fn has_existing(tags: &[String], slug: &str) -> bool {
    tags.iter()
        .any(|tag| comparable_tag(tag) == comparable_tag(slug))
}

fn merge_action(
    runtime: &AiTagRuntimeSuggestion,
    matched_existing_slug: Option<&str>,
    slug: &str,
) -> AiTagSuggestionMergeAction {
    match matched_existing_slug {
        Some(existing)
            if runtime.merge_target_slug.is_some()
                && comparable_tag(existing) != comparable_tag(slug) =>
        {
            AiTagSuggestionMergeAction::MergeWithExistingTag
        }
        Some(_) => AiTagSuggestionMergeAction::UseExistingTag,
        None => AiTagSuggestionMergeAction::CreateTag,
    }
}

fn display_name(value: Option<&str>, slug: &str) -> String {
    let Some(name) = value else {
        return slug.to_owned();
    };
    if validate_display_name(name).is_ok() {
        name.trim().to_owned()
    } else {
        slug.to_owned()
    }
}

fn comparable_tag(value: &str) -> String {
    normalize_tag_slug(value).unwrap_or_else(|_| value.trim().to_lowercase())
}
