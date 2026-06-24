use std::path::{Path, PathBuf};

use rusqlite::{params, Rows};

use crate::{
    CoreError, CoreResult, FileAvailabilityStatus, FileEntry, FileFilter, FileOrigin, StorageMode,
};

use super::{open_repo_connection, origin_from_db, storage_mode_from_db};

pub(crate) fn list_files(repo_path: String, filter: FileFilter) -> CoreResult<Vec<FileEntry>> {
    validate_file_filter(&filter)?;
    let repo = PathBuf::from(repo_path);
    let connection = open_repo_connection(&repo)?;
    let limit = filter.limit.clamp(0, 1000);
    let offset = filter.offset.max(0);
    let status_clause = list_files_status_clause(filter.include_deleted);
    let sql = format!(
        "SELECT id, path, original_name, current_name, category, size_bytes, \
         hash_sha256, storage_mode, origin, source_path, imported_at, updated_at \
         FROM files \
         WHERE {status_clause} \
           AND (?3 IS NULL OR category = ?3) \
           AND (?4 IS NULL OR imported_at >= ?4) \
           AND (?5 IS NULL OR imported_at < ?5) \
         ORDER BY imported_at DESC LIMIT ?1 OFFSET ?2"
    );
    let mut statement = connection
        .prepare(&sql)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut rows = statement
        .query(params![
            limit,
            offset,
            filter.category,
            filter.imported_after,
            filter.imported_before,
        ])
        .map_err(|error| CoreError::db(error.to_string()))?;
    collect_file_entries(&repo, &mut rows)
}

fn list_files_status_clause(include_deleted: Option<bool>) -> &'static str {
    if include_deleted.unwrap_or(false) {
        "status != 'staging'"
    } else {
        "status = 'active'"
    }
}

fn collect_file_entries(repo: &Path, rows: &mut Rows<'_>) -> CoreResult<Vec<FileEntry>> {
    let mut files = Vec::new();
    while let Some(row) = rows
        .next()
        .map_err(|error| CoreError::db(error.to_string()))?
    {
        let storage_mode_value: String = row
            .get(7)
            .map_err(|error| CoreError::db(error.to_string()))?;
        let origin_value: String = row
            .get(8)
            .map_err(|error| CoreError::db(error.to_string()))?;
        let mut entry = FileEntry {
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
            storage_mode: metadata_storage_mode_from_db(&storage_mode_value)?,
            origin: metadata_origin_from_db(&origin_value)?,
            source_path: row
                .get(9)
                .map_err(|error| CoreError::db(error.to_string()))?,
            imported_at: row
                .get(10)
                .map_err(|error| CoreError::db(error.to_string()))?,
            updated_at: row
                .get(11)
                .map_err(|error| CoreError::db(error.to_string()))?,
            availability_status: FileAvailabilityStatus::Available,
        };
        apply_availability_status(repo, &mut entry);
        files.push(entry);
    }
    Ok(files)
}

pub(crate) fn with_availability_status(repo: &Path, mut entry: FileEntry) -> FileEntry {
    apply_availability_status(repo, &mut entry);
    entry
}

fn apply_availability_status(repo: &Path, entry: &mut FileEntry) {
    entry.availability_status = if entry_backing_file_is_missing(repo, entry) {
        FileAvailabilityStatus::Missing
    } else {
        FileAvailabilityStatus::Available
    };
}

fn entry_backing_file_is_missing(repo: &Path, entry: &FileEntry) -> bool {
    let path = entry_backing_path(repo, entry);
    matches!(path.try_exists(), Ok(false))
}

fn entry_backing_path(repo: &Path, entry: &FileEntry) -> PathBuf {
    if matches!(entry.storage_mode, StorageMode::Copied | StorageMode::Moved) {
        return repo.join(&entry.path);
    }
    if let Some(source_path) = &entry.source_path {
        return PathBuf::from(source_path);
    }
    repo.join(&entry.path)
}

fn validate_file_filter(filter: &FileFilter) -> CoreResult<()> {
    if let (Some(after), Some(before)) = (filter.imported_after, filter.imported_before) {
        if after > before {
            return Err(CoreError::db("file list imported time range is invalid"));
        }
    }
    Ok(())
}

fn metadata_storage_mode_from_db(value: &str) -> CoreResult<StorageMode> {
    storage_mode_from_db(value).map_err(|_| CoreError::db("database error"))
}

fn metadata_origin_from_db(value: &str) -> CoreResult<FileOrigin> {
    origin_from_db(value).map_err(|_| CoreError::db("database error"))
}
