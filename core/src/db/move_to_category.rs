use std::path::Path;

use rusqlite::params;
use serde_json::Value;

use crate::{CoreError, CoreResult};

use super::{open_repo_connection, undo};

pub(crate) fn move_repo_owned_file_to_category(
    repo_path: &Path,
    file_id: i64,
    final_path: &str,
    final_name: &str,
    new_category: &str,
    detail: &Value,
) -> CoreResult<()> {
    update_file_category_and_log(
        repo_path,
        file_id,
        Some((final_path, final_name)),
        new_category,
        "storage_mode IN ('copied', 'moved')",
        detail,
    )
}

pub(crate) fn move_indexed_file_to_category(
    repo_path: &Path,
    file_id: i64,
    new_category: &str,
    detail: &Value,
) -> CoreResult<()> {
    update_file_category_and_log(
        repo_path,
        file_id,
        None,
        new_category,
        "storage_mode = 'indexed'",
        detail,
    )
}

fn update_file_category_and_log(
    repo_path: &Path,
    file_id: i64,
    final_location: Option<(&str, &str)>,
    new_category: &str,
    row_clause: &str,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let before = undo::load_active_file_undo_snapshot(&tx, file_id)?;
    let occurred_at = chrono::Utc::now().timestamp();
    let update_sql = update_sql(final_location.is_some(), row_clause);
    let changed = match final_location {
        Some((final_path, final_name)) => tx.execute(
            &update_sql,
            params![file_id, final_path, final_name, new_category],
        ),
        None => tx.execute(&update_sql, params![file_id, new_category]),
    }
    .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'moved', ?2, strftime('%s', 'now'))",
        params![file_id, detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    let (final_path, final_name, index_only) = match final_location {
        Some((path, name)) => (path, name, false),
        None => (before.path.as_str(), before.current_name.as_str(), true),
    };
    undo::insert_move_undo_action(
        &tx,
        file_id,
        &before,
        undo::FileUndoTarget {
            path: final_path,
            name: final_name,
            category: new_category,
            index_only,
        },
        occurred_at,
    )?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn update_sql(include_path: bool, row_clause: &str) -> String {
    if include_path {
        return format!(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 category = ?4,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1 AND status = 'active' AND {row_clause}"
        );
    }

    format!(
        "UPDATE files
         SET category = ?2,
             updated_at = strftime('%s', 'now')
         WHERE id = ?1 AND status = 'active' AND {row_clause}"
    )
}

fn detail_json(detail: &Value) -> CoreResult<String> {
    serde_json::to_string(detail).map_err(|error| CoreError::internal(error.to_string()))
}
