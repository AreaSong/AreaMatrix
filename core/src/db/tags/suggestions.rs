use std::path::Path;

use rusqlite::{params, OptionalExtension};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    CoreError, CoreResult, TagSet, TagSuggestionApplyItemResult, TagSuggestionApplyReport,
    TagSuggestionApplyStatus,
};

use super::{
    clear_redo_stack_in_tx, current_tag_updated_at, ensure_active_file, insert_tag_change,
    insert_tag_relation, load_tag_set, open_repo_connection,
};

/// Active-file metadata used by deterministic C2-19 suggestion generation.
pub(crate) struct TagSuggestionFileMetadata {
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) source_path: Option<String>,
}

/// DB snapshot consumed by the platform-neutral C2-19 suggestion engine.
pub(crate) struct TagSuggestionSnapshot {
    pub(crate) file: TagSuggestionFileMetadata,
    pub(crate) tag_set: TagSet,
}

/// Normalized apply row after API-level validation.
pub(crate) struct TagSuggestionApplyRow {
    pub(crate) suggestion_id: String,
    pub(crate) slug: String,
    pub(crate) display_name: String,
}

struct AppliedTagSuggestion {
    suggestion_id: String,
    file_id: i64,
    tag: String,
}

struct TagSuggestionApplyAccumulator {
    file_id: i64,
    requested_count: i64,
    applied_count: i64,
    skipped_count: i64,
    failed_count: i64,
    item_results: Vec<TagSuggestionApplyItemResult>,
    applied_items: Vec<AppliedTagSuggestion>,
    undo_token: Option<String>,
}

impl TagSuggestionApplyAccumulator {
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
        }
    }

    fn push(&mut self, result: TagSuggestionApplyItemResult) {
        match result.status {
            TagSuggestionApplyStatus::Applied => {
                self.applied_count += 1;
                self.applied_items.push(AppliedTagSuggestion {
                    suggestion_id: result.suggestion_id.clone(),
                    file_id: self.file_id,
                    tag: result.slug.clone(),
                });
            }
            TagSuggestionApplyStatus::AlreadyAdded => self.skipped_count += 1,
            TagSuggestionApplyStatus::Failed => self.failed_count += 1,
        }
        self.item_results.push(result);
    }

    fn into_report(self, tag_set: TagSet) -> TagSuggestionApplyReport {
        TagSuggestionApplyReport {
            file_id: self.file_id,
            requested_count: self.requested_count,
            applied_count: self.applied_count,
            skipped_count: self.skipped_count,
            failed_count: self.failed_count,
            item_results: self.item_results,
            tag_set,
            undo_token: self.undo_token,
            refresh_targets: vec![
                "tags".to_owned(),
                "change_log".to_owned(),
                "undo_actions".to_owned(),
            ],
        }
    }
}

pub(crate) fn load_tag_suggestion_snapshot(
    repo_path: &Path,
    file_id: i64,
) -> CoreResult<TagSuggestionSnapshot> {
    let connection = open_repo_connection(repo_path)?;
    let file = load_active_file_metadata(&connection, file_id)?;
    let tag_set = load_tag_set(
        &connection,
        file_id,
        current_tag_updated_at(&connection, file_id)?,
    )?;
    Ok(TagSuggestionSnapshot { file, tag_set })
}

pub(crate) fn apply_tag_suggestion_rows(
    repo_path: &Path,
    file_id: i64,
    rows: &[TagSuggestionApplyRow],
) -> CoreResult<TagSuggestionApplyReport> {
    let mut connection = open_repo_connection(repo_path)?;
    let mut tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_tag_suggestion_apply_ready(&tx)?;
    ensure_active_file(&tx, file_id)?;

    let occurred_at = chrono::Utc::now().timestamp();
    let mut report = TagSuggestionApplyAccumulator::new(file_id, rows.len());
    for row in rows {
        report.push(apply_tag_suggestion_item(
            &mut tx,
            file_id,
            row,
            occurred_at,
        )?);
    }
    if report.applied_count > 0 {
        clear_redo_stack_in_tx(&tx, occurred_at)?;
        report.undo_token = Some(create_tag_suggestion_undo_action(
            &tx,
            &report.applied_items,
            occurred_at,
        )?);
    }

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

fn load_active_file_metadata(
    connection: &rusqlite::Connection,
    file_id: i64,
) -> CoreResult<TagSuggestionFileMetadata> {
    connection
        .query_row(
            "SELECT path, current_name, source_path
               FROM files
              WHERE id = ?1 AND status = 'active'",
            params![file_id],
            |row| {
                Ok(TagSuggestionFileMetadata {
                    path: row.get(0)?,
                    current_name: row.get(1)?,
                    source_path: row.get(2)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{file_id}")))
}

fn ensure_tag_suggestion_apply_ready(connection: &rusqlite::Connection) -> CoreResult<()> {
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

fn apply_tag_suggestion_item(
    tx: &mut rusqlite::Transaction<'_>,
    file_id: i64,
    row: &TagSuggestionApplyRow,
    occurred_at: i64,
) -> CoreResult<TagSuggestionApplyItemResult> {
    let savepoint = tx
        .savepoint()
        .map_err(|error| CoreError::db(error.to_string()))?;
    match try_apply_tag_suggestion_item(&savepoint, file_id, row, occurred_at) {
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

fn try_apply_tag_suggestion_item(
    connection: &rusqlite::Connection,
    file_id: i64,
    row: &TagSuggestionApplyRow,
    occurred_at: i64,
) -> CoreResult<TagSuggestionApplyItemResult> {
    let added = insert_tag_relation(connection, file_id, &row.slug, occurred_at)?;
    if added {
        insert_tag_suggestion_change(connection, file_id, row, occurred_at)?;
    }
    Ok(TagSuggestionApplyItemResult {
        suggestion_id: row.suggestion_id.clone(),
        slug: row.slug.clone(),
        status: if added {
            TagSuggestionApplyStatus::Applied
        } else {
            TagSuggestionApplyStatus::AlreadyAdded
        },
        error: None,
    })
}

fn failed_apply_item(
    row: &TagSuggestionApplyRow,
    error: CoreError,
) -> TagSuggestionApplyItemResult {
    TagSuggestionApplyItemResult {
        suggestion_id: row.suggestion_id.clone(),
        slug: row.slug.clone(),
        status: TagSuggestionApplyStatus::Failed,
        error: Some(apply_failure_message(error)),
    }
}

fn apply_failure_message(error: CoreError) -> String {
    match error {
        CoreError::FileNotFound { path } => format!("FileNotFound: {path}"),
        CoreError::Validation { reason } => format!("Validation: {reason}"),
        CoreError::Conflict { path } => format!("Conflict: {path}"),
        CoreError::Db { message } => format!("Db: {message}"),
        other => other.to_string(),
    }
}

fn insert_tag_suggestion_change(
    connection: &rusqlite::Connection,
    file_id: i64,
    row: &TagSuggestionApplyRow,
    occurred_at: i64,
) -> CoreResult<()> {
    let detail = json!({
        "kind": "tag_suggestion_applied",
        "suggestion_id": row.suggestion_id,
        "tag": row.slug,
        "display_name": row.display_name,
        "changed": true,
        "by": "user",
    });
    insert_tag_change(connection, file_id, &detail, occurred_at)
}

fn create_tag_suggestion_undo_action(
    tx: &rusqlite::Transaction<'_>,
    applied_items: &[AppliedTagSuggestion],
    occurred_at: i64,
) -> CoreResult<String> {
    let token = format!("undo:tag-suggestions:{}", Uuid::new_v4());
    let summary = json!({
        "kind": "tag_suggestions",
        "added_count": applied_items.len(),
        "affected_count": applied_items.len(),
    });
    let inverse = json!({
        "kind": "remove_tags",
        "relations": applied_items
            .iter()
            .map(tag_suggestion_relation)
            .collect::<Vec<_>>(),
    });
    let summary_json =
        serde_json::to_string(&summary).map_err(|error| CoreError::internal(error.to_string()))?;
    let inverse_json =
        serde_json::to_string(&inverse).map_err(|error| CoreError::internal(error.to_string()))?;
    tx.execute(
        "INSERT INTO undo_actions (
             token, kind, summary_json, inverse_json, status, created_at, updated_at
         ) VALUES (?1, 'batch_add_tags', ?2, ?3, 'pending', ?4, ?4)",
        params![token, summary_json, inverse_json, occurred_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}

fn tag_suggestion_relation(item: &AppliedTagSuggestion) -> Value {
    json!({
        "file_id": item.file_id,
        "tag": item.tag,
        "suggestion_id": item.suggestion_id,
    })
}
