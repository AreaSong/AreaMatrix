use std::{
    ffi::OsStr,
    fs,
    io::{self, Write},
    path::{Component, Path, PathBuf},
};

use uuid::Uuid;

use crate::{db, CoreError, CoreResult, FileEntry};

const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(crate) fn read_note(repo_path: String, file_id: i64) -> CoreResult<Option<String>> {
    let repo = validate_repo_path(&repo_path)?;
    let entry = db::get_active_file_by_id(&repo, file_id)?;
    let Some(content) = db::read_note_content(&repo, file_id)? else {
        return Ok(None);
    };

    let sidecar = sidecar_path(&repo, &entry)?;
    let sidecar_content = read_text_file(&sidecar)?;
    if sidecar_content == content {
        Ok(Some(content))
    } else {
        Err(CoreError::Db)
    }
}

pub(crate) fn write_note(repo_path: String, file_id: i64, content_md: String) -> CoreResult<()> {
    let repo = validate_repo_path(&repo_path)?;
    let entry = db::get_active_file_by_id(&repo, file_id)?;
    let target = entry_file_path(&repo, &entry)?;
    ensure_regular_file(&target)?;

    let sidecar = sidecar_path(&repo, &entry)?;
    let previous_note = db::read_note_content(&repo, file_id)?;
    let previous_sidecar = read_optional_text_file(&sidecar)?;
    validate_previous_sidecar(previous_note.as_deref(), previous_sidecar.as_deref())?;

    let length_before = markdown_len(previous_note.as_deref().unwrap_or_default());
    let length_after = markdown_len(&content_md);
    let write_policy = SidecarWritePolicy::from_previous(previous_sidecar.as_deref());
    let mut rollback = SidecarRollback::capture(&sidecar, previous_sidecar);
    write_sidecar_atomically(&sidecar, &content_md, write_policy)?;

    if let Err(error) =
        db::upsert_note_and_log(&repo, file_id, &content_md, length_before, length_after)
    {
        rollback.restore()?;
        return Err(error);
    }

    rollback.disarm();
    Ok(())
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::InvalidPath);
    }
    Ok(PathBuf::from(repo_path))
}

fn entry_file_path(repo: &Path, entry: &FileEntry) -> CoreResult<PathBuf> {
    let path = Path::new(&entry.path);
    validate_entry_path(path)?;
    if path.is_absolute() {
        Ok(path.to_path_buf())
    } else {
        Ok(repo.join(path))
    }
}

fn sidecar_path(repo: &Path, entry: &FileEntry) -> CoreResult<PathBuf> {
    let target = entry_file_path(repo, entry)?;
    let parent = target.parent().ok_or(CoreError::InvalidPath)?;
    let file_name = target
        .file_name()
        .and_then(OsStr::to_str)
        .filter(|value| !value.is_empty())
        .ok_or(CoreError::InvalidPath)?;
    Ok(parent.join(format!("{file_name}.md")))
}

fn validate_entry_path(path: &Path) -> CoreResult<()> {
    if path.as_os_str().is_empty() {
        return Err(CoreError::InvalidPath);
    }

    for component in path.components() {
        match component {
            Component::Normal(part) => {
                if part == OsStr::new(AREA_MATRIX_DIR) {
                    return Err(CoreError::InvalidPath);
                }
            }
            Component::RootDir | Component::Prefix(_) => {
                if !path.is_absolute() {
                    return Err(CoreError::InvalidPath);
                }
            }
            Component::CurDir | Component::ParentDir => return Err(CoreError::InvalidPath),
        }
    }
    Ok(())
}

fn ensure_regular_file(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_io_error)?;
    if metadata.is_file() {
        Ok(())
    } else {
        Err(CoreError::FileNotFound)
    }
}

fn validate_previous_sidecar(
    previous_note: Option<&str>,
    previous_sidecar: Option<&str>,
) -> CoreResult<()> {
    match (previous_note, previous_sidecar) {
        (None, None) => Ok(()),
        (None, Some(_)) => Err(CoreError::PermissionDenied),
        (Some(_), None) => Err(CoreError::Io),
        (Some(note), Some(sidecar)) if note == sidecar => Ok(()),
        (Some(_), Some(_)) => Err(CoreError::Db),
    }
}

fn read_text_file(path: &Path) -> CoreResult<String> {
    fs::read_to_string(path).map_err(map_io_error)
}

fn read_optional_text_file(path: &Path) -> CoreResult<Option<String>> {
    match fs::read_to_string(path) {
        Ok(content) => Ok(Some(content)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(map_io_error(error)),
    }
}

#[derive(Clone, Copy)]
enum SidecarWritePolicy {
    CreateNew,
    ReplaceExisting,
}

impl SidecarWritePolicy {
    fn from_previous(previous_sidecar: Option<&str>) -> Self {
        match previous_sidecar {
            Some(_) => Self::ReplaceExisting,
            None => Self::CreateNew,
        }
    }
}

fn write_sidecar_atomically(
    path: &Path,
    content: &str,
    policy: SidecarWritePolicy,
) -> CoreResult<()> {
    let parent = path.parent().ok_or(CoreError::InvalidPath)?;
    let temp_path = temporary_sidecar_path(path)?;
    let result =
        write_temp_file(&temp_path, content).and_then(|()| persist_temp(&temp_path, path, policy));
    if result.is_err() {
        // The destination is unchanged on this branch; leftover temp cleanup is best effort.
        let _cleanup_result = fs::remove_file(&temp_path);
    }
    // The temp file itself is fsync'ed; directory fsync is best effort for portability.
    let _sync_result = sync_directory(parent);
    result
}

fn persist_temp(temp_path: &Path, final_path: &Path, policy: SidecarWritePolicy) -> CoreResult<()> {
    match policy {
        SidecarWritePolicy::CreateNew => persist_temp_without_replace(temp_path, final_path),
        SidecarWritePolicy::ReplaceExisting => rename_temp(temp_path, final_path),
    }
}

fn persist_temp_without_replace(temp_path: &Path, final_path: &Path) -> CoreResult<()> {
    match fs::hard_link(temp_path, final_path) {
        Ok(()) => remove_temp_after_persist(temp_path, final_path),
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            Err(CoreError::PermissionDenied)
        }
        Err(_) => copy_temp_without_replace(temp_path, final_path),
    }
}

fn copy_temp_without_replace(temp_path: &Path, final_path: &Path) -> CoreResult<()> {
    let mut source = fs::File::open(temp_path).map_err(map_io_error)?;
    let expected_size = source.metadata().map_err(map_io_error)?.len();
    let mut destination = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(final_path)
        .map_err(map_create_sidecar_error)?;

    let result = copy_temp_to_new_file(&mut source, &mut destination, expected_size)
        .and_then(|()| remove_temp_after_persist(temp_path, final_path));
    if result.is_err() {
        let _cleanup_result = fs::remove_file(final_path);
    }
    result
}

fn copy_temp_to_new_file(
    source: &mut fs::File,
    destination: &mut fs::File,
    expected_size: u64,
) -> CoreResult<()> {
    let copied_size = io::copy(source, destination).map_err(map_io_error)?;
    if copied_size != expected_size {
        return Err(CoreError::Io);
    }
    destination.sync_all().map_err(map_io_error)
}

fn remove_temp_after_persist(temp_path: &Path, final_path: &Path) -> CoreResult<()> {
    match fs::remove_file(temp_path) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _cleanup_result = fs::remove_file(final_path);
            Err(map_io_error(error))
        }
    }
}

fn temporary_sidecar_path(path: &Path) -> CoreResult<PathBuf> {
    let file_name = path
        .file_name()
        .and_then(OsStr::to_str)
        .filter(|value| !value.is_empty())
        .ok_or(CoreError::InvalidPath)?;
    Ok(path.with_file_name(format!(".{file_name}.{}.tmp", Uuid::new_v4())))
}

fn write_temp_file(path: &Path, content: &str) -> CoreResult<()> {
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(map_io_error)?;
    file.write_all(content.as_bytes()).map_err(map_io_error)?;
    file.sync_all().map_err(map_io_error)
}

fn rename_temp(temp_path: &Path, final_path: &Path) -> CoreResult<()> {
    fs::rename(temp_path, final_path).map_err(map_io_error)
}

fn sync_directory(path: &Path) -> CoreResult<()> {
    let directory = fs::File::open(path).map_err(map_io_error)?;
    directory.sync_all().map_err(map_io_error)
}

fn markdown_len(content: &str) -> i64 {
    content.chars().count() as i64
}

fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::FileNotFound,
        std::io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        std::io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    }
}

fn map_create_sidecar_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::AlreadyExists => CoreError::PermissionDenied,
        _ => map_io_error(error),
    }
}

struct SidecarRollback {
    path: PathBuf,
    previous: Option<String>,
    armed: bool,
}

impl SidecarRollback {
    fn capture(path: &Path, previous: Option<String>) -> Self {
        Self {
            path: path.to_path_buf(),
            previous,
            armed: true,
        }
    }

    fn restore(&mut self) -> CoreResult<()> {
        if !self.armed {
            return Ok(());
        }

        match &self.previous {
            Some(content) => {
                write_sidecar_atomically(&self.path, content, SidecarWritePolicy::ReplaceExisting)?;
            }
            None => match fs::remove_file(&self.path) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(map_io_error(error)),
            },
        }
        self.disarm();
        Ok(())
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_write_note_sidecar_create_new_refuses_final_time_existing_destination() {
        let dir = tempfile::tempdir().expect("create note tempdir");
        let sidecar = dir.path().join("report.pdf.md");
        fs::write(&sidecar, "external note").expect("write external sidecar");

        let result = write_sidecar_atomically(&sidecar, "new note", SidecarWritePolicy::CreateNew);

        assert_eq!(result, Err(CoreError::PermissionDenied));
        assert_eq!(
            fs::read_to_string(&sidecar).expect("read preserved external sidecar"),
            "external note"
        );
    }
}
