use crate::{
    observability::CoreOperationTrace, CoreResult, FileEntry, ImportResult,
    ImportSourceRemovalStatus, StorageMode,
};

use super::{
    check_duplicate, commit_filesystem, create_staging, db,
    ensure_replacement_is_recoverable_from_system_trash, finalize_source_removal,
    fingerprint_staged_source, finish_overview_regeneration, hash, insert_indexed_row,
    insert_replacing_indexed_row, insert_staging_row, promote_import, DbStagingRowGuard,
    FinalFileGuard, ImportDestinationPlan, IndexedImportCommit, PreparedImport,
    ReplacementDbRollback, ReplacementFileGuard, StagedImport,
};

struct OwnedImportPreparation {
    staged: StagedImport,
    destination: ImportDestinationPlan,
    file_id: i64,
}

struct OwnedImportCommit {
    entry: FileEntry,
    db_guard: DbStagingRowGuard,
    final_guard: FinalFileGuard,
    replacement_guard: Option<ReplacementFileGuard>,
    destination: ImportDestinationPlan,
}

pub(crate) fn import_file(
    repo_path: String,
    source_path: String,
    options: crate::ImportOptions,
) -> CoreResult<FileEntry> {
    Ok(import_file_with_result(repo_path, source_path, options)?.entry)
}

pub(crate) fn import_file_with_result(
    repo_path: String,
    source_path: String,
    options: crate::ImportOptions,
) -> CoreResult<ImportResult> {
    import_file_with_trace(repo_path, source_path, options, None)
}

pub(crate) fn import_file_with_trace(
    repo_path: String,
    source_path: String,
    options: crate::ImportOptions,
    trace: Option<&CoreOperationTrace>,
) -> CoreResult<ImportResult> {
    let prepared = observe(
        trace,
        "repository.import.validation",
        "core.storage.import",
        || PreparedImport::new(repo_path, source_path, options),
    )?;
    if matches!(prepared.options.mode, StorageMode::Indexed) {
        return import_indexed_file(prepared, trace);
    }
    let preparation = prepare_owned_import(&prepared, trace)?;
    let commit = commit_owned_import(&prepared, preparation, trace)?;
    Ok(finalize_owned_import(&prepared, commit, trace))
}

fn prepare_owned_import(
    prepared: &PreparedImport,
    trace: Option<&CoreOperationTrace>,
) -> CoreResult<OwnedImportPreparation> {
    let staging_guard = observe(
        trace,
        "repository.import.staging",
        "core.storage.import",
        || create_staging(prepared),
    )?;
    let staged = observe(
        trace,
        "repository.import.fingerprint",
        "core.storage.import",
        || fingerprint_staged_source(prepared, staging_guard),
    )?;
    let duplicate_resolution = observe_duplicate(trace, prepared, &staged.hash_sha256)?;
    let destination = observe(
        trace,
        "repository.import.destination",
        "core.storage.import",
        || {
            ImportDestinationPlan::prepare(
                &prepared.repo,
                &prepared.target.relative_dir,
                &prepared.target.category,
                &prepared.target_filename,
                duplicate_resolution,
            )
        },
    )?;
    let file_id = observe(
        trace,
        "repository.import.staging_db_row",
        "core.storage.import",
        || insert_staging_row(prepared, &staged, &destination),
    )?;
    Ok(OwnedImportPreparation {
        staged,
        destination,
        file_id,
    })
}

fn commit_owned_import(
    prepared: &PreparedImport,
    preparation: OwnedImportPreparation,
    trace: Option<&CoreOperationTrace>,
) -> CoreResult<OwnedImportCommit> {
    let OwnedImportPreparation {
        mut staged,
        destination,
        file_id,
    } = preparation;
    let db_guard = DbStagingRowGuard::new(prepared.repo.clone(), file_id);
    let mut replacement_guard = observe(
        trace,
        "repository.import.filesystem_commit",
        "core.storage.import",
        || commit_filesystem(&staged, &destination),
    )?;
    staged.staging_guard.disarm();
    let final_guard = FinalFileGuard::new(
        &prepared.options.mode,
        destination.final_path.clone(),
        prepared.source.clone(),
    );

    let replacement_rollback = destination
        .replacement()
        .map(ReplacementDbRollback::from_plan);
    let entry = promote_and_render_owned(
        prepared,
        file_id,
        &destination,
        replacement_rollback.as_ref(),
        trace,
    )?;
    observe_replacement_trash(
        trace,
        &mut replacement_guard,
        &prepared.repo,
        file_id,
        replacement_rollback.as_ref(),
    )?;
    Ok(OwnedImportCommit {
        entry,
        db_guard,
        final_guard,
        replacement_guard,
        destination,
    })
}

fn promote_and_render_owned(
    prepared: &PreparedImport,
    file_id: i64,
    destination: &ImportDestinationPlan,
    replacement_rollback: Option<&ReplacementDbRollback>,
    trace: Option<&CoreOperationTrace>,
) -> CoreResult<FileEntry> {
    observe(
        trace,
        "repository.import.db_promotion",
        "core.storage.import",
        || promote_import(prepared, file_id, destination),
    )?;
    let entry = db::get_active_file_by_id(&prepared.repo, file_id)?;
    observe(
        trace,
        "repository.import.overview",
        "core.storage.overview",
        || {
            finish_overview_regeneration(
                &prepared.repo,
                entry,
                replacement_rollback,
                prepared.options.content_locale.as_str(),
            )
        },
    )
}

fn finalize_owned_import(
    prepared: &PreparedImport,
    mut commit: OwnedImportCommit,
    trace: Option<&CoreOperationTrace>,
) -> ImportResult {
    commit.db_guard.disarm();
    commit.final_guard.disarm();
    if let Some(guard) = &mut commit.replacement_guard {
        guard.disarm();
    }
    commit.destination.disarm();
    let source_removal = match prepared.options.mode {
        StorageMode::Moved => trace.map_or_else(
            || finalize_source_removal(&prepared.options.mode, &prepared.source),
            |trace| {
                trace.stage_with_outcome(
                    "repository.import.source_removal",
                    "core.storage.import",
                    || finalize_source_removal(&prepared.options.mode, &prepared.source),
                    |outcome| match outcome.status {
                        ImportSourceRemovalStatus::Retained => {
                            crate::ObservabilityOutcome::Degraded
                        }
                        ImportSourceRemovalStatus::Removed => {
                            crate::ObservabilityOutcome::Succeeded
                        }
                        ImportSourceRemovalStatus::NotRequested => {
                            crate::ObservabilityOutcome::Skipped
                        }
                    },
                )
            },
        ),
        StorageMode::Copied | StorageMode::Indexed => {
            skip(
                trace,
                "repository.import.source_removal",
                "core.storage.import",
            );
            finalize_source_removal(&prepared.options.mode, &prepared.source)
        }
    };
    ImportResult {
        entry: commit.entry,
        source_removal_status: source_removal.status,
        source_removal_failure: source_removal.failure,
    }
}

fn import_indexed_file(
    prepared: PreparedImport,
    trace: Option<&CoreOperationTrace>,
) -> CoreResult<ImportResult> {
    let commit = prepare_indexed_commit(&prepared, trace)?;
    finish_indexed_import(&prepared, commit, trace)
}

fn prepare_indexed_commit(
    prepared: &PreparedImport,
    trace: Option<&CoreOperationTrace>,
) -> CoreResult<IndexedImportCommit> {
    skip(trace, "repository.import.staging", "core.storage.import");
    let fingerprint = observe(
        trace,
        "repository.import.fingerprint",
        "core.storage.import",
        || hash::hash_file(&prepared.source),
    )?;
    let duplicate_resolution = observe_duplicate(trace, prepared, &fingerprint.hash_sha256)?;
    observe(
        trace,
        "repository.import.destination",
        "core.storage.import",
        || Ok(()),
    )?;
    skip(
        trace,
        "repository.import.staging_db_row",
        "core.storage.import",
    );
    skip(
        trace,
        "repository.import.filesystem_commit",
        "core.storage.import",
    );
    observe(
        trace,
        "repository.import.db_promotion",
        "core.storage.import",
        || match duplicate_resolution {
            crate::storage::dedup::DuplicateResolution::Overwrite { existing, .. } => {
                insert_replacing_indexed_row(prepared, &fingerprint, existing)
            }
            crate::storage::dedup::DuplicateResolution::NoDuplicate
            | crate::storage::dedup::DuplicateResolution::KeepBoth => Ok(IndexedImportCommit {
                file_id: insert_indexed_row(prepared, &fingerprint)?,
                replacement_guard: None,
                replacement_rollback: None,
            }),
        },
    )
}

fn finish_indexed_import(
    prepared: &PreparedImport,
    mut commit: IndexedImportCommit,
    trace: Option<&CoreOperationTrace>,
) -> CoreResult<ImportResult> {
    let mut db_guard = DbStagingRowGuard::new(prepared.repo.clone(), commit.file_id);
    let entry = db::get_active_file_by_id(&prepared.repo, commit.file_id)?;
    let entry = observe(
        trace,
        "repository.import.overview",
        "core.storage.overview",
        || {
            finish_overview_regeneration(
                &prepared.repo,
                entry,
                commit.replacement_rollback.as_ref(),
                prepared.options.content_locale.as_str(),
            )
        },
    )?;
    observe_replacement_trash(
        trace,
        &mut commit.replacement_guard,
        &prepared.repo,
        commit.file_id,
        commit.replacement_rollback.as_ref(),
    )?;

    db_guard.disarm();
    if let Some(guard) = &mut commit.replacement_guard {
        guard.disarm();
    }
    skip(
        trace,
        "repository.import.source_removal",
        "core.storage.import",
    );
    Ok(ImportResult {
        entry,
        source_removal_status: ImportSourceRemovalStatus::NotRequested,
        source_removal_failure: None,
    })
}

fn observe<T>(
    trace: Option<&CoreOperationTrace>,
    action_id: &str,
    component_id: &str,
    operation: impl FnOnce() -> CoreResult<T>,
) -> CoreResult<T> {
    match trace {
        Some(trace) => trace.stage(action_id, component_id, operation),
        None => operation(),
    }
}

fn observe_duplicate(
    trace: Option<&CoreOperationTrace>,
    prepared: &PreparedImport,
    hash_sha256: &str,
) -> CoreResult<super::dedup::DuplicateResolution> {
    let result = observe(
        trace,
        "repository.import.duplicate_resolution",
        "core.storage.dedup",
        || check_duplicate(prepared, hash_sha256),
    );
    if matches!(&result, Err(crate::CoreError::DuplicateFile { .. })) {
        if let Some(trace) = trace {
            trace.event(
                "repository.import.duplicate.detected",
                "core.storage.dedup",
                "validation",
                crate::ObservabilityOutcome::Failed,
                vec![crate::CoreObservabilityAttribute {
                    key: "reason".to_owned(),
                    value: "duplicate_hash".to_owned(),
                    privacy: crate::ObservabilityPrivacy::Public,
                }],
            );
        }
    }
    result
}

fn observe_replacement_trash(
    trace: Option<&CoreOperationTrace>,
    replacement_guard: &mut Option<ReplacementFileGuard>,
    repo: &std::path::Path,
    file_id: i64,
    replacement_rollback: Option<&ReplacementDbRollback>,
) -> CoreResult<()> {
    if replacement_guard.is_none() {
        skip(
            trace,
            "repository.import.replacement_trash",
            "core.storage.replacement_trash",
        );
        return Ok(());
    }
    let used_fallback = observe(
        trace,
        "repository.import.replacement_trash",
        "core.storage.replacement_trash",
        || {
            ensure_replacement_is_recoverable_from_system_trash(
                replacement_guard,
                repo,
                file_id,
                replacement_rollback,
            )
        },
    )?;
    if used_fallback {
        if let Some(trace) = trace {
            trace.event(
                "repository.file.trash.fallback",
                "core.storage.replacement_trash",
                "system_trash",
                crate::ObservabilityOutcome::Degraded,
                vec![crate::CoreObservabilityAttribute {
                    key: "reason".to_owned(),
                    value: "system_trash_unavailable".to_owned(),
                    privacy: crate::ObservabilityPrivacy::Public,
                }],
            );
        }
    }
    Ok(())
}

fn skip(trace: Option<&CoreOperationTrace>, action_id: &str, component_id: &str) {
    if let Some(trace) = trace {
        trace.skip_stage(action_id, component_id);
    }
}
