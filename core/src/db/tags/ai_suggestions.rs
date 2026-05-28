use std::path::Path;

use rusqlite::params;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    AiTagSuggestionApplyItemResult, AiTagSuggestionApplyReport, AiTagSuggestionApplyStatus,
    CoreError, CoreResult, TagSet,
};

use super::{
    clear_redo_stack_in_tx, current_tag_updated_at, ensure_active_file, insert_tag_change,
    insert_tag_relation, load_tag_set, open_repo_connection,
};

/// Normalized C3-07 apply row after API-level validation.
pub(crate) struct AiTagSuggestionApplyRow {
    pub(crate) suggestion_id: String,
    pub(crate) slug: String,
    pub(crate) display_name: String,
    pub(crate) confidence: f32,
    pub(crate) edited_by_user: bool,
    pub(crate) merge_target_slug: Option<String>,
}

/// AI generation provenance carried into a confirmed C3-07 tag apply.
pub(crate) struct AiTagSuggestionApplyProvenance {
    pub(crate) source_call_log_id: Option<i64>,
    pub(crate) privacy_rule_id: Option<String>,
}

struct AppliedAiTagSuggestion {
    suggestion_id: String,
    file_id: i64,
    tag: String,
}

struct AiTagApplyAccumulator {
    file_id: i64,
    requested_count: i64,
    applied_count: i64,
    skipped_count: i64,
    failed_count: i64,
    item_results: Vec<AiTagSuggestionApplyItemResult>,
    applied_items: Vec<AppliedAiTagSuggestion>,
    undo_token: Option<String>,
    call_log_id: Option<i64>,
}

impl AiTagApplyAccumulator {
    fn new(file_id: i64, requested_count: usize) -> Self {
        Self {
            file_id,
            requested_count: requested_count as i64,
            applied_count: 0,
            skipped_count: 0,
            failed_count: 0,
            item_results: Vec::new(),
            applied_items: Vec::new(),
            undo_token: None,
            call_log_id: None,
        }
    }

    fn push(&mut self, result: AiTagSuggestionApplyItemResult) {
        match result.status {
            AiTagSuggestionApplyStatus::Applied => {
                self.applied_count += 1;
                self.applied_items.push(AppliedAiTagSuggestion {
                    suggestion_id: result.suggestion_id.clone(),
                    file_id: self.file_id,
                    tag: result.slug.clone(),
                });
            }
            AiTagSuggestionApplyStatus::AlreadyAdded => self.skipped_count += 1,
            AiTagSuggestionApplyStatus::Failed => self.failed_count += 1,
        }
        self.item_results.push(result);
    }

    fn into_report(self, tag_set: TagSet) -> AiTagSuggestionApplyReport {
        AiTagSuggestionApplyReport {
            file_id: self.file_id,
            requested_count: self.requested_count,
            applied_count: self.applied_count,
            skipped_count: self.skipped_count,
            failed_count: self.failed_count,
            item_results: self.item_results,
            tag_set,
            undo_token: self.undo_token,
            call_log_id: self.call_log_id,
            refresh_targets: vec![
                "tags".to_owned(),
                "change_log".to_owned(),
                "undo_actions".to_owned(),
                "ai_call_log".to_owned(),
            ],
        }
    }
}

pub(crate) fn apply_ai_tag_suggestion_rows(
    repo_path: &Path,
    file_id: i64,
    rows: &[AiTagSuggestionApplyRow],
    provenance: AiTagSuggestionApplyProvenance,
) -> CoreResult<AiTagSuggestionApplyReport> {
    super::super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        open_repo_connection(repo_path).map_err(super::super::map_update_open_error)?;
    let mut tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_ai_tag_apply_ready(&tx)?;
    ensure_active_file(&tx, file_id)?;

    let occurred_at = chrono::Utc::now().timestamp();
    let mut report = AiTagApplyAccumulator::new(file_id, rows.len());
    for row in rows {
        report.push(apply_ai_tag_item(
            &mut tx,
            file_id,
            row,
            &provenance,
            occurred_at,
        )?);
    }
    if report.applied_count > 0 {
        clear_redo_stack_in_tx(&tx, occurred_at)?;
        report.undo_token = Some(create_ai_tag_undo_action(
            &tx,
            &report.applied_items,
            occurred_at,
        )?);
    }
    report.call_log_id = Some(insert_apply_call_log(&tx, file_id, &report, &provenance)?);

    let fallback_updated_at = if report.applied_count > 0 {
        occurred_at
    } else {
        current_tag_updated_at(&tx, file_id)?
    };
    let tag_set = load_tag_set(&tx, file_id, fallback_updated_at)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(report.into_report(tag_set))
}

fn ensure_ai_tag_apply_ready(connection: &rusqlite::Connection) -> CoreResult<()> {
    for statement in [
        "SELECT file_id, tag, added_at FROM tags LIMIT 0",
        "SELECT file_id, action, detail_json, occurred_at FROM change_log LIMIT 0",
        "SELECT token, kind, summary_json, inverse_json, status FROM undo_actions LIMIT 0",
    ] {
        connection
            .prepare(statement)
            .map(|_| ())
            .map_err(|error| CoreError::db(error.to_string()))?;
    }
    Ok(())
}

fn apply_ai_tag_item(
    tx: &mut rusqlite::Transaction<'_>,
    file_id: i64,
    row: &AiTagSuggestionApplyRow,
    provenance: &AiTagSuggestionApplyProvenance,
    occurred_at: i64,
) -> CoreResult<AiTagSuggestionApplyItemResult> {
    let savepoint = tx
        .savepoint()
        .map_err(|error| CoreError::db(error.to_string()))?;
    match try_apply_ai_tag_item(&savepoint, file_id, row, provenance, occurred_at) {
        Ok(result) => {
            savepoint
                .commit()
                .map_err(|error| CoreError::db(error.to_string()))?;
            Ok(result)
        }
        Err(error) => {
            let failure = failed_apply_item(row, error);
            savepoint
                .finish()
                .map_err(|error| CoreError::db(error.to_string()))?;
            Ok(failure)
        }
    }
}

fn try_apply_ai_tag_item(
    connection: &rusqlite::Connection,
    file_id: i64,
    row: &AiTagSuggestionApplyRow,
    provenance: &AiTagSuggestionApplyProvenance,
    occurred_at: i64,
) -> CoreResult<AiTagSuggestionApplyItemResult> {
    let added = insert_tag_relation(connection, file_id, &row.slug, occurred_at)?;
    if added {
        insert_ai_tag_change(connection, file_id, row, provenance, occurred_at)?;
    }
    Ok(AiTagSuggestionApplyItemResult {
        suggestion_id: row.suggestion_id.clone(),
        slug: row.slug.clone(),
        status: if added {
            AiTagSuggestionApplyStatus::Applied
        } else {
            AiTagSuggestionApplyStatus::AlreadyAdded
        },
        error: None,
    })
}

fn failed_apply_item(
    row: &AiTagSuggestionApplyRow,
    error: CoreError,
) -> AiTagSuggestionApplyItemResult {
    AiTagSuggestionApplyItemResult {
        suggestion_id: row.suggestion_id.clone(),
        slug: row.slug.clone(),
        status: AiTagSuggestionApplyStatus::Failed,
        error: Some(apply_failure_message(error)),
    }
}

fn apply_failure_message(error: CoreError) -> String {
    match error {
        CoreError::FileNotFound { path } => format!("FileNotFound: {path}"),
        CoreError::Config { reason } => format!("Config: {reason}"),
        CoreError::Db { message } => format!("Db: {message}"),
        other => other.to_string(),
    }
}

fn insert_ai_tag_change(
    connection: &rusqlite::Connection,
    file_id: i64,
    row: &AiTagSuggestionApplyRow,
    provenance: &AiTagSuggestionApplyProvenance,
    occurred_at: i64,
) -> CoreResult<()> {
    let detail = json!({
        "kind": "ai_tag_suggestion_applied",
        "suggestion_id": row.suggestion_id,
        "tag": row.slug,
        "display_name": row.display_name,
        "confidence": row.confidence,
        "edited_by_user": row.edited_by_user,
        "merge_target_slug": row.merge_target_slug,
        "source_call_log_id": provenance.source_call_log_id,
        "privacy_rule_id": provenance.privacy_rule_id,
        "changed": true,
        "by": "user",
    });
    insert_tag_change(connection, file_id, &detail, occurred_at)
}

fn create_ai_tag_undo_action(
    tx: &rusqlite::Transaction<'_>,
    applied_items: &[AppliedAiTagSuggestion],
    occurred_at: i64,
) -> CoreResult<String> {
    let token = format!("undo:ai-tags:{}", Uuid::new_v4());
    let summary = json!({
        "kind": "ai_tag_suggestions",
        "added_count": applied_items.len(),
        "affected_count": applied_items.len(),
    });
    let inverse = json!({
        "kind": "remove_tags",
        "relations": applied_items.iter().map(ai_tag_relation).collect::<Vec<_>>(),
    });
    let summary_json = value_json(&summary)?;
    let inverse_json = value_json(&inverse)?;
    tx.execute(
        "INSERT INTO undo_actions (
             token, kind, summary_json, inverse_json, status, created_at, updated_at
         ) VALUES (?1, 'batch_add_tags', ?2, ?3, 'pending', ?4, ?4)",
        params![token, summary_json, inverse_json, occurred_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}

fn ai_tag_relation(item: &AppliedAiTagSuggestion) -> Value {
    json!({
        "file_id": item.file_id,
        "tag": item.tag,
        "suggestion_id": item.suggestion_id,
    })
}

fn insert_apply_call_log(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    report: &AiTagApplyAccumulator,
    provenance: &AiTagSuggestionApplyProvenance,
) -> CoreResult<i64> {
    let status = if report.failed_count > 0 {
        "failed"
    } else {
        "success"
    };
    crate::db::insert_ai_call_log_record_in_tx(
        tx,
        crate::db::AiCallLogInsertRecord {
            feature: "tags".to_owned(),
            file_id: Some(file_id),
            route: None,
            provider: None,
            model: None,
            status: status.to_owned(),
            sent_fields_json: "[]".to_owned(),
            privacy_rule_id: provenance.privacy_rule_id.clone(),
            result_summary: apply_result_summary(report, provenance),
            error_code: (report.failed_count > 0).then(|| "ApplyPartialFailure".to_owned()),
        },
    )
}

fn apply_result_summary(
    report: &AiTagApplyAccumulator,
    provenance: &AiTagSuggestionApplyProvenance,
) -> String {
    let mut summary = format!(
        "Applied {} AI tag suggestions, skipped {}, failed {}",
        report.applied_count, report.skipped_count, report.failed_count
    );
    if let Some(call_log_id) = provenance.source_call_log_id {
        summary.push_str(&format!("; source_call_log_id={call_log_id}"));
    }
    summary
}

fn value_json(value: &Value) -> CoreResult<String> {
    serde_json::to_string(value).map_err(|error| CoreError::internal(error.to_string()))
}
