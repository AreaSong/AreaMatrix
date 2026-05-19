use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension, Row};
use serde::Deserialize;

use crate::{CoreError, CoreResult};

use super::open_repo_connection;

/// Minimal active-file metadata needed by C2-11 file candidates.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct CommandFileCandidateRow {
    pub(crate) id: i64,
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
    pub(crate) updated_at: i64,
}

/// Read-only recent-command metadata used by C2-11.
#[derive(Clone, Debug, Eq, PartialEq, Deserialize)]
pub(crate) struct RecentCommandRow {
    pub(crate) target_id: String,
    pub(crate) used_at: i64,
    pub(crate) use_count: i64,
}

pub(crate) fn count_active_command_selection_files(
    repo_path: &Path,
    file_ids: &[i64],
) -> CoreResult<i64> {
    if file_ids.is_empty() {
        return Ok(0);
    }

    let connection = open_command_index_connection(repo_path)?;
    let placeholders = placeholders(file_ids.len());
    let sql = format!(
        "SELECT COUNT(*)
           FROM files
          WHERE status = 'active'
            AND id IN ({placeholders})"
    );
    connection
        .query_row(&sql, rusqlite::params_from_iter(file_ids.iter()), |row| {
            row.get(0)
        })
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn list_command_file_candidate_rows(
    repo_path: &Path,
    query: Option<&str>,
    current_path: Option<&str>,
    limit: i64,
) -> CoreResult<Vec<CommandFileCandidateRow>> {
    let connection = open_command_index_connection(repo_path)?;
    let like_query = query.map(like_pattern);
    let scoped_path = current_path.map(scoped_path_pattern);
    let limit = limit.clamp(0, 50);
    let mut statement = connection
        .prepare(
            r"SELECT id, path, current_name, category, updated_at
               FROM files
              WHERE status = 'active'
                AND (?1 IS NULL
                     OR lower(current_name) LIKE ?1 ESCAPE '\'
                     OR lower(path) LIKE ?1 ESCAPE '\'
                     OR lower(category) LIKE ?1 ESCAPE '\')
                AND (?2 IS NULL OR path = ?3 OR path LIKE ?2 ESCAPE '\')
              ORDER BY updated_at DESC, imported_at DESC, id ASC
              LIMIT ?4",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(
            params![
                like_query.as_deref(),
                scoped_path.as_deref(),
                current_path,
                limit,
            ],
            command_file_candidate_from_row,
        )
        .map_err(|error| CoreError::db(error.to_string()))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn list_recent_command_rows(
    repo_path: &Path,
    limit: i64,
) -> CoreResult<Vec<RecentCommandRow>> {
    let connection = open_command_index_connection(repo_path)?;
    let limit = usize::try_from(limit.clamp(0, 20))
        .map_err(|_| CoreError::db("command index recent limit is invalid"))?;
    let Some(json) = connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'recent_commands'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
    else {
        return Ok(Vec::new());
    };

    let mut rows: Vec<RecentCommandRow> =
        serde_json::from_str(&json).map_err(|error| CoreError::db(error.to_string()))?;
    rows.sort_by(|left, right| {
        right
            .used_at
            .cmp(&left.used_at)
            .then_with(|| right.use_count.cmp(&left.use_count))
            .then_with(|| left.target_id.cmp(&right.target_id))
    });
    rows.truncate(limit);
    Ok(rows)
}

fn open_command_index_connection(repo_path: &Path) -> CoreResult<Connection> {
    open_repo_connection(repo_path).map_err(|error| match error {
        CoreError::Db { .. } => error,
        other => CoreError::db(other.to_string()),
    })
}

fn command_file_candidate_from_row(row: &Row<'_>) -> rusqlite::Result<CommandFileCandidateRow> {
    Ok(CommandFileCandidateRow {
        id: row.get(0)?,
        path: row.get(1)?,
        current_name: row.get(2)?,
        category: row.get(3)?,
        updated_at: row.get(4)?,
    })
}

fn placeholders(count: usize) -> String {
    std::iter::repeat("?")
        .take(count)
        .collect::<Vec<_>>()
        .join(",")
}

fn like_pattern(query: &str) -> String {
    let lowered = query.to_lowercase();
    let escaped = escape_like_pattern(&lowered);
    format!("%{escaped}%")
}

fn scoped_path_pattern(path: &str) -> String {
    let escaped = escape_like_pattern(path.trim_end_matches('/'));
    format!("{escaped}/%")
}

fn escape_like_pattern(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}
