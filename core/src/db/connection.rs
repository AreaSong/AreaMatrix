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
        Err(CoreError::db_corrupted("file is not a database"))
    }
}

pub(crate) fn open_repo_connection(repo_path: &Path) -> CoreResult<Connection> {
    ensure_initialized(repo_path)?;
    let mut connection = Connection::open(db_path(repo_path)).map_err(CoreError::from)?;
    configure_connection(&connection)?;
    run_schema_migrations(&mut connection, repo_path)?;
    Ok(connection)
}

pub(crate) fn open_repo_read_connection(repo_path: &Path) -> CoreResult<Connection> {
    ensure_initialized_readable(repo_path)?;
    let connection =
        Connection::open_with_flags(db_path(repo_path), OpenFlags::SQLITE_OPEN_READ_ONLY)
            .map_err(CoreError::from)?;
    configure_read_connection(&connection)?;
    Ok(connection)
}

pub(crate) fn open_repo_snapshot_read_connection(repo_path: &Path) -> CoreResult<Connection> {
    ensure_initialized_readable(repo_path)?;
    let database = db_path(repo_path);
    let wal_exists = sqlite_sidecar_exists(&database, "-wal")?;
    let shm_exists = sqlite_sidecar_exists(&database, "-shm")?;
    if wal_exists != shm_exists {
        return Err(CoreError::db("database sidecar state is incomplete"));
    }

    let connection = if wal_exists {
        Connection::open_with_flags(&database, OpenFlags::SQLITE_OPEN_READ_ONLY)
    } else {
        Connection::open_with_flags(
            sqlite_immutable_uri(&database),
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI,
        )
    }
    .map_err(CoreError::from)?;
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
        .map_err(CoreError::from)
}

fn configure_read_connection(connection: &Connection) -> CoreResult<()> {
    connection
        .execute_batch(
            "PRAGMA query_only = ON;
             PRAGMA foreign_keys = ON;
             PRAGMA busy_timeout = 5000;",
        )
        .map_err(CoreError::from)
}

fn sqlite_sidecar_exists(database: &Path, suffix: &str) -> CoreResult<bool> {
    let file_name = database
        .file_name()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?
        .to_string_lossy();
    let sidecar = database.with_file_name(format!("{file_name}{suffix}"));
    match sidecar.symlink_metadata() {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            Err(CoreError::db("database sidecar state is invalid"))
        }
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(CoreError::from(error)),
    }
}

fn sqlite_immutable_uri(path: &Path) -> String {
    let mut encoded = String::with_capacity(path.as_os_str().len() + 24);
    for byte in path.to_string_lossy().bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'-' | b'_' | b'.' | b'~') {
            encoded.push(char::from(byte));
        } else {
            encoded.push_str(&format!("%{byte:02X}"));
        }
    }
    format!("file:{encoded}?immutable=1")
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
