use rusqlite::params;

use crate::{CoreError, CoreResult, StorageMode};

use super::{open_repo_connection, storage_mode_from_db};

pub(crate) struct StagingFileRow {
    pub(crate) id: i64,
    pub(crate) path: String,
    pub(crate) storage_mode: StorageMode,
    pub(crate) source_path: Option<String>,
}

pub(crate) fn list_staging_file_rows(
    repo_path: &std::path::Path,
) -> CoreResult<Vec<StagingFileRow>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT id, path, storage_mode, source_path
             FROM files
             WHERE status = 'staging'
             ORDER BY id ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| {
            Ok(StagingFileRow {
                id: row.get(0)?,
                path: row.get(1)?,
                storage_mode: storage_mode_from_db(&row.get::<_, String>(2)?)
                    .map_err(|_| rusqlite::Error::InvalidQuery)?,
                source_path: row.get(3)?,
            })
        })
        .map_err(|error| CoreError::db(error.to_string()))?;

    let mut staging_rows = Vec::new();
    for row in rows {
        staging_rows.push(row.map_err(|error| CoreError::db(error.to_string()))?);
    }
    Ok(staging_rows)
}

pub(crate) fn list_protected_staging_paths(repo_path: &std::path::Path) -> CoreResult<Vec<String>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT path
             FROM files
             WHERE status != 'staging'
               AND path LIKE '.areamatrix/staging/%'",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|error| CoreError::db(error.to_string()))?;

    let mut paths = Vec::new();
    for row in rows {
        paths.push(row.map_err(|error| CoreError::db(error.to_string()))?);
    }
    Ok(paths)
}

pub(crate) fn delete_staging_file_row(repo_path: &std::path::Path, file_id: i64) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    let changed = connection
        .execute(
            "DELETE FROM files WHERE id = ?1 AND status = 'staging'",
            params![file_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::db("database error"))
    }
}
