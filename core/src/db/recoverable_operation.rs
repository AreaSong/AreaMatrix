//! SQLite persistence for restart-safe operation identity and frozen context.

use std::path::Path;

use rusqlite::{params, OptionalExtension, Transaction};

use crate::{
    ContentLocale, CoreError, CoreResult, RecoverableOperationContext, RecoverableOperationStatus,
};

use super::open_repo_connection;

pub(crate) struct RecoverableOperationRecord {
    pub(crate) context: RecoverableOperationContext,
    pub(crate) status: RecoverableOperationStatus,
    pub(crate) created_at: i64,
    pub(crate) updated_at: i64,
    pub(crate) finished_at: Option<i64>,
    pub(crate) error_code: Option<String>,
}

pub(crate) fn insert_recoverable_operation(
    repo_path: &Path,
    context: &RecoverableOperationContext,
    status: RecoverableOperationStatus,
) -> CoreResult<RecoverableOperationRecord> {
    context.validate()?;
    super::ensure_config_storage_writable(repo_path)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    insert_recoverable_operation_in_tx(&tx, context, &status)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    load_recoverable_operation(repo_path, &context.operation_id)
}

pub(crate) fn update_recoverable_operation_status(
    repo_path: &Path,
    operation_id: &str,
    status: RecoverableOperationStatus,
    error_code: Option<&str>,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    let finished = status.is_terminal();
    let updated = connection
        .execute(
            "UPDATE recoverable_operations SET
               status = ?2,
               updated_at = CAST(strftime('%s', 'now') AS INTEGER),
               finished_at = CASE WHEN ?3 = 1 THEN CAST(strftime('%s', 'now') AS INTEGER) ELSE NULL END,
               error_code = ?4
             WHERE operation_id = ?1",
            params![operation_id, status.as_str(), i64::from(finished), error_code],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if updated == 1 {
        Ok(())
    } else {
        Err(CoreError::file_not_found(operation_id))
    }
}

pub(crate) fn insert_recoverable_operation_in_tx(
    tx: &Transaction<'_>,
    context: &RecoverableOperationContext,
    status: &RecoverableOperationStatus,
) -> CoreResult<()> {
    context.validate()?;
    let timestamp = current_timestamp(tx)?;
    tx.execute(
        "INSERT INTO recoverable_operations (
           operation_id, retry_of_operation_id, operation_code,
           operation_payload_json, content_locale, repository_revision,
           format_contract_version, target_set_hash, status, run_sequence,
           created_at, updated_at, finished_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11, ?12)",
        params![
            context.operation_id,
            context.retry_of_operation_id,
            context.operation_code,
            context.operation_payload_json,
            context.content_locale.as_ref().map(ContentLocale::as_str),
            context.repository_revision,
            context.format_contract_version,
            context.target_set_hash,
            status.as_str(),
            context.run_sequence,
            timestamp,
            status.is_terminal().then_some(timestamp),
        ],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn load_recoverable_operation(
    repo_path: &Path,
    operation_id: &str,
) -> CoreResult<RecoverableOperationRecord> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT retry_of_operation_id, operation_code, operation_payload_json,
                    content_locale, repository_revision, format_contract_version,
                    target_set_hash, status, run_sequence, created_at, updated_at,
                    finished_at, error_code
             FROM recoverable_operations WHERE operation_id = ?1",
            params![operation_id],
            |row| {
                Ok((
                    row.get::<_, Option<String>>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, String>(7)?,
                    row.get::<_, i64>(8)?,
                    row.get::<_, i64>(9)?,
                    row.get::<_, i64>(10)?,
                    row.get::<_, Option<i64>>(11)?,
                    row.get::<_, Option<String>>(12)?,
                ))
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(operation_id))
        .and_then(|row| decode_record(operation_id, row))
}

type OperationRow = (
    Option<String>,
    String,
    String,
    Option<String>,
    i64,
    i64,
    Option<String>,
    String,
    i64,
    i64,
    i64,
    Option<i64>,
    Option<String>,
);

fn decode_record(operation_id: &str, row: OperationRow) -> CoreResult<RecoverableOperationRecord> {
    let content_locale = match row.3.as_deref() {
        Some(value) => Some(
            ContentLocale::parse(value)
                .ok_or_else(|| CoreError::db("recoverable operation locale is invalid"))?,
        ),
        None => None,
    };
    let status = RecoverableOperationStatus::parse(&row.7)
        .ok_or_else(|| CoreError::db("recoverable operation status is invalid"))?;
    let context = RecoverableOperationContext {
        operation_id: operation_id.to_owned(),
        retry_of_operation_id: row.0,
        operation_code: row.1,
        operation_payload_json: row.2,
        content_locale,
        repository_revision: row.4,
        format_contract_version: row.5,
        target_set_hash: row.6,
        run_sequence: row.8,
    };
    context.validate()?;
    Ok(RecoverableOperationRecord {
        context,
        status,
        created_at: row.9,
        updated_at: row.10,
        finished_at: row.11,
        error_code: row.12,
    })
}

fn current_timestamp(tx: &Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT CAST(strftime('%s', 'now') AS INTEGER)", [], |row| {
        row.get(0)
    })
    .map_err(|error| CoreError::db(error.to_string()))
}
