use std::{
    ffi::OsStr,
    fs,
    io::Write,
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
    let mut rollback = SidecarRollback::capture(&sidecar, previous_sidecar);
    write_sidecar_atomically(&sidecar, &content_md)?;

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

fn write_sidecar_atomically(path: &Path, content: &str) -> CoreResult<()> {
    let parent = path.parent().ok_or(CoreError::InvalidPath)?;
    let temp_path = temporary_sidecar_path(path)?;
    let result = write_temp_file(&temp_path, content).and_then(|()| rename_temp(&temp_path, path));
    if result.is_err() {
        // The destination is unchanged on this branch; leftover temp cleanup is best effort.
        let _cleanup_result = fs::remove_file(&temp_path);
    }
    // The temp file itself is fsync'ed; directory fsync is best effort for portability.
    let _sync_result = sync_directory(parent);
    result
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
            Some(content) => write_sidecar_atomically(&self.path, content)?,
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
