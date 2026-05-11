use std::path::{Component, Path, PathBuf};

use rusqlite::{params, Connection, OpenFlags, Row};

use crate::{CoreError, CoreResult, FileEntry, FileOrigin, SearchFilter, SearchScope, StorageMode};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";

#[derive(Clone)]
pub(super) struct SearchRow {
    pub(super) entry: FileEntry,
    pub(super) notes: Vec<String>,
    pub(super) changes: Vec<String>,
    pub(super) tags: Vec<String>,
}

pub(super) fn validated_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component)
        || repo.components().any(is_icloud_placeholder_component)
    {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(repo)
}

pub(super) fn validate_current_path(filter: &SearchFilter) -> CoreResult<()> {
    let Some(current_path) = filter.current_path.as_deref() else {
        return if filter.scope == SearchScope::CurrentNode {
            Err(CoreError::invalid_path("invalid path"))
        } else {
            Ok(())
        };
    };

    if current_path.trim().is_empty() || current_path.starts_with('~') {
        return Err(CoreError::invalid_path("invalid path"));
    }
    let path = Path::new(current_path);
    if path.is_absolute() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    for component in path.components() {
        match component {
            Component::Normal(part) if part != AREA_MATRIX_DIR => {}
            _ => return Err(CoreError::invalid_path("invalid path")),
        }
    }
    Ok(())
}

pub(super) fn query_rows(repo: &Path, filter: &SearchFilter) -> CoreResult<Vec<SearchRow>> {
    let connection = open_connection(repo)?;
    let mut statement = connection
        .prepare(search_sql())
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut rows = statement
        .query(params![
            filter.include_deleted.unwrap_or(false),
            filter.category.as_deref(),
            filter.file_kind.as_deref(),
            filter.imported_after,
            filter.imported_before,
            filter.modified_after,
            filter.modified_before,
            storage_mode_filter(filter.storage_mode.as_ref()),
            current_scope_path(filter),
        ])
        .map_err(|error| CoreError::db(error.to_string()))?;

    let mut results = Vec::new();
    while let Some(row) = rows
        .next()
        .map_err(|error| CoreError::db(error.to_string()))?
    {
        results.push(row_to_search_row(row)?);
    }
    Ok(results)
}

fn search_sql() -> &'static str {
    "SELECT f.id, f.path, f.original_name, f.current_name, f.category,
            f.size_bytes, f.hash_sha256, f.storage_mode, f.origin,
            f.source_path, f.imported_at, f.updated_at,
            COALESCE(n.content_md, ''),
            COALESCE(GROUP_CONCAT(DISTINCT cl.action || ' ' || cl.detail_json), ''),
            COALESCE(GROUP_CONCAT(DISTINCT t.tag), '')
       FROM files f
       LEFT JOIN notes n ON n.file_id = f.id
       LEFT JOIN change_log cl ON cl.file_id = f.id
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

fn row_to_search_row(row: &Row<'_>) -> CoreResult<SearchRow> {
    let storage_mode_value: String = row
        .get(7)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let origin_value: String = row
        .get(8)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let note: String = row
        .get(12)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let changes: String = row
        .get(13)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let tags: String = row
        .get(14)
        .map_err(|error| CoreError::db(error.to_string()))?;

    Ok(SearchRow {
        entry: file_entry_from_row(row, &storage_mode_value, &origin_value)?,
        notes: split_grouped_text(&note),
        changes: split_grouped_text(&changes),
        tags: split_grouped_text(&tags),
    })
}

fn file_entry_from_row(
    row: &Row<'_>,
    storage_mode_value: &str,
    origin_value: &str,
) -> CoreResult<FileEntry> {
    Ok(FileEntry {
        id: row
            .get(0)
            .map_err(|error| CoreError::db(error.to_string()))?,
        path: row
            .get(1)
            .map_err(|error| CoreError::db(error.to_string()))?,
        original_name: row
            .get(2)
            .map_err(|error| CoreError::db(error.to_string()))?,
        current_name: row
            .get(3)
            .map_err(|error| CoreError::db(error.to_string()))?,
        category: row
            .get(4)
            .map_err(|error| CoreError::db(error.to_string()))?,
        size_bytes: row
            .get(5)
            .map_err(|error| CoreError::db(error.to_string()))?,
        hash_sha256: row
            .get(6)
            .map_err(|error| CoreError::db(error.to_string()))?,
        storage_mode: storage_mode_from_db(storage_mode_value)?,
        origin: origin_from_db(origin_value)?,
        source_path: row
            .get(9)
            .map_err(|error| CoreError::db(error.to_string()))?,
        imported_at: row
            .get(10)
            .map_err(|error| CoreError::db(error.to_string()))?,
        updated_at: row
            .get(11)
            .map_err(|error| CoreError::db(error.to_string()))?,
    })
}

fn open_connection(repo: &Path) -> CoreResult<Connection> {
    let db_path = repo.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE);
    if !db_path
        .try_exists()
        .map_err(|error| map_path_probe_error(error, repo))?
    {
        return Err(CoreError::db("database error"));
    }
    let connection = Connection::open_with_flags(db_path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|error| CoreError::db(error.to_string()))?;
    connection
        .execute_batch(
            "PRAGMA query_only = ON;
             PRAGMA busy_timeout = 5000;",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(connection)
}

fn current_scope_path(filter: &SearchFilter) -> Option<&str> {
    if filter.scope == SearchScope::CurrentNode {
        filter.current_path.as_deref()
    } else {
        None
    }
}

fn storage_mode_filter(mode: Option<&StorageMode>) -> Option<&'static str> {
    mode.map(storage_mode_to_db)
}

fn storage_mode_to_db(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn split_grouped_text(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
        .collect()
}

fn storage_mode_from_db(value: &str) -> CoreResult<StorageMode> {
    match value {
        "moved" | "Moved" => Ok(StorageMode::Moved),
        "copied" | "Copied" => Ok(StorageMode::Copied),
        "indexed" | "Indexed" => Ok(StorageMode::Indexed),
        _ => Err(CoreError::config("configuration error")),
    }
}

fn origin_from_db(value: &str) -> CoreResult<FileOrigin> {
    match value {
        "imported" | "Imported" => Ok(FileOrigin::Imported),
        "adopted" | "Adopted" => Ok(FileOrigin::Adopted),
        "external" | "External" => Ok(FileOrigin::External),
        _ => Err(CoreError::db("database error")),
    }
}

fn map_path_probe_error(error: std::io::Error, repo: &Path) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::db("database error"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path(repo.to_string_lossy()),
        _ => CoreError::db(error.to_string()),
    }
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}

fn is_icloud_placeholder_component(component: Component<'_>) -> bool {
    component
        .as_os_str()
        .to_string_lossy()
        .to_ascii_lowercase()
        .ends_with(".icloud")
}
