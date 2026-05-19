use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{CoreError, CoreResult, RedoActionRecord, RedoActionResult, RedoActionStatus};

use super::open_repo_connection;

#[path = "redo/fs_ops.rs"]
mod fs_ops;

const REDO_ACTION_LIMIT: i64 = 100;
const BATCH_ADD_TAGS_KIND: &str = "batch_add_tags";
const RENAME_FILES_KIND: &str = "rename_files";
const MOVE_FILES_KIND: &str = "move_files";
const CHANGE_CATEGORY_KIND: &str = "change_category";
const BATCH_CHANGE_CATEGORY_KIND: &str = "batch_change_category";
const TRASH_DELETE_KIND: &str = "trash_delete";
const REDO_CLEARED_REASON: &str = "Redo action was cleared by a new write";

pub(crate) fn list_redo_action_rows(repo_path: &Path) -> CoreResult<Vec<RedoActionRecord>> {
    let connection = open_repo_connection(repo_path)?;
    ensure_redo_metadata_ready(&connection)?;
    let rows = load_redo_actions(&connection)?;
    rows.into_iter()
        .map(|row| redo_record_from_row(repo_path, &connection, row))
        .collect()
}

pub(crate) fn execute_redo_action_row(
    repo_path: &Path,
    action_id: &str,
) -> CoreResult<RedoActionResult> {
    let mut connection = open_repo_connection(repo_path)?;
    ensure_redo_metadata_ready(&connection)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let row = load_executed_action(&tx, action_id)?;
    let completed_at = chrono::Utc::now().timestamp();

    let execution = if row.kind == BATCH_ADD_TAGS_KIND {
        execute_batch_tag_redo(&tx, &row, completed_at)?
    } else if is_file_action_kind(&row.kind) {
        execute_file_redo(&tx, repo_path, &row, completed_at)?
    } else {
        return Err(CoreError::conflict("Unsupported redo action kind"));
    };

    restore_pending_undo_action(&tx, row.token.as_str(), completed_at)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut execution = execution;
    execution.disarm();

    Ok(RedoActionResult {
        action_id: row.token.clone(),
        status: RedoActionStatus::Executed,
        summary: execution.summary,
        affected_count: execution.affected_count,
        refresh_targets: execution.refresh_targets,
        undo_token: Some(row.token),
        completed_at,
    })
}

pub(crate) fn clear_redo_stack_in_tx(
    connection: &rusqlite::Connection,
    updated_at: i64,
) -> CoreResult<()> {
    let mut statement = connection
        .prepare("SELECT token, summary_json FROM undo_actions WHERE status = 'executed'")
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)))
        .map_err(|error| CoreError::db(error.to_string()))?;
    let actions = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))?;
    drop(statement);

    for (token, summary_json) in actions {
        let summary_json = redo_cleared_summary_json(&summary_json)?;
        connection
            .execute(
                "UPDATE undo_actions
                    SET summary_json = ?2,
                        status = 'expired',
                        updated_at = ?3
                  WHERE token = ?1 AND status = 'executed'",
                params![token, summary_json, updated_at],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
    }
    Ok(())
}

#[derive(Debug)]
struct StoredRedoAction {
    token: String,
    kind: String,
    summary_json: String,
    inverse_json: String,
    status: String,
    updated_at: i64,
}

#[derive(Debug, Deserialize)]
struct RedoSummary {
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

#[derive(Debug, Deserialize)]
struct RestoreFileStateInverse {
    kind: String,
    file_id: i64,
    operation: String,
    expected_path: String,
    expected_name: String,
    expected_category: String,
    restore_path: String,
    restore_name: String,
    restore_category: String,
    index_only: bool,
}

#[derive(Debug, Deserialize)]
struct RestoreBatchFileStateInverse {
    kind: String,
    operation: String,
    items: Vec<RestoreBatchFileStateItem>,
}

#[derive(Debug, Deserialize)]
struct RestoreBatchFileStateItem {
    file_id: i64,
    expected_path: String,
    expected_name: String,
    expected_category: String,
    restore_path: String,
    restore_name: String,
    restore_category: String,
    index_only: bool,
}

#[derive(Debug, Deserialize)]
struct RestoreDeletedFileInverse {
    kind: String,
    file_id: i64,
    #[serde(rename = "trash_path")]
    _trash_path: Option<String>,
    restore_path: String,
    restore_name: String,
    restore_category: String,
}

#[derive(Debug, Deserialize)]
struct RestoreBatchDeletedFilesInverse {
    kind: String,
    operation: String,
    items: Vec<RestoreBatchDeletedFileItem>,
}

#[derive(Debug, Deserialize)]
struct RestoreBatchDeletedFileItem {
    file_id: i64,
    #[serde(rename = "trash_path")]
    _trash_path: String,
    restore_path: String,
    restore_name: String,
    restore_category: String,
}

#[derive(Debug)]
struct FileDbState {
    path: String,
    current_name: String,
    category: String,
    status: String,
}

struct RedoExecution {
    summary: String,
    affected_count: i64,
    refresh_targets: Vec<String>,
    guards: Vec<fs_ops::FileMoveRollbackGuard>,
}

impl RedoExecution {
    fn disarm(&mut self) {
        for guard in &mut self.guards {
            guard.disarm();
        }
    }
}

fn ensure_redo_metadata_ready(connection: &rusqlite::Connection) -> CoreResult<()> {
    for statement in [
        "SELECT token, kind, summary_json, inverse_json, status FROM undo_actions LIMIT 0",
        "SELECT file_id, tag, added_at FROM tags LIMIT 0",
        "SELECT id, path, current_name, category, status FROM files LIMIT 0",
        "SELECT file_id, action, detail_json, occurred_at FROM change_log LIMIT 0",
    ] {
        connection
            .prepare(statement)
            .map(|_| ())
            .map_err(|error| CoreError::db(error.to_string()))?;
    }
    Ok(())
}

fn load_redo_actions(connection: &rusqlite::Connection) -> CoreResult<Vec<StoredRedoAction>> {
    let mut statement = connection
        .prepare(
            "SELECT token, kind, summary_json, inverse_json, status, updated_at
               FROM undo_actions
              WHERE status IN ('executed', 'expired', 'blocked')
              ORDER BY updated_at DESC, token DESC
              LIMIT ?1",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![REDO_ACTION_LIMIT], stored_action_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn load_executed_action(
    connection: &rusqlite::Connection,
    action_id: &str,
) -> CoreResult<StoredRedoAction> {
    let action = connection
        .query_row(
            "SELECT token, kind, summary_json, inverse_json, status, updated_at
               FROM undo_actions
              WHERE token = ?1",
            params![action_id],
            stored_action_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(action_id.to_owned()))?;
    match action.status.as_str() {
        "executed" => Ok(action),
        "pending" => Err(CoreError::file_not_found(action_id.to_owned())),
        "expired" | "blocked" => Err(CoreError::expired_action(action_id.to_owned())),
        _ => Err(CoreError::db("invalid redo action status")),
    }
}

fn stored_action_from_row(row: &Row<'_>) -> rusqlite::Result<StoredRedoAction> {
    Ok(StoredRedoAction {
        token: row.get(0)?,
        kind: row.get(1)?,
        summary_json: row.get(2)?,
        inverse_json: row.get(3)?,
        status: row.get(4)?,
        updated_at: row.get(5)?,
    })
}

fn redo_record_from_row(
    repo_path: &Path,
    connection: &rusqlite::Connection,
    row: StoredRedoAction,
) -> CoreResult<RedoActionRecord> {
    let summary = parse_summary(&row.summary_json)?;
    let inverse = parse_inverse_value(&row.inverse_json)?;
    let mut status = status_from_db(&row.status)?;
    if status == RedoActionStatus::Expired
        && summary.disabled_reason.as_deref() == Some(REDO_CLEARED_REASON)
    {
        status = RedoActionStatus::Cleared;
    }
    let disabled_reason = disabled_reason(
        connection, &status, &row.kind, &inverse, &summary, repo_path,
    )?;
    if status == RedoActionStatus::Available && disabled_reason.is_some() {
        status = RedoActionStatus::Blocked;
    }

    Ok(RedoActionRecord {
        action_id: row.token.clone(),
        kind: row.kind.clone(),
        summary: redo_display_summary(&row.kind, &summary),
        affected_count: affected_count(&summary, &inverse),
        affected_file_names: summary.affected_file_names.unwrap_or_default(),
        can_redo: status == RedoActionStatus::Available,
        disabled_reason,
        status,
        source_undo_action_id: row.token,
        created_at: row.updated_at,
        updated_at: row.updated_at,
    })
}

fn status_from_db(status: &str) -> CoreResult<RedoActionStatus> {
    match status {
        "executed" => Ok(RedoActionStatus::Available),
        "expired" => Ok(RedoActionStatus::Expired),
        "blocked" => Ok(RedoActionStatus::Blocked),
        _ => Err(CoreError::db("invalid redo action status")),
    }
}

fn parse_summary(summary_json: &str) -> CoreResult<RedoSummary> {
    serde_json::from_str(summary_json).map_err(|error| CoreError::db(error.to_string()))
}

fn parse_inverse_value(inverse_json: &str) -> CoreResult<Value> {
    serde_json::from_str(inverse_json).map_err(|error| CoreError::db(error.to_string()))
}

fn redo_cleared_summary_json(summary_json: &str) -> CoreResult<String> {
    let mut value: Value =
        serde_json::from_str(summary_json).map_err(|error| CoreError::db(error.to_string()))?;
    let Value::Object(ref mut object) = value else {
        return Err(CoreError::db("invalid redo summary"));
    };
    object.insert(
        "disabled_reason".to_owned(),
        Value::String(REDO_CLEARED_REASON.to_owned()),
    );
    serde_json::to_string(&value).map_err(|error| CoreError::internal(error.to_string()))
}

fn redo_display_summary(kind: &str, summary: &RedoSummary) -> String {
    match kind {
        BATCH_ADD_TAGS_KIND => {
            let count = summary.added_count.or(summary.affected_count).unwrap_or(0);
            format!("Redo: add {count} tag relation(s).")
        }
        RENAME_FILES_KIND => "Redo: rename 1 file.".to_owned(),
        MOVE_FILES_KIND => "Redo: move 1 file.".to_owned(),
        CHANGE_CATEGORY_KIND => "Redo: change category for 1 file.".to_owned(),
        BATCH_CHANGE_CATEGORY_KIND => {
            let count = summary.affected_count.unwrap_or(0);
            format!("Redo: change category for {count} file(s).")
        }
        TRASH_DELETE_KIND => redo_trash_delete_summary(summary),
        _ => format!("Redo action: {kind}"),
    }
}

fn redo_trash_delete_summary(summary: &RedoSummary) -> String {
    let count = summary.affected_count.unwrap_or(1);
    if count == 1 {
        "Redo: move 1 file to Trash.".to_owned()
    } else {
        format!("Redo: move {count} files to Trash.")
    }
}

fn affected_count(summary: &RedoSummary, inverse: &Value) -> i64 {
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
        .unwrap_or_else(|| {
            inverse
                .get("items")
                .and_then(Value::as_array)
                .map(|items| items.len() as i64)
                .unwrap_or(0)
        })
}

fn disabled_reason(
    connection: &rusqlite::Connection,
    status: &RedoActionStatus,
    kind: &str,
    inverse: &Value,
    summary: &RedoSummary,
    repo_path: &Path,
) -> CoreResult<Option<String>> {
    if let Some(reason) = summary.disabled_reason.clone() {
        return Ok(Some(reason));
    }
    match status {
        RedoActionStatus::Available if kind == BATCH_ADD_TAGS_KIND => {
            batch_tag_redo_block_reason(connection, inverse)
        }
        RedoActionStatus::Available if is_file_action_kind(kind) => {
            file_redo_block_reason(connection, repo_path, inverse)
        }
        RedoActionStatus::Available => Ok(Some("Unsupported redo action kind".to_owned())),
        RedoActionStatus::Cleared => Ok(Some("Redo action was cleared by a new write".to_owned())),
        RedoActionStatus::Blocked => Ok(Some("Redo action is blocked".to_owned())),
        RedoActionStatus::Expired => Ok(Some("Redo action expired".to_owned())),
        RedoActionStatus::Executed => Ok(Some("Already redone".to_owned())),
    }
}

fn execute_batch_tag_redo(
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

fn execute_file_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    row: &StoredRedoAction,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    let inverse = parse_inverse_value(&row.inverse_json)?;
    match inverse.get("kind").and_then(Value::as_str) {
        Some("restore_file_state") => {
            let inverse = parse_restore_file_state(&inverse)?;
            execute_restore_file_state_redo(tx, repo, &row.kind, &inverse, completed_at)
        }
        Some("restore_batch_file_state") => {
            let inverse = parse_restore_batch_file_state(&inverse)?;
            execute_restore_batch_file_state_redo(tx, repo, &row.kind, &inverse, completed_at)
        }
        Some("restore_deleted_file") => {
            let inverse = parse_restore_deleted_file(&inverse)?;
            execute_restore_deleted_file_redo(tx, repo, &inverse, completed_at)
        }
        Some("restore_batch_deleted_files") => {
            let inverse = parse_restore_batch_deleted_files(&inverse)?;
            execute_restore_batch_deleted_files_redo(tx, repo, &inverse, completed_at)
        }
        _ => Err(CoreError::conflict("Unsupported redo inverse")),
    }
}

fn batch_tag_redo_block_reason(
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

fn file_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &Value,
) -> CoreResult<Option<String>> {
    match inverse.get("kind").and_then(Value::as_str) {
        Some("restore_file_state") => {
            let inverse = parse_restore_file_state(inverse)?;
            file_state_redo_block_reason(connection, repo, &inverse)
        }
        Some("restore_batch_file_state") => {
            let inverse = parse_restore_batch_file_state(inverse)?;
            batch_file_state_redo_block_reason(connection, repo, &inverse)
        }
        Some("restore_deleted_file") => {
            let inverse = parse_restore_deleted_file(inverse)?;
            deleted_file_redo_block_reason(connection, repo, &inverse)
        }
        Some("restore_batch_deleted_files") => {
            let inverse = parse_restore_batch_deleted_files(inverse)?;
            batch_deleted_files_redo_block_reason(connection, repo, &inverse)
        }
        _ => Ok(Some("Unsupported redo inverse".to_owned())),
    }
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

fn execute_restore_file_state_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    kind: &str,
    inverse: &RestoreFileStateInverse,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    ensure_restore_file_state_kind(inverse)?;
    ensure_file_state_matches_restored(tx, inverse)?;
    let mut guards = if inverse.index_only {
        Vec::new()
    } else {
        move_redo_active_path(repo, &inverse.restore_path, &inverse.expected_path)?
    };
    if let Err(error) = update_active_file_state_to_expected(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    insert_file_redo_change(tx, kind, inverse.file_id, completed_at, &inverse.operation)?;
    Ok(RedoExecution {
        summary: format!("Redone: {}.", inverse.operation),
        affected_count: 1,
        refresh_targets: file_refresh_targets(kind),
        guards,
    })
}

fn execute_restore_batch_file_state_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    kind: &str,
    inverse: &RestoreBatchFileStateInverse,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    ensure_restore_batch_file_state_kind(inverse)?;
    ensure_batch_file_state_matches_restored(tx, inverse)?;
    let mut guards = move_redo_batch_active_paths(repo, inverse)?;
    if let Err(error) = update_batch_file_state_to_expected(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    for item in &inverse.items {
        insert_file_redo_change(tx, kind, item.file_id, completed_at, &inverse.operation)?;
    }
    Ok(RedoExecution {
        summary: format!("Redone: {}.", inverse.operation),
        affected_count: inverse.items.len() as i64,
        refresh_targets: file_refresh_targets(kind),
        guards,
    })
}

fn execute_restore_deleted_file_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    inverse: &RestoreDeletedFileInverse,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    ensure_restore_deleted_file_kind(inverse)?;
    ensure_deleted_file_matches_restored(tx, inverse)?;
    let current_path = fs_ops::repo_relative_path(repo, &inverse.restore_path)?;
    let mut guards = vec![fs_ops::move_path_to_user_trash(&current_path)?];
    if let Err(error) = update_deleted_file_state_to_deleted(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    insert_file_redo_change(
        tx,
        TRASH_DELETE_KIND,
        inverse.file_id,
        completed_at,
        "delete",
    )?;
    Ok(RedoExecution {
        summary: "Redone: moved file to Trash.".to_owned(),
        affected_count: 1,
        refresh_targets: file_refresh_targets(TRASH_DELETE_KIND),
        guards,
    })
}

fn execute_restore_batch_deleted_files_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    inverse: &RestoreBatchDeletedFilesInverse,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    ensure_restore_batch_deleted_files_kind(inverse)?;
    ensure_batch_deleted_files_match_restored(tx, inverse)?;
    let mut guards = move_batch_files_to_trash(repo, inverse)?;
    if let Err(error) = update_batch_deleted_files_to_deleted(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    for item in &inverse.items {
        insert_file_redo_change(
            tx,
            TRASH_DELETE_KIND,
            item.file_id,
            completed_at,
            &inverse.operation,
        )?;
    }
    Ok(RedoExecution {
        summary: "Redone: moved files to Trash.".to_owned(),
        affected_count: inverse.items.len() as i64,
        refresh_targets: file_refresh_targets(TRASH_DELETE_KIND),
        guards,
    })
}

fn file_state_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreFileStateInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_file_state_kind(inverse)?;
    let Some(state) = load_file_state(connection, inverse.file_id)? else {
        return Ok(Some("File no longer exists".to_owned()));
    };
    if state.status != "active" {
        return Ok(Some("File no longer active".to_owned()));
    }
    if !state_matches_restored(&state, inverse) {
        return Ok(Some("File changed after undo".to_owned()));
    }
    if inverse.index_only {
        return Ok(None);
    }
    filesystem_redo_block_reason(repo, &inverse.restore_path, &inverse.expected_path)
}

fn batch_file_state_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_batch_file_state_kind(inverse)?;
    for item in &inverse.items {
        let Some(state) = load_file_state(connection, item.file_id)? else {
            return Ok(Some("File no longer exists".to_owned()));
        };
        if state.status != "active" {
            return Ok(Some("File no longer active".to_owned()));
        }
        if !batch_state_matches_restored(&state, item) {
            return Ok(Some("File changed after undo".to_owned()));
        }
        if item.index_only {
            continue;
        }
        if let Some(reason) =
            filesystem_redo_block_reason(repo, &item.restore_path, &item.expected_path)?
        {
            return Ok(Some(reason));
        }
    }
    Ok(None)
}

fn deleted_file_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreDeletedFileInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_deleted_file_kind(inverse)?;
    let Some(state) = load_file_state(connection, inverse.file_id)? else {
        return Ok(Some("File no longer exists".to_owned()));
    };
    if state.status != "active" || !deleted_state_matches_restored(&state, inverse) {
        return Ok(Some("File changed after undo".to_owned()));
    }
    let current_path = fs_ops::repo_relative_path(repo, &inverse.restore_path)?;
    if !fs_ops::path_exists(&current_path)? {
        return Ok(Some("File no longer exists".to_owned()));
    }
    if !current_path
        .metadata()
        .map_err(fs_ops::map_io_error)?
        .is_file()
    {
        return Ok(Some("File changed after undo".to_owned()));
    }
    Ok(None)
}

fn batch_deleted_files_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreBatchDeletedFilesInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_batch_deleted_files_kind(inverse)?;
    for item in &inverse.items {
        let Some(state) = load_file_state(connection, item.file_id)? else {
            return Ok(Some("File no longer exists".to_owned()));
        };
        if state.status != "active" || !batch_deleted_state_matches_restored(&state, item) {
            return Ok(Some("File changed after undo".to_owned()));
        }
        let current_path = fs_ops::repo_relative_path(repo, &item.restore_path)?;
        if !fs_ops::path_exists(&current_path)? {
            return Ok(Some("File no longer exists".to_owned()));
        }
        if !current_path
            .metadata()
            .map_err(fs_ops::map_io_error)?
            .is_file()
        {
            return Ok(Some("File changed after undo".to_owned()));
        }
    }
    Ok(None)
}

fn filesystem_redo_block_reason(
    repo: &Path,
    restored_relative: &str,
    expected_relative: &str,
) -> CoreResult<Option<String>> {
    let restored_path = fs_ops::repo_relative_path(repo, restored_relative)?;
    let expected_path = fs_ops::repo_relative_path(repo, expected_relative)?;
    if !fs_ops::path_exists(&restored_path)? {
        return Ok(Some("File no longer exists".to_owned()));
    }
    if !restored_path
        .metadata()
        .map_err(fs_ops::map_io_error)?
        .is_file()
    {
        return Ok(Some("File changed after undo".to_owned()));
    }
    if restored_path == expected_path {
        return Ok(None);
    }
    if fs_ops::path_exists(&expected_path)? {
        return Ok(Some("Redo destination is occupied".to_owned()));
    }
    Ok(None)
}

fn move_redo_active_path(
    repo: &Path,
    restored_relative: &str,
    expected_relative: &str,
) -> CoreResult<Vec<fs_ops::FileMoveRollbackGuard>> {
    let restored_path = fs_ops::repo_relative_path(repo, restored_relative)?;
    let expected_path = fs_ops::repo_relative_path(repo, expected_relative)?;
    if restored_path == expected_path {
        return Ok(Vec::new());
    }
    fs_ops::move_checked_path(&restored_path, &expected_path).map(|guard| vec![guard])
}

fn move_redo_batch_active_paths(
    repo: &Path,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<Vec<fs_ops::FileMoveRollbackGuard>> {
    let mut guards = Vec::new();
    for item in &inverse.items {
        if item.index_only {
            continue;
        }
        let mut item_guards = move_redo_active_path(repo, &item.restore_path, &item.expected_path)?;
        guards.append(&mut item_guards);
    }
    Ok(guards)
}

fn move_batch_files_to_trash(
    repo: &Path,
    inverse: &RestoreBatchDeletedFilesInverse,
) -> CoreResult<Vec<fs_ops::FileMoveRollbackGuard>> {
    let mut guards = Vec::new();
    for item in &inverse.items {
        let current_path = fs_ops::repo_relative_path(repo, &item.restore_path)?;
        guards.push(fs_ops::move_path_to_user_trash(&current_path)?);
    }
    Ok(guards)
}

fn update_active_file_state_to_expected(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreFileStateInverse,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 category = ?4,
                 updated_at = ?5
             WHERE id = ?1 AND status = 'active'",
            params![
                inverse.file_id,
                inverse.expected_path,
                inverse.expected_name,
                inverse.expected_category,
                updated_at
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_single_row_changed(changed, inverse.file_id)
}

fn update_batch_file_state_to_expected(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreBatchFileStateInverse,
    updated_at: i64,
) -> CoreResult<()> {
    for item in &inverse.items {
        let changed = tx
            .execute(
                "UPDATE files
                 SET path = ?2,
                     current_name = ?3,
                     category = ?4,
                     updated_at = ?5
                 WHERE id = ?1 AND status = 'active'",
                params![
                    item.file_id,
                    item.expected_path,
                    item.expected_name,
                    item.expected_category,
                    updated_at
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        ensure_single_row_changed(changed, item.file_id)?;
    }
    Ok(())
}

fn update_deleted_file_state_to_deleted(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreDeletedFileInverse,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET deleted_at = ?2,
                 updated_at = ?2,
                 status = 'deleted'
             WHERE id = ?1 AND status = 'active'",
            params![inverse.file_id, updated_at],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_single_row_changed(changed, inverse.file_id)
}

fn update_batch_deleted_files_to_deleted(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreBatchDeletedFilesInverse,
    updated_at: i64,
) -> CoreResult<()> {
    for item in &inverse.items {
        let changed = tx
            .execute(
                "UPDATE files
                 SET deleted_at = ?2,
                     updated_at = ?2,
                     status = 'deleted'
                 WHERE id = ?1 AND status = 'active'",
                params![item.file_id, updated_at],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        ensure_single_row_changed(changed, item.file_id)?;
    }
    Ok(())
}

fn ensure_file_state_matches_restored(
    connection: &rusqlite::Connection,
    inverse: &RestoreFileStateInverse,
) -> CoreResult<()> {
    let state = load_file_state(connection, inverse.file_id)?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{}", inverse.file_id)))?;
    if state.status != "active" || !state_matches_restored(&state, inverse) {
        return Err(CoreError::conflict("File changed after undo"));
    }
    Ok(())
}

fn ensure_batch_file_state_matches_restored(
    connection: &rusqlite::Connection,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<()> {
    for item in &inverse.items {
        let state = load_file_state(connection, item.file_id)?
            .ok_or_else(|| CoreError::file_not_found(format!("file:{}", item.file_id)))?;
        if state.status != "active" || !batch_state_matches_restored(&state, item) {
            return Err(CoreError::conflict("File changed after undo"));
        }
    }
    Ok(())
}

fn ensure_deleted_file_matches_restored(
    connection: &rusqlite::Connection,
    inverse: &RestoreDeletedFileInverse,
) -> CoreResult<()> {
    let state = load_file_state(connection, inverse.file_id)?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{}", inverse.file_id)))?;
    if state.status != "active" || !deleted_state_matches_restored(&state, inverse) {
        return Err(CoreError::conflict("File changed after undo"));
    }
    Ok(())
}

fn ensure_batch_deleted_files_match_restored(
    connection: &rusqlite::Connection,
    inverse: &RestoreBatchDeletedFilesInverse,
) -> CoreResult<()> {
    for item in &inverse.items {
        let state = load_file_state(connection, item.file_id)?
            .ok_or_else(|| CoreError::file_not_found(format!("file:{}", item.file_id)))?;
        if state.status != "active" || !batch_deleted_state_matches_restored(&state, item) {
            return Err(CoreError::conflict("File changed after undo"));
        }
    }
    Ok(())
}

fn state_matches_restored(state: &FileDbState, inverse: &RestoreFileStateInverse) -> bool {
    state.path == inverse.restore_path
        && state.current_name == inverse.restore_name
        && state.category == inverse.restore_category
}

fn batch_state_matches_restored(state: &FileDbState, inverse: &RestoreBatchFileStateItem) -> bool {
    state.path == inverse.restore_path
        && state.current_name == inverse.restore_name
        && state.category == inverse.restore_category
}

fn deleted_state_matches_restored(
    state: &FileDbState,
    inverse: &RestoreDeletedFileInverse,
) -> bool {
    state.path == inverse.restore_path
        && state.current_name == inverse.restore_name
        && state.category == inverse.restore_category
}

fn batch_deleted_state_matches_restored(
    state: &FileDbState,
    inverse: &RestoreBatchDeletedFileItem,
) -> bool {
    state.path == inverse.restore_path
        && state.current_name == inverse.restore_name
        && state.category == inverse.restore_category
}

fn load_file_state(
    connection: &rusqlite::Connection,
    file_id: i64,
) -> CoreResult<Option<FileDbState>> {
    connection
        .query_row(
            "SELECT path, current_name, category, status
               FROM files
              WHERE id = ?1",
            params![file_id],
            |row| {
                Ok(FileDbState {
                    path: row.get(0)?,
                    current_name: row.get(1)?,
                    category: row.get(2)?,
                    status: row.get(3)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn insert_file_redo_change(
    tx: &rusqlite::Transaction<'_>,
    kind: &str,
    file_id: i64,
    occurred_at: i64,
    operation: &str,
) -> CoreResult<()> {
    let action = match kind {
        RENAME_FILES_KIND => "renamed",
        MOVE_FILES_KIND | CHANGE_CATEGORY_KIND | BATCH_CHANGE_CATEGORY_KIND => "moved",
        TRASH_DELETE_KIND => "deleted",
        _ => return Err(CoreError::conflict("Unsupported redo action kind")),
    };
    let detail = json!({
        "kind": "redo_file_action",
        "operation": operation,
        "by": "redo",
    });
    insert_change_log(tx, file_id, action, &detail, occurred_at)
}

fn insert_change_log(
    connection: &rusqlite::Connection,
    file_id: i64,
    action: &str,
    detail: &Value,
    occurred_at: i64,
) -> CoreResult<()> {
    let detail_json =
        serde_json::to_string(detail).map_err(|error| CoreError::internal(error.to_string()))?;
    connection
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![file_id, action, detail_json, occurred_at],
        )
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn restore_pending_undo_action(
    tx: &rusqlite::Transaction<'_>,
    action_id: &str,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE undo_actions
                SET status = 'pending',
                    updated_at = ?2
              WHERE token = ?1 AND status = 'executed'",
            params![action_id, updated_at],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::expired_action(action_id.to_owned()))
    }
}

fn is_file_action_kind(kind: &str) -> bool {
    matches!(
        kind,
        RENAME_FILES_KIND
            | MOVE_FILES_KIND
            | CHANGE_CATEGORY_KIND
            | BATCH_CHANGE_CATEGORY_KIND
            | TRASH_DELETE_KIND
    )
}

fn file_refresh_targets(kind: &str) -> Vec<String> {
    let mut targets = vec![
        "files".to_owned(),
        "undo_actions".to_owned(),
        "redo_actions".to_owned(),
        "change_log".to_owned(),
        "selection".to_owned(),
    ];
    if matches!(
        kind,
        MOVE_FILES_KIND | CHANGE_CATEGORY_KIND | TRASH_DELETE_KIND
    ) {
        targets.push("tree".to_owned());
    }
    targets
}

fn parse_restore_file_state(value: &Value) -> CoreResult<RestoreFileStateInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

fn parse_restore_batch_file_state(value: &Value) -> CoreResult<RestoreBatchFileStateInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

fn parse_restore_deleted_file(value: &Value) -> CoreResult<RestoreDeletedFileInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

fn parse_restore_batch_deleted_files(value: &Value) -> CoreResult<RestoreBatchDeletedFilesInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_restore_file_state_kind(inverse: &RestoreFileStateInverse) -> CoreResult<()> {
    if inverse.kind == "restore_file_state" {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}

fn ensure_restore_batch_file_state_kind(inverse: &RestoreBatchFileStateInverse) -> CoreResult<()> {
    if inverse.kind == "restore_batch_file_state" && !inverse.items.is_empty() {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}

fn ensure_restore_deleted_file_kind(inverse: &RestoreDeletedFileInverse) -> CoreResult<()> {
    if inverse.kind == "restore_deleted_file" {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}

fn ensure_restore_batch_deleted_files_kind(
    inverse: &RestoreBatchDeletedFilesInverse,
) -> CoreResult<()> {
    if inverse.kind == "restore_batch_deleted_files" && !inverse.items.is_empty() {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}

fn ensure_single_row_changed(changed: usize, file_id: i64) -> CoreResult<()> {
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::file_not_found(format!("file:{file_id}")))
    }
}

#[allow(dead_code)]
fn new_redo_token(kind: &str) -> String {
    format!("redo:{kind}:{}", Uuid::new_v4())
}
