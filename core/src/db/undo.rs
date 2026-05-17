use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde::Deserialize;
use serde_json::Value;

use crate::{CoreError, CoreResult, UndoActionRecord, UndoActionResult, UndoActionStatus};

use super::open_repo_connection;

mod actions;
mod file_actions;
pub(crate) use actions::{
    delete_undo_action, insert_delete_undo_action, insert_move_undo_action,
    insert_rename_undo_action, load_active_file_undo_snapshot, update_delete_undo_trash_path,
    FileUndoTarget,
};
use file_actions::{CHANGE_CATEGORY_KIND, MOVE_FILES_KIND, RENAME_FILES_KIND, TRASH_DELETE_KIND};

const UNDO_ACTION_LIMIT: i64 = 100;
const BATCH_ADD_TAGS_KIND: &str = "batch_add_tags";

pub(crate) fn list_undo_action_rows(repo_path: &Path) -> CoreResult<Vec<UndoActionRecord>> {
    let connection = open_repo_connection(repo_path)?;
    ensure_undo_metadata_ready(&connection)?;
    let rows = load_undo_actions(&connection)?;
    rows.into_iter()
        .map(|row| undo_record_from_row(repo_path, &connection, row))
        .collect()
}

pub(crate) fn execute_undo_action_row(
    repo_path: &Path,
    action_id: &str,
) -> CoreResult<UndoActionResult> {
    let mut connection = open_repo_connection(repo_path)?;
    ensure_undo_metadata_ready(&connection)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let row = load_pending_action(&tx, action_id)?;
    let completed_at = chrono::Utc::now().timestamp();

    if row.kind == BATCH_ADD_TAGS_KIND {
        let result = execute_batch_tag_action(&tx, &row, completed_at)?;
        tx.commit()
            .map_err(|error| CoreError::db(error.to_string()))?;
        return Ok(result);
    }

    if file_actions::is_file_action_kind(&row.kind) {
        let mut execution = file_actions::execute_file_action(
            &tx,
            repo_path,
            &row.kind,
            &row.inverse_json,
            &row.token,
            completed_at,
        )?;
        mark_action_status(&tx, row.token.as_str(), "executed", completed_at)?;
        tx.commit()
            .map_err(|error| CoreError::db(error.to_string()))?;
        execution.disarm();
        return Ok(UndoActionResult {
            action_id: row.token,
            status: UndoActionStatus::Executed,
            summary: execution.summary,
            affected_count: execution.affected_count,
            refresh_targets: execution.refresh_targets,
            completed_at,
        });
    }

    Err(CoreError::conflict("Unsupported undo action kind"))
}

fn execute_batch_tag_action(
    tx: &rusqlite::Transaction<'_>,
    row: &StoredUndoAction,
    completed_at: i64,
) -> CoreResult<UndoActionResult> {
    let inverse = parse_remove_tags_inverse(&row.inverse_json)?;
    ensure_relations_still_undoable(tx, &inverse.relations)?;
    for relation in &inverse.relations {
        remove_tag_relation(tx, relation)?;
        insert_undo_change(tx, relation, row.token.as_str(), completed_at)?;
    }
    mark_action_status(tx, row.token.as_str(), "executed", completed_at)?;

    Ok(UndoActionResult {
        action_id: row.token.clone(),
        status: UndoActionStatus::Executed,
        summary: undo_completion_summary(&inverse),
        affected_count: inverse.relations.len() as i64,
        refresh_targets: vec![
            "files".to_owned(),
            "tags".to_owned(),
            "undo_actions".to_owned(),
            "change_log".to_owned(),
        ],
        completed_at,
    })
}

#[derive(Debug)]
struct StoredUndoAction {
    token: String,
    kind: String,
    inverse_json: String,
}

#[derive(Debug)]
struct StoredUndoActionRow {
    token: String,
    kind: String,
    summary_json: String,
    inverse_json: String,
    status: String,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Deserialize)]
struct UndoSummary {
    added_count: Option<i64>,
    affected_count: Option<i64>,
    affected_file_names: Option<Vec<String>>,
    disabled_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RemoveTagsInverse {
    kind: String,
    relations: Vec<TagRelation>,
}

#[derive(Clone, Debug, Deserialize)]
struct TagRelation {
    file_id: i64,
    tag: String,
}

fn ensure_undo_metadata_ready(connection: &rusqlite::Connection) -> CoreResult<()> {
    for statement in [
        "SELECT token, kind, summary_json, inverse_json, status FROM undo_actions LIMIT 0",
        "SELECT file_id, tag, added_at FROM tags LIMIT 0",
        "SELECT id, current_name, status FROM files LIMIT 0",
        "SELECT file_id, action, detail_json, occurred_at FROM change_log LIMIT 0",
    ] {
        connection
            .prepare(statement)
            .map(|_| ())
            .map_err(|error| CoreError::db(error.to_string()))?;
    }
    Ok(())
}

fn load_undo_actions(connection: &rusqlite::Connection) -> CoreResult<Vec<StoredUndoActionRow>> {
    let mut statement = connection
        .prepare(
            "SELECT token, kind, summary_json, inverse_json, status, created_at, updated_at
               FROM undo_actions
              ORDER BY created_at DESC, token DESC
              LIMIT ?1",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![UNDO_ACTION_LIMIT], stored_action_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn stored_action_from_row(row: &Row<'_>) -> rusqlite::Result<StoredUndoActionRow> {
    Ok(StoredUndoActionRow {
        token: row.get(0)?,
        kind: row.get(1)?,
        summary_json: row.get(2)?,
        inverse_json: row.get(3)?,
        status: row.get(4)?,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
    })
}

fn undo_record_from_row(
    repo_path: &Path,
    connection: &rusqlite::Connection,
    row: StoredUndoActionRow,
) -> CoreResult<UndoActionRecord> {
    let status = status_from_db(&row.status)?;
    let summary = parse_summary(&row.summary_json)?;
    let inverse = parse_inverse_value(&row.inverse_json)?;
    let display_summary = display_summary(&row.kind, &summary);
    let affected_count = affected_count(&summary, &inverse);
    let disabled_reason = disabled_reason(
        connection,
        &status,
        &row.kind,
        &inverse,
        summary.disabled_reason.clone(),
        repo_path,
    )?;
    let effective_status = if status == UndoActionStatus::Pending && disabled_reason.is_some() {
        UndoActionStatus::Blocked
    } else {
        status
    };

    Ok(UndoActionRecord {
        action_id: row.token,
        kind: row.kind.clone(),
        summary: display_summary,
        affected_count,
        affected_file_names: summary.affected_file_names.unwrap_or_default(),
        can_undo: effective_status == UndoActionStatus::Pending,
        disabled_reason,
        status: effective_status,
        created_at: row.created_at,
        updated_at: row.updated_at,
    })
}

fn status_from_db(status: &str) -> CoreResult<UndoActionStatus> {
    match status {
        "pending" => Ok(UndoActionStatus::Pending),
        "executed" => Ok(UndoActionStatus::Executed),
        "expired" => Ok(UndoActionStatus::Expired),
        "blocked" => Ok(UndoActionStatus::Blocked),
        _ => Err(CoreError::db("invalid undo action status")),
    }
}

fn parse_summary(summary_json: &str) -> CoreResult<UndoSummary> {
    serde_json::from_str(summary_json).map_err(|error| CoreError::db(error.to_string()))
}

fn parse_inverse_value(inverse_json: &str) -> CoreResult<Value> {
    serde_json::from_str(inverse_json).map_err(|error| CoreError::db(error.to_string()))
}

fn display_summary(kind: &str, summary: &UndoSummary) -> String {
    match kind {
        BATCH_ADD_TAGS_KIND => {
            let count = summary.added_count.or(summary.affected_count).unwrap_or(0);
            format!("Added tags to {count} relation(s).")
        }
        RENAME_FILES_KIND => "Renamed 1 file.".to_owned(),
        MOVE_FILES_KIND => "Moved 1 file.".to_owned(),
        CHANGE_CATEGORY_KIND => "Changed category for 1 file.".to_owned(),
        TRASH_DELETE_KIND => "Moved 1 file to Trash.".to_owned(),
        _ => format!("Undo action: {kind}"),
    }
}

fn affected_count(summary: &UndoSummary, inverse: &Value) -> i64 {
    summary
        .added_count
        .or(summary.affected_count)
        .unwrap_or_else(|| inverse_relation_count(inverse))
}

fn inverse_relation_count(inverse: &Value) -> i64 {
    inverse
        .get("relations")
        .and_then(Value::as_array)
        .map(|relations| relations.len() as i64)
        .unwrap_or(0)
}

fn disabled_reason(
    connection: &rusqlite::Connection,
    status: &UndoActionStatus,
    kind: &str,
    inverse: &Value,
    stored_reason: Option<String>,
    repo_path: &Path,
) -> CoreResult<Option<String>> {
    if let Some(reason) = stored_reason {
        return Ok(Some(reason));
    }
    let reason = match status {
        UndoActionStatus::Pending if kind == BATCH_ADD_TAGS_KIND => {
            pending_batch_tag_block_reason(connection, inverse)?
        }
        UndoActionStatus::Pending if file_actions::is_file_action_kind(kind) => {
            file_actions::pending_file_block_reason(connection, repo_path, inverse)?
        }
        UndoActionStatus::Pending => Some("Unsupported undo action kind".to_owned()),
        UndoActionStatus::Executed => Some("Already undone".to_owned()),
        UndoActionStatus::Expired => Some("Undo action expired".to_owned()),
        UndoActionStatus::Blocked => Some("Undo action is blocked".to_owned()),
    };
    Ok(reason)
}

fn pending_batch_tag_block_reason(
    connection: &rusqlite::Connection,
    inverse: &Value,
) -> CoreResult<Option<String>> {
    if inverse["kind"] != "remove_tags" {
        return Ok(Some("Unsupported undo inverse".to_owned()));
    }
    let parsed: RemoveTagsInverse = serde_json::from_value(inverse.clone())
        .map_err(|error| CoreError::db(error.to_string()))?;
    for relation in parsed.relations {
        if active_file_exists(connection, relation.file_id)?.is_none() {
            return Ok(Some("File no longer exists".to_owned()));
        }
        if tag_relation_exists(connection, &relation)?.is_none() {
            return Ok(Some("Tag relation already changed".to_owned()));
        }
    }
    Ok(None)
}

fn load_pending_action(
    connection: &rusqlite::Connection,
    action_id: &str,
) -> CoreResult<StoredUndoAction> {
    connection
        .query_row(
            "SELECT token, kind, inverse_json
               FROM undo_actions
              WHERE token = ?1 AND status = 'pending'",
            params![action_id],
            |row| {
                Ok(StoredUndoAction {
                    token: row.get(0)?,
                    kind: row.get(1)?,
                    inverse_json: row.get(2)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(action_id.to_owned()))
}

fn parse_remove_tags_inverse(inverse_json: &str) -> CoreResult<RemoveTagsInverse> {
    let inverse: RemoveTagsInverse =
        serde_json::from_str(inverse_json).map_err(|error| CoreError::db(error.to_string()))?;
    if inverse.kind != "remove_tags" || inverse.relations.is_empty() {
        return Err(CoreError::conflict("Unsupported undo inverse"));
    }
    Ok(inverse)
}

fn ensure_relations_still_undoable(
    connection: &rusqlite::Connection,
    relations: &[TagRelation],
) -> CoreResult<()> {
    for relation in relations {
        ensure_active_file(connection, relation.file_id)?;
        ensure_tag_relation_exists(connection, relation)?;
    }
    Ok(())
}

fn ensure_active_file(connection: &rusqlite::Connection, file_id: i64) -> CoreResult<()> {
    active_file_exists(connection, file_id)?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{file_id}")))
        .map(|_| ())
}

fn ensure_tag_relation_exists(
    connection: &rusqlite::Connection,
    relation: &TagRelation,
) -> CoreResult<()> {
    tag_relation_exists(connection, relation)?
        .ok_or_else(|| CoreError::conflict(format!("tag:{}", relation.tag)))
        .map(|_| ())
}

fn active_file_exists(connection: &rusqlite::Connection, file_id: i64) -> CoreResult<Option<()>> {
    connection
        .query_row(
            "SELECT 1 FROM files WHERE id = ?1 AND status = 'active'",
            params![file_id],
            |_| Ok(()),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn tag_relation_exists(
    connection: &rusqlite::Connection,
    relation: &TagRelation,
) -> CoreResult<Option<()>> {
    connection
        .query_row(
            "SELECT 1 FROM tags WHERE file_id = ?1 AND tag = ?2",
            params![relation.file_id, relation.tag.as_str()],
            |_| Ok(()),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn remove_tag_relation(
    connection: &rusqlite::Connection,
    relation: &TagRelation,
) -> CoreResult<()> {
    connection
        .execute(
            "DELETE FROM tags WHERE file_id = ?1 AND tag = ?2",
            params![relation.file_id, relation.tag.as_str()],
        )
        .and_then(|changed| {
            if changed == 1 {
                Ok(())
            } else {
                Err(rusqlite::Error::InvalidQuery)
            }
        })
        .map_err(|error| CoreError::db(error.to_string()))
}

fn insert_undo_change(
    connection: &rusqlite::Connection,
    relation: &TagRelation,
    action_id: &str,
    occurred_at: i64,
) -> CoreResult<()> {
    let detail = serde_json::json!({
        "kind": "undo_batch_tag_removed",
        "undo_action": action_id,
        "tag": relation.tag,
        "changed": true,
        "by": "undo",
    });
    let detail_json =
        serde_json::to_string(&detail).map_err(|error| CoreError::internal(error.to_string()))?;
    connection
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, 'external_modified', ?2, ?3)",
            params![relation.file_id, detail_json, occurred_at],
        )
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn mark_action_status(
    connection: &rusqlite::Connection,
    action_id: &str,
    status: &str,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = connection
        .execute(
            "UPDATE undo_actions
                SET status = ?1, updated_at = ?2
              WHERE token = ?3 AND status = 'pending'",
            params![status, updated_at, action_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::file_not_found(action_id.to_owned()))
    }
}

fn undo_completion_summary(inverse: &RemoveTagsInverse) -> String {
    format!(
        "Undone: removed {} tag relation(s).",
        inverse.relations.len()
    )
}
