use std::path::Path;

use rusqlite::params;
use uuid::Uuid;

use crate::{CoreError, CoreResult};

use super::{super::open_repo_connection, json::serialize_json};

pub(crate) fn preflight_import_conflict_undo_action(repo_path: &Path) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    insert_import_conflict_undo_action_in_tx(&tx, &["preflight".to_owned()])?;
    tx.rollback()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn insert_import_conflict_undo_action(
    repo_path: &Path,
    affected_names: &[String],
) -> CoreResult<String> {
    let connection = open_repo_connection(repo_path)?;
    insert_import_conflict_undo_action_in_tx(&connection, affected_names)
}

fn insert_import_conflict_undo_action_in_tx(
    connection: &rusqlite::Connection,
    affected_names: &[String],
) -> CoreResult<String> {
    let token = format!("undo:import-conflict:{}", Uuid::new_v4());
    let occurred_at = chrono::Utc::now().timestamp();
    let summary = serde_json::json!({
        "kind": "import_conflict_batch",
        "affected_count": affected_names.len(),
        "affected_file_names": affected_names,
        "disabled_reason": "Import conflict batch undo requires manual review",
    });
    let inverse = serde_json::json!({
        "kind": "manual_import_conflict_batch_review",
        "affected_file_names": affected_names,
    });
    connection
        .execute(
            "INSERT INTO undo_actions (
                 token, kind, summary_json, inverse_json, status, created_at, updated_at
             ) VALUES (?1, 'import_conflict_batch', ?2, ?3, 'blocked', ?4, ?4)",
            params![
                token,
                serialize_json(&summary)?,
                serialize_json(&inverse)?,
                occurred_at,
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}
