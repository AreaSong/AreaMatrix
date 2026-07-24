use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
};

use rusqlite::{params, Connection, OptionalExtension, Transaction, TransactionBehavior};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::{
    ContentLocale, CoreError, CoreResult, ExternalEventKind, ExternalSyncLocaleRecoveryPlan,
    ExternalSyncLocaleRecoveryReceipt, ExternalSyncLocaleRecoveryReport,
};

use super::super::open_repo_connection;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ExternalSyncReceiptRow {
    pub(crate) event_id: i64,
    pub(crate) kind: String,
    pub(crate) path: String,
    pub(crate) file_id: Option<i64>,
    pub(crate) previous_category: Option<String>,
    pub(crate) current_category: Option<String>,
    pub(crate) content_locale: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ExternalSyncReceiptKey {
    pub(crate) event_id: i64,
    pub(crate) kind: String,
    pub(crate) path: String,
}

pub(crate) fn prepare_external_sync_locale_recovery(
    repo_path: &Path,
) -> CoreResult<Option<ExternalSyncLocaleRecoveryPlan>> {
    let connection = super::super::open_repo_read_connection(repo_path)?;
    let receipts = legacy_receipts(&connection)?;
    if receipts.is_empty() {
        return Ok(None);
    }
    let cursor = fs_event_cursor(&connection)?;
    Ok(Some(ExternalSyncLocaleRecoveryPlan {
        recovery_token: recovery_token(repo_path, cursor, &receipts),
        cursor,
        receipts,
    }))
}

pub(crate) fn resolve_external_sync_locale_recovery(
    repo_path: &Path,
    expected_token: &str,
    content_locale: ContentLocale,
) -> CoreResult<ExternalSyncLocaleRecoveryReport> {
    if expected_token.trim().is_empty() {
        return Err(CoreError::conflict(
            "legacy external sync locale recovery token is required",
        ));
    }
    let mut connection = super::super::open_repo_connection(repo_path)?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let receipts = legacy_receipts(&tx)?;
    if receipts.is_empty() {
        return Err(CoreError::conflict(
            "legacy external sync locale recovery is no longer required",
        ));
    }
    let cursor = fs_event_cursor(&tx)?;
    let actual_token = recovery_token(repo_path, cursor, &receipts);
    if actual_token != expected_token {
        return Err(CoreError::conflict(
            "legacy external sync locale recovery token is stale",
        ));
    }

    let locale = content_locale.as_str();
    for receipt in &receipts {
        let changed = tx
            .execute(
                "UPDATE external_sync_receipts
                 SET content_locale = ?4
                 WHERE event_id = ?1 AND kind = ?2 AND path = ?3
                   AND content_locale IS NULL",
                params![
                    receipt.event_id,
                    event_kind_name(&receipt.kind),
                    receipt.path,
                    locale
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        if changed != 1 {
            return Err(CoreError::conflict(
                "legacy external sync locale recovery receipt set changed",
            ));
        }
    }
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(ExternalSyncLocaleRecoveryReport {
        recovered_receipts: receipts.len() as i64,
        content_locale,
    })
}

pub(crate) struct ExternalSyncOverviewLocales {
    pub(crate) node_locales: BTreeMap<String, String>,
    pub(crate) root_locale: Option<String>,
}

#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd)]
enum OverviewLocaleScope {
    Root,
    Node(String),
}

struct LocaleAtEvent {
    event_id: i64,
    locales: BTreeSet<String>,
}

struct StoredExternalSyncReceiptRow {
    event_id: i64,
    kind: String,
    path: String,
    file_id: Option<i64>,
    previous_category: Option<String>,
    current_category: Option<String>,
    content_locale: Option<String>,
}

pub(crate) fn ensure_external_sync_receipts(repo_path: &Path) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS external_sync_receipts (
               event_id INTEGER NOT NULL,
               kind TEXT NOT NULL CHECK (kind IN ('created', 'renamed', 'removed', 'modified')),
               path TEXT NOT NULL,
               file_id INTEGER,
               previous_category TEXT,
               current_category TEXT,
               content_locale TEXT CHECK (content_locale IN ('zh-Hans', 'en')),
               applied_at INTEGER NOT NULL,
               PRIMARY KEY (event_id, kind, path)
             );
             CREATE INDEX IF NOT EXISTS idx_external_sync_receipts_applied
               ON external_sync_receipts(applied_at DESC);",
        )
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn claim_external_sync_receipts(
    repo_path: &Path,
    keys: &[ExternalSyncReceiptKey],
    content_locale: &str,
) -> CoreResult<Vec<Option<ExternalSyncReceiptRow>>> {
    let content_locale = crate::config::validate_content_locale(content_locale)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let receipts = keys
        .iter()
        .map(|key| claim_external_sync_receipt(&tx, key, content_locale))
        .collect::<CoreResult<Vec<_>>>()?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(receipts)
}

pub(crate) fn external_sync_overview_locales(
    receipts: &[ExternalSyncReceiptRow],
) -> CoreResult<ExternalSyncOverviewLocales> {
    let mut provenance = BTreeMap::new();
    for receipt in receipts {
        record_locale_provenance(&mut provenance, OverviewLocaleScope::Root, receipt);
        for node in [
            receipt.previous_category.as_ref(),
            receipt.current_category.as_ref(),
        ]
        .into_iter()
        .flatten()
        {
            record_locale_provenance(
                &mut provenance,
                OverviewLocaleScope::Node(node.clone()),
                receipt,
            );
        }
    }
    let root_locale = provenance
        .remove(&OverviewLocaleScope::Root)
        .map(resolve_locale_provenance)
        .transpose()?;
    let node_locales = provenance
        .into_iter()
        .filter_map(|(scope, provenance)| match scope {
            OverviewLocaleScope::Root => None,
            OverviewLocaleScope::Node(node) => {
                Some(resolve_locale_provenance(provenance).map(|locale| (node, locale)))
            }
        })
        .collect::<CoreResult<BTreeMap<_, _>>>()?;
    Ok(ExternalSyncOverviewLocales {
        node_locales,
        root_locale,
    })
}

fn record_locale_provenance(
    provenance: &mut BTreeMap<OverviewLocaleScope, LocaleAtEvent>,
    scope: OverviewLocaleScope,
    receipt: &ExternalSyncReceiptRow,
) {
    use std::collections::btree_map::Entry;

    match provenance.entry(scope) {
        Entry::Vacant(entry) => {
            entry.insert(locale_at_event(receipt));
        }
        Entry::Occupied(mut entry) if receipt.event_id > entry.get().event_id => {
            entry.insert(locale_at_event(receipt));
        }
        Entry::Occupied(mut entry) if receipt.event_id == entry.get().event_id => {
            entry
                .get_mut()
                .locales
                .insert(receipt.content_locale.clone());
        }
        Entry::Occupied(_) => {}
    }
}

fn locale_at_event(receipt: &ExternalSyncReceiptRow) -> LocaleAtEvent {
    LocaleAtEvent {
        event_id: receipt.event_id,
        locales: BTreeSet::from([receipt.content_locale.clone()]),
    }
}

fn resolve_locale_provenance(provenance: LocaleAtEvent) -> CoreResult<String> {
    if provenance.locales.len() != 1 {
        return Err(CoreError::internal(
            "external sync receipt locale provenance invariant",
        ));
    }
    provenance
        .locales
        .into_iter()
        .next()
        .ok_or_else(|| CoreError::internal("external sync receipt locale provenance missing"))
}

fn claim_external_sync_receipt(
    tx: &Transaction<'_>,
    key: &ExternalSyncReceiptKey,
    content_locale: &str,
) -> CoreResult<Option<ExternalSyncReceiptRow>> {
    let stored = tx
        .query_row(
            "SELECT event_id, kind, path, file_id, previous_category, current_category,
                    content_locale
             FROM external_sync_receipts
             WHERE event_id = ?1 AND kind = ?2 AND path = ?3",
            params![key.event_id, key.kind, key.path],
            |row| {
                Ok(StoredExternalSyncReceiptRow {
                    event_id: row.get(0)?,
                    kind: row.get(1)?,
                    path: row.get(2)?,
                    file_id: row.get(3)?,
                    previous_category: row.get(4)?,
                    current_category: row.get(5)?,
                    content_locale: row.get(6)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    stored
        .map(|stored| resolve_external_sync_receipt_locale(tx, stored, content_locale))
        .transpose()
}

fn resolve_external_sync_receipt_locale(
    tx: &Transaction<'_>,
    stored: StoredExternalSyncReceiptRow,
    content_locale: &str,
) -> CoreResult<ExternalSyncReceiptRow> {
    let resolved_locale = match stored.content_locale {
        Some(locale) => crate::config::validate_content_locale(&locale)?.to_owned(),
        None => {
            let _ = (tx, content_locale);
            return Err(CoreError::config(
                "legacy external sync receipt locale recovery required",
            ));
        }
    };
    Ok(ExternalSyncReceiptRow {
        event_id: stored.event_id,
        kind: stored.kind,
        path: stored.path,
        file_id: stored.file_id,
        previous_category: stored.previous_category,
        current_category: stored.current_category,
        content_locale: resolved_locale,
    })
}

fn legacy_receipts(connection: &Connection) -> CoreResult<Vec<ExternalSyncLocaleRecoveryReceipt>> {
    let mut statement = connection
        .prepare(
            "SELECT event_id, kind, path
             FROM external_sync_receipts
             WHERE content_locale IS NULL
             ORDER BY event_id ASC, kind ASC, path ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| {
            let kind: String = row.get(1)?;
            Ok((row.get(0)?, kind, row.get(2)?))
        })
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.map(|row| {
        let (event_id, kind, path): (i64, String, String) =
            row.map_err(|error| CoreError::db(error.to_string()))?;
        Ok(ExternalSyncLocaleRecoveryReceipt {
            event_id,
            kind: parse_event_kind(&kind)?,
            path,
        })
    })
    .collect()
}

fn fs_event_cursor(connection: &Connection) -> CoreResult<Option<i64>> {
    connection
        .query_row(
            "SELECT last_event_id FROM fs_event_cursor WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn recovery_token(
    repo_path: &Path,
    cursor: Option<i64>,
    receipts: &[ExternalSyncLocaleRecoveryReceipt],
) -> String {
    let mut hasher = Sha256::new();
    feed_token_part(&mut hasher, b"area-matrix:external-sync-locale-recovery:v1");
    feed_token_part(&mut hasher, repo_path.to_string_lossy().as_bytes());
    match cursor {
        Some(value) => feed_token_part(&mut hasher, value.to_string().as_bytes()),
        None => feed_token_part(&mut hasher, b"none"),
    }
    for receipt in receipts {
        feed_token_part(&mut hasher, receipt.event_id.to_string().as_bytes());
        feed_token_part(&mut hasher, event_kind_name(&receipt.kind).as_bytes());
        feed_token_part(&mut hasher, receipt.path.as_bytes());
    }
    format!("{:x}", hasher.finalize())
}

fn feed_token_part(hasher: &mut Sha256, value: &[u8]) {
    hasher.update((value.len() as u64).to_le_bytes());
    hasher.update(value);
}

fn parse_event_kind(value: &str) -> CoreResult<ExternalEventKind> {
    match value {
        "created" => Ok(ExternalEventKind::Created),
        "renamed" => Ok(ExternalEventKind::Renamed),
        "removed" => Ok(ExternalEventKind::Removed),
        "modified" => Ok(ExternalEventKind::Modified),
        _ => Err(CoreError::internal(
            "legacy external sync receipt has an invalid event kind",
        )),
    }
}

fn event_kind_name(kind: &ExternalEventKind) -> &'static str {
    match kind {
        ExternalEventKind::Created => "created",
        ExternalEventKind::Renamed => "renamed",
        ExternalEventKind::Removed => "removed",
        ExternalEventKind::Modified => "modified",
    }
}

pub(crate) fn latest_external_rename_source_category(
    repo_path: &Path,
    file_id: i64,
    event_id: i64,
    target_path: &str,
) -> CoreResult<Option<String>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT detail_json
             FROM change_log
             WHERE file_id = ?1 AND action = 'renamed'
             ORDER BY id DESC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let details = statement
        .query_map(params![file_id], |row| row.get::<_, String>(0))
        .map_err(|error| CoreError::db(error.to_string()))?;

    for detail in details {
        let detail = detail.map_err(|error| CoreError::db(error.to_string()))?;
        let value: Value =
            serde_json::from_str(&detail).map_err(|error| CoreError::db(error.to_string()))?;
        if value.get("event_id").and_then(Value::as_i64) != Some(event_id)
            || value.get("to_path").and_then(Value::as_str) != Some(target_path)
        {
            continue;
        }
        return Ok(value
            .get("from_category")
            .and_then(Value::as_str)
            .map(str::to_owned));
    }
    latest_legacy_external_rename_source_category(&connection, file_id, target_path)
}

pub(crate) fn get_fs_event_cursor(repo_path: &Path) -> CoreResult<Option<i64>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT last_event_id FROM fs_event_cursor WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn set_fs_event_cursor(repo_path: &Path, last_event_id: i64) -> CoreResult<()> {
    ensure_external_sync_receipts(repo_path)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    set_cursor(&tx, last_event_id)?;
    tx.execute(
        "DELETE FROM external_sync_receipts WHERE event_id <= ?1",
        params![last_event_id],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn count_existing_receipts(
    tx: &Transaction<'_>,
    receipts: &[ExternalSyncReceiptRow],
) -> CoreResult<usize> {
    let mut count = 0;
    for receipt in receipts {
        let exists = tx
            .query_row(
                "SELECT EXISTS(
                   SELECT 1 FROM external_sync_receipts
                   WHERE event_id = ?1 AND kind = ?2 AND path = ?3
                 )",
                params![receipt.event_id, receipt.kind, receipt.path],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        if exists {
            count += 1;
        }
    }
    Ok(count)
}

pub(super) fn insert_external_sync_receipt(
    tx: &Transaction<'_>,
    receipt: ExternalSyncReceiptRow,
) -> CoreResult<()> {
    let content_locale = crate::config::validate_content_locale(&receipt.content_locale)?;
    tx.execute(
        "INSERT INTO external_sync_receipts (
           event_id, kind, path, file_id, previous_category, current_category,
           content_locale, applied_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, strftime('%s', 'now'))",
        params![
            receipt.event_id,
            receipt.kind,
            receipt.path,
            receipt.file_id,
            receipt.previous_category,
            receipt.current_category,
            content_locale,
        ],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn latest_legacy_external_rename_source_category(
    connection: &rusqlite::Connection,
    file_id: i64,
    target_path: &str,
) -> CoreResult<Option<String>> {
    let latest = connection
        .query_row(
            "SELECT action, detail_json
             FROM change_log
             WHERE file_id = ?1
             ORDER BY id DESC
             LIMIT 1",
            params![file_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let Some((action, detail)) = latest else {
        return Ok(None);
    };
    if action != "renamed" {
        return Ok(None);
    }
    let value: Value =
        serde_json::from_str(&detail).map_err(|error| CoreError::db(error.to_string()))?;
    if value.get("event_id").is_some()
        || value.get("to_path").and_then(Value::as_str) != Some(target_path)
    {
        return Ok(None);
    }
    Ok(value
        .get("from_category")
        .and_then(Value::as_str)
        .map(str::to_owned))
}

fn set_cursor(tx: &Transaction<'_>, last_event_id: i64) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO fs_event_cursor (id, last_event_id, updated_at)
         VALUES (1, ?1, strftime('%s', 'now'))
         ON CONFLICT(id) DO UPDATE SET
             last_event_id = MAX(fs_event_cursor.last_event_id, excluded.last_event_id),
             updated_at = excluded.updated_at",
        params![last_event_id],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}
