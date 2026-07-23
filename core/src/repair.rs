//! metadata repair and diagnostics helpers.

use std::{
    fs::{self, OpenOptions},
    io::{self, BufReader, BufWriter, Read, Write},
    path::{Path, PathBuf},
};

use chrono::Utc;
use rusqlite::{params, Connection, OpenFlags, OptionalExtension, TransactionBehavior};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    config, db, repo_init, repo_scan, CoreError, CoreResult, DiagnosticsSnapshot, OverviewOutput,
    ReindexReport, RepairMetadataLocaleState, RepairMetadataOutcome, RepairMetadataPreflight,
    RepairOptions, RepairReport, RepositoryLocalePolicySnapshot, RepositoryLocalePolicyState,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const DIAGNOSTICS_DIR: &str = "diagnostics";
const INDEX_DB_FILE: &str = "index.db";
const COPY_BUFFER_BYTES: usize = 64 * 1024;

pub(crate) fn reindex_from_filesystem(repo_path: String) -> CoreResult<ReindexReport> {
    repo_scan::reindex_from_filesystem(repo_path)
}

pub(crate) fn preflight_repair_metadata(
    repo_path: String,
) -> CoreResult<RepairMetadataPreflight> {
    let repo = repair_repo_path(&repo_path)?;
    observe_repair_metadata(&repo)
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
    let repo = repair_repo_path(&repo_path)?;
    let observed = observe_repair_metadata(&repo)?;
    if options.preflight_token.is_empty() || options.preflight_token != observed.preflight_token {
        return Err(CoreError::conflict(repo_path));
    }
    let policy = validate_repair_policy(&observed, &options.repository_locale_policy)?;
    let database_exists = metadata_database_exists(&repo)?;
    let snapshot = if options.preserve_diagnostics_snapshot && database_exists {
        Some(create_diagnostics_snapshot(repo_path.clone())?)
    } else {
        None
    };

    let outcome = match observed.locale_state {
        RepairMetadataLocaleState::Healthy => {
            ensure_preflight_token(&repo, &observed.preflight_token)?;
            RepairMetadataOutcome::Verified
        }
        RepairMetadataLocaleState::MetadataAbsent => {
            ensure_preflight_token(&repo, &observed.preflight_token)?;
            initialize_missing_metadata(&repo, &repo_path, &policy)?;
            RepairMetadataOutcome::Initialized
        }
        RepairMetadataLocaleState::DatabaseMissing => {
            rebuild_index_db(&repo, &repo_path, &policy, &observed.preflight_token)?;
            RepairMetadataOutcome::Initialized
        }
        RepairMetadataLocaleState::DatabaseCorrupt => {
            rebuild_index_db(&repo, &repo_path, &policy, &observed.preflight_token)?;
            RepairMetadataOutcome::Rebuilt
        }
        RepairMetadataLocaleState::LocaleMissing
        | RepairMetadataLocaleState::LocaleUnsupported => {
            ensure_preflight_token(&repo, &observed.preflight_token)?;
            repair_repository_locale(&repo, &observed, &policy)?;
            RepairMetadataOutcome::Rebuilt
        }
    };
    verify_repair_result(&repo, &policy)?;

    Ok(RepairReport {
        diagnostics_snapshot_path: snapshot.map(|snapshot| snapshot.snapshot_path),
        outcome,
    })
}

fn initialize_missing_metadata(
    repo: &Path,
    repo_path: &str,
    repository_locale_policy: &str,
) -> CoreResult<()> {
    let area_matrix = repo.join(AREA_MATRIX_DIR);
    match fs::symlink_metadata(&area_matrix) {
        Ok(_) => Err(CoreError::conflict(repo_path.to_owned())),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            repo_init::initialize_metadata_for_repair(repo_path, repository_locale_policy)
        }
        Err(error) => Err(map_io_error(error)),
    }
}

fn rebuild_index_db(
    repo: &Path,
    repo_path: &str,
    repository_locale_policy: &str,
    expected_preflight_token: &str,
) -> CoreResult<()> {
    let area_matrix = repo.join(AREA_MATRIX_DIR);
    let temp_db = area_matrix.join(format!("{INDEX_DB_FILE}.repair-{}", Uuid::new_v4()));
    let result = build_replacement_index_db(&temp_db, repo_path, repository_locale_policy)
        .and_then(|()| ensure_preflight_token(repo, expected_preflight_token))
        .and_then(|()| install_replacement_index_db(&area_matrix, &temp_db));
    if result.is_err() {
        cleanup_temp_sqlite_files(&temp_db);
    }
    result
}

fn observe_repair_metadata(repo: &Path) -> CoreResult<RepairMetadataPreflight> {
    let area_matrix = repo.join(AREA_MATRIX_DIR);
    let state = match fs::symlink_metadata(&area_matrix) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => {
            return Err(CoreError::repo_not_initialized(
                "repository not initialized",
            ));
        }
        Ok(_) => inspect_repair_database(&area_matrix.join(INDEX_DB_FILE))?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            RepairObservation::without_locale(RepairMetadataLocaleState::MetadataAbsent)
        }
        Err(error) => return Err(map_initialized_metadata_error(error)),
    };
    state.into_preflight(repo)
}

#[derive(Debug)]
struct RepairObservation {
    locale_state: RepairMetadataLocaleState,
    repository_locale_policy: Option<String>,
    unsupported_locale: Option<String>,
}

impl RepairObservation {
    fn without_locale(locale_state: RepairMetadataLocaleState) -> Self {
        Self {
            locale_state,
            repository_locale_policy: None,
            unsupported_locale: None,
        }
    }

    fn into_preflight(self, repo: &Path) -> CoreResult<RepairMetadataPreflight> {
        let preflight_token = repair_preflight_token(
            repo,
            &self.locale_state,
            self.repository_locale_policy.as_deref(),
            self.unsupported_locale.as_deref(),
        )?;
        let requires_explicit_locale_selection =
            self.locale_state != RepairMetadataLocaleState::Healthy;
        Ok(RepairMetadataPreflight {
            locale_state: self.locale_state,
            repository_locale_policy: self.repository_locale_policy,
            unsupported_locale: self.unsupported_locale,
            requires_explicit_locale_selection,
            preflight_token,
        })
    }
}

fn inspect_repair_database(index_db: &Path) -> CoreResult<RepairObservation> {
    match fs::symlink_metadata(index_db) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            return Err(CoreError::repo_not_initialized(
                "repository not initialized",
            ));
        }
        Ok(_) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(RepairObservation::without_locale(
                RepairMetadataLocaleState::DatabaseMissing,
            ));
        }
        Err(error) => return Err(map_initialized_metadata_error(error)),
    }

    let raw_locale = match read_repair_locale(index_db) {
        Ok(raw_locale) => raw_locale,
        Err(CoreError::Db { .. }) => {
            return Ok(RepairObservation::without_locale(
                RepairMetadataLocaleState::DatabaseCorrupt,
            ));
        }
        Err(error) => return Err(error),
    };
    let Some(raw_locale) = raw_locale else {
        return Ok(RepairObservation::without_locale(
            RepairMetadataLocaleState::LocaleMissing,
        ));
    };
    if raw_locale.trim().is_empty() {
        return Ok(RepairObservation::without_locale(
            RepairMetadataLocaleState::LocaleMissing,
        ));
    }
    let snapshot = RepositoryLocalePolicySnapshot::from_raw(raw_locale);
    if snapshot.state == RepositoryLocalePolicyState::Unsupported {
        return Ok(RepairObservation {
            locale_state: RepairMetadataLocaleState::LocaleUnsupported,
            repository_locale_policy: None,
            unsupported_locale: Some(snapshot.raw_value),
        });
    }
    Ok(RepairObservation {
        locale_state: RepairMetadataLocaleState::Healthy,
        repository_locale_policy: Some(snapshot.raw_value),
        unsupported_locale: None,
    })
}

fn read_repair_locale(index_db: &Path) -> CoreResult<Option<String>> {
    fs::File::open(index_db).map_err(map_initialized_metadata_error)?;
    let connection = open_repair_read_connection(index_db)?;
    if !repair_database_is_healthy(&connection) {
        return Err(CoreError::db("database repair is required"));
    }
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'locale'",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|_| CoreError::db("database repair is required"))
}

fn open_repair_read_connection(index_db: &Path) -> CoreResult<Connection> {
    let connection = Connection::open_with_flags(index_db, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|error| CoreError::db(error.to_string()))?;
    connection
        .execute_batch(
            "PRAGMA query_only = ON;
             PRAGMA foreign_keys = ON;
             PRAGMA busy_timeout = 5000;",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(connection)
}

fn repair_database_is_healthy(connection: &Connection) -> bool {
    let integrity = connection.query_row("PRAGMA integrity_check", [], |row| {
        row.get::<_, String>(0)
    });
    if !matches!(integrity, Ok(value) if value == "ok") {
        return false;
    }
    let has_repo_config = connection.query_row(
        "SELECT EXISTS(
           SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'repo_config'
         )",
        [],
        |row| row.get::<_, bool>(0),
    );
    if !matches!(has_repo_config, Ok(true)) {
        return false;
    }
    let foreign_key_issue = connection.query_row(
        "SELECT EXISTS(SELECT 1 FROM pragma_foreign_key_check)",
        [],
        |row| row.get::<_, bool>(0),
    );
    matches!(foreign_key_issue, Ok(false))
}

fn validate_repair_policy(
    preflight: &RepairMetadataPreflight,
    requested_policy: &str,
) -> CoreResult<String> {
    if preflight.locale_state == RepairMetadataLocaleState::Healthy {
        return match preflight.repository_locale_policy.as_deref() {
            Some(raw_policy) if raw_policy == requested_policy => Ok(raw_policy.to_owned()),
            _ => Err(CoreError::config("configuration error")),
        };
    }
    match requested_policy {
        "system" | "zh-Hans" | "en" => Ok(requested_policy.to_owned()),
        _ => Err(CoreError::config("configuration error")),
    }
}

fn ensure_preflight_token(repo: &Path, expected_token: &str) -> CoreResult<()> {
    let current = observe_repair_metadata(repo)?;
    if current.preflight_token == expected_token {
        Ok(())
    } else {
        Err(CoreError::conflict(repo.to_string_lossy().into_owned()))
    }
}

fn repair_repository_locale(
    repo: &Path,
    preflight: &RepairMetadataPreflight,
    policy: &str,
) -> CoreResult<()> {
    db::ensure_config_storage_writable(repo)?;
    let index_db = repo.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE);
    let mut connection = Connection::open_with_flags(
        index_db,
        OpenFlags::SQLITE_OPEN_READ_WRITE,
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    connection
        .execute_batch("PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;")
        .map_err(|error| CoreError::db(error.to_string()))?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_locale_observation_matches(&tx, preflight, repo)?;
    let updated_at = Utc::now().timestamp();
    tx.execute(
        "INSERT INTO repo_config (key, value, updated_at) VALUES ('locale', ?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
        params![policy, updated_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    let changed = tx
        .execute(
            "UPDATE repo_config_revision SET revision = revision + 1 WHERE id = 1",
            [],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("repository configuration revision is missing"));
    }
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_locale_observation_matches(
    connection: &Connection,
    preflight: &RepairMetadataPreflight,
    repo: &Path,
) -> CoreResult<()> {
    let raw_locale: Option<String> = connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'locale'",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let matches = match preflight.locale_state {
        RepairMetadataLocaleState::LocaleMissing => {
            raw_locale.as_deref().is_none_or(|value| value.trim().is_empty())
        }
        RepairMetadataLocaleState::LocaleUnsupported => {
            raw_locale.as_deref() == preflight.unsupported_locale.as_deref()
        }
        _ => false,
    };
    if matches {
        Ok(())
    } else {
        Err(CoreError::conflict(repo.to_string_lossy().into_owned()))
    }
}

fn verify_repair_result(repo: &Path, expected_policy: &str) -> CoreResult<()> {
    let preflight = observe_repair_metadata(repo)?;
    if preflight.locale_state == RepairMetadataLocaleState::Healthy
        && preflight.repository_locale_policy.as_deref() == Some(expected_policy)
    {
        Ok(())
    } else {
        Err(CoreError::internal("internal error"))
    }
}

fn repair_preflight_token(
    repo: &Path,
    state: &RepairMetadataLocaleState,
    policy: Option<&str>,
    unsupported_locale: Option<&str>,
) -> CoreResult<String> {
    let mut hasher = Sha256::new();
    hasher.update(b"AreaMatrix repair metadata preflight v1\0");
    hash_token_field(&mut hasher, repo.to_string_lossy().as_bytes());
    hash_token_field(&mut hasher, repair_state_name(state).as_bytes());
    hash_token_field(&mut hasher, policy.unwrap_or_default().as_bytes());
    hash_token_field(&mut hasher, unsupported_locale.unwrap_or_default().as_bytes());
    let index_db = repo.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE);
    hash_optional_metadata_file(&mut hasher, b"index.db", &index_db)?;
    hash_optional_metadata_file(&mut hasher, b"index.db-wal", &sqlite_companion_path(&index_db, "-wal")?)?;
    hash_optional_metadata_file(&mut hasher, b"index.db-shm", &sqlite_companion_path(&index_db, "-shm")?)?;
    Ok(format!("{:x}", hasher.finalize()))
}

fn hash_token_field(hasher: &mut Sha256, value: &[u8]) {
    hasher.update(value.len().to_le_bytes());
    hasher.update(value);
}

fn hash_optional_metadata_file(
    hasher: &mut Sha256,
    label: &[u8],
    path: &Path,
) -> CoreResult<()> {
    hash_token_field(hasher, label);
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            return Err(CoreError::repo_not_initialized(
                "repository not initialized",
            ));
        }
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            hash_token_field(hasher, b"missing");
            return Ok(());
        }
        Err(error) => return Err(map_initialized_metadata_error(error)),
    };
    hash_token_field(hasher, b"present");
    hash_token_field(hasher, &metadata.len().to_le_bytes());
    let mut file = fs::File::open(path).map_err(map_initialized_metadata_error)?;
    let mut buffer = [0_u8; COPY_BUFFER_BYTES];
    loop {
        let read = file.read(&mut buffer).map_err(map_initialized_metadata_error)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(())
}

fn repair_state_name(state: &RepairMetadataLocaleState) -> &'static str {
    match state {
        RepairMetadataLocaleState::Healthy => "healthy",
        RepairMetadataLocaleState::MetadataAbsent => "metadata-absent",
        RepairMetadataLocaleState::DatabaseMissing => "database-missing",
        RepairMetadataLocaleState::DatabaseCorrupt => "database-corrupt",
        RepairMetadataLocaleState::LocaleMissing => "locale-missing",
        RepairMetadataLocaleState::LocaleUnsupported => "locale-unsupported",
    }
}

fn build_replacement_index_db(
    temp_db: &Path,
    repo_path: &str,
    repository_locale_policy: &str,
) -> CoreResult<()> {
    let mut repo_config =
        config::default_repo_config(repo_path.to_owned(), OverviewOutput::GeneratedOnly);
    repo_config.locale = repository_locale_policy.to_owned();
    db::initialize_repository_db(temp_db, &repo_config)?;
    checkpoint_replacement_db(temp_db)?;
    remove_sqlite_companions(temp_db)
}

fn install_replacement_index_db(area_matrix: &Path, temp_db: &Path) -> CoreResult<()> {
    let index_db = area_matrix.join(INDEX_DB_FILE);
    match fs::symlink_metadata(&index_db) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => Err(
            CoreError::repo_not_initialized("repository not initialized"),
        ),
        Ok(_) => install_replacement_for_existing_db(area_matrix, temp_db, &index_db),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            install_replacement_for_missing_db(area_matrix, temp_db, &index_db)
        }
        Err(error) => Err(map_io_error(error)),
    }
}

fn install_replacement_for_existing_db(
    area_matrix: &Path,
    temp_db: &Path,
    index_db: &Path,
) -> CoreResult<()> {
    let retired_db = area_matrix.join(format!("{INDEX_DB_FILE}.replaced-{}", Uuid::new_v4()));
    remove_sqlite_companions(index_db)?;
    fs::rename(index_db, &retired_db).map_err(map_io_error)?;

    match fs::rename(temp_db, index_db) {
        Ok(()) => {
            cleanup_temp_file(&retired_db);
            Ok(())
        }
        Err(error) => {
            restore_retired_index_db(&retired_db, index_db)?;
            Err(map_io_error(error))
        }
    }
}

fn install_replacement_for_missing_db(
    area_matrix: &Path,
    temp_db: &Path,
    index_db: &Path,
) -> CoreResult<()> {
    preserve_orphaned_sqlite_companions(area_matrix, index_db)?;
    fs::rename(temp_db, index_db).map_err(map_io_error)
}

fn preserve_orphaned_sqlite_companions(area_matrix: &Path, index_db: &Path) -> CoreResult<()> {
    let diagnostics_dir = area_matrix.join(DIAGNOSTICS_DIR);
    for suffix in ["-wal", "-shm"] {
        let source = sqlite_companion_path(index_db, suffix)?;
        if !source.try_exists().map_err(map_io_error)? {
            continue;
        }
        fs::create_dir_all(&diagnostics_dir).map_err(map_io_error)?;
        let destination = diagnostics_dir.join(format!(
            "orphaned-{INDEX_DB_FILE}-{}{suffix}",
            Uuid::new_v4()
        ));
        fs::rename(source, destination).map_err(map_io_error)?;
    }
    Ok(())
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
    let repo = repair_repo_path(repo_path)?;
    if !metadata_database_exists(&repo)? {
        return Err(CoreError::repo_not_initialized(
            "repository not initialized",
        ));
    }
    Ok(repo)
}

fn repair_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
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

    Ok(repo)
}

fn metadata_database_exists(repo: &Path) -> CoreResult<bool> {
    let area_matrix = repo.join(AREA_MATRIX_DIR);
    match fs::symlink_metadata(&area_matrix) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => {
            return Err(CoreError::repo_not_initialized(
                "repository not initialized",
            ));
        }
        Ok(_) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(map_initialized_metadata_error(error)),
    }

    match fs::symlink_metadata(area_matrix.join(INDEX_DB_FILE)) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => Err(
            CoreError::repo_not_initialized("repository not initialized"),
        ),
        Ok(_) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(map_initialized_metadata_error(error)),
    }
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
