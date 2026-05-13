use std::path::PathBuf;

use crate::db;

pub(super) struct DbStagingRowGuard {
    repo: PathBuf,
    file_id: i64,
    armed: bool,
}

impl DbStagingRowGuard {
    pub(super) fn new(repo: PathBuf, file_id: i64) -> Self {
        Self {
            repo,
            file_id,
            armed: true,
        }
    }

    pub(super) fn disarm(&mut self) {
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
