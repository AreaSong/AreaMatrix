use std::{
    fs::File,
    io::Read,
    path::{Path, PathBuf},
};

use rusqlite::{Connection, OpenFlags};

use crate::{CoreError, CoreResult};

use super::schema::run_schema_migrations;

pub(crate) const AREA_MATRIX_DIR: &str = ".areamatrix";
pub(crate) const INDEX_DB_FILE: &str = "index.db";
const SQLITE_HEADER: &[u8; 16] = b"SQLite format 3\0";

pub(crate) fn ensure_initialized(repo_path: &Path) -> CoreResult<()> {
    if path_exists(&db_path(repo_path))? {
        Ok(())
    } else {
        Err(CoreError::repo_not_initialized(
            "repository not initialized",
        ))
    }
}

pub(crate) fn ensure_initialized_readable(repo_path: &Path) -> CoreResult<()> {
    ensure_initialized(repo_path)?;
    let mut file =
        File::open(db_path(repo_path)).map_err(|error| CoreError::db(error.to_string()))?;
    let mut header = [0_u8; 16];
    file.read_exact(&mut header)
        .map_err(|error| CoreError::db(error.to_string()))?;
    if &header == SQLITE_HEADER {
        Ok(())
    } else {
        Err(CoreError::db("file is not a database"))
    }
}

pub(crate) fn open_repo_connection(repo_path: &Path) -> CoreResult<Connection> {
    ensure_initialized(repo_path)?;
    let mut connection =
        Connection::open(db_path(repo_path)).map_err(|error| CoreError::db(error.to_string()))?;
    configure_connection(&connection)?;
    run_schema_migrations(&mut connection, repo_path)?;
    Ok(connection)
}

pub(crate) fn open_repo_read_connection(repo_path: &Path) -> CoreResult<Connection> {
    ensure_initialized_readable(repo_path)?;
    let connection =
        Connection::open_with_flags(db_path(repo_path), OpenFlags::SQLITE_OPEN_READ_ONLY)
            .map_err(|error| CoreError::db(error.to_string()))?;
    configure_read_connection(&connection)?;
    Ok(connection)
}

pub(crate) fn configure_connection(connection: &Connection) -> CoreResult<()> {
    connection
        .execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA foreign_keys = ON;
             PRAGMA synchronous = NORMAL;
             PRAGMA temp_store = MEMORY;
             PRAGMA mmap_size = 268435456;
             PRAGMA cache_size = -65536;
             PRAGMA busy_timeout = 5000;",
        )
        .map_err(|error| CoreError::db(error.to_string()))
}

fn configure_read_connection(connection: &Connection) -> CoreResult<()> {
    connection
        .execute_batch(
            "PRAGMA query_only = ON;
             PRAGMA foreign_keys = ON;
             PRAGMA busy_timeout = 5000;",
        )
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn db_path(repo_path: &Path) -> PathBuf {
    repo_path.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE)
}

pub(crate) fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(|error| match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    })
}
