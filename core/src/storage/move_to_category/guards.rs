use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{db, CoreError, CoreResult};

use super::super::{hash, safe_move::move_recoverable_file};

pub(super) fn move_note_sidecar(
    note_sidecar: Option<NoteSidecarPlan>,
    file_guard: &mut MoveRollbackGuard,
) -> CoreResult<Option<MoveRollbackGuard>> {
    let Some(note_sidecar) = note_sidecar else {
        return Ok(None);
    };

    match note_sidecar.move_to_final() {
        Ok(guard) => Ok(Some(guard)),
        Err(error) => {
            file_guard.rollback()?;
            Err(error)
        }
    }
}

pub(super) fn rollback_filesystem_move(
    file_guard: &mut MoveRollbackGuard,
    note_guard: &mut Option<MoveRollbackGuard>,
) -> CoreResult<()> {
    if let Some(note_guard) = note_guard.as_mut() {
        note_guard.rollback()?;
    }
    file_guard.rollback()
}

pub(super) struct NoteSidecarPlan {
    current_path: PathBuf,
    final_path: PathBuf,
}

impl NoteSidecarPlan {
    pub(super) fn from_move(
        repo: &Path,
        file_id: i64,
        current_file: &Path,
        final_file: &Path,
    ) -> CoreResult<Option<Self>> {
        let Some(note_content) = db::read_note_content(repo, file_id)? else {
            return Ok(None);
        };
        let current_path = sidecar_path_for_file(current_file)?;
        let final_path = sidecar_path_for_file(final_file)?;
        let sidecar_content = fs::read_to_string(&current_path).map_err(hash::map_io_error)?;
        if sidecar_content != note_content {
            return Err(CoreError::db("database error"));
        }
        if final_path.try_exists().map_err(hash::map_io_error)? {
            return Err(CoreError::conflict("path conflict"));
        }
        Ok(Some(Self {
            current_path,
            final_path,
        }))
    }

    fn move_to_final(self) -> CoreResult<MoveRollbackGuard> {
        move_recoverable_file(&self.current_path, &self.final_path)?;
        Ok(MoveRollbackGuard::new(self.final_path, self.current_path))
    }
}

fn sidecar_path_for_file(file_path: &Path) -> CoreResult<PathBuf> {
    let parent = file_path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    let file_name = file_path
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    Ok(parent.join(format!("{file_name}.md")))
}

pub(super) struct MoveRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    armed: bool,
}

impl MoveRollbackGuard {
    pub(super) fn new(current_path: PathBuf, original_path: PathBuf) -> Self {
        Self {
            current_path,
            original_path,
            armed: true,
        }
    }

    pub(super) fn disarm(&mut self) {
        self.armed = false;
    }

    pub(super) fn rollback(&mut self) -> CoreResult<()> {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            move_recoverable_file(&self.current_path, &self.original_path)?;
        }
        self.armed = false;
        Ok(())
    }
}

impl Drop for MoveRollbackGuard {
    fn drop(&mut self) {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            let _restore_result = move_recoverable_file(&self.current_path, &self.original_path);
        }
    }
}
