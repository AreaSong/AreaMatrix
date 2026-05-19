use std::path::Path;

use rusqlite::params;

use crate::{CoreError, CoreResult, RedoActionRecord, RedoActionResult, RedoActionStatus};

use super::open_repo_connection;

mod batch_file_actions;
mod change_log;
mod file_actions;
mod file_state;
mod fs_ops;
mod records;
mod tags;

pub(super) const BATCH_ADD_TAGS_KIND: &str = "batch_add_tags";
pub(super) const RENAME_FILES_KIND: &str = "rename_files";
pub(super) const MOVE_FILES_KIND: &str = "move_files";
pub(super) const CHANGE_CATEGORY_KIND: &str = "change_category";
pub(super) const BATCH_CHANGE_CATEGORY_KIND: &str = "batch_change_category";
pub(super) const TRASH_DELETE_KIND: &str = "trash_delete";
pub(super) const REDO_CLEARED_REASON: &str = "Redo action was cleared by a new write";

pub(crate) fn list_redo_action_rows(repo_path: &Path) -> CoreResult<Vec<RedoActionRecord>> {
    let connection = open_repo_connection(repo_path)?;
    records::ensure_redo_metadata_ready(&connection)?;
    let rows = records::load_redo_actions(&connection)?;
    rows.into_iter()
        .map(|row| records::redo_record_from_row(repo_path, &connection, row))
        .collect()
}

pub(crate) fn execute_redo_action_row(
    repo_path: &Path,
    action_id: &str,
) -> CoreResult<RedoActionResult> {
    let mut connection = open_repo_connection(repo_path)?;
    records::ensure_redo_metadata_ready(&connection)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let row = records::load_executed_action(&tx, action_id)?;
    let completed_at = chrono::Utc::now().timestamp();

    let mut execution = if row.kind == BATCH_ADD_TAGS_KIND {
        tags::execute_batch_tag_redo(&tx, &row, completed_at)?
    } else if file_actions::is_file_action_kind(&row.kind) {
        file_actions::execute_file_redo(&tx, repo_path, &row, completed_at)?
    } else {
        return Err(CoreError::conflict("Unsupported redo action kind"));
    };

    restore_pending_undo_action(&tx, row.token.as_str(), completed_at)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
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
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|error| CoreError::db(error.to_string()))?;
    let actions = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))?;
    drop(statement);

    for (token, summary_json) in actions {
        let summary_json = records::redo_cleared_summary_json(&summary_json)?;
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
pub(super) struct StoredRedoAction {
    pub(super) token: String,
    pub(super) kind: String,
    pub(super) summary_json: String,
    pub(super) inverse_json: String,
    pub(super) status: String,
    pub(super) updated_at: i64,
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
