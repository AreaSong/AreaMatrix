use std::path::Path;

use rusqlite::{params, OptionalExtension};

use crate::{CoreError, CoreResult};

use super::{
    super::{file_entry_from_row, open_repo_connection},
    schema::ensure_import_conflict_schema,
    status,
    types::ImportConflictRow,
};

pub(crate) fn list_import_conflicts_for_session(
    repo_path: &Path,
    import_session_id: &str,
) -> CoreResult<Vec<ImportConflictRow>> {
    ensure_import_conflict_schema(repo_path)?;
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT conflict_id, import_session_id, conflict_type, staging_file_id,
                    existing_file_id, incoming_path, target_path, status, failure_reason
               FROM import_conflicts
              WHERE import_session_id = ?1
              ORDER BY created_at ASC, conflict_id ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![import_session_id], status::import_conflict_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn get_import_session_status(
    repo_path: &Path,
    import_session_id: &str,
) -> CoreResult<String> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT status FROM import_sessions WHERE import_session_id = ?1",
            params![import_session_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found("missing import session"))
}

pub(crate) fn get_staging_file_snapshot(
    repo_path: &Path,
    file_id: i64,
) -> CoreResult<Option<crate::FileEntry>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT id, path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path, imported_at, updated_at
               FROM files
              WHERE id = ?1 AND status = 'staging'",
            params![file_id],
            file_entry_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}
