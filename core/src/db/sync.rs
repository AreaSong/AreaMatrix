use std::path::Path;

use rusqlite::{params, OptionalExtension, Transaction, TransactionBehavior};

use crate::{CoreError, CoreResult};

use super::{open_repo_connection, storage_mode_to_db};

mod receipts;

pub(crate) use receipts::{
    claim_external_sync_receipts, ensure_external_sync_receipts, external_sync_overview_locales,
    get_fs_event_cursor, latest_external_rename_source_category,
    prepare_external_sync_locale_recovery, resolve_external_sync_locale_recovery,
    set_fs_event_cursor, ExternalSyncReceiptKey, ExternalSyncReceiptRow,
};
use receipts::{count_existing_receipts, insert_external_sync_receipt};

pub(crate) struct ExternalCreatedRow {
    pub(crate) path: String,
    pub(crate) original_name: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
    pub(crate) detail_json: String,
}

pub(crate) struct ExternalRenamedRow {
    pub(crate) file_id: i64,
    pub(crate) from_path: String,
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
    pub(crate) expected_size_bytes: i64,
    pub(crate) expected_hash_sha256: String,
    pub(crate) detail_json: String,
}

pub(crate) struct ExternalModifiedRow {
    pub(crate) file_id: i64,
    pub(crate) expected_path: String,
    pub(crate) expected_size_bytes: i64,
    pub(crate) expected_hash_sha256: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
    pub(crate) detail_json: String,
}

pub(crate) struct ExternalRemovedRow {
    pub(crate) file_id: i64,
    pub(crate) expected_path: String,
    pub(crate) expected_size_bytes: i64,
    pub(crate) expected_hash_sha256: String,
    pub(crate) detail_json: String,
}

pub(crate) struct ExternalRenameCandidate {
    pub(crate) id: i64,
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
}

pub(crate) struct ExternalPathRow {
    pub(crate) id: i64,
    pub(crate) status: String,
}

pub(crate) struct ExternalSyncApplyResult {
    pub(crate) detected_creates: i64,
    pub(crate) detected_renames: i64,
    pub(crate) detected_deletes: i64,
    pub(crate) detected_modifies: i64,
}

pub(crate) fn apply_external_sync_batch(
    repo_path: &Path,
    created_rows: Vec<ExternalCreatedRow>,
    renamed_rows: Vec<ExternalRenamedRow>,
    modified_rows: Vec<ExternalModifiedRow>,
    removed_rows: Vec<ExternalRemovedRow>,
    receipts: Vec<ExternalSyncReceiptRow>,
) -> CoreResult<ExternalSyncApplyResult> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut detected_creates = 0_i64;
    let mut detected_renames = 0_i64;
    let mut detected_deletes = 0_i64;
    let mut detected_modifies = 0_i64;

    let existing_receipt_count = count_existing_receipts(&tx, &receipts)?;
    if existing_receipt_count == receipts.len() && !receipts.is_empty() {
        tx.commit()
            .map_err(|error| CoreError::db(error.to_string()))?;
        return Ok(ExternalSyncApplyResult {
            detected_creates,
            detected_renames,
            detected_deletes,
            detected_modifies,
        });
    }
    if existing_receipt_count > 0 {
        return Err(CoreError::conflict("external sync receipt conflict"));
    }

    for row in &renamed_rows {
        ensure_rename_target_available(&tx, row)?;
    }
    for row in renamed_rows {
        update_external_renamed_file(&tx, row)?;
        detected_renames += 1;
    }
    for row in created_rows {
        if insert_external_file(&tx, row)? {
            detected_creates += 1;
        }
    }
    for row in modified_rows {
        update_external_modified_file(&tx, row)?;
        detected_modifies += 1;
    }
    for row in removed_rows {
        soft_delete_external_removed_file(&tx, row)?;
        detected_deletes += 1;
    }
    for receipt in receipts {
        insert_external_sync_receipt(&tx, receipt)?;
    }

    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(ExternalSyncApplyResult {
        detected_creates,
        detected_renames,
        detected_deletes,
        detected_modifies,
    })
}

pub(crate) fn find_external_rename_candidates_by_hash(
    repo_path: &Path,
    hash_sha256: &str,
    new_path: &str,
) -> CoreResult<Vec<ExternalRenameCandidate>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT id, path, current_name, category, size_bytes, hash_sha256
             FROM files
             WHERE hash_sha256 = ?1
               AND path != ?2
               AND status = 'active'
             ORDER BY imported_at ASC, id ASC
             LIMIT 2",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![hash_sha256, new_path], |row| {
            Ok(ExternalRenameCandidate {
                id: row.get(0)?,
                path: row.get(1)?,
                current_name: row.get(2)?,
                category: row.get(3)?,
                size_bytes: row.get(4)?,
                hash_sha256: row.get(5)?,
            })
        })
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn find_file_by_path_any_status(
    repo_path: &Path,
    relative_path: &str,
) -> CoreResult<Option<ExternalPathRow>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT id, status
             FROM files
             WHERE path = ?1
             LIMIT 1",
            params![relative_path],
            |row| {
                Ok(ExternalPathRow {
                    id: row.get(0)?,
                    status: row.get(1)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn insert_external_file(tx: &Transaction<'_>, row: ExternalCreatedRow) -> CoreResult<bool> {
    let existing = tx
        .query_row(
            "SELECT id, status FROM files WHERE path = ?1",
            params![row.path],
            |record| Ok((record.get::<_, i64>(0)?, record.get::<_, String>(1)?)),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    if let Some((file_id, status)) = existing {
        if status == "active" {
            return Ok(false);
        }
        if status != "deleted" {
            return Err(CoreError::conflict("path conflict"));
        }
        reactivate_external_file(tx, file_id, row)?;
        return Ok(true);
    }

    let changed = tx
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?3, ?4, ?5,
                ?6, ?7, 'external', NULL,
                strftime('%s', 'now'), strftime('%s', 'now'), 'active'
             )",
            params![
                row.path,
                row.original_name,
                row.current_name,
                row.category,
                row.size_bytes,
                row.hash_sha256,
                storage_mode_to_db(&crate::StorageMode::Indexed),
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 0 {
        return Ok(false);
    }

    let file_id = tx.last_insert_rowid();
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, strftime('%s', 'now'))",
        params![file_id, row.detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(true)
}

fn reactivate_external_file(
    tx: &Transaction<'_>,
    file_id: i64,
    row: ExternalCreatedRow,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET original_name = ?2,
                 current_name = ?3,
                 category = ?4,
                 size_bytes = ?5,
                 hash_sha256 = ?6,
                 storage_mode = ?7,
                 origin = 'external',
                 source_path = NULL,
                 deleted_at = NULL,
                 updated_at = strftime('%s', 'now'),
                 status = 'active'
             WHERE id = ?1 AND status = 'deleted'",
            params![
                file_id,
                row.original_name,
                row.current_name,
                row.category,
                row.size_bytes,
                row.hash_sha256,
                storage_mode_to_db(&crate::StorageMode::Indexed),
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::conflict("path conflict"));
    }
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, strftime('%s', 'now'))",
        params![file_id, row.detail_json],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn update_external_renamed_file(tx: &Transaction<'_>, row: ExternalRenamedRow) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 category = ?4,
                 size_bytes = ?5,
                 hash_sha256 = ?6,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1
               AND path = ?7
               AND size_bytes = ?8
               AND hash_sha256 = ?9
               AND status = 'active'",
            params![
                row.file_id,
                row.path,
                row.current_name,
                row.category,
                row.size_bytes,
                row.hash_sha256,
                row.from_path,
                row.expected_size_bytes,
                row.expected_hash_sha256,
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::conflict(row.path));
    }

    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'renamed', ?2, strftime('%s', 'now'))",
        params![row.file_id, row.detail_json],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_rename_target_available(
    tx: &Transaction<'_>,
    row: &ExternalRenamedRow,
) -> CoreResult<()> {
    let occupant = tx
        .query_row(
            "SELECT id FROM files WHERE path = ?1 LIMIT 1",
            params![row.path],
            |record| record.get::<_, i64>(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    match occupant {
        None => Ok(()),
        Some(file_id) if file_id == row.file_id => Ok(()),
        Some(_) => Err(CoreError::conflict(row.path.clone())),
    }
}

fn update_external_modified_file(tx: &Transaction<'_>, row: ExternalModifiedRow) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET size_bytes = ?2,
                 hash_sha256 = ?3,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1
               AND path = ?4
               AND size_bytes = ?5
               AND hash_sha256 = ?6
               AND status = 'active'",
            params![
                row.file_id,
                row.size_bytes,
                row.hash_sha256,
                row.expected_path,
                row.expected_size_bytes,
                row.expected_hash_sha256,
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::conflict(row.expected_path));
    }

    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, strftime('%s', 'now'))",
        params![row.file_id, row.detail_json],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn soft_delete_external_removed_file(
    tx: &Transaction<'_>,
    row: ExternalRemovedRow,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET deleted_at = strftime('%s', 'now'),
                 updated_at = strftime('%s', 'now'),
                 status = 'deleted'
             WHERE id = ?1
               AND path = ?2
               AND size_bytes = ?3
               AND hash_sha256 = ?4
               AND status = 'active'",
            params![
                row.file_id,
                row.expected_path,
                row.expected_size_bytes,
                row.expected_hash_sha256,
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::conflict(row.expected_path));
    }

    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'deleted', ?2, strftime('%s', 'now'))",
        params![row.file_id, row.detail_json],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

#[cfg(test)]
mod tests;
