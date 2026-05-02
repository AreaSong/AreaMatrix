use std::{
    fs,
    path::{Path, PathBuf},
};

use serde_json::json;

use crate::{
    classify, db, CoreError, CoreResult, FileEntry, FileOrigin, ImportDestination, ImportOptions,
    StorageMode,
};

use super::{
    dedup,
    destination::{ImportDestinationPlan, ReplacementFileGuard, ReplacementPlan},
    hash,
    safe_move::{move_source_to_staging, FinalFileGuard, StagingFileGuard},
    validate,
};

pub(crate) fn import_file(
    repo_path: String,
    source_path: String,
    options: ImportOptions,
) -> CoreResult<FileEntry> {
    let prepared = prepare_import(repo_path, source_path, options)?;
    if matches!(prepared.options.mode, StorageMode::Indexed) {
        return import_indexed_file(prepared);
    }

    let mut staged = stage_source(&prepared)?;
    let duplicate_resolution = check_duplicate(&prepared, &staged.hash_sha256)?;
    let destination = ImportDestinationPlan::prepare(
        &prepared.repo,
        &prepared.target.relative_dir,
        &prepared.target.category,
        &prepared.target_filename,
        duplicate_resolution,
    )?;
    let file_id = insert_staging_row(&prepared, &staged, &destination)?;
    let mut db_guard = DbStagingRowGuard::new(prepared.repo.clone(), file_id);

    let mut replacement_guard = commit_filesystem(&staged, &destination)?;
    staged.staging_guard.disarm();
    let mut final_guard = FinalFileGuard::new(
        &prepared.options.mode,
        destination.final_path.clone(),
        prepared.source.clone(),
    );

    promote_import(&prepared, file_id, &destination)?;
    db_guard.disarm();
    final_guard.disarm();
    if let Some(guard) = &mut replacement_guard {
        guard.disarm();
    }
    destination.disarm();
    db::get_active_file_by_id(&prepared.repo, file_id)
}

struct PreparedImport {
    repo: PathBuf,
    source: PathBuf,
    original_name: String,
    target_filename: String,
    target: ImportTarget,
    options: ImportOptions,
}

impl PreparedImport {
    fn new(repo_path: String, source_path: String, options: ImportOptions) -> CoreResult<Self> {
        let repo = validate_repo_path(&repo_path)?;
        db::ensure_initialized(&repo)?;
        let source = PathBuf::from(source_path);
        validate::source_file(&source)?;

        let original_name = source_filename(&source)?;
        let target_filename = options
            .override_filename
            .clone()
            .unwrap_or_else(|| original_name.clone());
        validate::filename(&target_filename)?;

        let target = resolve_import_target(&repo, &repo_path, &original_name, &options)?;
        Ok(Self {
            repo,
            source,
            original_name,
            target_filename,
            target,
            options,
        })
    }
}

fn prepare_import(
    repo_path: String,
    source_path: String,
    options: ImportOptions,
) -> CoreResult<PreparedImport> {
    PreparedImport::new(repo_path, source_path, options)
}

struct StagedImport {
    staging_guard: StagingFileGuard,
    hash_sha256: String,
    size_bytes: i64,
}

fn stage_source(prepared: &PreparedImport) -> CoreResult<StagedImport> {
    let staging_guard = match prepared.options.mode {
        StorageMode::Copied => StagingFileGuard::create_for_copy(&prepared.repo)?,
        StorageMode::Moved => {
            StagingFileGuard::create_for_move(&prepared.repo, prepared.source.clone())?
        }
        StorageMode::Indexed => return Err(CoreError::Internal),
    };
    let hashed_copy = match prepared.options.mode {
        StorageMode::Copied => hash::copy_and_hash(&prepared.source, staging_guard.path())?,
        StorageMode::Moved => {
            move_source_to_staging(&prepared.source, staging_guard.path())?;
            hash::hash_file(staging_guard.path())?
        }
        StorageMode::Indexed => return Err(CoreError::Internal),
    };
    Ok(StagedImport {
        staging_guard,
        hash_sha256: hashed_copy.hash_sha256,
        size_bytes: hashed_copy.size_bytes,
    })
}

fn check_duplicate(
    prepared: &PreparedImport,
    hash_sha256: &str,
) -> CoreResult<dedup::DuplicateResolution> {
    let existing = db::find_active_file_by_hash(&prepared.repo, hash_sha256)?;
    dedup::resolve_duplicate(&prepared.options.duplicate_strategy, existing)
}

fn import_indexed_file(prepared: PreparedImport) -> CoreResult<FileEntry> {
    let fingerprint = hash::hash_file(&prepared.source)?;
    let duplicate_resolution = check_duplicate(&prepared, &fingerprint.hash_sha256)?;

    let file_id = match duplicate_resolution {
        dedup::DuplicateResolution::Overwrite(existing) => {
            insert_replacing_indexed_row(&prepared, &fingerprint, existing)?
        }
        dedup::DuplicateResolution::NoDuplicate | dedup::DuplicateResolution::KeepBoth => {
            insert_indexed_row(&prepared, &fingerprint)?
        }
    };
    db::get_active_file_by_id(&prepared.repo, file_id)
}

fn insert_staging_row(
    prepared: &PreparedImport,
    staged: &StagedImport,
    destination: &ImportDestinationPlan,
) -> CoreResult<i64> {
    let imported_at = chrono::Utc::now().timestamp();
    db::insert_import_staging(
        &prepared.repo,
        db::NewImportRow {
            path: relative_repo_path(&prepared.repo, staged.staging_guard.path())?,
            original_name: prepared.original_name.clone(),
            current_name: destination.final_name.clone(),
            category: destination.category.clone(),
            size_bytes: staged.size_bytes,
            hash_sha256: staged.hash_sha256.clone(),
            storage_mode: prepared.options.mode.clone(),
            origin: FileOrigin::Imported,
            source_path: Some(prepared.source.to_string_lossy().into_owned()),
            imported_at,
        },
    )
}

fn commit_filesystem(
    staged: &StagedImport,
    destination: &ImportDestinationPlan,
) -> CoreResult<Option<ReplacementFileGuard>> {
    let replacement_guard = destination.archive_replacement()?;
    persist_staging_to_final(staged.staging_guard.path(), &destination.final_path)
        .map(|()| replacement_guard)
}

fn promote_import(
    prepared: &PreparedImport,
    file_id: i64,
    destination: &ImportDestinationPlan,
) -> CoreResult<()> {
    let import_detail = import_change_detail(prepared, destination);
    match destination.replacement() {
        Some(replacement) => db::promote_replacing_imported_file(
            &prepared.repo,
            replacement.db_row(),
            file_id,
            &destination.final_relative_path,
            &destination.final_name,
            &import_detail,
            &replacement.deleted_change_detail(),
        ),
        None => db::promote_imported_file(
            &prepared.repo,
            file_id,
            &destination.final_relative_path,
            &destination.final_name,
            &import_detail,
        ),
    }
}

fn insert_indexed_row(
    prepared: &PreparedImport,
    fingerprint: &hash::HashedCopy,
) -> CoreResult<i64> {
    let imported_at = chrono::Utc::now().timestamp();
    let source_path = prepared.source.to_string_lossy().into_owned();
    db::insert_active_indexed_import(
        &prepared.repo,
        db::NewImportRow {
            path: source_path.clone(),
            original_name: prepared.original_name.clone(),
            current_name: prepared.target_filename.clone(),
            category: prepared.target.category.clone(),
            size_bytes: fingerprint.size_bytes,
            hash_sha256: fingerprint.hash_sha256.clone(),
            storage_mode: StorageMode::Indexed,
            origin: FileOrigin::Imported,
            source_path: Some(source_path.clone()),
            imported_at,
        },
        &json!({
            "source": source_path.clone(),
            "mode": storage_mode_detail(&prepared.options.mode),
            "category": prepared.target.category,
            "destination": destination_detail(&prepared.options.destination),
            "renamed_from_original": prepared.original_name != prepared.target_filename,
            "by": "user",
        }),
    )
}

fn insert_replacing_indexed_row(
    prepared: &PreparedImport,
    fingerprint: &hash::HashedCopy,
    existing: FileEntry,
) -> CoreResult<i64> {
    let imported_at = chrono::Utc::now().timestamp();
    let source_path = prepared.source.to_string_lossy().into_owned();
    let replacement = ReplacementPlan::prepare_for_existing(&prepared.repo, existing)?;
    let mut replacement_guard = replacement.archive_existing_file(&prepared.repo)?;
    let file_id = db::insert_replacing_active_indexed_import(
        &prepared.repo,
        replacement.db_row(),
        db::NewImportRow {
            path: source_path.clone(),
            original_name: prepared.original_name.clone(),
            current_name: prepared.target_filename.clone(),
            category: prepared.target.category.clone(),
            size_bytes: fingerprint.size_bytes,
            hash_sha256: fingerprint.hash_sha256.clone(),
            storage_mode: StorageMode::Indexed,
            origin: FileOrigin::Imported,
            source_path: Some(source_path.clone()),
            imported_at,
        },
        &json!({
            "source": source_path,
            "mode": storage_mode_detail(&prepared.options.mode),
            "category": prepared.target.category,
            "destination": destination_detail(&prepared.options.destination),
            "renamed_from_original": prepared.original_name != prepared.target_filename,
            "duplicate_strategy": "overwrite",
            "replaced_file_id": replacement.replaced_file_id(),
            "replaced_path": replacement.replaced_path(),
            "by": "user",
        }),
        &replacement.deleted_change_detail(),
    )?;
    if let Some(guard) = &mut replacement_guard {
        guard.disarm();
    }
    Ok(file_id)
}

fn import_change_detail(
    prepared: &PreparedImport,
    destination: &ImportDestinationPlan,
) -> serde_json::Value {
    match destination.replacement() {
        Some(replacement) => json!({
            "source": prepared.source.to_string_lossy(),
            "mode": storage_mode_detail(&prepared.options.mode),
            "category": destination.category,
            "destination": destination_detail(&prepared.options.destination),
            "renamed_from_original": prepared.original_name != destination.final_name,
            "duplicate_strategy": "overwrite",
            "replaced_file_id": replacement.replaced_file_id(),
            "replaced_path": replacement.replaced_path(),
            "by": "user",
        }),
        None => json!({
            "source": prepared.source.to_string_lossy(),
            "mode": storage_mode_detail(&prepared.options.mode),
            "category": destination.category,
            "destination": destination_detail(&prepared.options.destination),
            "renamed_from_original": prepared.original_name != destination.final_name,
            "by": "user",
        }),
    }
}

struct ImportTarget {
    relative_dir: String,
    category: String,
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::InvalidPath);
    }
    Ok(PathBuf::from(repo_path))
}

fn source_filename(source: &Path) -> CoreResult<String> {
    source
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or(CoreError::InvalidPath)
}

fn resolve_import_target(
    repo: &Path,
    repo_path: &str,
    original_name: &str,
    options: &ImportOptions,
) -> CoreResult<ImportTarget> {
    match options.destination {
        ImportDestination::AutoClassify => {
            let category = match &options.override_category {
                Some(category) => category.clone(),
                None => {
                    classify::predict_category(repo_path.to_owned(), original_name.to_owned())?
                        .category
                }
            };
            validate::category_slug(&category)?;
            Ok(ImportTarget {
                relative_dir: category.clone(),
                category,
            })
        }
        ImportDestination::SelectedDirectory => {
            let directory = options
                .target_directory
                .as_deref()
                .ok_or(CoreError::InvalidPath)?;
            validate::relative_directory(directory)?;
            let category = validate::top_level_category(directory)?;
            Ok(ImportTarget {
                relative_dir: directory.to_owned(),
                category,
            })
        }
        ImportDestination::Category => {
            let category = options
                .override_category
                .as_deref()
                .ok_or(CoreError::InvalidPath)?;
            validate::category_slug(category)?;
            let relative_dir = repo
                .join(category)
                .strip_prefix(repo)
                .map_err(|_| CoreError::InvalidPath)?
                .to_string_lossy()
                .into_owned();
            Ok(ImportTarget {
                relative_dir,
                category: category.to_owned(),
            })
        }
    }
}

fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn destination_detail(destination: &ImportDestination) -> &'static str {
    match destination {
        ImportDestination::AutoClassify => "auto_classify",
        ImportDestination::SelectedDirectory => "selected_directory",
        ImportDestination::Category => "category",
    }
}

fn persist_staging_to_final(staging: &Path, final_path: &Path) -> CoreResult<()> {
    if path_exists(final_path)? {
        return Err(CoreError::Conflict);
    }

    match fs::rename(staging, final_path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => Err(CoreError::Conflict),
        Err(_) => copy_staging_to_final(staging, final_path),
    }
}

fn copy_staging_to_final(staging: &Path, final_path: &Path) -> CoreResult<()> {
    let expected_size = staging.metadata().map_err(hash::map_io_error)?.len();
    let copied_size = hash::copy_to_new_file(staging, final_path)?;
    if copied_size != expected_size {
        let _ = fs::remove_file(final_path);
        return Err(CoreError::Io);
    }
    match remove_staging_after_persist(staging) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _cleanup_result = fs::remove_file(final_path);
            Err(error)
        }
    }
}

fn remove_staging_after_persist(staging: &Path) -> CoreResult<()> {
    fs::remove_file(staging).map_err(hash::map_io_error)
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|_| CoreError::InvalidPath)
        .map(|relative| relative.to_string_lossy().into_owned())
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(hash::map_io_error)
}

struct DbStagingRowGuard {
    repo: PathBuf,
    file_id: i64,
    armed: bool,
}

impl DbStagingRowGuard {
    fn new(repo: PathBuf, file_id: i64) -> Self {
        Self {
            repo,
            file_id,
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for DbStagingRowGuard {
    fn drop(&mut self) {
        if self.armed {
            // Best-effort rollback for the staging metadata row owned by this attempt.
            let _cleanup_result = db::delete_file_row(&self.repo, self.file_id);
        }
    }
}
