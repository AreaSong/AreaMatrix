use std::path::Path;

use rusqlite::{params, OptionalExtension};
use serde_json::json;

use crate::{CoreError, CoreResult, FileOrigin, StorageMode};

use super::{
    open_repo_connection, open_repo_read_connection, origin_from_db, storage_mode_from_db,
    FileIndexInput, ScanFileChange, ScanFileSnapshot,
};

pub(crate) fn active_scan_file_snapshots(repo_path: &Path) -> CoreResult<Vec<ScanFileSnapshot>> {
    let connection = open_repo_connection(repo_path)?;
    active_scan_file_snapshots_on_connection(&connection)
}

pub(crate) fn active_scan_file_snapshots_read_only(
    repo_path: &Path,
) -> CoreResult<Vec<ScanFileSnapshot>> {
    let connection = open_repo_read_connection(repo_path)?;
    active_scan_file_snapshots_on_connection(&connection)
}

fn active_scan_file_snapshots_on_connection(
    connection: &rusqlite::Connection,
) -> CoreResult<Vec<ScanFileSnapshot>> {
    let mut statement = connection
        .prepare(
            "SELECT path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path
             FROM files
             WHERE status = 'active'",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut rows = statement
        .query([])
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut snapshots = Vec::new();
    while let Some(row) = rows
        .next()
        .map_err(|error| CoreError::db(error.to_string()))?
    {
        let storage_mode: String = row
            .get(6)
            .map_err(|error| CoreError::db(error.to_string()))?;
        let origin: String = row
            .get(7)
            .map_err(|error| CoreError::db(error.to_string()))?;
        snapshots.push(ScanFileSnapshot {
            path: row
                .get(0)
                .map_err(|error| CoreError::db(error.to_string()))?,
            original_name: row
                .get(1)
                .map_err(|error| CoreError::db(error.to_string()))?,
            current_name: row
                .get(2)
                .map_err(|error| CoreError::db(error.to_string()))?,
            category: row
                .get(3)
                .map_err(|error| CoreError::db(error.to_string()))?,
            size_bytes: row
                .get(4)
                .map_err(|error| CoreError::db(error.to_string()))?,
            hash_sha256: row
                .get(5)
                .map_err(|error| CoreError::db(error.to_string()))?,
            storage_mode: storage_mode_from_db(&storage_mode)?,
            origin: origin_from_db(&origin)?,
            source_path: row
                .get(8)
                .map_err(|error| CoreError::db(error.to_string()))?,
        });
    }
    Ok(snapshots)
}

pub(crate) fn upsert_adopted_file(
    repo_path: &Path,
    input: &FileIndexInput,
) -> CoreResult<ScanFileChange> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let existing = existing_file_for_path(&tx, &input.path)?;
    let change = match existing {
        Some(existing) if existing.matches(input, FileOrigin::Adopted) => ScanFileChange::Skipped,
        Some(existing) => {
            tx.execute(
                "UPDATE files
                 SET original_name = ?2,
                     current_name = ?3,
                     category = ?4,
                     size_bytes = ?5,
                     hash_sha256 = ?6,
                     storage_mode = 'indexed',
                     origin = 'adopted',
                     source_path = NULL,
                     updated_at = strftime('%s', 'now'),
                     status = 'active'
                 WHERE id = ?1",
                params![
                    existing.id,
                    input.original_name,
                    input.current_name,
                    input.category,
                    input.size_bytes,
                    input.hash_sha256,
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            ScanFileChange::Updated
        }
        None => {
            tx.execute(
                "INSERT INTO files (
                    path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path,
                    imported_at, updated_at, status
                 ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, 'indexed', 'adopted', NULL,
                    strftime('%s', 'now'), strftime('%s', 'now'), 'active'
                 )",
                params![
                    input.path,
                    input.original_name,
                    input.current_name,
                    input.category,
                    input.size_bytes,
                    input.hash_sha256,
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            let file_id = tx.last_insert_rowid();
            tx.execute(
                "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
                 VALUES (?1, 'adopted', ?2, strftime('%s', 'now'))",
                params![file_id, r#"{"mode":"indexed","source":"adopt_existing"}"#],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            ScanFileChange::Inserted
        }
    };
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(change)
}

pub(crate) fn upsert_reindexed_file(
    repo_path: &Path,
    input: &FileIndexInput,
) -> CoreResult<ScanFileChange> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let existing = existing_file_for_path(&tx, &input.path)?;
    let change = match existing {
        Some(existing) if existing.matches(input, FileOrigin::External) => ScanFileChange::Skipped,
        Some(existing) => {
            tx.execute(
                "UPDATE files
                 SET original_name = ?2,
                     current_name = ?3,
                     category = ?4,
                     size_bytes = ?5,
                     hash_sha256 = ?6,
                     storage_mode = 'indexed',
                     origin = 'external',
                     source_path = NULL,
                     deleted_at = NULL,
                     updated_at = strftime('%s', 'now'),
                     status = 'active'
                 WHERE id = ?1",
                params![
                    existing.id,
                    input.original_name,
                    input.current_name,
                    input.category,
                    input.size_bytes,
                    input.hash_sha256,
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            insert_reindex_change(&tx, existing.id, input)?;
            ScanFileChange::Updated
        }
        None => {
            tx.execute(
                "INSERT INTO files (
                    path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path,
                    imported_at, updated_at, status
                 ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, 'indexed', 'external', NULL,
                    strftime('%s', 'now'), strftime('%s', 'now'), 'active'
                 )",
                params![
                    input.path,
                    input.original_name,
                    input.current_name,
                    input.category,
                    input.size_bytes,
                    input.hash_sha256,
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            let file_id = tx.last_insert_rowid();
            insert_reindex_change(&tx, file_id, input)?;
            ScanFileChange::Inserted
        }
    };
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(change)
}

#[derive(Debug)]
struct ExistingFile {
    id: i64,
    original_name: String,
    current_name: String,
    category: String,
    size_bytes: i64,
    hash_sha256: String,
    storage_mode: StorageMode,
    origin: FileOrigin,
    status: String,
}

impl ExistingFile {
    fn matches(&self, input: &FileIndexInput, origin: FileOrigin) -> bool {
        self.original_name == input.original_name
            && self.current_name == input.current_name
            && self.category == input.category
            && self.size_bytes == input.size_bytes
            && self.hash_sha256 == input.hash_sha256
            && self.storage_mode == StorageMode::Indexed
            && self.origin == origin
            && self.status == "active"
    }
}

fn insert_reindex_change(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    input: &FileIndexInput,
) -> CoreResult<()> {
    let detail_json = json!({
        "kind": "reindex",
        "path": input.path,
        "category": input.category,
        "hash_after": input.hash_sha256,
        "size_bytes": input.size_bytes,
    })
    .to_string();
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, strftime('%s', 'now'))",
        params![file_id, detail_json],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn existing_file_for_path(
    connection: &rusqlite::Transaction<'_>,
    path: &str,
) -> CoreResult<Option<ExistingFile>> {
    connection
        .query_row(
            "SELECT id, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, status
             FROM files
             WHERE path = ?1",
            params![path],
            |row| {
                let storage_mode: String = row.get(6)?;
                let origin: String = row.get(7)?;
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, String>(5)?,
                    storage_mode,
                    origin,
                    row.get::<_, String>(8)?,
                ))
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .map(|row| {
            Ok(ExistingFile {
                id: row.0,
                original_name: row.1,
                current_name: row.2,
                category: row.3,
                size_bytes: row.4,
                hash_sha256: row.5,
                storage_mode: storage_mode_from_db(&row.6)?,
                origin: origin_from_db(&row.7)?,
                status: row.8,
            })
        })
        .transpose()
}
