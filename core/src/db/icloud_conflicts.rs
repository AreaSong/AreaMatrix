use std::{collections::HashMap, path::Path};

use rusqlite::{params, Transaction};
use serde_json::json;
use uuid::Uuid;

use crate::{CoreError, CoreResult, ICloudConflictStatus};

use super::open_repo_connection;

const CHANGE_LOG_ACTION: &str = "external_modified";
const CONFLICT_KIND: &str = "icloud_conflict_resolved";
const UNDO_KIND: &str = "icloud_conflict_resolution";

pub(crate) fn list_icloud_conflict_statuses(
    repo_path: &Path,
) -> CoreResult<HashMap<String, ICloudConflictStatus>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT detail_json
             FROM change_log
             WHERE action = ?1
             ORDER BY occurred_at DESC, id DESC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![CHANGE_LOG_ACTION], |row| row.get::<_, String>(0))
        .map_err(|error| CoreError::db(error.to_string()))?;

    let mut statuses = HashMap::new();
    for row in rows {
        let detail_json = row.map_err(|error| CoreError::db(error.to_string()))?;
        if let Some(conflict_id) = resolved_conflict_id(&detail_json)? {
            statuses
                .entry(conflict_id)
                .or_insert(ICloudConflictStatus::Resolved);
        }
    }
    Ok(statuses)
}

pub(crate) fn record_icloud_conflict_resolution(
    repo_path: &Path,
    conflict_id: &str,
    resolution: &str,
    create_undo: bool,
) -> CoreResult<Option<String>> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let occurred_at = chrono::Utc::now().timestamp();
    let undo_token = if create_undo {
        Some(insert_conflict_resolution_undo(
            &tx,
            conflict_id,
            resolution,
            occurred_at,
        )?)
    } else {
        None
    };
    insert_conflict_resolution_change(&tx, conflict_id, resolution, occurred_at)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(undo_token)
}

fn resolved_conflict_id(detail_json: &str) -> CoreResult<Option<String>> {
    let value: serde_json::Value =
        serde_json::from_str(detail_json).map_err(|error| CoreError::db(error.to_string()))?;
    let is_conflict_resolution =
        value.get("kind").and_then(serde_json::Value::as_str) == Some(CONFLICT_KIND);
    if !is_conflict_resolution {
        return Ok(None);
    }
    Ok(value
        .get("conflict_id")
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned))
}

fn insert_conflict_resolution_undo(
    tx: &Transaction<'_>,
    conflict_id: &str,
    resolution: &str,
    occurred_at: i64,
) -> CoreResult<String> {
    let token = format!("undo:icloud-conflict-resolution:{}", Uuid::new_v4());
    let summary = json!({
        "kind": UNDO_KIND,
        "affected_count": 1,
        "affected_file_names": [conflict_id],
        "disabled_reason": "iCloud conflict resolution undo requires manual review",
    });
    let inverse = json!({
        "kind": "mark_icloud_conflict_unresolved",
        "conflict_id": conflict_id,
        "resolution": resolution,
    });
    tx.execute(
        "INSERT INTO undo_actions (
             token, kind, summary_json, inverse_json, status, created_at, updated_at
         ) VALUES (?1, ?2, ?3, ?4, 'blocked', ?5, ?5)",
        params![
            token,
            UNDO_KIND,
            serialize_json(&summary)?,
            serialize_json(&inverse)?,
            occurred_at,
        ],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}

fn insert_conflict_resolution_change(
    tx: &Transaction<'_>,
    conflict_id: &str,
    resolution: &str,
    occurred_at: i64,
) -> CoreResult<()> {
    let detail = json!({
        "kind": CONFLICT_KIND,
        "conflict_id": conflict_id,
        "resolution": resolution,
        "status": "resolved",
        "by": "user",
    });
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (NULL, ?1, ?2, ?3)",
        params![CHANGE_LOG_ACTION, serialize_json(&detail)?, occurred_at],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn serialize_json(value: &serde_json::Value) -> CoreResult<String> {
    serde_json::to_string(value).map_err(|error| CoreError::internal(error.to_string()))
}
