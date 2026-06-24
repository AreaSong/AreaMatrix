use rusqlite::params;
use serde_json::Value;

use crate::{CoreError, CoreResult};

const REDO_CLEARED_REASON: &str = "Redo action was cleared by a new write";

pub(crate) fn clear_redo_stack_in_tx(
    connection: &rusqlite::Connection,
    updated_at: i64,
) -> CoreResult<()> {
    let mut statement = connection
        .prepare("SELECT token, summary_json FROM undo_actions WHERE status = 'executed'")
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
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
