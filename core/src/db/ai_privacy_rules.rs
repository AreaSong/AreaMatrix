//! Repository config-table storage for C3-09 AI privacy metadata.

use std::path::Path;

use rusqlite::{params, OptionalExtension};

use crate::{CoreError, CoreResult};

const AI_PRIVACY_RULES_KEY: &str = "ai_privacy_rules";

pub(crate) struct AiPrivacyRulesRecord {
    pub(crate) serialized: Option<String>,
    pub(crate) updated_at: Option<i64>,
}

pub(crate) fn load_ai_privacy_rules_record(repo_path: &Path) -> CoreResult<AiPrivacyRulesRecord> {
    let db_path = super::db_path(repo_path);
    if !super::path_exists(&db_path)? {
        return Ok(AiPrivacyRulesRecord {
            serialized: None,
            updated_at: None,
        });
    }

    let connection = super::open_repo_connection(repo_path)?;
    let record = connection
        .query_row(
            "SELECT value, updated_at FROM repo_config WHERE key = ?1",
            params![AI_PRIVACY_RULES_KEY],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;

    Ok(AiPrivacyRulesRecord {
        serialized: record.as_ref().map(|(value, _)| value).cloned(),
        updated_at: record.map(|(_, updated_at)| updated_at),
    })
}

pub(crate) fn update_ai_privacy_rules_record(
    repo_path: &Path,
    serialized_rules: &str,
) -> CoreResult<i64> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let updated_at = current_timestamp(&tx)?;

    tx.execute(
        "INSERT INTO repo_config (key, value, updated_at) \
         VALUES (?1, ?2, ?3) \
         ON CONFLICT(key) DO UPDATE SET \
         value = excluded.value, updated_at = excluded.updated_at",
        params![AI_PRIVACY_RULES_KEY, serialized_rules, updated_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;

    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(updated_at)
}

fn current_timestamp(tx: &rusqlite::Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT CAST(strftime('%s', 'now') AS INTEGER)", [], |row| {
        row.get(0)
    })
    .map_err(|error| CoreError::db(error.to_string()))
}
