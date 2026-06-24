use rusqlite::{params, OptionalExtension};
use serde::Deserialize;
use serde_json::Value;

use crate::{CoreError, CoreResult, UndoActionResult, UndoActionStatus};

use super::records::StoredUndoAction;

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

pub(super) fn execute_batch_tag_action(
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
    super::mark_action_status(tx, row.token.as_str(), "executed", completed_at)?;

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

pub(super) fn pending_batch_tag_block_reason(
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

fn undo_completion_summary(inverse: &RemoveTagsInverse) -> String {
    format!(
        "Undone: removed {} tag relation(s).",
        inverse.relations.len()
    )
}
