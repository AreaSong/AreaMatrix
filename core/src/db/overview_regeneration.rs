//! Durable journal and provenance persistence for full overview regeneration.

use std::path::Path;

use rusqlite::{params, OptionalExtension, TransactionBehavior};

use crate::{
    ContentLocale, CoreError, CoreResult, RecoverableOperationContext, RecoverableOperationStatus,
};

use super::{insert_recoverable_operation_in_tx, open_repo_connection, RecoverableOperationRecord};

#[derive(Clone, Debug)]
pub(crate) struct OverviewProvenanceRecord {
    pub(crate) relative_path: String,
    pub(crate) operation_id: String,
    pub(crate) content_locale: ContentLocale,
    pub(crate) format_contract_version: i64,
    pub(crate) repository_revision: i64,
    pub(crate) content_sha256: String,
    pub(crate) generated_at: i64,
}

#[derive(Clone, Debug)]
pub(crate) struct OverviewJournalItem {
    pub(crate) relative_path: String,
    pub(crate) target_kind: String,
    pub(crate) old_exists: bool,
    pub(crate) old_sha256: Option<String>,
    pub(crate) new_exists: bool,
    pub(crate) new_sha256: String,
    pub(crate) staging_relative_path: String,
    pub(crate) backup_relative_path: Option<String>,
    pub(crate) state: String,
    pub(crate) old_provenance: Option<OverviewProvenanceRecord>,
}

pub(crate) fn create_overview_regeneration(
    repo_path: &Path,
    context: &RecoverableOperationContext,
    items: &[OverviewJournalItem],
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let active: i64 = tx
        .query_row(
            "SELECT COUNT(*) FROM recoverable_operations
             WHERE operation_code = 'overview_regeneration'
               AND status NOT IN ('completed','rolled_back','failed','canceled')",
            [],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if active != 0 {
        return Err(CoreError::conflict(
            "overview regeneration is already active",
        ));
    }
    insert_recoverable_operation_in_tx(&tx, context, &RecoverableOperationStatus::Running)?;
    for item in items {
        let provenance = load_provenance_in_tx(&tx, &item.relative_path)?;
        tx.execute(
            "INSERT INTO overview_regeneration_items (
               operation_id, relative_path, target_kind, old_exists, old_sha256,
               new_exists, new_sha256, staging_relative_path, backup_relative_path,
               state, old_provenance_operation_id, old_provenance_content_locale,
               old_provenance_format_version, old_provenance_repository_revision,
               old_provenance_content_sha256, old_provenance_generated_at
             ) VALUES (
               ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'planned',
               ?10, ?11, ?12, ?13, ?14, ?15
             )",
            params![
                context.operation_id,
                item.relative_path,
                item.target_kind,
                i64::from(item.old_exists),
                item.old_sha256,
                i64::from(item.new_exists),
                item.new_sha256,
                item.staging_relative_path,
                item.backup_relative_path,
                provenance.as_ref().map(|value| value.operation_id.as_str()),
                provenance
                    .as_ref()
                    .map(|value| value.content_locale.as_str()),
                provenance
                    .as_ref()
                    .map(|value| value.format_contract_version),
                provenance.as_ref().map(|value| value.repository_revision),
                provenance
                    .as_ref()
                    .map(|value| value.content_sha256.as_str()),
                provenance.as_ref().map(|value| value.generated_at),
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    }
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn load_overview_regeneration(
    repo_path: &Path,
    operation_id: &str,
) -> CoreResult<(RecoverableOperationRecord, Vec<OverviewJournalItem>)> {
    let operation = super::load_recoverable_operation(repo_path, operation_id)?;
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT relative_path, target_kind, old_exists, old_sha256, new_exists,
                    new_sha256, staging_relative_path, backup_relative_path, state,
                    old_provenance_operation_id, old_provenance_content_locale,
                    old_provenance_format_version, old_provenance_repository_revision,
                    old_provenance_content_sha256, old_provenance_generated_at
             FROM overview_regeneration_items
             WHERE operation_id = ?1 ORDER BY relative_path ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![operation_id], |row| {
            let locale = row.get::<_, Option<String>>(10)?;
            let old_provenance = match locale {
                Some(locale) => Some((
                    row.get::<_, Option<String>>(9)?,
                    locale,
                    row.get::<_, Option<i64>>(11)?,
                    row.get::<_, Option<i64>>(12)?,
                    row.get::<_, Option<String>>(13)?,
                    row.get::<_, Option<i64>>(14)?,
                )),
                None => None,
            };
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)? != 0,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, i64>(4)? != 0,
                row.get::<_, String>(5)?,
                row.get::<_, String>(6)?,
                row.get::<_, Option<String>>(7)?,
                row.get::<_, String>(8)?,
                old_provenance,
            ))
        })
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut items = Vec::new();
    for row in rows {
        let row = row.map_err(|error| CoreError::db(error.to_string()))?;
        let old_provenance = row.9.map(decode_old_provenance).transpose()?;
        items.push(OverviewJournalItem {
            relative_path: row.0,
            target_kind: row.1,
            old_exists: row.2,
            old_sha256: row.3,
            new_exists: row.4,
            new_sha256: row.5,
            staging_relative_path: row.6,
            backup_relative_path: row.7,
            state: row.8,
            old_provenance,
        });
    }
    Ok((operation, items))
}

type OldProvenanceTuple = (
    Option<String>,
    String,
    Option<i64>,
    Option<i64>,
    Option<String>,
    Option<i64>,
);

fn decode_old_provenance(value: OldProvenanceTuple) -> CoreResult<OverviewProvenanceRecord> {
    let required = || CoreError::db("overview provenance journal is incomplete");
    Ok(OverviewProvenanceRecord {
        relative_path: String::new(),
        operation_id: value.0.ok_or_else(required)?,
        content_locale: ContentLocale::parse(&value.1).ok_or_else(required)?,
        format_contract_version: value.2.ok_or_else(required)?,
        repository_revision: value.3.ok_or_else(required)?,
        content_sha256: value.4.ok_or_else(required)?,
        generated_at: value.5.ok_or_else(required)?,
    })
}

pub(crate) fn update_overview_operation_status(
    repo_path: &Path,
    operation_id: &str,
    status: RecoverableOperationStatus,
    error_code: Option<&str>,
    increment_run_sequence: bool,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    let finished = status.is_terminal();
    let updated = connection
        .execute(
            "UPDATE recoverable_operations SET
               status = ?2,
               updated_at = CAST(strftime('%s', 'now') AS INTEGER),
               finished_at = CASE WHEN ?3 = 1 THEN CAST(strftime('%s', 'now') AS INTEGER) ELSE NULL END,
               error_code = ?4,
               run_sequence = run_sequence + ?5
             WHERE operation_id = ?1 AND operation_code = 'overview_regeneration'",
            params![
                operation_id,
                status.as_str(),
                i64::from(finished),
                error_code,
                i64::from(increment_run_sequence),
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if updated == 1 {
        Ok(())
    } else {
        Err(CoreError::file_not_found(operation_id))
    }
}

pub(crate) fn update_overview_item_state(
    repo_path: &Path,
    operation_id: &str,
    relative_path: &str,
    state: &str,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    let updated = connection
        .execute(
            "UPDATE overview_regeneration_items SET state = ?3
             WHERE operation_id = ?1 AND relative_path = ?2",
            params![operation_id, relative_path, state],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if updated == 1 {
        Ok(())
    } else {
        Err(CoreError::db("overview journal item is missing"))
    }
}

pub(crate) fn replace_overview_provenance(
    repo_path: &Path,
    provenance: &OverviewProvenanceRecord,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    replace_provenance_in_connection(&connection, provenance)
}

pub(crate) fn record_completed_overview_generation(
    repo_path: &Path,
    context: &RecoverableOperationContext,
    records: &[OverviewProvenanceRecord],
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    insert_recoverable_operation_in_tx(&tx, context, &RecoverableOperationStatus::Completed)?;
    for record in records {
        replace_provenance_in_connection(&tx, record)?;
    }
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn replace_provenance_in_connection(
    connection: &rusqlite::Connection,
    provenance: &OverviewProvenanceRecord,
) -> CoreResult<()> {
    connection
        .execute(
            "INSERT INTO overview_provenance (
               relative_path, operation_id, content_locale, format_contract_version,
               repository_revision, content_sha256, generated_at
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(relative_path) DO UPDATE SET
               operation_id = excluded.operation_id,
               content_locale = excluded.content_locale,
               format_contract_version = excluded.format_contract_version,
               repository_revision = excluded.repository_revision,
               content_sha256 = excluded.content_sha256,
               generated_at = excluded.generated_at",
            params![
                provenance.relative_path,
                provenance.operation_id,
                provenance.content_locale.as_str(),
                provenance.format_contract_version,
                provenance.repository_revision,
                provenance.content_sha256,
                provenance.generated_at,
            ],
        )
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn restore_overview_provenance(
    repo_path: &Path,
    relative_path: &str,
    provenance: Option<&OverviewProvenanceRecord>,
) -> CoreResult<()> {
    let mut value = provenance.cloned();
    if let Some(value) = value.as_mut() {
        value.relative_path = relative_path.to_owned();
        replace_overview_provenance(repo_path, value)
    } else {
        let connection = open_repo_connection(repo_path)?;
        connection
            .execute(
                "DELETE FROM overview_provenance WHERE relative_path = ?1",
                params![relative_path],
            )
            .map(|_| ())
            .map_err(|error| CoreError::db(error.to_string()))
    }
}

pub(crate) fn load_overview_provenance(
    repo_path: &Path,
    relative_path: &str,
) -> CoreResult<Option<OverviewProvenanceRecord>> {
    let connection = open_repo_connection(repo_path)?;
    load_provenance_in_tx(&connection, relative_path)
}

fn load_provenance_in_tx(
    connection: &rusqlite::Connection,
    relative_path: &str,
) -> CoreResult<Option<OverviewProvenanceRecord>> {
    connection
        .query_row(
            "SELECT operation_id, content_locale, format_contract_version,
                    repository_revision, content_sha256, generated_at
             FROM overview_provenance WHERE relative_path = ?1",
            params![relative_path],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, i64>(5)?,
                ))
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .map(|row| {
            let locale = ContentLocale::parse(&row.1)
                .ok_or_else(|| CoreError::db("overview provenance locale is invalid"))?;
            Ok(OverviewProvenanceRecord {
                relative_path: relative_path.to_owned(),
                operation_id: row.0,
                content_locale: locale,
                format_contract_version: row.2,
                repository_revision: row.3,
                content_sha256: row.4,
                generated_at: row.5,
            })
        })
        .transpose()
}

pub(crate) fn has_unsettled_overview_regeneration(repo_path: &Path) -> CoreResult<bool> {
    let connection = open_repo_connection(repo_path)?;
    let count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM recoverable_operations
             WHERE operation_code = 'overview_regeneration'
               AND status NOT IN ('completed','rolled_back','failed','canceled')",
            [],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(count != 0)
}

pub(crate) fn load_unsettled_overview_regeneration_id(
    repo_path: &Path,
) -> CoreResult<Option<String>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT operation_id FROM recoverable_operations
             WHERE operation_code = 'overview_regeneration'
               AND status NOT IN ('completed','rolled_back','failed','canceled')
             ORDER BY created_at ASC, operation_id ASC
             LIMIT 2",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|error| CoreError::db(error.to_string()))?;
    let operation_ids = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))?;
    match operation_ids.as_slice() {
        [] => Ok(None),
        [operation_id] => Ok(Some(operation_id.clone())),
        _ => Err(CoreError::db(
            "multiple unsettled overview regeneration operations exist",
        )),
    }
}
