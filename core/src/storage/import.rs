use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use crate::{
    db, overview, CoreError, CoreResult, DuplicateStrategy, FileEntry, FileOrigin,
    ImportDestination, ImportOptions, StorageMode,
};

use super::{
    dedup,
    destination::{ImportDestinationPlan, ReplacementPlan},
    hash,
    import_target::{resolve_import_target, ImportTarget},
    replacement_trash::ReplacementFileGuard,
    safe_move::{move_recoverable_file, move_source_to_staging, FinalFileGuard, StagingFileGuard},
    staging_row::DbStagingRowGuard,
    validate,
};

pub(crate) fn import_file(
    repo_path: String,
    source_path: String,
    options: ImportOptions,
) -> CoreResult<FileEntry> {
    let prepared = PreparedImport::new(repo_path, source_path, options)?;
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
    ensure_replacement_is_recoverable_from_system_trash(&mut replacement_guard)?;

    let replacement_rollback = destination
        .replacement()
        .map(ReplacementDbRollback::from_plan);
    promote_import(&prepared, file_id, &destination)?;
    let entry = db::get_active_file_by_id(&prepared.repo, file_id)?;
    let entry = finish_overview_regeneration(&prepared.repo, entry, replacement_rollback.as_ref())?;

    db_guard.disarm();
    final_guard.disarm();
    if let Some(guard) = &mut replacement_guard {
        guard.disarm();
    }
    destination.disarm();
    Ok(entry)
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

struct StagedImport {
    staging_guard: StagingFileGuard,
    hash_sha256: String,
    size_bytes: i64,
}

struct ReplacementDbRollback {
    existing_id: i64,
    original_path: String,
    deleted_detail: Value,
}

impl ReplacementDbRollback {
    fn from_plan(plan: &ReplacementPlan) -> Self {
        Self {
            existing_id: plan.replaced_file_id(),
            original_path: plan.replaced_path().to_owned(),
            deleted_detail: plan.deleted_change_detail(),
        }
    }

    fn rollback(&self, repo: &Path, new_file_id: i64) -> CoreResult<()> {
        db::rollback_replacing_imported_file(
            repo,
            self.existing_id,
            &self.original_path,
            new_file_id,
            &self.deleted_detail,
        )
    }
}

struct IndexedImportCommit {
    file_id: i64,
    replacement_guard: Option<ReplacementFileGuard>,
    replacement_rollback: Option<ReplacementDbRollback>,
}

fn stage_source(prepared: &PreparedImport) -> CoreResult<StagedImport> {
    let staging_guard = match prepared.options.mode {
        StorageMode::Copied => StagingFileGuard::create_for_copy(&prepared.repo)?,
        StorageMode::Moved => {
            StagingFileGuard::create_for_move(&prepared.repo, prepared.source.clone())?
        }
        StorageMode::Indexed => return Err(CoreError::internal("internal error")),
    };
    let hashed_copy = match prepared.options.mode {
        StorageMode::Copied => hash::copy_and_hash(&prepared.source, staging_guard.path())?,
        StorageMode::Moved => {
            move_source_to_staging(&prepared.source, staging_guard.path())?;
            hash::hash_file(staging_guard.path())?
        }
        StorageMode::Indexed => return Err(CoreError::internal("internal error")),
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
    if existing.is_some() {
        return dedup::resolve_duplicate(&prepared.options.duplicate_strategy, existing);
    }
    if matches!(
        prepared.options.duplicate_strategy,
        DuplicateStrategy::Overwrite
    ) {
        let target_path = requested_target_relative_path(prepared)?;
        let existing_by_path = db::find_active_file_by_path(&prepared.repo, &target_path)?;
        if let Some(existing) = existing_by_path {
            return Ok(dedup::DuplicateResolution::Overwrite {
                existing,
                reason: dedup::ReplacementReason::NameConflict,
            });
        }
    }
    dedup::resolve_duplicate(&prepared.options.duplicate_strategy, None)
}

fn import_indexed_file(prepared: PreparedImport) -> CoreResult<FileEntry> {
    let fingerprint = hash::hash_file(&prepared.source)?;
    let duplicate_resolution = check_duplicate(&prepared, &fingerprint.hash_sha256)?;

    let mut commit = match duplicate_resolution {
        dedup::DuplicateResolution::Overwrite { existing, .. } => {
            insert_replacing_indexed_row(&prepared, &fingerprint, existing)?
        }
        dedup::DuplicateResolution::NoDuplicate | dedup::DuplicateResolution::KeepBoth => {
            IndexedImportCommit {
                file_id: insert_indexed_row(&prepared, &fingerprint)?,
                replacement_guard: None,
                replacement_rollback: None,
            }
        }
    };
    let mut db_guard = DbStagingRowGuard::new(prepared.repo.clone(), commit.file_id);
    let entry = db::get_active_file_by_id(&prepared.repo, commit.file_id)?;
    let entry =
        finish_overview_regeneration(&prepared.repo, entry, commit.replacement_rollback.as_ref())?;

    db_guard.disarm();
    if let Some(guard) = &mut commit.replacement_guard {
        guard.disarm();
    }
    Ok(entry)
}

fn finish_overview_regeneration(
    repo: &Path,
    entry: FileEntry,
    replacement_rollback: Option<&ReplacementDbRollback>,
) -> CoreResult<FileEntry> {
    match overview::regenerate_after_import(repo, &entry) {
        Ok(()) => Ok(entry),
        Err(error) => {
            if let Some(rollback) = replacement_rollback {
                rollback.rollback(repo, entry.id)?;
            }
            Err(error)
        }
    }
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

fn ensure_replacement_is_recoverable_from_system_trash(
    replacement_guard: &mut Option<ReplacementFileGuard>,
) -> CoreResult<()> {
    if let Some(guard) = replacement_guard {
        guard.ensure_system_trash_copy()?;
    }
    Ok(())
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
) -> CoreResult<IndexedImportCommit> {
    let imported_at = chrono::Utc::now().timestamp();
    let source_path = prepared.source.to_string_lossy().into_owned();
    let replacement = ReplacementPlan::prepare_for_existing(&prepared.repo, existing)?;
    let mut replacement_guard = replacement.archive_existing_file(&prepared.repo)?;
    ensure_replacement_is_recoverable_from_system_trash(&mut replacement_guard)?;
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
            "replace_reason": replacement.reason_detail(),
            "replaced_file_id": replacement.replaced_file_id(),
            "replaced_path": replacement.replaced_path(),
            "by": "user",
        }),
        &replacement.deleted_change_detail(),
    )?;
    Ok(IndexedImportCommit {
        file_id,
        replacement_guard,
        replacement_rollback: Some(ReplacementDbRollback::from_plan(&replacement)),
    })
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
            "requested_name": prepared.target_filename,
            "final_name": destination.final_name,
            "final_path": destination.final_relative_path,
            "name_conflict_resolved": prepared.target_filename != destination.final_name,
            "duplicate_strategy": "overwrite",
            "replace_reason": replacement.reason_detail(),
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
            "requested_name": prepared.target_filename,
            "final_name": destination.final_name,
            "final_path": destination.final_relative_path,
            "name_conflict_resolved": prepared.target_filename != destination.final_name,
            "by": "user",
        }),
    }
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(PathBuf::from(repo_path))
}

fn source_filename(source: &Path) -> CoreResult<String> {
    source
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
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
    move_recoverable_file(staging, final_path)
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))
        .map(|relative| relative.to_string_lossy().into_owned())
}

fn requested_target_relative_path(prepared: &PreparedImport) -> CoreResult<String> {
    let target_path = prepared
        .repo
        .join(&prepared.target.relative_dir)
        .join(&prepared.target_filename);
    relative_repo_path(&prepared.repo, &target_path)
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    #[test]
    fn resolve_name_conflict_persist_refuses_raced_final_without_overwrite() {
        let dir = tempfile::tempdir().expect("create import tempdir");
        let staging = dir.path().join("staging-file");
        let final_path = dir.path().join("final.pdf");
        fs::write(&staging, b"new content").expect("write staging file");
        fs::write(&final_path, b"raced content").expect("write raced final file");

        let result = persist_staging_to_final(&staging, &final_path);

        assert!(matches!(result, Err(CoreError::Conflict { .. })));
        assert_eq!(
            fs::read(&staging).expect("staging remains recoverable"),
            b"new content"
        );
        assert_eq!(
            fs::read(&final_path).expect("raced final remains unmodified"),
            b"raced content"
        );
    }
}
