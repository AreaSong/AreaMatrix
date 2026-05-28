//! AI call log storage used by Stage 3 AI producers and audit readers.

#[path = "ai_call_log/helpers.rs"]
mod helpers;
#[path = "ai_call_log/schema.rs"]
mod schema;

use std::path::Path;

use rusqlite::{params, params_from_iter};

use crate::{CoreError, CoreResult};

use helpers::{
    bool_to_db, db_to_bool, default_scope, ensure_storage_readable, ensure_storage_writable,
    map_open_error,
};
use schema::{ensure_ai_call_log_schema, read_schema, AiCallLogSchema};

pub(crate) struct AiCallLogInsertRecord {
    pub(crate) feature: String,
    pub(crate) file_id: Option<i64>,
    pub(crate) route: Option<String>,
    pub(crate) provider: Option<String>,
    pub(crate) model: Option<String>,
    pub(crate) status: String,
    pub(crate) sent_fields_json: String,
    pub(crate) privacy_rule_id: Option<String>,
    pub(crate) result_summary: String,
    pub(crate) error_code: Option<String>,
}

pub(crate) struct AiCallLogListFilter {
    pub(crate) feature: Option<String>,
    pub(crate) route: Option<String>,
    pub(crate) status: Option<String>,
    pub(crate) occurred_after: Option<i64>,
    pub(crate) occurred_before: Option<i64>,
    pub(crate) search_pattern: Option<String>,
}

pub(crate) struct AiCallLogPagination {
    pub(crate) limit: i64,
    pub(crate) offset: i64,
}

pub(crate) struct AiCallLogRow {
    pub(crate) id: i64,
    pub(crate) occurred_at: i64,
    pub(crate) feature: String,
    pub(crate) file_id: Option<i64>,
    pub(crate) file_display_name: Option<String>,
    pub(crate) batch_id: Option<String>,
    pub(crate) scope: Option<String>,
    pub(crate) route: Option<String>,
    pub(crate) provider_name: Option<String>,
    pub(crate) model_name: Option<String>,
    pub(crate) status: String,
    pub(crate) duration_ms: Option<i64>,
    pub(crate) sent_fields_json: String,
    pub(crate) privacy_rules_checked: bool,
    pub(crate) privacy_rule_id: Option<String>,
    pub(crate) privacy_rule_name: Option<String>,
    pub(crate) matched_field_type: Option<String>,
    pub(crate) result_summary: String,
    pub(crate) error_code: Option<String>,
}

pub(crate) struct AiCallLogListPage {
    pub(crate) total_count: i64,
    pub(crate) rows: Vec<AiCallLogRow>,
}

pub(crate) enum AiCallLogClearSpec {
    All,
    SelectedEntries(Vec<i64>),
    OlderThan(i64),
}

pub(crate) struct AiCallLogClearStats {
    pub(crate) deleted_count: i64,
    pub(crate) remaining_count: i64,
    pub(crate) cleared_at: i64,
}

pub(crate) fn insert_ai_call_log_record(
    repo_path: &Path,
    record: AiCallLogInsertRecord,
) -> CoreResult<i64> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_ai_call_log_schema(&tx)?;
    let privacy_rules_checked = record.privacy_rule_id.is_some();
    let scope = default_scope(&record.feature);
    tx.execute(
        "INSERT INTO ai_call_log (
            feature, file_id, batch_id, scope, route, provider, model, status,
            duration_ms, sent_fields_json, privacy_rules_checked, privacy_rule_id,
            privacy_rule_name, matched_field_type, result_summary, error_code, occurred_at
         ) VALUES (
            ?1, ?2, NULL, ?3, ?4, ?5, ?6, ?7, NULL, ?8, ?9, ?10, NULL, NULL, ?11, ?12, ?13
         )",
        params![
            record.feature,
            record.file_id,
            scope,
            record.route,
            record.provider,
            record.model,
            record.status,
            record.sent_fields_json,
            bool_to_db(privacy_rules_checked),
            record.privacy_rule_id,
            record.result_summary,
            record.error_code,
            current_timestamp(&tx)?,
        ],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    let id = tx.last_insert_rowid();
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(id)
}

pub(crate) fn list_ai_call_log_rows(
    repo_path: &Path,
    filter: &AiCallLogListFilter,
    pagination: &AiCallLogPagination,
) -> CoreResult<AiCallLogListPage> {
    ensure_storage_readable(repo_path)?;

    let connection = super::open_repo_connection(repo_path).map_err(map_open_error)?;
    let schema = read_schema(&connection)?;
    if !schema.exists {
        return Ok(AiCallLogListPage {
            total_count: 0,
            rows: Vec::new(),
        });
    }
    schema.require_base_columns()?;

    let total_count = query_count(&connection, &schema, filter)?;
    let rows = query_rows(&connection, &schema, filter, pagination)?;
    Ok(AiCallLogListPage { total_count, rows })
}

pub(crate) fn clear_ai_call_log_rows(
    repo_path: &Path,
    spec: AiCallLogClearSpec,
) -> CoreResult<AiCallLogClearStats> {
    ensure_storage_writable(repo_path)?;

    let mut connection = super::open_repo_connection(repo_path).map_err(map_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let schema = read_schema(&tx)?;
    let cleared_at = current_timestamp(&tx)?;
    if !schema.exists {
        return Ok(AiCallLogClearStats {
            deleted_count: 0,
            remaining_count: 0,
            cleared_at,
        });
    }
    schema.require_base_columns()?;

    let deleted_count = delete_rows(&tx, spec)?;
    let remaining_count = count_remaining_rows(&tx)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(AiCallLogClearStats {
        deleted_count,
        remaining_count,
        cleared_at,
    })
}

fn current_timestamp(tx: &rusqlite::Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT CAST(strftime('%s', 'now') AS INTEGER)", [], |row| {
        row.get(0)
    })
    .map_err(|error| CoreError::db(error.to_string()))
}

fn query_count(
    connection: &rusqlite::Connection,
    schema: &AiCallLogSchema,
    filter: &AiCallLogListFilter,
) -> CoreResult<i64> {
    let sql = format!(
        "SELECT COUNT(*)
         FROM ai_call_log log
         LEFT JOIN files ON files.id = log.file_id
         WHERE {}",
        where_clause(schema)
    );
    connection
        .query_row(&sql, filter_params(filter), |row| row.get(0))
        .map_err(|error| CoreError::db(error.to_string()))
}

fn query_rows(
    connection: &rusqlite::Connection,
    schema: &AiCallLogSchema,
    filter: &AiCallLogListFilter,
    pagination: &AiCallLogPagination,
) -> CoreResult<Vec<AiCallLogRow>> {
    let sql = format!(
        "SELECT
            log.id,
            log.occurred_at,
            log.feature,
            log.file_id,
            CASE
                WHEN files.current_name IS NULL THEN NULL
                ELSE replace(files.current_name, char(0), '')
            END,
            {},
            {},
            log.route,
            log.provider,
            log.model,
            log.status,
            {},
            log.sent_fields_json,
            {},
            log.privacy_rule_id,
            {},
            {},
            log.result_summary,
            log.error_code
         FROM ai_call_log log
         LEFT JOIN files ON files.id = log.file_id
         WHERE {}
         ORDER BY log.occurred_at DESC, log.id DESC
         LIMIT ?7 OFFSET ?8",
        schema.expr_or("batch_id", "NULL"),
        schema.expr_or("scope", "NULL"),
        schema.expr_or("duration_ms", "NULL"),
        schema.expr_or(
            "privacy_rules_checked",
            "CASE WHEN log.privacy_rule_id IS NULL THEN 0 ELSE 1 END",
        ),
        schema.expr_or("privacy_rule_name", "NULL"),
        schema.expr_or("matched_field_type", "NULL"),
        where_clause(schema)
    );
    let mut statement = connection
        .prepare(&sql)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let params = row_params(filter, pagination);
    let mut rows = statement
        .query(params_from_iter(params.iter()))
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut result = Vec::new();
    while let Some(row) = rows
        .next()
        .map_err(|error| CoreError::db(error.to_string()))?
    {
        result.push(row_from_sql(row)?);
    }
    Ok(result)
}

fn row_from_sql(row: &rusqlite::Row<'_>) -> CoreResult<AiCallLogRow> {
    Ok(AiCallLogRow {
        id: read_column(row, 0)?,
        occurred_at: read_column(row, 1)?,
        feature: read_column(row, 2)?,
        file_id: read_column(row, 3)?,
        file_display_name: read_column(row, 4)?,
        batch_id: read_column(row, 5)?,
        scope: read_column(row, 6)?,
        route: read_column(row, 7)?,
        provider_name: read_column(row, 8)?,
        model_name: read_column(row, 9)?,
        status: read_column(row, 10)?,
        duration_ms: read_column(row, 11)?,
        sent_fields_json: read_column(row, 12)?,
        privacy_rules_checked: db_to_bool(read_column(row, 13)?)?,
        privacy_rule_id: read_column(row, 14)?,
        privacy_rule_name: read_column(row, 15)?,
        matched_field_type: read_column(row, 16)?,
        result_summary: read_column(row, 17)?,
        error_code: read_column(row, 18)?,
    })
}

fn read_column<T: rusqlite::types::FromSql>(
    row: &rusqlite::Row<'_>,
    index: usize,
) -> CoreResult<T> {
    row.get(index)
        .map_err(|error| CoreError::db(error.to_string()))
}

fn where_clause(schema: &AiCallLogSchema) -> String {
    let searchable_scope = schema.expr_or("scope", "NULL");
    format!(
        "(?1 IS NULL OR log.feature = ?1)
         AND (?2 IS NULL OR log.route = ?2)
         AND (?3 IS NULL OR log.status = ?3)
         AND (?4 IS NULL OR log.occurred_at >= ?4)
         AND (?5 IS NULL OR log.occurred_at < ?5)
         AND (
            ?6 IS NULL
            OR lower(coalesce(files.current_name, '')) LIKE ?6 ESCAPE '\\'
            OR lower(coalesce(log.provider, '')) LIKE ?6 ESCAPE '\\'
            OR lower(coalesce(log.model, '')) LIKE ?6 ESCAPE '\\'
            OR lower(coalesce(log.error_code, '')) LIKE ?6 ESCAPE '\\'
            OR lower(coalesce({searchable_scope}, '')) LIKE ?6 ESCAPE '\\'
         )"
    )
}

fn filter_params(filter: &AiCallLogListFilter) -> [&dyn rusqlite::ToSql; 6] {
    [
        &filter.feature,
        &filter.route,
        &filter.status,
        &filter.occurred_after,
        &filter.occurred_before,
        &filter.search_pattern,
    ]
}

fn row_params<'a>(
    filter: &'a AiCallLogListFilter,
    pagination: &'a AiCallLogPagination,
) -> [&'a dyn rusqlite::ToSql; 8] {
    [
        &filter.feature,
        &filter.route,
        &filter.status,
        &filter.occurred_after,
        &filter.occurred_before,
        &filter.search_pattern,
        &pagination.limit,
        &pagination.offset,
    ]
}

fn delete_rows(tx: &rusqlite::Transaction<'_>, spec: AiCallLogClearSpec) -> CoreResult<i64> {
    let deleted = match spec {
        AiCallLogClearSpec::All => tx
            .execute("DELETE FROM ai_call_log", [])
            .map_err(|error| CoreError::db(error.to_string()))?,
        AiCallLogClearSpec::OlderThan(cutoff) => tx
            .execute(
                "DELETE FROM ai_call_log WHERE occurred_at < ?1",
                params![cutoff],
            )
            .map_err(|error| CoreError::db(error.to_string()))?,
        AiCallLogClearSpec::SelectedEntries(entry_ids) => {
            let placeholders = (1..=entry_ids.len())
                .map(|index| format!("?{index}"))
                .collect::<Vec<_>>()
                .join(", ");
            let sql = format!("DELETE FROM ai_call_log WHERE id IN ({placeholders})");
            tx.execute(&sql, params_from_iter(entry_ids.iter()))
                .map_err(|error| CoreError::db(error.to_string()))?
        }
    };
    i64::try_from(deleted).map_err(|_| CoreError::db("AI call log delete count overflow"))
}

fn count_remaining_rows(tx: &rusqlite::Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| row.get(0))
        .map_err(|error| CoreError::db(error.to_string()))
}
