use std::path::PathBuf;

use crate::{db, CoreResult};

use super::{
    super::{
        validate_clear_request, validate_repo_path, validate_save_request, AiSummaryClearReport,
        AiSummaryClearRequest, AiSummarySaveReport, AiSummarySaveRequest,
    },
    codec::{summary_route_to_db, used_context_json},
    common::{character_count, map_file_lookup_error},
};

pub(in crate::ai_summary) fn save_ai_summary(
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
            expected_content_revision: request.expected_content_revision,
            confirm_replace_user_owned: request.confirm_replace_user_owned,
            summary_text: request.summary_text.clone(),
            draft_id: request.draft_id.clone(),
            route: request.route.as_ref().map(summary_route_to_db),
            model_name: request.model_name.clone(),
            generated_at: request.generated_at,
            used_context_json,
            privacy_rule_id: request.privacy_rule_id.clone(),
            call_log_id: request.call_log_id,
            ownership: request.ownership.clone(),
            operation_id: request.operation_id.clone(),
            content_locale: request.content_locale.clone(),
            format_contract_version: request.format_contract_version,
        },
    )?;
    Ok(AiSummarySaveReport {
        file_id: request.file_id,
        content_revision: stats.content_revision,
        ownership: request.ownership,
        saved_summary: request.summary_text.clone(),
        saved_at: stats.saved_at,
        route: request.route,
        model_name: request.model_name,
        generated_at: request.generated_at,
        used_context: request.used_context,
        privacy_rule_id: request.privacy_rule_id,
        call_log_id: request.call_log_id,
        operation_id: request.operation_id,
        content_locale: request.content_locale,
        format_contract_version: request.format_contract_version,
        character_count: character_count(&request.summary_text),
    })
}

pub(in crate::ai_summary) fn clear_ai_summary(
    repo_path: String,
    request: AiSummaryClearRequest,
) -> CoreResult<AiSummaryClearReport> {
    validate_repo_path(&repo_path)?;
    validate_clear_request(&request)?;
    let repo = PathBuf::from(&repo_path);
    db::get_active_file_by_id(&repo, request.file_id).map_err(map_file_lookup_error)?;
    let stats =
        db::clear_ai_summary_metadata(&repo, request.file_id, request.expected_content_revision)?;
    Ok(AiSummaryClearReport {
        file_id: request.file_id,
        cleared: stats.cleared,
        content_revision: stats.content_revision,
        cleared_at: stats.cleared_at,
    })
}
