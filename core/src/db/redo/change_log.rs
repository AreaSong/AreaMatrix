use rusqlite::params;
use serde_json::Value;

use crate::{CoreError, CoreResult};

pub(super) fn insert_change_log(
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
