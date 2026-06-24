use rusqlite::{params, OptionalExtension};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{CoreError, CoreResult};

use super::{change_log::insert_change_log, RedoExecution, StoredRedoAction};

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

pub(super) fn execute_batch_tag_redo(
    tx: &rusqlite::Transaction<'_>,
    row: &StoredRedoAction,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    let inverse = parse_remove_tags_inverse(&row.inverse_json)?;
    ensure_relations_redoable(tx, &inverse.relations)?;
    for relation in &inverse.relations {
        add_tag_relation(tx, relation, completed_at)?;
        insert_redo_tag_change(tx, relation, row.token.as_str(), completed_at)?;
    }
    Ok(RedoExecution {
        summary: format!("Redone: added {} tag relation(s).", inverse.relations.len()),
        affected_count: inverse.relations.len() as i64,
        refresh_targets: vec![
            "files".to_owned(),
            "tags".to_owned(),
            "undo_actions".to_owned(),
            "redo_actions".to_owned(),
            "change_log".to_owned(),
        ],
        guards: Vec::new(),
    })
}

pub(super) fn batch_tag_redo_block_reason(
    connection: &rusqlite::Connection,
    inverse: &Value,
) -> CoreResult<Option<String>> {
    let inverse: RemoveTagsInverse = serde_json::from_value(inverse.clone())
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_remove_tags_inverse(&inverse)?;
    for relation in inverse.relations {
        if active_file_exists(connection, relation.file_id)?.is_none() {
            return Ok(Some("File no longer exists".to_owned()));
        }
        if tag_relation_exists(connection, &relation)?.is_some() {
            return Ok(Some("Tag relation already exists".to_owned()));
        }
    }
    Ok(None)
}

fn parse_remove_tags_inverse(inverse_json: &str) -> CoreResult<RemoveTagsInverse> {
    let inverse: RemoveTagsInverse =
        serde_json::from_str(inverse_json).map_err(|error| CoreError::db(error.to_string()))?;
    ensure_remove_tags_inverse(&inverse)?;
    Ok(inverse)
}

fn ensure_remove_tags_inverse(inverse: &RemoveTagsInverse) -> CoreResult<()> {
    if inverse.kind == "remove_tags" && !inverse.relations.is_empty() {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}

fn ensure_relations_redoable(
    connection: &rusqlite::Connection,
    relations: &[TagRelation],
) -> CoreResult<()> {
    for relation in relations {
        ensure_active_file(connection, relation.file_id)?;
        if tag_relation_exists(connection, relation)?.is_some() {
            return Err(CoreError::conflict(format!("tag:{}", relation.tag)));
        }
    }
    Ok(())
}

fn ensure_active_file(connection: &rusqlite::Connection, file_id: i64) -> CoreResult<()> {
    active_file_exists(connection, file_id)?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{file_id}")))
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

fn add_tag_relation(
    connection: &rusqlite::Connection,
    relation: &TagRelation,
    added_at: i64,
) -> CoreResult<()> {
    connection
        .execute(
            "INSERT INTO tags (file_id, tag, added_at)
             VALUES (?1, ?2, ?3)",
            params![relation.file_id, relation.tag.as_str(), added_at],
        )
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn insert_redo_tag_change(
    connection: &rusqlite::Connection,
    relation: &TagRelation,
    action_id: &str,
    occurred_at: i64,
) -> CoreResult<()> {
    let detail = json!({
        "kind": "redo_batch_tag_added",
        "undo_action": action_id,
        "tag": relation.tag,
        "changed": true,
        "by": "redo",
    });
    insert_change_log(
        connection,
        relation.file_id,
        "external_modified",
        &detail,
        occurred_at,
    )
}
