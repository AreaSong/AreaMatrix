//! Repository config-table storage for C4-15/C4-16 sync conflict metadata.

use std::path::Path;

use rusqlite::{params, OptionalExtension, Transaction};
use serde_json::Value;

use crate::{CoreError, CoreResult};

const SYNC_CONFLICT_STATE_KEY: &str = "sync_conflict_state";

pub(crate) struct ActiveSyncConflictFile {
    pub(crate) id: i64,
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
    pub(crate) updated_at: i64,
}

pub(crate) struct SyncConflictCanonicalUpdate<'a> {
    pub(crate) file_id: i64,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: &'a str,
}

pub(crate) struct SyncConflictRetainedFileRecord {
    pub(crate) path: String,
    pub(crate) original_name: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
}

pub(crate) struct SyncConflictResolutionRecord<'a> {
    pub(crate) serialized_state: &'a str,
    pub(crate) file_update: Option<SyncConflictCanonicalUpdate<'a>>,
    pub(crate) retained_files: &'a [SyncConflictRetainedFileRecord],
    pub(crate) log_file_id: Option<i64>,
    pub(crate) detail_json: &'a str,
    pub(crate) occurred_at: i64,
}

pub(crate) struct SyncConflictResolutionDbResult {
    pub(crate) affected_file_ids: Vec<i64>,
}

pub(crate) fn list_active_sync_conflict_files(
    repo_path: &Path,
) -> CoreResult<Vec<ActiveSyncConflictFile>> {
    let connection = super::open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT id, path, current_name, size_bytes, hash_sha256, updated_at
             FROM files
             WHERE status = 'active'
             ORDER BY path ASC, id ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| {
            Ok(ActiveSyncConflictFile {
                id: row.get(0)?,
                path: row.get(1)?,
                current_name: row.get(2)?,
                size_bytes: row.get(3)?,
                hash_sha256: row.get(4)?,
                updated_at: row.get(5)?,
            })
        })
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn load_sync_conflict_state(repo_path: &Path) -> CoreResult<Option<(String, i64)>> {
    super::load_repo_config_record(repo_path, SYNC_CONFLICT_STATE_KEY)
}

pub(crate) fn replace_sync_conflict_state(
    repo_path: &Path,
    serialized_state: &str,
    detected_at: i64,
) -> CoreResult<()> {
    super::ensure_config_storage_writable(repo_path)?;
    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    super::upsert_repo_config_record(&tx, SYNC_CONFLICT_STATE_KEY, serialized_state, detected_at)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn preflight_sync_conflict_resolution(repo_path: &Path) -> CoreResult<()> {
    super::ensure_config_storage_writable(repo_path)?;
    let connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let available_tables = connection
        .query_row(
            "SELECT COUNT(*)
             FROM sqlite_master
             WHERE type = 'table'
               AND name IN ('repo_config', 'files', 'change_log')",
            [],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if available_tables == 3 {
        Ok(())
    } else {
        Err(CoreError::db(
            "sync conflict resolution metadata is unavailable",
        ))
    }
}

pub(crate) fn record_sync_conflict_resolution(
    repo_path: &Path,
    record: SyncConflictResolutionRecord<'_>,
) -> CoreResult<SyncConflictResolutionDbResult> {
    super::ensure_config_storage_writable(repo_path)?;
    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    if let Some(update) = &record.file_update {
        update_canonical_file_metadata(&tx, update, record.occurred_at)?;
    }
    let mut retained_file_ids = Vec::new();
    for retained_file in record.retained_files {
        push_unique(
            &mut retained_file_ids,
            retain_visible_file_record(&tx, retained_file, record.occurred_at)?,
        );
    }
    super::upsert_repo_config_record(
        &tx,
        SYNC_CONFLICT_STATE_KEY,
        record.serialized_state,
        record.occurred_at,
    )?;
    let merged_detail = merge_detail_affected_file_ids(record.detail_json, &retained_file_ids)?;
    insert_resolution_change(
        &tx,
        record.log_file_id,
        &merged_detail.detail_json,
        record.occurred_at,
    )?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(SyncConflictResolutionDbResult {
        affected_file_ids: merged_detail.affected_file_ids,
    })
}

fn update_canonical_file_metadata(
    tx: &Transaction<'_>,
    update: &SyncConflictCanonicalUpdate<'_>,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET size_bytes = ?2,
                 hash_sha256 = ?3,
                 updated_at = ?4
             WHERE id = ?1 AND status = 'active'",
            params![
                update.file_id,
                update.size_bytes,
                update.hash_sha256,
                updated_at,
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::conflict("sync conflict file record is stale"))
    }
}

fn retain_visible_file_record(
    tx: &Transaction<'_>,
    retained_file: &SyncConflictRetainedFileRecord,
    occurred_at: i64,
) -> CoreResult<i64> {
    if let Some(existing) = active_file_at_path(tx, &retained_file.path)? {
        if existing.matches(retained_file) {
            return Ok(existing.id);
        }
        return Err(CoreError::conflict(
            "sync conflict retained file record is stale",
        ));
    }

    tx.execute(
        "INSERT INTO files (
            path, original_name, current_name, category, size_bytes,
            hash_sha256, storage_mode, origin, source_path,
            imported_at, updated_at, status
         ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, 'indexed', 'external', NULL,
            ?7, ?7, 'active'
         )",
        params![
            retained_file.path,
            retained_file.original_name,
            retained_file.current_name,
            retained_file.category,
            retained_file.size_bytes,
            retained_file.hash_sha256,
            occurred_at,
        ],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(tx.last_insert_rowid())
}

fn active_file_at_path(tx: &Transaction<'_>, path: &str) -> CoreResult<Option<RetainedActiveFile>> {
    tx.query_row(
        "SELECT id, size_bytes, hash_sha256
         FROM files
         WHERE path = ?1 AND status = 'active'",
        params![path],
        |row| {
            Ok(RetainedActiveFile {
                id: row.get(0)?,
                size_bytes: row.get(1)?,
                hash_sha256: row.get(2)?,
            })
        },
    )
    .optional()
    .map_err(|error| CoreError::db(error.to_string()))
}

struct RetainedActiveFile {
    id: i64,
    size_bytes: i64,
    hash_sha256: String,
}

impl RetainedActiveFile {
    fn matches(&self, retained_file: &SyncConflictRetainedFileRecord) -> bool {
        self.size_bytes == retained_file.size_bytes && self.hash_sha256 == retained_file.hash_sha256
    }
}

fn merge_detail_affected_file_ids(
    detail_json: &str,
    retained_file_ids: &[i64],
) -> CoreResult<MergedResolutionDetail> {
    let mut detail: Value = serde_json::from_str(detail_json)
        .map_err(|error| CoreError::internal(error.to_string()))?;
    let Some(ids) = detail
        .get_mut("affected_file_ids")
        .and_then(Value::as_array_mut)
    else {
        return Err(CoreError::internal(
            "sync conflict resolution detail is missing affected file ids",
        ));
    };

    for retained_id in retained_file_ids {
        if !ids.iter().any(|id| id.as_i64() == Some(*retained_id)) {
            ids.push(Value::from(*retained_id));
        }
    }

    let affected_file_ids = ids.iter().filter_map(Value::as_i64).collect();
    let detail_json =
        serde_json::to_string(&detail).map_err(|error| CoreError::internal(error.to_string()))?;
    Ok(MergedResolutionDetail {
        detail_json,
        affected_file_ids,
    })
}

struct MergedResolutionDetail {
    detail_json: String,
    affected_file_ids: Vec<i64>,
}

fn push_unique(ids: &mut Vec<i64>, id: i64) {
    if !ids.contains(&id) {
        ids.push(id);
    }
}

fn insert_resolution_change(
    tx: &Transaction<'_>,
    log_file_id: Option<i64>,
    detail_json: &str,
    occurred_at: i64,
) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, ?3)",
        params![log_file_id, detail_json, occurred_at],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}
