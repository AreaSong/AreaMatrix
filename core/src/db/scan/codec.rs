use rusqlite::{types::Type, Row};

use crate::{ScanSession, ScanSessionKind, ScanSessionStatus};

pub(super) fn scan_session_from_row(row: &Row<'_>) -> rusqlite::Result<ScanSession> {
    let kind: String = row.get(1)?;
    let status: String = row.get(2)?;
    let errors_json: String = row.get(14)?;
    let errors = serde_json::from_str(&errors_json).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(14, Type::Text, Box::new(error))
    })?;
    Ok(ScanSession {
        id: row.get(0)?,
        kind: kind_from_db(&kind)?,
        status: status_from_db(&status)?,
        last_path: row.get(3)?,
        inserted: row.get(4)?,
        updated: row.get(5)?,
        missing: row.get(6)?,
        conflicts: row.get(7)?,
        unreadable: row.get(8)?,
        unknown: row.get(9)?,
        skipped: row.get(10)?,
        started_at: row.get(11)?,
        updated_at: row.get(12)?,
        finished_at: row.get(13)?,
        errors,
    })
}

pub(super) fn kind_to_db(kind: &ScanSessionKind) -> &'static str {
    match kind {
        ScanSessionKind::Adopt => "adopt",
        ScanSessionKind::Reindex => "reindex",
    }
}

fn kind_from_db(value: &str) -> rusqlite::Result<ScanSessionKind> {
    match value {
        "adopt" | "Adopt" => Ok(ScanSessionKind::Adopt),
        "reindex" | "Reindex" => Ok(ScanSessionKind::Reindex),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}

pub(super) fn status_to_db(status: &ScanSessionStatus) -> &'static str {
    match status {
        ScanSessionStatus::Running => "running",
        ScanSessionStatus::Completed => "completed",
        ScanSessionStatus::Paused => "paused",
        ScanSessionStatus::Failed => "failed",
        ScanSessionStatus::Interrupted => "interrupted",
    }
}

fn status_from_db(value: &str) -> rusqlite::Result<ScanSessionStatus> {
    match value {
        "running" | "Running" => Ok(ScanSessionStatus::Running),
        "completed" | "Completed" => Ok(ScanSessionStatus::Completed),
        "paused" | "Paused" => Ok(ScanSessionStatus::Paused),
        "failed" | "Failed" => Ok(ScanSessionStatus::Failed),
        "interrupted" | "Interrupted" => Ok(ScanSessionStatus::Interrupted),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}
