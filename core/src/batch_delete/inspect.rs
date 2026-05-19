use std::{
    fs::File,
    io::{BufReader, Read},
    path::Path,
    time::UNIX_EPOCH,
};

use sha2::{Digest, Sha256};

use crate::{CoreError, CoreResult};

pub(super) enum PathInspection {
    File(InspectedPathState),
    Missing,
    Other,
}

#[derive(Clone, Debug)]
pub(super) enum InspectedPathState {
    File {
        len: u64,
        readonly: bool,
        modified_secs: i64,
        modified_nanos: u32,
        content_sha256: String,
    },
    Missing,
}

impl InspectedPathState {
    pub(super) fn missing() -> Self {
        Self::Missing
    }

    pub(super) fn is_readonly_file(&self) -> bool {
        matches!(self, Self::File { readonly: true, .. })
    }

    pub(super) fn feed_preview_token(&self, hasher: &mut Sha256) {
        match self {
            Self::File {
                len,
                readonly,
                modified_secs,
                modified_nanos,
                content_sha256,
            } => {
                hasher.update(b"file");
                hasher.update(len.to_le_bytes());
                hasher.update(if *readonly { b"\x01" } else { b"\x00" });
                hasher.update(modified_secs.to_le_bytes());
                hasher.update(modified_nanos.to_le_bytes());
                hasher.update(content_sha256.as_bytes());
            }
            Self::Missing => hasher.update(b"missing"),
        }
    }
}

pub(super) fn inspect_path(path: &Path) -> CoreResult<PathInspection> {
    match path.metadata() {
        Ok(metadata) if metadata.is_file() => {
            Ok(PathInspection::File(inspect_file_state(path, &metadata)?))
        }
        Ok(_) => Ok(PathInspection::Other),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(PathInspection::Missing),
        Err(error) => Err(map_inspection_io_error(path, error)),
    }
}

pub(super) fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists()
        .map_err(|error| map_inspection_io_error(path, error))
}

pub(super) fn path_is_writable_dir(path: &Path) -> CoreResult<bool> {
    let metadata = path
        .metadata()
        .map_err(|error| map_inspection_io_error(path, error))?;
    Ok(metadata.is_dir() && !metadata.permissions().readonly())
}

fn map_inspection_io_error(path: &Path, error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => {
            CoreError::permission_denied(path.display().to_string())
        }
        std::io::ErrorKind::NotFound => CoreError::file_not_found(path.display().to_string()),
        _ => CoreError::io(error.to_string()),
    }
}

fn inspect_file_state(path: &Path, metadata: &std::fs::Metadata) -> CoreResult<InspectedPathState> {
    let modified = metadata
        .modified()
        .map_err(|error| map_inspection_io_error(path, error))?;
    let modified = modified
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::io(error.to_string()))?;
    Ok(InspectedPathState::File {
        len: metadata.len(),
        readonly: metadata.permissions().readonly(),
        modified_secs: modified.as_secs() as i64,
        modified_nanos: modified.subsec_nanos(),
        content_sha256: sha256_file(path)?,
    })
}

fn sha256_file(path: &Path) -> CoreResult<String> {
    let file = File::open(path).map_err(|error| map_inspection_io_error(path, error))?;
    let mut reader = BufReader::with_capacity(64 * 1024, file);
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = reader
            .read(&mut buffer)
            .map_err(|error| map_inspection_io_error(path, error))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}
