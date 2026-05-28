use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OpenFlags, OptionalExtension, Row};

use crate::{CoreError, CoreResult, SearchFilter, SearchScope};

use super::{Candidate, SemanticFieldTerms};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";

pub(super) fn open_read_connection(repo: &Path) -> CoreResult<Connection> {
    let connection = Connection::open_with_flags(db_path(repo), OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|error| CoreError::db(error.to_string()))?;
    configure_read_connection(&connection)?;
    Ok(connection)
}

pub(super) fn ensure_schema(connection: &Connection) -> CoreResult<()> {
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS semantic_index_entries (
                file_id INTEGER PRIMARY KEY,
                search_text TEXT NOT NULL,
                terms_json TEXT NOT NULL,
                tags_json TEXT NOT NULL DEFAULT '[]',
                indexed_at INTEGER NOT NULL,
                FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
             );
             CREATE INDEX IF NOT EXISTS idx_semantic_index_entries_search
               ON semantic_index_entries(search_text);",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_tags_json_column(connection)
}

pub(super) fn ensure_schema_tx(tx: &rusqlite::Transaction<'_>) -> CoreResult<()> {
    ensure_schema(tx)
}

pub(super) fn load_source_candidates(
    tx: &rusqlite::Transaction<'_>,
    filter: &SearchFilter,
) -> CoreResult<Vec<Candidate>> {
    let mut statement = tx
        .prepare(index_source_sql())
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(filter_params(filter), candidate_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.map(|row| row.map_err(|error| CoreError::db(error.to_string())))
        .collect()
}

pub(super) fn load_indexed_candidates(
    connection: &Connection,
    filter: &SearchFilter,
) -> CoreResult<Vec<Candidate>> {
    let mut statement = connection
        .prepare(indexed_files_sql())
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(filter_params(filter), indexed_candidate_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.map(|row| row.map_err(|error| CoreError::db(error.to_string())))
        .collect()
}

pub(super) fn insert_index_entry(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    field_terms: &[SemanticFieldTerms],
    tags: &[String],
) -> CoreResult<()> {
    let search_text = field_terms
        .iter()
        .flat_map(|field| field.terms.iter().map(String::as_str))
        .collect::<Vec<_>>()
        .join(" ");
    let terms_json = serde_json::to_string(field_terms)
        .map_err(|_| CoreError::db("semantic index terms are invalid"))?;
    let tags_json = serde_json::to_string(tags)
        .map_err(|_| CoreError::db("semantic index tags are invalid"))?;
    tx.execute(
        "INSERT INTO semantic_index_entries (file_id, search_text, terms_json, tags_json, indexed_at)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![file_id, search_text, terms_json, tags_json, current_timestamp(tx)?],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn repo_config_value(connection: &Connection, key: &str) -> CoreResult<Option<String>> {
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn repo_config_value_tx(
    tx: &rusqlite::Transaction<'_>,
    key: &str,
) -> CoreResult<Option<String>> {
    tx.query_row(
        "SELECT value FROM repo_config WHERE key = ?1",
        params![key],
        |row| row.get(0),
    )
    .optional()
    .map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn current_timestamp(tx: &rusqlite::Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT CAST(strftime('%s', 'now') AS INTEGER)", [], |row| {
        row.get(0)
    })
    .map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_tags_json_column(connection: &Connection) -> CoreResult<()> {
    let has_column = connection
        .prepare("PRAGMA table_info(semantic_index_entries)")
        .map_err(|error| CoreError::db(error.to_string()))?
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|error| CoreError::db(error.to_string()))?
        .filter_map(Result::ok)
        .any(|name| name == "tags_json");
    if has_column {
        return Ok(());
    }
    connection
        .execute(
            "ALTER TABLE semantic_index_entries ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'",
            [],
        )
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn indexed_files_sql() -> &'static str {
    "SELECT f.id, f.path, f.original_name, f.current_name, f.category,
            f.size_bytes, f.hash_sha256, f.storage_mode, f.origin, f.source_path,
            f.imported_at, f.updated_at, idx.terms_json, idx.tags_json
       FROM semantic_index_entries idx
       JOIN files f ON f.id = idx.file_id
      WHERE ((?1 = 1 AND f.status != 'staging') OR (?1 = 0 AND f.status = 'active'))
        AND (?2 IS NULL OR f.category = ?2)
        AND (?3 IS NULL OR lower(f.current_name) LIKE '%.' || lower(?3)
             OR lower(f.path) LIKE '%.' || lower(?3))
        AND (?4 IS NULL OR f.imported_at >= ?4)
        AND (?5 IS NULL OR f.imported_at < ?5)
        AND (?6 IS NULL OR f.updated_at >= ?6)
        AND (?7 IS NULL OR f.updated_at < ?7)
        AND (?8 IS NULL OR f.storage_mode = ?8)
        AND (?9 IS NULL OR f.path = ?9 OR f.path LIKE ?9 || '/%')
      ORDER BY f.imported_at DESC, f.id DESC"
}

fn index_source_sql() -> &'static str {
    "SELECT f.id, f.path, f.original_name, f.current_name, f.category,
            f.size_bytes, f.hash_sha256, f.storage_mode, f.origin, f.source_path,
            f.imported_at, f.updated_at, COALESCE(n.content_md, ''),
            COALESCE(GROUP_CONCAT(DISTINCT t.tag), '')
       FROM files f
       LEFT JOIN notes n ON n.file_id = f.id
       LEFT JOIN tags t ON t.file_id = f.id
      WHERE ((?1 = 1 AND f.status != 'staging') OR (?1 = 0 AND f.status = 'active'))
        AND (?2 IS NULL OR f.category = ?2)
        AND (?3 IS NULL OR lower(f.current_name) LIKE '%.' || lower(?3)
             OR lower(f.path) LIKE '%.' || lower(?3))
        AND (?4 IS NULL OR f.imported_at >= ?4)
        AND (?5 IS NULL OR f.imported_at < ?5)
        AND (?6 IS NULL OR f.updated_at >= ?6)
        AND (?7 IS NULL OR f.updated_at < ?7)
        AND (?8 IS NULL OR f.storage_mode = ?8)
        AND (?9 IS NULL OR f.path = ?9 OR f.path LIKE ?9 || '/%')
       GROUP BY f.id
      ORDER BY f.imported_at DESC, f.id DESC"
}

fn filter_params(filter: &SearchFilter) -> [rusqlite::types::Value; 9] {
    [
        i64::from(filter.include_deleted.unwrap_or(false)).into(),
        optional_text_value(filter.category.as_deref()),
        optional_text_value(filter.file_kind.as_deref()),
        optional_i64_value(filter.imported_after),
        optional_i64_value(filter.imported_before),
        optional_i64_value(filter.modified_after),
        optional_i64_value(filter.modified_before),
        optional_text_value(storage_mode_filter(filter)),
        optional_text_value(current_scope_path(filter)),
    ]
}

fn candidate_from_row(row: &Row<'_>) -> rusqlite::Result<Candidate> {
    let tags: String = row.get(13)?;
    Ok(Candidate {
        entry: crate::db::file_entry_from_row(row)?,
        note: row.get(12)?,
        tags: split_grouped_text(&tags),
        field_terms: Vec::new(),
    })
}

fn indexed_candidate_from_row(row: &Row<'_>) -> rusqlite::Result<Candidate> {
    let terms_json: String = row.get(12)?;
    let tags_json: String = row.get(13)?;
    let field_terms =
        serde_json::from_str(&terms_json).map_err(|_| rusqlite::Error::InvalidQuery)?;
    let tags = serde_json::from_str(&tags_json).map_err(|_| rusqlite::Error::InvalidQuery)?;
    Ok(Candidate {
        entry: crate::db::file_entry_from_row(row)?,
        note: String::new(),
        tags,
        field_terms,
    })
}

fn split_grouped_text(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
        .collect()
}

fn optional_text_value(value: Option<&str>) -> rusqlite::types::Value {
    value
        .map(str::to_owned)
        .map_or(rusqlite::types::Value::Null, Into::into)
}

fn optional_i64_value(value: Option<i64>) -> rusqlite::types::Value {
    value.map_or(rusqlite::types::Value::Null, Into::into)
}

fn storage_mode_filter(filter: &SearchFilter) -> Option<&'static str> {
    filter.storage_mode.as_ref().map(|mode| match mode {
        crate::StorageMode::Moved => "moved",
        crate::StorageMode::Copied => "copied",
        crate::StorageMode::Indexed => "indexed",
    })
}

fn current_scope_path(filter: &SearchFilter) -> Option<&str> {
    if matches!(filter.scope, SearchScope::CurrentNode) {
        filter.current_path.as_deref()
    } else {
        None
    }
}

fn configure_read_connection(connection: &Connection) -> CoreResult<()> {
    connection
        .execute_batch(
            "PRAGMA query_only = ON;
             PRAGMA foreign_keys = ON;
             PRAGMA busy_timeout = 5000;",
        )
        .map_err(|error| CoreError::db(error.to_string()))
}

fn db_path(repo: &Path) -> PathBuf {
    repo.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE)
}
