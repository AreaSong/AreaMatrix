use std::{
    fs, io,
    path::{Path, PathBuf},
};

use crate::CoreResult;

pub(super) struct WritePlan {
    path: PathBuf,
    content: String,
}

impl WritePlan {
    pub(super) fn new(path: PathBuf, content: String) -> Self {
        Self { path, content }
    }
}

pub(super) fn write_plans_with_rollback(plans: &[WritePlan]) -> CoreResult<()> {
    let snapshots = plans
        .iter()
        .map(|plan| FileSnapshot::capture(&plan.path))
        .collect::<CoreResult<Vec<_>>>()?;

    for plan in plans {
        if let Err(error) = super::write_atomic_replace(&plan.path, &plan.content) {
            restore_snapshots(&snapshots);
            return Err(error);
        }
    }
    Ok(())
}

fn restore_snapshots(snapshots: &[FileSnapshot]) {
    for snapshot in snapshots.iter().rev() {
        snapshot.restore();
    }
}

struct FileSnapshot {
    path: PathBuf,
    state: SnapshotState,
}

impl FileSnapshot {
    fn capture(path: &Path) -> CoreResult<Self> {
        let state = match fs::symlink_metadata(path) {
            Ok(metadata) if metadata.is_file() => {
                SnapshotState::File(fs::read(path).map_err(super::map_io_error)?)
            }
            Ok(_) => SnapshotState::Other,
            Err(error) if error.kind() == io::ErrorKind::NotFound => SnapshotState::Missing,
            Err(error) => return Err(super::map_io_error(error)),
        };
        Ok(Self {
            path: path.to_path_buf(),
            state,
        })
    }

    fn restore(&self) {
        match &self.state {
            SnapshotState::Missing => remove_file_if_present(&self.path),
            SnapshotState::File(bytes) => {
                let _restore_result = fs::write(&self.path, bytes);
            }
            SnapshotState::Other => {}
        }
    }
}

enum SnapshotState {
    Missing,
    File(Vec<u8>),
    Other,
}

fn remove_file_if_present(path: &Path) {
    let Ok(metadata) = fs::symlink_metadata(path) else {
        return;
    };
    if metadata.is_file() || metadata.file_type().is_symlink() {
        let _remove_result = fs::remove_file(path);
    }
}
