//! Stable file snapshots and filesystem error helpers.

use std::{
    fs,
    io::{self, Read},
    path::Path,
};

use sha2::{Digest, Sha256};

use crate::{CoreError, CoreResult};

const HASH_BUFFER_BYTES: usize = 64 * 1024;
const SNAPSHOT_READ_ATTEMPTS: usize = 3;

pub(super) struct StableFileSnapshot {
    pub(super) size_bytes: i64,
    pub(super) hash_sha256: String,
}

pub(super) enum SnapshotAttempt {
    Stable(StableFileSnapshot),
    Changed,
}

pub(super) fn stable_file_snapshot(
    path: &Path,
    relative_path: &str,
) -> CoreResult<StableFileSnapshot> {
    retry_stable_snapshot(relative_path, || {
        read_stable_snapshot_attempt(path, relative_path)
    })
}

pub(super) fn retry_stable_snapshot<F>(
    relative_path: &str,
    mut attempt: F,
) -> CoreResult<StableFileSnapshot>
where
    F: FnMut() -> CoreResult<SnapshotAttempt>,
{
    for _ in 0..SNAPSHOT_READ_ATTEMPTS {
        match attempt()? {
            SnapshotAttempt::Stable(snapshot) => return Ok(snapshot),
            SnapshotAttempt::Changed => {}
        }
    }
    Err(CoreError::conflict(relative_path))
}

fn read_stable_snapshot_attempt(path: &Path, relative_path: &str) -> CoreResult<SnapshotAttempt> {
    let mut file = fs::File::open(path).map_err(|error| map_io_error(error, relative_path))?;
    let before = file
        .metadata()
        .map_err(|error| map_io_error(error, relative_path))?;
    let hash_sha256 = sha256_reader(&mut file, relative_path)?;
    let after = file
        .metadata()
        .map_err(|error| map_io_error(error, relative_path))?;
    let path_after =
        fs::symlink_metadata(path).map_err(|error| map_io_error(error, relative_path))?;
    if !snapshot_metadata_is_stable(&before, &after, &path_after, relative_path)? {
        return Ok(SnapshotAttempt::Changed);
    }
    Ok(SnapshotAttempt::Stable(StableFileSnapshot {
        size_bytes: after.len() as i64,
        hash_sha256,
    }))
}

pub(super) fn snapshot_metadata_is_stable(
    before: &fs::Metadata,
    after: &fs::Metadata,
    path_after: &fs::Metadata,
    relative_path: &str,
) -> CoreResult<bool> {
    let before_modified = before
        .modified()
        .map_err(|error| map_io_error(error, relative_path))?;
    Ok(after.len() == before.len()
        && after
            .modified()
            .map_err(|error| map_io_error(error, relative_path))?
            == before_modified
        && path_after.is_file()
        && path_after.len() == after.len()
        && path_after
            .modified()
            .map_err(|error| map_io_error(error, relative_path))?
            == before_modified
        && same_file_identity(after, path_after))
}

#[cfg(unix)]
fn same_file_identity(open_file: &fs::Metadata, final_path: &fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;

    // Atomic replacement can preserve size and mtime while switching the file behind the path.
    open_file.dev() == final_path.dev() && open_file.ino() == final_path.ino()
}

#[cfg(not(unix))]
fn same_file_identity(_open_file: &fs::Metadata, _final_path: &fs::Metadata) -> bool {
    true
}

fn sha256_reader(file: &mut fs::File, relative_path: &str) -> CoreResult<String> {
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; HASH_BUFFER_BYTES];

    loop {
        let bytes_read = file
            .read(&mut buffer)
            .map_err(|error| map_io_error(error, relative_path))?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

pub(super) fn rename_source_is_absent(repo: &Path, relative_path: &str) -> CoreResult<bool> {
    let source_path = repo.join(relative_path);
    match fs::symlink_metadata(source_path) {
        Ok(_) => Ok(false),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(true),
        Err(error) => Err(map_io_error(error, relative_path)),
    }
}

pub(super) fn ensure_path_absent(path: &Path, relative_path: &str) -> CoreResult<()> {
    match fs::symlink_metadata(path) {
        Ok(_) => Err(CoreError::conflict(relative_path)),
        Err(error) => match error.kind() {
            io::ErrorKind::NotFound => Ok(()),
            io::ErrorKind::InvalidInput => Err(CoreError::invalid_path(relative_path)),
            io::ErrorKind::PermissionDenied => Err(CoreError::permission_denied(relative_path)),
            _ => Err(CoreError::io(format!("{relative_path}: {error}"))),
        },
    }
}

pub(super) fn map_io_error(error: io::Error, relative_path: &str) -> CoreError {
    match error.kind() {
        io::ErrorKind::NotFound => CoreError::file_not_found(relative_path),
        io::ErrorKind::InvalidInput => CoreError::invalid_path(relative_path),
        io::ErrorKind::PermissionDenied => CoreError::permission_denied(relative_path),
        _ => CoreError::io(format!("{relative_path}: {error}")),
    }
}

pub(super) fn map_renamed_target_metadata_error(
    error: io::Error,
    relative_path: &str,
) -> CoreError {
    map_io_error(error, relative_path)
}
