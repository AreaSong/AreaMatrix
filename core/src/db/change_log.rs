use std::path::PathBuf;

use rusqlite::{params, Rows};
use serde_json::Value;

use crate::{ChangeFilter, ChangeLogEntry, CoreError, CoreResult};

use super::open_repo_connection;

pub(crate) fn list_changes(
    repo_path: String,
    filter: ChangeFilter,
) -> CoreResult<Vec<ChangeLogEntry>> {
    validate_change_filter(&filter)?;
    let repo = PathBuf::from(repo_path);
    let connection = open_repo_connection(&repo)?;
    let limit = normalized_limit(filter.limit);
    let offset = filter.offset.max(0);
    let mut statement = connection
        .prepare(
            "SELECT cl.id, cl.file_id, COALESCE(f.current_name, ''),
                    COALESCE(f.category, ''), cl.action, cl.detail_json, cl.occurred_at
             FROM change_log cl
             LEFT JOIN files f ON f.id = cl.file_id
             WHERE (?1 IS NULL OR cl.file_id = ?1)
               AND (?2 IS NULL OR f.category = ?2)
               AND (?3 IS NULL OR cl.action = ?3)
               AND (?4 IS NULL OR cl.occurred_at >= ?4)
               AND (?5 IS NULL OR cl.occurred_at < ?5)
             ORDER BY cl.occurred_at DESC, cl.id DESC
             LIMIT ?6 OFFSET ?7",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut rows = statement
        .query(params![
            filter.file_id,
            filter.category,
            filter.action,
            filter.since,
            filter.until,
            limit,
            offset,
        ])
        .map_err(|error| CoreError::db(error.to_string()))?;
    collect_change_entries(&mut rows)
}

fn validate_change_filter(filter: &ChangeFilter) -> CoreResult<()> {
    if filter.file_id.is_some_and(|file_id| file_id <= 0) {
        return Err(CoreError::db("change log file id is invalid"));
    }
    if let (Some(since), Some(until)) = (filter.since, filter.until) {
        if since > until {
            return Err(CoreError::db("change log time range is invalid"));
        }
    }
    Ok(())
}

fn collect_change_entries(rows: &mut Rows<'_>) -> CoreResult<Vec<ChangeLogEntry>> {
    let mut changes = Vec::new();
    while let Some(row) = rows
        .next()
        .map_err(|error| CoreError::db(error.to_string()))?
    {
        let detail_json: String = row
            .get(5)
            .map_err(|error| CoreError::db(error.to_string()))?;
        ensure_detail_json_object(&detail_json)?;
        changes.push(ChangeLogEntry {
            id: row
                .get(0)
                .map_err(|error| CoreError::db(error.to_string()))?,
            file_id: row
                .get(1)
                .map_err(|error| CoreError::db(error.to_string()))?,
            filename: row
                .get(2)
                .map_err(|error| CoreError::db(error.to_string()))?,
            category: row
                .get(3)
                .map_err(|error| CoreError::db(error.to_string()))?,
            action: row
                .get(4)
                .map_err(|error| CoreError::db(error.to_string()))?,
            detail_json,
            occurred_at: row
                .get(6)
                .map_err(|error| CoreError::db(error.to_string()))?,
        });
    }
    Ok(changes)
}

fn ensure_detail_json_object(detail_json: &str) -> CoreResult<()> {
    match serde_json::from_str::<Value>(detail_json) {
        Ok(Value::Object(_)) => Ok(()),
        Ok(_) | Err(_) => Err(CoreError::db("database error")),
    }
}

fn normalized_limit(limit: i64) -> i64 {
    if limit <= 0 {
        100
    } else {
        limit.min(1000)
    }
}
