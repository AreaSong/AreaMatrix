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
    repo_scan, CoreError, CoreResult, DiagnosticsSnapshot, ReindexReport, RepairOptions,
    RepairReport,
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
    let snapshot = if options.preserve_diagnostics_snapshot {
        Some(create_diagnostics_snapshot(repo_path.clone())?)
    } else {
        None
    };
    let repo = diagnostics_repo_path(&repo_path)?;
    verify_metadata_health(&repo)?;

    let reindex_report = if options.full_rescan {
        reindex_from_filesystem(repo_path)?
    } else {
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
