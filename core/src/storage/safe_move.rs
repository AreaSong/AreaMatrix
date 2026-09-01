use std::{
    fs,
    io::{Read, Seek, SeekFrom, Write},
    path::{Component, Path, PathBuf},
    time::UNIX_EPOCH,
};

use crate::{CoreError, CoreResult, StorageMode};

use super::hash;

const AREA_MATRIX_DIR: &str = ".areamatrix";
const STAGING_DIR: &str = "staging";

pub(super) struct StagingFileGuard {
    path: PathBuf,
    armed: bool,
}

impl StagingFileGuard {
    pub(super) fn create_for_copy(repo: &Path) -> CoreResult<Self> {
        Self::create(repo, "copy-import")
    }

    pub(super) fn create_for_move(repo: &Path) -> CoreResult<Self> {
        Self::create(repo, "move-import")
    }

    fn create(repo: &Path, prefix: &str) -> CoreResult<Self> {
        let staging_dir = repo.join(AREA_MATRIX_DIR).join(STAGING_DIR);
        ensure_directory_chain(&staging_dir, true)?;
        Ok(Self {
            path: staging_dir.join(format!("{}-{}", prefix, uuid::Uuid::new_v4())),
            armed: true,
        })
    }

    pub(super) fn path(&self) -> &Path {
        &self.path
    }

    pub(super) fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for StagingFileGuard {
    fn drop(&mut self) {
        if self.armed {
            // Best-effort cleanup for the internal staging file created by this import.
            let _cleanup_result = fs::remove_file(&self.path);
        }
    }
}

pub(super) enum FinalFileGuard {
    Delete {
        path: PathBuf,
        armed: bool,
    },
    RestoreSource {
        path: PathBuf,
        source: PathBuf,
        armed: bool,
    },
}

impl FinalFileGuard {
    pub(super) fn new(mode: &StorageMode, path: PathBuf, source: PathBuf) -> Self {
        match mode {
            StorageMode::Moved => Self::RestoreSource {
                path,
                source,
                armed: true,
            },
            StorageMode::Copied | StorageMode::Indexed => Self::Delete { path, armed: true },
        }
    }

    pub(super) fn disarm(&mut self) {
        match self {
            Self::Delete { armed, .. } | Self::RestoreSource { armed, .. } => *armed = false,
        }
    }
}

impl Drop for FinalFileGuard {
    fn drop(&mut self) {
        match self {
            Self::Delete { path, armed } if *armed => {
                // This path is created from AreaMatrix staging during the current attempt.
                if ensure_safe_file_path(path).is_ok() {
                    let _cleanup_result = fs::remove_file(path);
                }
            }
            Self::RestoreSource {
                path,
                source,
                armed,
            } if *armed => {
                restore_staged_source_or_keep_recoverable(path, source);
            }
            _ => {}
        }
    }
}

fn restore_staged_source_or_keep_recoverable(current_path: &Path, source: &Path) {
    if !path_exists_no_follow(current_path) {
        return;
    }
    if path_exists_no_follow(source) {
        // Never remove a path merely because the lexical destination exists;
        // a symlink or replaced ancestor must remain untouched.
        if ensure_safe_file_path(current_path).is_ok() {
            let _cleanup_result = fs::remove_file(current_path);
        }
        return;
    }
    let _restore_result = move_recoverable_file(current_path, source);
}

pub(super) fn remove_imported_source(source: &Path) -> CoreResult<()> {
    ensure_safe_file_path(source)?;
    fs::remove_file(source).map_err(map_source_removal_error)
}

pub(crate) fn move_recoverable_file(current_path: &Path, source: &Path) -> CoreResult<()> {
    move_file_no_replace(current_path, source, None)
}

/// Moves a file only when its no-follow identity and content still match the
/// preview sample. This is used by destructive conflict resolution; ordinary
/// callers use `move_recoverable_file`, which still performs identity checks.
pub(crate) fn move_recoverable_file_checked(
    current_path: &Path,
    destination: &Path,
    expected_identity: &str,
    expected_size: i64,
    expected_modified_nanos: u128,
    expected_hash: &str,
) -> CoreResult<()> {
    let expected = SourceExpectation {
        identity: expected_identity,
        size: expected_size,
        modified_nanos: expected_modified_nanos,
        hash: Some(expected_hash),
    };
    move_file_no_replace(current_path, destination, Some(expected))
}

/// Moves a file only when its current identity and content still match the
/// supplied durable hash. Recovery uses this to avoid moving a user-created
/// replacement after a crash window.
pub(crate) fn move_recoverable_file_with_hash(
    current_path: &Path,
    destination: &Path,
    expected_hash: &str,
) -> CoreResult<()> {
    let metadata = fs::symlink_metadata(current_path).map_err(hash::map_io_error)?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(CoreError::conflict(current_path.display().to_string()));
    }
    let actual_hash = hash::hash_file(current_path)?.hash_sha256;
    if actual_hash != expected_hash {
        return Err(CoreError::conflict(current_path.display().to_string()));
    }
    let identity = metadata_identity(&metadata);
    let expected = SourceExpectation {
        identity: &identity,
        size: metadata.len() as i64,
        modified_nanos: modified_nanos(&metadata)?,
        hash: Some(expected_hash),
    };
    move_file_no_replace(current_path, destination, Some(expected))
}

#[derive(Clone, Copy)]
struct SourceExpectation<'a> {
    identity: &'a str,
    size: i64,
    modified_nanos: u128,
    hash: Option<&'a str>,
}

#[derive(Clone)]
struct SourceObservation {
    identity: String,
    size: i64,
    modified_nanos: u128,
    hash: Option<String>,
    #[cfg(not(unix))]
    ancestors: String,
}

fn move_file_no_replace(
    current_path: &Path,
    destination: &Path,
    expected: Option<SourceExpectation<'_>>,
) -> CoreResult<()> {
    #[cfg(unix)]
    {
        move_file_no_replace_unix(current_path, destination, expected)
    }

    #[cfg(not(unix))]
    {
        move_file_no_replace_path(current_path, destination, expected)
    }
}

#[cfg(not(unix))]
fn move_file_no_replace_path(
    current_path: &Path,
    destination: &Path,
    expected: Option<SourceExpectation<'_>>,
) -> CoreResult<()> {
    let source = observe_source(current_path, expected.as_ref().and_then(|value| value.hash))?;
    if let Some(expected) = expected {
        ensure_observation_matches(&source, expected)?;
    }

    let destination_parent = destination
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    ensure_directory_chain(destination_parent, true)?;
    let destination_ancestors = directory_identity(destination_parent)?;
    ensure_destination_absent(destination)?;
    ensure_source_unchanged(
        current_path,
        &source,
        expected.as_ref().and_then(|v| v.hash),
    )?;

    let linked = match fs::hard_link(current_path, destination) {
        Ok(()) => true,
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            return Err(CoreError::conflict("path conflict"));
        }
        Err(_) => false,
    };
    if !linked {
        copy_to_new_destination(
            current_path,
            destination,
            &source,
            expected,
            &destination_ancestors,
        )?;
    }

    let source_after = match observe_source(current_path, expected.as_ref().and_then(|v| v.hash)) {
        Ok(value) => value,
        Err(error) => {
            cleanup_destination(destination, &destination_ancestors);
            return Err(error);
        }
    };
    if !same_observation(&source, &source_after)
        || expected.is_some_and(|value| ensure_observation_matches(&source_after, value).is_err())
    {
        cleanup_destination(destination, &destination_ancestors);
        return Err(CoreError::conflict(current_path.display().to_string()));
    }

    match fs::remove_file(current_path) {
        Ok(()) => Ok(()),
        Err(error) => {
            cleanup_destination(destination, &destination_ancestors);
            Err(hash::map_io_error(error))
        }
    }
}

#[cfg(unix)]
fn move_file_no_replace_unix(
    current_path: &Path,
    destination: &Path,
    expected: Option<SourceExpectation<'_>>,
) -> CoreResult<()> {
    use std::os::fd::AsRawFd;

    let source_parent_path = current_path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    let source_name = file_name_cstring(current_path)?;
    let destination_parent_path = destination
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    let destination_name = file_name_cstring(destination)?;

    let source_parent = open_directory_fd(source_parent_path, false)?;
    let destination_parent = open_directory_fd(destination_parent_path, true)?;
    let source_file = open_regular_file_at(&source_parent, &source_name, libc::O_RDONLY)?;
    let source = observe_source_fd(&source_file)?;
    if let Some(expected) = expected {
        ensure_observation_matches(&source, expected)?;
    }
    ensure_destination_absent_at(&destination_parent, &destination_name)?;
    ensure_source_name_matches(&source_parent, &source_name, &source_file)?;

    let linked = match unsafe {
        libc::linkat(
            source_parent.as_raw_fd(),
            source_name.as_ptr(),
            destination_parent.as_raw_fd(),
            destination_name.as_ptr(),
            0,
        )
    } {
        0 => true,
        _ if std::io::Error::last_os_error().raw_os_error() == Some(libc::EEXIST) => {
            return Err(CoreError::conflict("path conflict"));
        }
        _ => false,
    };

    if !linked {
        copy_to_new_destination_at(
            &source_file,
            &source,
            &destination_parent,
            &destination_name,
        )?;
    }

    let destination_file =
        match open_regular_file_at(&destination_parent, &destination_name, libc::O_RDONLY) {
            Ok(file) => file,
            Err(error) => {
                cleanup_destination_at(&destination_parent, &destination_name);
                return Err(error);
            }
        };
    let destination_metadata = destination_file.metadata().map_err(hash::map_io_error)?;
    let destination_hash = hash_file_handle(&destination_file)?;
    let source_after = observe_source_fd(&source_file)?;
    if !same_file_identity_metadata(&source_file, &destination_metadata)
        || destination_metadata.len() as i64 != source.size
        || source.hash.as_deref() != Some(destination_hash.as_str())
        || !same_observation_unix(&source, &source_after)
        || expected.is_some_and(|value| ensure_observation_matches(&source_after, value).is_err())
    {
        cleanup_destination_at(&destination_parent, &destination_name);
        return Err(CoreError::conflict(destination.display().to_string()));
    }

    // The directory descriptor keeps the ancestor chain stable. Re-check the
    // source name immediately before unlinking so a same-name replacement is
    // rejected rather than silently removed.
    ensure_source_name_matches(&source_parent, &source_name, &source_file)?;
    let removed = unsafe { libc::unlinkat(source_parent.as_raw_fd(), source_name.as_ptr(), 0) };
    if removed != 0 {
        cleanup_destination_at(&destination_parent, &destination_name);
        return Err(hash::map_io_error(std::io::Error::last_os_error()));
    }
    Ok(())
}

#[cfg(unix)]
fn open_directory_fd(path: &Path, create_missing: bool) -> CoreResult<std::fs::File> {
    use std::{ffi::CString, os::fd::FromRawFd, os::unix::ffi::OsStrExt};

    let mut current_fd = unsafe {
        let root = CString::new(if path.is_absolute() { "/" } else { "." })
            .map_err(|_| CoreError::invalid_path("invalid path"))?;
        libc::open(
            root.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_CLOEXEC,
        )
    };
    if current_fd < 0 {
        return Err(hash::map_io_error(std::io::Error::last_os_error()));
    }

    let mut lexical = if path.is_absolute() {
        PathBuf::from("/")
    } else {
        PathBuf::from(".")
    };
    for component in path.components() {
        let part = match component {
            Component::Normal(part) => part,
            Component::RootDir | Component::CurDir => continue,
            Component::ParentDir | Component::Prefix(_) => {
                unsafe { libc::close(current_fd) };
                return Err(CoreError::invalid_path(path.display().to_string()));
            }
        };
        lexical.push(part);
        let name = CString::new(part.as_bytes())
            .map_err(|_| CoreError::invalid_path(path.display().to_string()))?;
        let flags = libc::O_RDONLY | libc::O_DIRECTORY | libc::O_CLOEXEC | libc::O_NOFOLLOW;
        let mut next = unsafe { libc::openat(current_fd, name.as_ptr(), flags) };
        if next < 0
            && std::io::Error::last_os_error().raw_os_error() == Some(libc::ENOENT)
            && create_missing
        {
            let created = unsafe { libc::mkdirat(current_fd, name.as_ptr(), 0o700) };
            if created != 0 {
                let error = std::io::Error::last_os_error();
                if error.raw_os_error() != Some(libc::EEXIST) {
                    unsafe { libc::close(current_fd) };
                    return Err(hash::map_io_error(error));
                }
            }
            next = unsafe { libc::openat(current_fd, name.as_ptr(), flags) };
        }
        if next < 0 {
            let error = std::io::Error::last_os_error();
            // macOS exposes /tmp and /var as stable system aliases. They are
            // the only symlink components allowed at this boundary.
            if matches!(error.raw_os_error(), Some(value) if value == libc::ELOOP || value == libc::ENOTDIR)
                && is_allowed_system_alias(&lexical)
            {
                next = unsafe {
                    libc::openat(
                        current_fd,
                        name.as_ptr(),
                        libc::O_RDONLY | libc::O_DIRECTORY | libc::O_CLOEXEC,
                    )
                };
            }
        }
        if next < 0 {
            let error = std::io::Error::last_os_error();
            unsafe { libc::close(current_fd) };
            return Err(hash::map_io_error(error));
        }
        unsafe { libc::close(current_fd) };
        current_fd = next;
    }

    Ok(unsafe { std::fs::File::from_raw_fd(current_fd) })
}

#[cfg(unix)]
fn file_name_cstring(path: &Path) -> CoreResult<std::ffi::CString> {
    use std::os::unix::ffi::OsStrExt;

    let name = path
        .file_name()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    std::ffi::CString::new(name.as_bytes()).map_err(|_| CoreError::invalid_path("invalid path"))
}

#[cfg(unix)]
fn open_regular_file_at(
    parent: &std::fs::File,
    name: &std::ffi::CString,
    extra_flags: i32,
) -> CoreResult<std::fs::File> {
    use std::os::fd::FromRawFd;

    let fd = unsafe {
        libc::openat(
            {
                use std::os::fd::AsRawFd;
                parent.as_raw_fd()
            },
            name.as_ptr(),
            extra_flags | libc::O_CLOEXEC | libc::O_NOFOLLOW,
        )
    };
    if fd < 0 {
        return Err(hash::map_io_error(std::io::Error::last_os_error()));
    }
    let file = unsafe { std::fs::File::from_raw_fd(fd) };
    let metadata = file.metadata().map_err(hash::map_io_error)?;
    if !metadata.is_file() {
        return Err(CoreError::conflict("not a regular file"));
    }
    Ok(file)
}

#[cfg(unix)]
fn observe_source_fd(file: &std::fs::File) -> CoreResult<SourceObservation> {
    let metadata = file.metadata().map_err(hash::map_io_error)?;
    let hash = Some(hash_file_handle(file)?);
    Ok(SourceObservation {
        identity: metadata_identity(&metadata),
        size: metadata.len() as i64,
        modified_nanos: modified_nanos(&metadata)?,
        hash,
    })
}

#[cfg(unix)]
fn same_observation_unix(left: &SourceObservation, right: &SourceObservation) -> bool {
    left.identity == right.identity
        && left.size == right.size
        && left.modified_nanos == right.modified_nanos
        && left.hash == right.hash
}

#[cfg(unix)]
fn hash_file_handle(file: &std::fs::File) -> CoreResult<String> {
    use sha2::{Digest, Sha256};

    let mut reader = file.try_clone().map_err(hash::map_io_error)?;
    reader
        .seek(SeekFrom::Start(0))
        .map_err(hash::map_io_error)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = reader.read(&mut buffer).map_err(hash::map_io_error)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

#[cfg(unix)]
fn ensure_source_name_matches(
    parent: &std::fs::File,
    name: &std::ffi::CString,
    source: &std::fs::File,
) -> CoreResult<()> {
    use std::{os::fd::AsRawFd, os::unix::fs::MetadataExt};

    let mut info = std::mem::MaybeUninit::<libc::stat>::zeroed();
    let result = unsafe {
        libc::fstatat(
            parent.as_raw_fd(),
            name.as_ptr(),
            info.as_mut_ptr(),
            libc::AT_SYMLINK_NOFOLLOW,
        )
    };
    if result != 0 {
        return Err(hash::map_io_error(std::io::Error::last_os_error()));
    }
    let source_metadata = source.metadata().map_err(hash::map_io_error)?;
    let path_stat = unsafe { info.assume_init() };
    if (path_stat.st_dev as u64) != source_metadata.dev()
        || path_stat.st_ino != source_metadata.ino()
    {
        return Err(CoreError::conflict("stale file identity"));
    }
    Ok(())
}

#[cfg(unix)]
fn ensure_destination_absent_at(
    parent: &std::fs::File,
    name: &std::ffi::CString,
) -> CoreResult<()> {
    use std::os::fd::AsRawFd;

    let mut info = std::mem::MaybeUninit::<libc::stat>::zeroed();
    let result = unsafe {
        libc::fstatat(
            parent.as_raw_fd(),
            name.as_ptr(),
            info.as_mut_ptr(),
            libc::AT_SYMLINK_NOFOLLOW,
        )
    };
    if result == 0 {
        return Err(CoreError::conflict("path conflict"));
    }
    let error = std::io::Error::last_os_error();
    if error.raw_os_error() == Some(libc::ENOENT) {
        Ok(())
    } else {
        Err(hash::map_io_error(error))
    }
}

#[cfg(unix)]
fn copy_to_new_destination_at(
    source: &std::fs::File,
    observation: &SourceObservation,
    destination_parent: &std::fs::File,
    destination_name: &std::ffi::CString,
) -> CoreResult<()> {
    use std::os::fd::{AsRawFd, FromRawFd};

    let fd = unsafe {
        libc::openat(
            destination_parent.as_raw_fd(),
            destination_name.as_ptr(),
            libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL | libc::O_CLOEXEC | libc::O_NOFOLLOW,
            0o600,
        )
    };
    if fd < 0 {
        return Err(hash::map_io_error(std::io::Error::last_os_error()));
    }
    let mut destination = unsafe { std::fs::File::from_raw_fd(fd) };
    let mut source_reader = source.try_clone().map_err(hash::map_io_error)?;
    source_reader
        .seek(SeekFrom::Start(0))
        .map_err(hash::map_io_error)?;
    let copied = std::io::copy(&mut source_reader, &mut destination).map_err(hash::map_io_error)?;
    destination.flush().map_err(hash::map_io_error)?;
    destination.sync_all().map_err(hash::map_io_error)?;
    if copied != observation.size as u64 {
        return Err(CoreError::conflict("source changed during copy"));
    }
    Ok(())
}

#[cfg(unix)]
fn cleanup_destination_at(parent: &std::fs::File, name: &std::ffi::CString) {
    use std::os::fd::AsRawFd;

    unsafe {
        libc::unlinkat(parent.as_raw_fd(), name.as_ptr(), 0);
    }
}

#[cfg(unix)]
fn same_file_identity_metadata(file: &std::fs::File, metadata: &fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;

    let Ok(source) = file.metadata() else {
        return false;
    };
    source.dev() == metadata.dev() && source.ino() == metadata.ino()
}

#[cfg(not(unix))]
fn copy_to_new_destination(
    current_path: &Path,
    destination: &Path,
    source: &SourceObservation,
    expected: Option<SourceExpectation<'_>>,
    destination_ancestors: &str,
) -> CoreResult<()> {
    let copied_size = hash::copy_to_new_file(current_path, destination)?;
    if copied_size != source.size as u64 {
        cleanup_destination(destination, destination_ancestors);
        return Err(CoreError::conflict(current_path.display().to_string()));
    }
    let source_after = observe_source(current_path, expected.as_ref().and_then(|v| v.hash))?;
    if !same_observation(source, &source_after)
        || expected.is_some_and(|value| ensure_observation_matches(&source_after, value).is_err())
    {
        cleanup_destination(destination, destination_ancestors);
        return Err(CoreError::conflict(current_path.display().to_string()));
    }
    Ok(())
}

#[cfg(not(unix))]
fn ensure_source_unchanged(
    path: &Path,
    before: &SourceObservation,
    expected_hash: Option<&str>,
) -> CoreResult<()> {
    let after = observe_source(path, expected_hash)?;
    if same_observation(before, &after) {
        Ok(())
    } else {
        Err(CoreError::conflict(path.display().to_string()))
    }
}

#[cfg(not(unix))]
fn observe_source(path: &Path, expected_hash: Option<&str>) -> CoreResult<SourceObservation> {
    ensure_safe_file_path(path)?;
    let metadata = fs::symlink_metadata(path).map_err(hash::map_io_error)?;
    let modified_nanos = modified_nanos(&metadata)?;
    let hash = expected_hash
        .map(|_| hash::hash_file(path).map(|value| value.hash_sha256))
        .transpose()?;
    Ok(SourceObservation {
        identity: metadata_identity(&metadata),
        size: metadata.len() as i64,
        modified_nanos,
        hash,
        ancestors: directory_identity(path.parent().unwrap_or(path))?,
    })
}

fn ensure_observation_matches(
    observation: &SourceObservation,
    expected: SourceExpectation<'_>,
) -> CoreResult<()> {
    if observation.identity != expected.identity
        || observation.size != expected.size
        || observation.modified_nanos != expected.modified_nanos
        || expected
            .hash
            .is_some_and(|hash| observation.hash.as_deref() != Some(hash))
    {
        Err(CoreError::conflict("stale file identity"))
    } else {
        Ok(())
    }
}

#[cfg(not(unix))]
fn same_observation(left: &SourceObservation, right: &SourceObservation) -> bool {
    left.identity == right.identity
        && left.size == right.size
        && left.modified_nanos == right.modified_nanos
        && left.hash == right.hash
        && {
            #[cfg(not(unix))]
            {
                left.ancestors == right.ancestors
            }
            #[cfg(unix)]
            {
                true
            }
        }
}

#[cfg(not(unix))]
fn ensure_destination_absent(path: &Path) -> CoreResult<()> {
    match fs::symlink_metadata(path) {
        Ok(_) => Err(CoreError::conflict(path.display().to_string())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(hash::map_io_error(error)),
    }
}

#[cfg(not(unix))]
fn cleanup_destination(path: &Path, expected_ancestors: &str) {
    if directory_identity(path.parent().unwrap_or(path))
        .ok()
        .as_deref()
        != Some(expected_ancestors)
    {
        return;
    }
    if let Ok(metadata) = fs::symlink_metadata(path) {
        if !metadata.file_type().is_symlink() && metadata.is_file() {
            let _cleanup_result = fs::remove_file(path);
        }
    }
}

fn path_exists_no_follow(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

pub(super) fn ensure_safe_file_path(path: &Path) -> CoreResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    directory_identity(parent)?;
    let metadata = fs::symlink_metadata(path).map_err(hash::map_io_error)?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(CoreError::conflict(path.display().to_string()));
    }
    Ok(())
}

/// Ensures that every existing ancestor is a real directory. Missing
/// destination ancestors are created one component at a time and rechecked,
/// so a symlink cannot redirect `create_dir_all` outside the intended tree.
pub(super) fn ensure_directory_chain(path: &Path, create_missing: bool) -> CoreResult<()> {
    let mut current = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(prefix) => current.push(prefix.as_os_str()),
            Component::RootDir => current.push(Path::new(std::path::MAIN_SEPARATOR_STR)),
            Component::CurDir => {}
            Component::ParentDir => {
                return Err(CoreError::invalid_path(path.display().to_string()))
            }
            Component::Normal(part) => {
                current.push(part);
                match fs::symlink_metadata(&current) {
                    Ok(metadata)
                        if (metadata.file_type().is_symlink()
                            && !is_allowed_system_alias(&current))
                            || (!metadata.file_type().is_symlink() && !metadata.is_dir()) =>
                    {
                        return Err(CoreError::conflict(current.display().to_string()));
                    }
                    Ok(_) => {}
                    Err(error)
                        if error.kind() == std::io::ErrorKind::NotFound && create_missing =>
                    {
                        fs::create_dir(&current).map_err(hash::map_io_error)?;
                        let metadata =
                            fs::symlink_metadata(&current).map_err(hash::map_io_error)?;
                        if (metadata.file_type().is_symlink() && !is_allowed_system_alias(&current))
                            || (!metadata.file_type().is_symlink() && !metadata.is_dir())
                        {
                            return Err(CoreError::conflict(current.display().to_string()));
                        }
                    }
                    Err(error) => return Err(hash::map_io_error(error)),
                }
            }
        }
    }
    Ok(())
}

pub(super) fn directory_identity(path: &Path) -> CoreResult<String> {
    reject_untrusted_lexical_symlinks(path)?;
    let canonical = fs::canonicalize(path).map_err(hash::map_io_error)?;
    let mut ancestors = canonical.ancestors().collect::<Vec<_>>();
    ancestors.reverse();
    let mut result = String::new();
    for ancestor in ancestors {
        if ancestor.as_os_str().is_empty() {
            continue;
        }
        let metadata = fs::symlink_metadata(ancestor).map_err(hash::map_io_error)?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err(CoreError::conflict(ancestor.display().to_string()));
        }
        result.push_str(&ancestor.to_string_lossy());
        result.push('\0');
        result.push_str(&metadata_identity(&metadata));
        result.push('\0');
    }
    Ok(result)
}

fn reject_untrusted_lexical_symlinks(path: &Path) -> CoreResult<()> {
    let mut ancestors = path.ancestors().collect::<Vec<_>>();
    ancestors.reverse();
    for ancestor in ancestors {
        let metadata = match fs::symlink_metadata(ancestor) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(hash::map_io_error(error)),
        };
        if metadata.file_type().is_symlink() && !is_allowed_system_alias(ancestor) {
            return Err(CoreError::conflict(ancestor.display().to_string()));
        }
    }
    Ok(())
}

fn is_allowed_system_alias(path: &Path) -> bool {
    #[cfg(unix)]
    {
        let text = path.to_string_lossy();
        if text != "/tmp" && text != "/var" {
            return false;
        }
        fs::canonicalize(path)
            .map(|target| target.starts_with("/private"))
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        false
    }
}

#[cfg(unix)]
fn metadata_identity(metadata: &fs::Metadata) -> String {
    use std::os::unix::fs::MetadataExt;

    format!("unix:{}:{}", metadata.dev(), metadata.ino())
}

#[cfg(not(unix))]
fn metadata_identity(metadata: &fs::Metadata) -> String {
    format!("portable:{}", metadata.len())
}

fn modified_nanos(metadata: &fs::Metadata) -> CoreResult<u128> {
    let modified = metadata
        .modified()
        .map_err(hash::map_io_error)?
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::io(error.to_string()))?;
    Ok(modified.as_nanos())
}

fn map_source_removal_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::file_not_found("missing file"),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    #[test]
    fn resolve_name_conflict_safe_move_refuses_existing_destination_without_overwrite() {
        let dir = tempfile::tempdir().expect("create safe-move tempdir");
        let source = dir.path().join("source.pdf");
        let destination = dir.path().join("target.pdf");
        fs::write(&source, b"new content").expect("write source file");
        fs::write(&destination, b"existing content").expect("write existing destination");

        let result = move_recoverable_file(&source, &destination);

        assert!(matches!(result, Err(CoreError::Conflict { .. })));
        assert_eq!(
            fs::read(&source).expect("source remains readable after refused move"),
            b"new content"
        );
        assert_eq!(
            fs::read(&destination).expect("destination remains unmodified"),
            b"existing content"
        );
    }
}
