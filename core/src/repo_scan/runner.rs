use std::path::Path;

use crate::{
    db::{self, FileIndexInput, ScanFileChange},
    CoreError, CoreResult, ScanSessionStatus,
};

use super::{
    files::{collect_scan_files, index_input_for_file},
    preview::{active_file_snapshots, has_present_hash_conflict, missing_metadata_paths},
    types::ScanMode,
};

pub(super) fn run_adopt_scan(
    repo_path: &Path,
    scan_session_id: i64,
    resume_after: Option<&str>,
) -> CoreResult<()> {
    run_filesystem_scan(
        repo_path,
        scan_session_id,
        resume_after,
        ScanMode::Adopt,
        false,
    )
}

pub(super) fn run_filesystem_scan(
    repo_path: &Path,
    scan_session_id: i64,
    resume_after: Option<&str>,
    mode: ScanMode,
    track_missing_metadata: bool,
) -> CoreResult<()> {
    let plan = match collect_scan_files(repo_path, resume_after) {
        Ok(plan) => plan,
        Err(error) => {
            return finish_failed_scan(repo_path, scan_session_id, "scan setup", error);
        }
    };
    let active_rows = if track_missing_metadata {
        match active_file_snapshots(repo_path) {
            Ok(rows) => rows,
            Err(error) => {
                return finish_failed_scan(repo_path, scan_session_id, "metadata snapshot", error);
            }
        }
    } else {
        Vec::new()
    };
    for _ in 0..plan.skipped {
        db::update_scan_session_progress(repo_path, scan_session_id, "", ScanFileChange::Skipped)?;
    }
    if track_missing_metadata {
        let missing_paths = missing_metadata_paths(repo_path, &plan.files, &active_rows);
        for _ in missing_paths {
            db::update_scan_session_progress(
                repo_path,
                scan_session_id,
                "",
                ScanFileChange::Missing,
            )?;
        }
    }

    for file in plan.files {
        let index_input = match index_input_for_file(&file.path, file.relative_path.clone()) {
            Ok(index_input) => index_input,
            Err(error) => {
                let change = change_for_scan_error(&error);
                db::update_scan_session_progress(repo_path, scan_session_id, "", change)?;
                return finish_failed_scan(repo_path, scan_session_id, &file.relative_path, error);
            }
        };
        if track_missing_metadata
            && has_present_hash_conflict(repo_path, &active_rows, &index_input)
        {
            db::update_scan_session_progress(
                repo_path,
                scan_session_id,
                &index_input.path,
                ScanFileChange::Conflict,
            )?;
        }
        let change = match upsert_scan_file(repo_path, &index_input, mode) {
            Ok(change) => change,
            Err(error) => {
                return finish_failed_scan(repo_path, scan_session_id, &index_input.path, error);
            }
        };
        db::update_scan_session_progress(repo_path, scan_session_id, &index_input.path, change)?;
    }

    db::finish_scan_session(
        repo_path,
        scan_session_id,
        ScanSessionStatus::Completed,
        &[],
    )
}

fn upsert_scan_file(
    repo_path: &Path,
    input: &FileIndexInput,
    mode: ScanMode,
) -> CoreResult<ScanFileChange> {
    match mode {
        ScanMode::Adopt => db::upsert_adopted_file(repo_path, input),
        ScanMode::Reindex => db::upsert_reindexed_file(repo_path, input),
    }
}

fn change_for_scan_error(error: &CoreError) -> ScanFileChange {
    match error {
        CoreError::PermissionDenied { .. } => ScanFileChange::Unreadable,
        _ => ScanFileChange::Unknown,
    }
}

fn finish_failed_scan(
    repo_path: &Path,
    scan_session_id: i64,
    relative_path: &str,
    error: CoreError,
) -> CoreResult<()> {
    let errors = vec![format!("{relative_path}: {error}")];
    match db::finish_scan_session(
        repo_path,
        scan_session_id,
        ScanSessionStatus::Failed,
        &errors,
    ) {
        Ok(()) => Err(error),
        Err(persist_error) => Err(CoreError::db(format!(
            "failed to persist failed scan session after {relative_path}: {error}; {persist_error}"
        ))),
    }
}
