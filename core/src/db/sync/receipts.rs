use std::path::Path;

use rusqlite::{params, OptionalExtension, Transaction};
use serde_json::Value;

use crate::{CoreError, CoreResult};

use super::super::open_repo_connection;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ExternalSyncReceiptRow {
    pub(crate) event_id: i64,
    pub(crate) kind: String,
    pub(crate) path: String,
    pub(crate) file_id: Option<i64>,
    pub(crate) previous_category: Option<String>,
    pub(crate) current_category: Option<String>,
}

pub(crate) fn ensure_external_sync_receipts(repo_path: &Path) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS external_sync_receipts (
               event_id INTEGER NOT NULL,
               kind TEXT NOT NULL CHECK (kind IN ('created', 'renamed', 'removed', 'modified')),
               path TEXT NOT NULL,
               file_id INTEGER,
               previous_category TEXT,
               current_category TEXT,
               applied_at INTEGER NOT NULL,
               PRIMARY KEY (event_id, kind, path)
             );
             CREATE INDEX IF NOT EXISTS idx_external_sync_receipts_applied
               ON external_sync_receipts(applied_at DESC);",
        )
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn find_external_sync_receipt(
    repo_path: &Path,
    event_id: i64,
    kind: &str,
    path: &str,
) -> CoreResult<Option<ExternalSyncReceiptRow>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT event_id, kind, path, file_id, previous_category, current_category
             FROM external_sync_receipts
             WHERE event_id = ?1 AND kind = ?2 AND path = ?3",
            params![event_id, kind, path],
            |row| {
                Ok(ExternalSyncReceiptRow {
                    event_id: row.get(0)?,
                    kind: row.get(1)?,
                    path: row.get(2)?,
                    file_id: row.get(3)?,
                    previous_category: row.get(4)?,
                    current_category: row.get(5)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn latest_external_rename_source_category(
    repo_path: &Path,
    file_id: i64,
    event_id: i64,
    target_path: &str,
) -> CoreResult<Option<String>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT detail_json
             FROM change_log
             WHERE file_id = ?1 AND action = 'renamed'
             ORDER BY id DESC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let details = statement
        .query_map(params![file_id], |row| row.get::<_, String>(0))
        .map_err(|error| CoreError::db(error.to_string()))?;

    for detail in details {
        let detail = detail.map_err(|error| CoreError::db(error.to_string()))?;
        let value: Value =
            serde_json::from_str(&detail).map_err(|error| CoreError::db(error.to_string()))?;
        if value.get("event_id").and_then(Value::as_i64) != Some(event_id)
            || value.get("to_path").and_then(Value::as_str) != Some(target_path)
        {
            continue;
        }
        return Ok(value
            .get("from_category")
            .and_then(Value::as_str)
            .map(str::to_owned));
    }
    latest_legacy_external_rename_source_category(&connection, file_id, target_path)
}

pub(crate) fn get_fs_event_cursor(repo_path: &Path) -> CoreResult<Option<i64>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT last_event_id FROM fs_event_cursor WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn set_fs_event_cursor(repo_path: &Path, last_event_id: i64) -> CoreResult<()> {
    ensure_external_sync_receipts(repo_path)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    set_cursor(&tx, last_event_id)?;
    tx.execute(
        "DELETE FROM external_sync_receipts WHERE event_id <= ?1",
        params![last_event_id],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn count_existing_receipts(
    tx: &Transaction<'_>,
    receipts: &[ExternalSyncReceiptRow],
) -> CoreResult<usize> {
    let mut count = 0;
    for receipt in receipts {
        let exists = tx
            .query_row(
                "SELECT EXISTS(
                   SELECT 1 FROM external_sync_receipts
                   WHERE event_id = ?1 AND kind = ?2 AND path = ?3
                 )",
                params![receipt.event_id, receipt.kind, receipt.path],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        if exists {
            count += 1;
        }
    }
    Ok(count)
}

pub(super) fn insert_external_sync_receipt(
    tx: &Transaction<'_>,
    receipt: ExternalSyncReceiptRow,
) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO external_sync_receipts (
           event_id, kind, path, file_id, previous_category, current_category, applied_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, strftime('%s', 'now'))",
        params![
            receipt.event_id,
            receipt.kind,
            receipt.path,
            receipt.file_id,
            receipt.previous_category,
            receipt.current_category,
        ],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn latest_legacy_external_rename_source_category(
    connection: &rusqlite::Connection,
    file_id: i64,
    target_path: &str,
) -> CoreResult<Option<String>> {
    let latest = connection
        .query_row(
            "SELECT action, detail_json
             FROM change_log
             WHERE file_id = ?1
             ORDER BY id DESC
             LIMIT 1",
            params![file_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let Some((action, detail)) = latest else {
        return Ok(None);
    };
    if action != "renamed" {
        return Ok(None);
    }
    let value: Value =
        serde_json::from_str(&detail).map_err(|error| CoreError::db(error.to_string()))?;
    if value.get("event_id").is_some()
        || value.get("to_path").and_then(Value::as_str) != Some(target_path)
    {
        return Ok(None);
    }
    Ok(value
        .get("from_category")
        .and_then(Value::as_str)
        .map(str::to_owned))
}

fn set_cursor(tx: &Transaction<'_>, last_event_id: i64) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO fs_event_cursor (id, last_event_id, updated_at)
         VALUES (1, ?1, strftime('%s', 'now'))
         ON CONFLICT(id) DO UPDATE SET
             last_event_id = MAX(fs_event_cursor.last_event_id, excluded.last_event_id),
             updated_at = excluded.updated_at",
        params![last_event_id],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}
