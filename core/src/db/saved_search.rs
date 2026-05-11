use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension, Row};

use crate::{
    CoreError, CoreResult, CreateSavedSearchRequest, SavedSearch, SavedSearchQuery,
    UpdateSavedSearchRequest,
};

use super::open_repo_connection;

const SAVED_SEARCH_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS saved_searches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  query_json TEXT NOT NULL,
  icon TEXT,
  color TEXT,
  pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_saved_searches_sidebar
  ON saved_searches(pinned DESC, updated_at DESC, name COLLATE NOCASE ASC);
"#;

pub(crate) fn create_saved_search_row(
    repo_path: &Path,
    request: &CreateSavedSearchRequest,
) -> CoreResult<SavedSearch> {
    let mut connection = open_saved_search_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let query_json =
        serde_json::to_string(&request.query).map_err(|error| CoreError::db(error.to_string()))?;
    let now = chrono::Utc::now().timestamp();

    tx.execute(
        "INSERT INTO saved_searches (
             name, query_json, icon, color, pinned, created_at, updated_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
        params![
            request.name.trim(),
            query_json,
            request.icon.as_deref(),
            request.color.as_deref(),
            bool_to_db(request.pinned),
            now,
        ],
    )
    .map_err(map_create_saved_search_write_error)?;

    let id = tx.last_insert_rowid();
    let saved = select_saved_search_by_id(&tx, id)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(saved)
}

pub(crate) fn update_saved_search_row(
    repo_path: &Path,
    request: &UpdateSavedSearchRequest,
) -> CoreResult<SavedSearch> {
    let mut connection = open_saved_search_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let query_json =
        serde_json::to_string(&request.query).map_err(|error| CoreError::db(error.to_string()))?;
    let now = chrono::Utc::now().timestamp();

    let changed = tx
        .execute(
            "UPDATE saved_searches
                SET name = ?1,
                    query_json = ?2,
                    icon = ?3,
                    color = ?4,
                    pinned = ?5,
                    updated_at = ?6
              WHERE id = ?7",
            params![
                request.name.trim(),
                query_json,
                request.icon.as_deref(),
                request.color.as_deref(),
                bool_to_db(request.pinned),
                now,
                request.id,
            ],
        )
        .map_err(map_update_saved_search_write_error)?;
    if changed == 0 {
        return Err(CoreError::db("saved search not found"));
    }

    let saved = select_saved_search_by_id(&tx, request.id)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(saved)
}

pub(crate) fn delete_saved_search_row(repo_path: &Path, saved_search_id: i64) -> CoreResult<()> {
    let connection = open_saved_search_connection(repo_path)?;
    let changed = connection
        .execute(
            "DELETE FROM saved_searches WHERE id = ?1",
            params![saved_search_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 0 {
        return Err(CoreError::db("saved search not found"));
    }
    Ok(())
}

pub(crate) fn list_saved_search_rows(repo_path: &Path) -> CoreResult<Vec<SavedSearch>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT id, name, query_json, icon, color, pinned, created_at, updated_at
               FROM saved_searches
              ORDER BY pinned DESC,
                       CASE WHEN pinned = 1 THEN updated_at END DESC,
                       CASE WHEN pinned = 0 THEN lower(name) END ASC,
                       id ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], saved_search_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn select_saved_search_by_id(tx: &rusqlite::Transaction<'_>, id: i64) -> CoreResult<SavedSearch> {
    tx.query_row(
        "SELECT id, name, query_json, icon, color, pinned, created_at, updated_at
           FROM saved_searches
          WHERE id = ?1",
        params![id],
        saved_search_from_row,
    )
    .optional()
    .map_err(|error| CoreError::db(error.to_string()))?
    .ok_or_else(|| CoreError::db("saved search not found"))
}

fn open_saved_search_connection(repo_path: &Path) -> CoreResult<Connection> {
    let connection = open_repo_connection(repo_path).map_err(|error| match error {
        CoreError::Db { .. } => error,
        other => CoreError::db(other.to_string()),
    })?;
    connection
        .execute_batch(SAVED_SEARCH_SCHEMA)
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(connection)
}

fn saved_search_from_row(row: &Row<'_>) -> rusqlite::Result<SavedSearch> {
    let query_json: String = row.get(2)?;
    Ok(SavedSearch {
        id: row.get(0)?,
        name: row.get(1)?,
        query: saved_search_query_from_json(query_json)?,
        icon: row.get(3)?,
        color: row.get(4)?,
        pinned: db_bool(row.get(5)?),
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

fn saved_search_query_from_json(value: String) -> rusqlite::Result<SavedSearchQuery> {
    serde_json::from_str(&value).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(2, rusqlite::types::Type::Text, Box::new(error))
    })
}

fn map_create_saved_search_write_error(error: rusqlite::Error) -> CoreError {
    match &error {
        rusqlite::Error::SqliteFailure(_, Some(message))
            if message.to_ascii_lowercase().contains("unique") =>
        {
            CoreError::config("saved search name must be unique")
        }
        _ => CoreError::db(error.to_string()),
    }
}

fn map_update_saved_search_write_error(error: rusqlite::Error) -> CoreError {
    match &error {
        rusqlite::Error::SqliteFailure(_, Some(message))
            if message.to_ascii_lowercase().contains("unique") =>
        {
            CoreError::db("saved search name already exists")
        }
        _ => CoreError::db(error.to_string()),
    }
}

fn bool_to_db(value: bool) -> i64 {
    i64::from(value)
}

fn db_bool(value: i64) -> bool {
    value != 0
}
