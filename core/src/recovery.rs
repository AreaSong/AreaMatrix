use std::{
    collections::HashSet,
    fs::{self, File, OpenOptions},
    io,
    path::{Component, Path, PathBuf},
};

use crate::{db, CoreError, CoreResult, RecoveryReport, StorageMode};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const STAGING_DIR: &str = "staging";

enum StagingRoot {
    Missing,
    Directory(PathBuf),
}

enum StagingFileState {
    Missing,
    Removable(PathBuf),
    Unsafe(String),
}

enum MovedFileRecovery {
    Restored,
    Kept(String),
}

pub(crate) fn recover_on_startup(repo_path: String) -> CoreResult<RecoveryReport> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::repo_not_initialized(
            "repository not initialized",
        ));
    }

    let repo = PathBuf::from(repo_path);
    db::ensure_initialized_readable(&repo)?;

    let staging_root = inspect_staging_root(&staging_dir(&repo))?;
    let protected_paths = protected_staging_paths(&repo)?;
    let staging_rows = db::list_staging_file_rows(&repo)?;
    let mut report = empty_report();

    for row in staging_rows {
        recover_staging_row(&repo, &staging_root, row, &mut report)?;
    }
    clean_orphan_staging_files(&staging_root, &protected_paths, &mut report)?;

    Ok(report)
}

fn empty_report() -> RecoveryReport {
    RecoveryReport {
        cleaned_staging_files: 0,
        reverted_staging_db_rows: 0,
        warnings: Vec::new(),
    }
}

fn recover_staging_row(
    repo: &Path,
    staging_root: &StagingRoot,
    row: db::StagingFileRow,
    report: &mut RecoveryReport,
) -> CoreResult<()> {
    let Some(relative_path) = safe_staging_relative_path(&row.path) else {
        report.warnings.push(format!(
            "Skipped filesystem cleanup for non-staging row {} at {}",
            row.id, row.path
        ));
        db::delete_staging_file_row(repo, row.id)?;
        report.reverted_staging_db_rows += 1;
        return Ok(());
    };

    if row.storage_mode == StorageMode::Moved {
        return recover_moved_staging_row(repo, staging_root, row, &relative_path, report);
    }
    recover_internal_staging_row(repo, staging_root, row, &relative_path, report)
}

fn recover_internal_staging_row(
    repo: &Path,
    staging_root: &StagingRoot,
    row: db::StagingFileRow,
    relative_path: &Path,
    report: &mut RecoveryReport,
) -> CoreResult<()> {
    if let StagingRoot::Directory(staging_dir) = staging_root {
        match staging_file_state(staging_dir, relative_path)? {
            StagingFileState::Removable(path) => {
                ensure_staging_root_is_directory(staging_dir)?;
                remove_staging_file(&path)?;
                report.cleaned_staging_files += 1;
            }
            StagingFileState::Unsafe(reason) => report.warnings.push(format!(
                "Skipped unsafe staging cleanup for row {} at {}: {}",
                row.id, row.path, reason
            )),
            StagingFileState::Missing => {}
        }
    }
    db::delete_staging_file_row(repo, row.id)?;
    report.reverted_staging_db_rows += 1;
    Ok(())
}

fn recover_moved_staging_row(
    repo: &Path,
    staging_root: &StagingRoot,
    row: db::StagingFileRow,
    relative_path: &Path,
    report: &mut RecoveryReport,
) -> CoreResult<()> {
    let StagingRoot::Directory(staging_dir) = staging_root else {
        db::delete_staging_file_row(repo, row.id)?;
        report.reverted_staging_db_rows += 1;
        return Ok(());
    };

    match staging_file_state(staging_dir, relative_path)? {
        StagingFileState::Removable(path) => {
            ensure_staging_root_is_directory(staging_dir)?;
            match restore_moved_staging_file(&path, row.source_path.as_deref())? {
                MovedFileRecovery::Restored => {
                    db::delete_staging_file_row(repo, row.id)?;
                    report.reverted_staging_db_rows += 1;
                }
                MovedFileRecovery::Kept(reason) => report.warnings.push(format!(
                    "Kept moved staging row {} at {}: {}",
                    row.id, row.path, reason
                )),
            }
        }
        StagingFileState::Missing => {
            db::delete_staging_file_row(repo, row.id)?;
            report.reverted_staging_db_rows += 1;
        }
        StagingFileState::Unsafe(reason) => report.warnings.push(format!(
            "Kept unsafe moved staging row {} at {}: {}",
            row.id, row.path, reason
        )),
    }
    Ok(())
}

fn clean_orphan_staging_files(
    staging_root: &StagingRoot,
    protected_paths: &HashSet<PathBuf>,
    report: &mut RecoveryReport,
) -> CoreResult<()> {
    let StagingRoot::Directory(staging_dir) = staging_root else {
        return Ok(());
    };
    ensure_staging_root_is_directory(staging_dir)?;

    for entry in fs::read_dir(staging_dir).map_err(map_io_error)? {
        let entry = entry.map_err(map_io_error)?;
        let file_type = entry.file_type().map_err(map_io_error)?;
        let relative_path = Path::new(AREA_MATRIX_DIR)
            .join(STAGING_DIR)
            .join(entry.file_name());

        if protected_paths.contains(&relative_path) {
            report.warnings.push(format!(
                "Kept protected staging path {}",
                relative_path.display()
            ));
            continue;
        }

        if file_type.is_file() || file_type.is_symlink() {
            if is_safe_copy_orphan_name(&entry.file_name()) {
                ensure_staging_root_is_directory(staging_dir)?;
                remove_staging_file(&entry.path())?;
                report.cleaned_staging_files += 1;
            } else {
                report.warnings.push(format!(
                    "Kept unclassified staging file {}",
                    relative_path.display()
                ));
            }
        } else {
            report.warnings.push(format!(
                "Kept non-file staging entry {}",
                relative_path.display()
            ));
        }
    }
    Ok(())
}

fn staging_dir(repo: &Path) -> PathBuf {
    repo.join(AREA_MATRIX_DIR).join(STAGING_DIR)
}

fn inspect_staging_root(staging_dir: &Path) -> CoreResult<StagingRoot> {
    match fs::symlink_metadata(staging_dir) {
        Ok(metadata) if metadata.file_type().is_dir() => {
            Ok(StagingRoot::Directory(staging_dir.to_path_buf()))
        }
        Ok(_) => Err(CoreError::io("io error")),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(StagingRoot::Missing),
        Err(error) => Err(map_io_error(error)),
    }
}

fn ensure_staging_root_is_directory(staging_dir: &Path) -> CoreResult<()> {
    match inspect_staging_root(staging_dir)? {
        StagingRoot::Directory(_) => Ok(()),
        StagingRoot::Missing => Err(CoreError::io("io error")),
    }
}

fn protected_staging_paths(repo: &Path) -> CoreResult<HashSet<PathBuf>> {
    let paths = db::list_protected_staging_paths(repo)?
        .into_iter()
        .filter_map(|path| safe_staging_relative_path(&path))
        .collect::<HashSet<_>>();
    Ok(paths)
}

fn is_safe_copy_orphan_name(name: &std::ffi::OsStr) -> bool {
    name.to_string_lossy().starts_with("copy-import-")
}

fn safe_staging_relative_path(value: &str) -> Option<PathBuf> {
    let path = Path::new(value);
    if path.is_absolute() {
        return None;
    }

    let mut components = path.components();
    if !matches!(components.next(), Some(Component::Normal(part)) if part == AREA_MATRIX_DIR) {
        return None;
    }
    if !matches!(components.next(), Some(Component::Normal(part)) if part == STAGING_DIR) {
        return None;
    }

    let rest = components.collect::<Vec<_>>();
    if rest.is_empty() || rest.iter().any(|component| !is_safe_component(component)) {
        return None;
    }
    Some(path.to_path_buf())
}

fn staging_file_state(staging_dir: &Path, relative_path: &Path) -> CoreResult<StagingFileState> {
    let tail = relative_path.components().skip(2).collect::<Vec<_>>();
    let Some((file_name, parents)) = tail.split_last() else {
        return Ok(StagingFileState::Missing);
    };

    let mut parent = staging_dir.to_path_buf();
    for component in parents {
        parent.push(component.as_os_str());
        let metadata = match fs::symlink_metadata(&parent) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(StagingFileState::Missing);
            }
            Err(error) => return Err(map_io_error(error)),
        };
        if metadata.file_type().is_symlink() || !metadata.file_type().is_dir() {
            return Ok(StagingFileState::Unsafe(format!(
                "parent {} is not an owned staging directory",
                parent.display()
            )));
        }
    }

    let candidate = parent.join(file_name.as_os_str());
    match fs::symlink_metadata(&candidate) {
        Ok(metadata) if metadata.file_type().is_file() || metadata.file_type().is_symlink() => {
            Ok(StagingFileState::Removable(candidate))
        }
        Ok(_) => Ok(StagingFileState::Unsafe(format!(
            "{} is not a removable staging file",
            candidate.display()
        ))),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(StagingFileState::Missing),
        Err(error) => Err(map_io_error(error)),
    }
}

fn is_safe_component(component: &Component<'_>) -> bool {
    matches!(component, Component::Normal(_))
}

fn remove_staging_file(path: &Path) -> CoreResult<()> {
    fs::remove_file(path).map_err(map_io_error)
}

fn restore_moved_staging_file(
    staging_path: &Path,
    source_path: Option<&str>,
) -> CoreResult<MovedFileRecovery> {
    let Some(source_path) = recoverable_source_path(source_path) else {
        return Ok(MovedFileRecovery::Kept(
            "missing absolute original source path".to_owned(),
        ));
    };
    if source_path.try_exists().map_err(map_io_error)? {
        return Ok(MovedFileRecovery::Kept(format!(
            "original source path already exists at {}",
            source_path.display()
        )));
    }
    let Some(parent) = source_path.parent() else {
        return Ok(MovedFileRecovery::Kept(
            "original source path has no parent".to_owned(),
        ));
    };
    if !parent.try_exists().map_err(map_io_error)? {
        return Ok(MovedFileRecovery::Kept(format!(
            "original source parent is missing at {}",
            parent.display()
        )));
    }

    match move_file_no_replace(staging_path, &source_path) {
        Ok(()) => Ok(MovedFileRecovery::Restored),
        Err(CoreError::Conflict { .. }) => Ok(MovedFileRecovery::Kept(format!(
            "original source path appeared during recovery at {}",
            source_path.display()
        ))),
        Err(error) => Err(error),
    }
}

fn recoverable_source_path(source_path: Option<&str>) -> Option<PathBuf> {
    source_path
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
}

fn move_file_no_replace(current_path: &Path, destination: &Path) -> CoreResult<()> {
    match fs::hard_link(current_path, destination) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            return Err(CoreError::conflict("path conflict"));
        }
        Err(_) => copy_to_new_destination(current_path, destination)?,
    }

    match fs::remove_file(current_path) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _cleanup_result = fs::remove_file(destination);
            Err(map_io_error(error))
        }
    }
}

fn copy_to_new_destination(current_path: &Path, destination: &Path) -> CoreResult<()> {
    let expected_size = current_path.metadata().map_err(map_io_error)?.len();
    let mut reader = File::open(current_path).map_err(map_io_error)?;
    let mut writer = match OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(destination)
    {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            return Err(CoreError::conflict("path conflict"));
        }
        Err(error) => return Err(map_io_error(error)),
    };
    let copied_size = match io::copy(&mut reader, &mut writer) {
        Ok(size) => size,
        Err(error) => {
            let _cleanup_result = fs::remove_file(destination);
            return Err(map_io_error(error));
        }
    };
    if copied_size != expected_size {
        let _cleanup_result = fs::remove_file(destination);
        return Err(CoreError::io("io error"));
    }
    Ok(())
}

fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}
