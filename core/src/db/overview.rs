use std::path::Path;

use rusqlite::{params, Row};

use crate::{CoreError, CoreResult};

use super::open_repo_connection;

pub(crate) struct OverviewFileRow {
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) size_bytes: i64,
    pub(crate) imported_at: i64,
}

pub(crate) struct OverviewNodeSummary {
    pub(crate) slug: String,
    pub(crate) file_count: i64,
    pub(crate) total_bytes: i64,
    pub(crate) last_imported_at: i64,
}

pub(crate) struct OverviewChangeRow {
    pub(crate) filename: String,
    pub(crate) category: String,
    pub(crate) action: String,
    pub(crate) occurred_at: i64,
}

pub(crate) fn list_overview_node_files(
    repo_path: &Path,
    node_slug: &str,
    limit: i64,
) -> CoreResult<Vec<OverviewFileRow>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT path, current_name, size_bytes, imported_at
             FROM files
             WHERE status = 'active' AND category = ?1
             ORDER BY imported_at DESC, id DESC
             LIMIT ?2",
        )
        .map_err(|_| CoreError::Db)?;
    let rows = statement
        .query_map(params![node_slug, normalize_limit(limit)], file_row_from_db)
        .map_err(|_| CoreError::Db)?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|_| CoreError::Db)
}

pub(crate) fn list_overview_node_summaries(
    repo_path: &Path,
) -> CoreResult<Vec<OverviewNodeSummary>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT category, COUNT(*), COALESCE(SUM(size_bytes), 0),
                    COALESCE(MAX(imported_at), 0)
             FROM files
             WHERE status = 'active'
             GROUP BY category
             ORDER BY category COLLATE NOCASE ASC",
        )
        .map_err(|_| CoreError::Db)?;
    let rows = statement
        .query_map([], summary_row_from_db)
        .map_err(|_| CoreError::Db)?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|_| CoreError::Db)
}

pub(crate) fn list_overview_recent_changes(
    repo_path: &Path,
    node_slug: Option<&str>,
    days: i64,
    limit: i64,
) -> CoreResult<Vec<OverviewChangeRow>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(NULLIF(f.current_name, ''), ''),
                    COALESCE(NULLIF(f.category, ''), ''),
                    cl.action,
                    cl.occurred_at
             FROM change_log cl
             LEFT JOIN files f ON f.id = cl.file_id
             WHERE (?1 IS NULL OR f.category = ?1)
               AND cl.occurred_at >= strftime('%s', 'now') - (?2 * 86400)
             ORDER BY cl.occurred_at DESC, cl.id DESC
             LIMIT ?3",
        )
        .map_err(|_| CoreError::Db)?;
    let rows = statement
        .query_map(
            params![node_slug, days.max(0), normalize_limit(limit)],
            change_row_from_db,
        )
        .map_err(|_| CoreError::Db)?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|_| CoreError::Db)
}

fn file_row_from_db(row: &Row<'_>) -> rusqlite::Result<OverviewFileRow> {
    Ok(OverviewFileRow {
        path: row.get(0)?,
        current_name: row.get(1)?,
        size_bytes: row.get(2)?,
        imported_at: row.get(3)?,
    })
}

fn summary_row_from_db(row: &Row<'_>) -> rusqlite::Result<OverviewNodeSummary> {
    Ok(OverviewNodeSummary {
        slug: row.get(0)?,
        file_count: row.get(1)?,
        total_bytes: row.get(2)?,
        last_imported_at: row.get(3)?,
    })
}

fn change_row_from_db(row: &Row<'_>) -> rusqlite::Result<OverviewChangeRow> {
    Ok(OverviewChangeRow {
        filename: row.get(0)?,
        category: row.get(1)?,
        action: row.get(2)?,
        occurred_at: row.get(3)?,
    })
}

fn normalize_limit(limit: i64) -> i64 {
    if limit <= 0 {
        100
    } else {
        limit.min(1000)
    }
}
