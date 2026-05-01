use std::{
    fs::{File, OpenOptions},
    io::{BufReader, BufWriter, Read, Write},
    path::Path,
};

use sha2::{Digest, Sha256};

use crate::{CoreError, CoreResult};

const COPY_BUFFER_BYTES: usize = 64 * 1024;

pub(super) struct HashedCopy {
    pub(super) hash_sha256: String,
    pub(super) size_bytes: i64,
}

pub(super) fn copy_and_hash(source: &Path, destination: &Path) -> CoreResult<HashedCopy> {
    let source_file = File::open(source).map_err(map_io_error)?;
    let destination_file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(destination)
        .map_err(map_io_error)?;

    let mut reader = BufReader::with_capacity(COPY_BUFFER_BYTES, source_file);
    let mut writer = BufWriter::with_capacity(COPY_BUFFER_BYTES, destination_file);
    let mut hasher = Sha256::new();
    let mut size_bytes = 0_i64;
    let mut buffer = [0_u8; COPY_BUFFER_BYTES];

    loop {
        let read = reader.read(&mut buffer).map_err(map_io_error)?;
        if read == 0 {
            break;
        }
        writer.write_all(&buffer[..read]).map_err(map_io_error)?;
        hasher.update(&buffer[..read]);
        size_bytes += read as i64;
    }

    writer.flush().map_err(map_io_error)?;
    writer.get_ref().sync_all().map_err(map_io_error)?;

    Ok(HashedCopy {
        hash_sha256: format!("{:x}", hasher.finalize()),
        size_bytes,
    })
}

pub(super) fn hash_file(path: &Path) -> CoreResult<HashedCopy> {
    let source_file = File::open(path).map_err(map_io_error)?;
    let mut reader = BufReader::with_capacity(COPY_BUFFER_BYTES, source_file);
    let mut hasher = Sha256::new();
    let mut size_bytes = 0_i64;
    let mut buffer = [0_u8; COPY_BUFFER_BYTES];

    loop {
        let read = reader.read(&mut buffer).map_err(map_io_error)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        size_bytes += read as i64;
    }

    Ok(HashedCopy {
        hash_sha256: format!("{:x}", hasher.finalize()),
        size_bytes,
    })
}

pub(super) fn copy_to_new_file(source: &Path, destination: &Path) -> CoreResult<u64> {
    let result = copy_to_new_file_inner(source, destination);
    if result.is_err() {
        let _cleanup_result = std::fs::remove_file(destination);
    }
    result
}

fn copy_to_new_file_inner(source: &Path, destination: &Path) -> CoreResult<u64> {
    let mut source_file = File::open(source).map_err(map_io_error)?;
    let destination_file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(destination)
        .map_err(map_io_error)?;
    let mut writer = BufWriter::with_capacity(COPY_BUFFER_BYTES, destination_file);
    let copied = std::io::copy(&mut source_file, &mut writer).map_err(map_io_error)?;
    writer.flush().map_err(map_io_error)?;
    writer.get_ref().sync_all().map_err(map_io_error)?;
    Ok(copied)
}

pub(super) fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::AlreadyExists => CoreError::Conflict,
        std::io::ErrorKind::NotFound => CoreError::FileNotFound,
        std::io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        std::io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    }
}
