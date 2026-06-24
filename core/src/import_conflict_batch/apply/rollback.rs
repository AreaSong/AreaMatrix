use std::path::{Path, PathBuf};

use crate::{db, storage, CoreError, CoreResult};

use crate::import_conflict_batch::path;

pub(super) enum ImportConflictRollback {
    Decision {
        row: db::ImportConflictRow,
        session_status: String,
    },
    KeepBoth {
        row: db::ImportConflictRow,
        final_path: String,
        staging_path: String,
        staging_name: String,
        session_status: String,
    },
    Replace {
        row: db::ImportConflictRow,
        final_path: String,
        archived_path: String,
        staging_path: String,
        staging_name: String,
        session_status: String,
    },
}

impl ImportConflictRollback {
    pub(super) fn apply(self, repo: &Path) -> CoreResult<()> {
        match self {
            Self::Decision {
                row,
                session_status,
            } => db::rollback_import_conflict_decision(repo, &row, &session_status),
            Self::KeepBoth {
                row,
                final_path,
                staging_path,
                staging_name,
                session_status,
            } => {
                restore_staging_file(repo, &final_path, &staging_path)?;
                db::rollback_import_conflict_keep_both(
                    repo,
                    &row,
                    &final_path,
                    &staging_path,
                    &staging_name,
                    &session_status,
                )
            }
            Self::Replace {
                row,
                final_path,
                archived_path,
                staging_path,
                staging_name,
                session_status,
            } => {
                restore_staging_file(repo, &final_path, &staging_path)?;
                restore_replaced_file(repo, &archived_path, &row.target_path)?;
                db::rollback_import_conflict_replace(
                    repo,
                    &row,
                    &final_path,
                    &archived_path,
                    &staging_path,
                    &staging_name,
                    &session_status,
                )
            }
        }
    }
}

fn restore_staging_file(repo: &Path, final_path: &str, staging_path: &str) -> CoreResult<()> {
    let final_absolute_path = path::repo_relative_file_path(repo, final_path)?;
    let staging_absolute_path = path::staging_file_path(repo, staging_path)?;
    if final_absolute_path.exists() && !staging_absolute_path.exists() {
        storage::move_recoverable_file(&final_absolute_path, &staging_absolute_path)?;
    }
    Ok(())
}

fn restore_replaced_file(repo: &Path, archived_path: &str, target_path: &str) -> CoreResult<()> {
    let archive_absolute_path = internal_repo_path(repo, archived_path)?;
    let target_absolute_path = path::repo_relative_file_path(repo, target_path)?;
    if archive_absolute_path.exists() && !target_absolute_path.exists() {
        storage::move_recoverable_file(&archive_absolute_path, &target_absolute_path)?;
    }
    Ok(())
}

fn internal_repo_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    if relative.is_absolute() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(repo.join(relative))
}
