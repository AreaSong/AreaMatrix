//! C1-26 metadata repair and diagnostics helpers.

use std::{
    fs::{self, OpenOptions},
    io::{self, BufReader, BufWriter, Write},
    path::{Path, PathBuf},
};

use chrono::Utc;
use rusqlite::Connection;
use uuid::Uuid;

use crate::{
    config, db, repo_scan, CoreError, CoreResult, DiagnosticsSnapshot, OverviewOutput,
    ReindexReport, RepairOptions, RepairReport,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const DIAGNOSTICS_DIR: &str = "diagnostics";
const INDEX_DB_FILE: &str = "index.db";
const COPY_BUFFER_BYTES: usize = 64 * 1024;

pub(crate) fn reindex_from_filesystem(repo_path: String) -> CoreResult<ReindexReport> {
    repo_scan::reindex_from_filesystem(repo_path)
}

pub(crate) fn create_diagnostics_snapshot(repo_path: String) -> CoreResult<DiagnosticsSnapshot> {
    let repo = diagnostics_repo_path(&repo_path)?;
    let created_at = Utc::now().timestamp();
    let diagnostics_dir = repo.join(AREA_MATRIX_DIR).join(DIAGNOSTICS_DIR);
    fs::create_dir_all(&diagnostics_dir).map_err(map_io_error)?;

    let snapshot_name = format!("index-{created_at}-{}.db", Uuid::new_v4());
    let snapshot_path = diagnostics_dir.join(&snapshot_name);
    let source_db = repo.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE);
    copy_to_new_file(&source_db, &snapshot_path)?;

    let mut warnings = Vec::new();
    copy_optional_companion(&source_db, &snapshot_path, "-wal", &mut warnings)?;
    copy_optional_companion(&source_db, &snapshot_path, "-shm", &mut warnings)?;

    let snapshot_path = repository_relative_path(&repo, &snapshot_path)?;
    if !snapshot_path.starts_with(".areamatrix/") {
        return Err(CoreError::internal("internal error"));
    }

    Ok(DiagnosticsSnapshot {
        snapshot_path,
        created_at,
        warnings,
    })
}

pub(crate) fn repair_metadata(
    repo_path: String,
    options: RepairOptions,
) -> CoreResult<RepairReport> {
    let mut snapshot = if options.preserve_diagnostics_snapshot {
        Some(create_diagnostics_snapshot(repo_path.clone())?)
    } else {
        None
    };
    let repo = diagnostics_repo_path(&repo_path)?;

    let reindex_report = if options.full_rescan {
        if let Some(repair_snapshot) =
            prepare_full_rescan_metadata(&repo, &repo_path, snapshot.is_some())?
        {
            snapshot = Some(repair_snapshot);
        }
        reindex_from_filesystem(repo_path)?
    } else {
        verify_metadata_health(&repo)?;
        ReindexReport {
            scan_session_id: None,
            inserted: 0,
            updated: 0,
            skipped: 0,
            errors: Vec::new(),
        }
    };

    Ok(RepairReport {
        scan_session_id: reindex_report.scan_session_id,
        diagnostics_snapshot_path: snapshot.map(|snapshot| snapshot.snapshot_path),
        inserted: reindex_report.inserted,
        updated: reindex_report.updated,
        skipped: reindex_report.skipped,
        errors: reindex_report.errors,
    })
}

fn prepare_full_rescan_metadata(
    repo: &Path,
    repo_path: &str,
    has_snapshot: bool,
) -> CoreResult<Option<DiagnosticsSnapshot>> {
    match verify_metadata_health(repo) {
        Ok(()) => Ok(None),
        Err(CoreError::Db { .. } | CoreError::Internal { .. }) => {
            let snapshot = if has_snapshot {
                None
            } else {
                Some(create_diagnostics_snapshot(repo_path.to_owned())?)
            };
            rebuild_index_db(repo, repo_path)?;
            Ok(snapshot)
        }
        Err(error) => Err(error),
    }
}

fn rebuild_index_db(repo: &Path, repo_path: &str) -> CoreResult<()> {
    let area_matrix = repo.join(AREA_MATRIX_DIR);
    let temp_db = area_matrix.join(format!("{INDEX_DB_FILE}.repair-{}", Uuid::new_v4()));
    let result = build_replacement_index_db(&temp_db, repo_path)
        .and_then(|()| install_replacement_index_db(&area_matrix, &temp_db));
    if result.is_err() {
        cleanup_temp_sqlite_files(&temp_db);
    }
    result
}

fn build_replacement_index_db(temp_db: &Path, repo_path: &str) -> CoreResult<()> {
    let repo_config =
        config::default_repo_config(repo_path.to_owned(), OverviewOutput::GeneratedOnly);
    db::initialize_repository_db(temp_db, &repo_config)?;
    checkpoint_replacement_db(temp_db)?;
    remove_sqlite_companions(temp_db)
}

fn install_replacement_index_db(area_matrix: &Path, temp_db: &Path) -> CoreResult<()> {
    let index_db = area_matrix.join(INDEX_DB_FILE);
    let retired_db = area_matrix.join(format!("{INDEX_DB_FILE}.replaced-{}", Uuid::new_v4()));
    remove_sqlite_companions(&index_db)?;
    fs::rename(&index_db, &retired_db).map_err(map_io_error)?;

    match fs::rename(temp_db, &index_db) {
        Ok(()) => {
            cleanup_temp_file(&retired_db);
            Ok(())
        }
        Err(error) => {
            restore_retired_index_db(&retired_db, &index_db)?;
            Err(map_io_error(error))
        }
    }
}

fn restore_retired_index_db(retired_db: &Path, index_db: &Path) -> CoreResult<()> {
    fs::rename(retired_db, index_db).map_err(map_io_error)
}

fn checkpoint_replacement_db(db_path: &Path) -> CoreResult<()> {
    let connection = Connection::open(db_path).map_err(|error| CoreError::db(error.to_string()))?;
    connection
        .execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")
        .map_err(|error| CoreError::db(error.to_string()))
}

fn remove_sqlite_companions(db_path: &Path) -> CoreResult<()> {
    for suffix in ["-wal", "-shm"] {
        remove_file_if_present(&sqlite_companion_path(db_path, suffix)?)?;
    }
    Ok(())
}

fn sqlite_companion_path(db_path: &Path, suffix: &str) -> CoreResult<PathBuf> {
    let file_name = db_path
        .file_name()
        .ok_or_else(|| CoreError::internal("internal error"))?
        .to_string_lossy();
    Ok(db_path.with_file_name(format!("{file_name}{suffix}")))
}

fn remove_file_if_present(path: &Path) -> CoreResult<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(map_io_error(error)),
    }
}

fn cleanup_temp_sqlite_files(temp_db: &Path) {
    cleanup_temp_file(temp_db);
    for suffix in ["-wal", "-shm"] {
        if let Ok(path) = sqlite_companion_path(temp_db, suffix) {
            cleanup_temp_file(&path);
        }
    }
}

fn cleanup_temp_file(path: &Path) {
    // Best-effort cleanup keeps the primary repair error visible to the caller.
    if matches!(path.try_exists(), Ok(true)) {
        let _ = fs::remove_file(path);
    }
}

fn diagnostics_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    let repo = PathBuf::from(repo_path);
    if is_inside_area_matrix(&repo) {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let metadata = fs::metadata(&repo).map_err(map_repo_metadata_error)?;
    if !metadata.is_dir() {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let area_matrix = repo.join(AREA_MATRIX_DIR);
    let metadata = fs::metadata(&area_matrix).map_err(map_initialized_metadata_error)?;
    if !metadata.is_dir() {
        return Err(CoreError::repo_not_initialized(
            "repository not initialized",
        ));
    }

    let db_metadata =
        fs::metadata(area_matrix.join(INDEX_DB_FILE)).map_err(map_initialized_metadata_error)?;
    if !db_metadata.is_file() {
        return Err(CoreError::repo_not_initialized(
            "repository not initialized",
        ));
    }
    Ok(repo)
}

fn verify_metadata_health(repo: &Path) -> CoreResult<()> {
    let connection = Connection::open(repo.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE))
        .map_err(|error| CoreError::db(error.to_string()))?;
    let integrity: String = connection
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .map_err(|error| CoreError::db(error.to_string()))?;
    if integrity != "ok" {
        return Err(CoreError::db("database error"));
    }

    let foreign_key_issues: i64 = connection
        .query_row("SELECT COUNT(*) FROM pragma_foreign_key_check", [], |row| {
            row.get(0)
        })
        .map_err(|error| CoreError::db(error.to_string()))?;
    if foreign_key_issues != 0 {
        return Err(CoreError::internal("internal error"));
    }
    Ok(())
}

fn copy_optional_companion(
    source_db: &Path,
    snapshot_path: &Path,
    suffix: &str,
    warnings: &mut Vec<String>,
) -> CoreResult<()> {
    let source = source_db.with_file_name(format!("{INDEX_DB_FILE}{suffix}"));
    match source.try_exists() {
        Ok(true) => {}
        Ok(false) => return Ok(()),
        Err(error) => return Err(map_io_error(error)),
    }

    let destination_name = snapshot_path
        .file_name()
        .ok_or_else(|| CoreError::internal("internal error"))?
        .to_string_lossy();
    let destination = snapshot_path.with_file_name(format!("{destination_name}{suffix}"));
    match copy_to_new_file(&source, &destination) {
        Ok(()) => Ok(()),
        Err(CoreError::FileNotFound { .. }) => {
            warnings.push(format!(
                "{INDEX_DB_FILE}{suffix} disappeared during snapshot"
            ));
            Ok(())
        }
        Err(error) => Err(error),
    }
}

fn copy_to_new_file(source: &Path, destination: &Path) -> CoreResult<()> {
    let source_file = fs::File::open(source).map_err(map_io_error)?;
    let destination_file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(destination)
        .map_err(map_io_error)?;
    let mut reader = BufReader::with_capacity(COPY_BUFFER_BYTES, source_file);
    let mut writer = BufWriter::with_capacity(COPY_BUFFER_BYTES, destination_file);
    io::copy(&mut reader, &mut writer).map_err(map_io_error)?;
    writer.flush().map_err(map_io_error)?;
    writer.get_ref().sync_all().map_err(map_io_error)
}

fn repository_relative_path(repo: &Path, path: &Path) -> CoreResult<String> {
    let relative = path
        .strip_prefix(repo)
        .map_err(|error| CoreError::internal(error.to_string()))?;
    Ok(relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/"))
}

fn is_inside_area_matrix(path: &Path) -> bool {
    path.components()
        .any(|component| component.as_os_str() == AREA_MATRIX_DIR)
}

fn map_repo_metadata_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::NotFound => CoreError::invalid_path("invalid path"),
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

fn map_initialized_metadata_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::NotFound => CoreError::repo_not_initialized("repository not initialized"),
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

fn map_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::AlreadyExists => CoreError::internal("internal error"),
        io::ErrorKind::NotFound => CoreError::file_not_found("missing file"),
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}
