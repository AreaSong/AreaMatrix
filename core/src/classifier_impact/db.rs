use std::path::Path;

use rusqlite::{params, Connection, OpenFlags};

use crate::{CoreError, CoreResult, FileAvailabilityStatus, FileEntry, FileOrigin, StorageMode};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";

pub(super) fn list_active_files(repo: &Path) -> CoreResult<Vec<FileEntry>> {
    let connection = Connection::open_with_flags(
        repo.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE),
        OpenFlags::SQLITE_OPEN_READ_ONLY,
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    let mut statement = connection
        .prepare(
            "SELECT id, path, original_name, current_name, category, size_bytes, \
             hash_sha256, storage_mode, origin, source_path, imported_at, updated_at \
             FROM files WHERE status = 'active' ORDER BY imported_at DESC, id ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![], file_entry_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.map(|row| row.map_err(|error| CoreError::db(error.to_string())))
        .collect()
}

fn file_entry_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<FileEntry> {
    let storage_mode: String = row.get(7)?;
    let origin: String = row.get(8)?;
    Ok(FileEntry {
        id: row.get(0)?,
        path: row.get(1)?,
        original_name: row.get(2)?,
        current_name: row.get(3)?,
        category: row.get(4)?,
        size_bytes: row.get(5)?,
        hash_sha256: row.get(6)?,
        storage_mode: storage_mode_from_db(&storage_mode)?,
        origin: origin_from_db(&origin)?,
        source_path: row.get(9)?,
        availability_status: FileAvailabilityStatus::Available,
        imported_at: row.get(10)?,
        updated_at: row.get(11)?,
    })
}

fn storage_mode_from_db(value: &str) -> rusqlite::Result<StorageMode> {
    match value {
        "moved" | "Moved" => Ok(StorageMode::Moved),
        "copied" | "Copied" => Ok(StorageMode::Copied),
        "indexed" | "Indexed" => Ok(StorageMode::Indexed),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}

fn origin_from_db(value: &str) -> rusqlite::Result<FileOrigin> {
    match value {
        "imported" | "Imported" => Ok(FileOrigin::Imported),
        "adopted" | "Adopted" => Ok(FileOrigin::Adopted),
        "external" | "External" => Ok(FileOrigin::External),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}
