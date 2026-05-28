use std::collections::HashSet;

use rusqlite::OptionalExtension;

use crate::{CoreError, CoreResult};

use super::helpers::optional_column_definitions;

pub(super) struct AiCallLogSchema {
    pub(super) exists: bool,
    columns: HashSet<String>,
}

impl AiCallLogSchema {
    pub(super) fn require_base_columns(&self) -> CoreResult<()> {
        for column in [
            "id",
            "feature",
            "file_id",
            "route",
            "provider",
            "model",
            "status",
            "sent_fields_json",
            "privacy_rule_id",
            "result_summary",
            "error_code",
            "occurred_at",
        ] {
            if !self.columns.contains(column) {
                return Err(CoreError::db("AI call log schema is invalid"));
            }
        }
        Ok(())
    }

    pub(super) fn expr_or(&self, column: &str, fallback: &str) -> String {
        if self.columns.contains(column) {
            format!("log.{column}")
        } else {
            fallback.to_owned()
        }
    }
}

pub(super) fn ensure_ai_call_log_schema(tx: &rusqlite::Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS ai_call_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            feature TEXT NOT NULL,
            file_id INTEGER,
            batch_id TEXT,
            scope TEXT,
            route TEXT,
            provider TEXT,
            model TEXT,
            status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'skipped', 'unavailable')),
            duration_ms INTEGER,
            sent_fields_json TEXT NOT NULL,
            privacy_rules_checked INTEGER NOT NULL DEFAULT 0
              CHECK (privacy_rules_checked IN (0, 1)),
            privacy_rule_id TEXT,
            privacy_rule_name TEXT,
            matched_field_type TEXT,
            result_summary TEXT NOT NULL,
            error_code TEXT,
            occurred_at INTEGER NOT NULL,
            FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL
         );
         CREATE INDEX IF NOT EXISTS idx_ai_call_log_time ON ai_call_log(occurred_at DESC);
         CREATE INDEX IF NOT EXISTS idx_ai_call_log_feature_time
           ON ai_call_log(feature, occurred_at DESC);",
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_optional_columns(tx)
}

fn ensure_optional_columns(tx: &rusqlite::Transaction<'_>) -> CoreResult<()> {
    let schema = read_schema(tx)?;
    for (name, definition) in optional_column_definitions() {
        if schema.columns.contains(name) {
            continue;
        }
        tx.execute(
            &format!("ALTER TABLE ai_call_log ADD COLUMN {definition}"),
            [],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    }
    Ok(())
}

pub(super) fn read_schema(connection: &rusqlite::Connection) -> CoreResult<AiCallLogSchema> {
    let exists = connection
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ai_call_log'",
            [],
            |_| Ok(true),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .unwrap_or(false);
    let mut columns = HashSet::new();
    if exists {
        let mut statement = connection
            .prepare("PRAGMA table_info(ai_call_log)")
            .map_err(|error| CoreError::db(error.to_string()))?;
        let rows = statement
            .query_map([], |row| row.get::<_, String>(1))
            .map_err(|error| CoreError::db(error.to_string()))?;
        for row in rows {
            columns.insert(row.map_err(|error| CoreError::db(error.to_string()))?);
        }
    }
    Ok(AiCallLogSchema { exists, columns })
}
