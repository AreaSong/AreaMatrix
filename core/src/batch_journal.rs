//! Durable per-item manifests for filesystem/SQLite batch mutations.
//!
//! A batch item changes two independently durable stores (the repository files
//! and SQLite). The manifest is written and synced before either store is
//! changed. Startup recovery then decides whether the item is still in the old
//! state (rollback), already in the new state (commit), or ambiguous (fail
//! closed and leave the manifest for a later, explicit recovery).

use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::{Component, Path, PathBuf},
};
use uuid::Uuid;

const JOURNAL_VERSION: u32 = 1;
const BATCH_JOURNAL_DIR: &str = ".areamatrix/staging/batch";

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct BatchJournal {
    pub version: u32,
    pub operation: String,
    pub file_id: i64,
    pub original_relative: String,
    pub current_relative: String,
    pub original_db_path: String,
    pub current_db_path: String,
    pub original_name: String,
    pub current_name: String,
    pub original_category: String,
    pub current_category: String,
    pub file_hash_sha256: String,
    pub sidecar: Option<BatchSidecarJournal>,
    /// A target directory which may have been created by this item. The
    /// identity is filled after directory creation and synced again. A
    /// missing identity is deliberately never removed during recovery.
    pub planned_directory_relative: Option<String>,
    pub created_directory_identity: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct BatchSidecarJournal {
    pub original_relative: String,
    pub current_relative: String,
    pub hash_sha256: String,
}

#[derive(Clone, Debug)]
pub(crate) struct BatchJournalPaths {
    pub original: PathBuf,
    pub current: PathBuf,
    pub sidecar: Option<(PathBuf, PathBuf)>,
    pub planned_directory: Option<PathBuf>,
}

pub(crate) struct BatchJournalInput<'a> {
    pub operation: &'a str,
    pub file_id: i64,
    pub original: &'a Path,
    pub current: &'a Path,
    pub original_db_path: &'a str,
    pub current_db_path: &'a str,
    pub original_name: &'a str,
    pub current_name: &'a str,
    pub original_category: &'a str,
    pub current_category: &'a str,
    pub file_hash_sha256: &'a str,
    pub sidecar: Option<(&'a Path, &'a Path)>,
    pub planned_directory: Option<&'a Path>,
}

impl BatchJournal {
    pub(crate) fn for_paths(repo: &Path, input: BatchJournalInput<'_>) -> io::Result<Self> {
        let sidecar = input
            .sidecar
            .map(|(old, new)| {
                Ok::<BatchSidecarJournal, io::Error>(BatchSidecarJournal {
                    original_relative: relative_path(repo, old)?,
                    current_relative: relative_path(repo, new)?,
                    hash_sha256: hash_file(old)?,
                })
            })
            .transpose()?;
        Ok(Self {
            version: JOURNAL_VERSION,
            operation: input.operation.to_owned(),
            file_id: input.file_id,
            original_relative: relative_path(repo, input.original)?,
            current_relative: relative_path(repo, input.current)?,
            original_db_path: validate_db_relative_path(input.original_db_path)?,
            current_db_path: validate_db_relative_path(input.current_db_path)?,
            original_name: input.original_name.to_owned(),
            current_name: input.current_name.to_owned(),
            original_category: input.original_category.to_owned(),
            current_category: input.current_category.to_owned(),
            file_hash_sha256: input.file_hash_sha256.to_owned(),
            sidecar,
            planned_directory_relative: input
                .planned_directory
                .map(|path| relative_path(repo, path))
                .transpose()?,
            created_directory_identity: None,
        })
    }

    pub(crate) fn paths(&self, repo: &Path) -> io::Result<BatchJournalPaths> {
        validate_relative_path(&self.original_relative)?;
        validate_relative_path(&self.current_relative)?;
        let sidecar = self
            .sidecar
            .as_ref()
            .map(|value| {
                Ok::<(PathBuf, PathBuf), io::Error>((
                    repo.join(validate_relative_path(&value.original_relative)?),
                    repo.join(validate_relative_path(&value.current_relative)?),
                ))
            })
            .transpose()?;
        let planned_directory = self
            .planned_directory_relative
            .as_deref()
            .map(|value| Ok::<PathBuf, io::Error>(repo.join(validate_relative_path(value)?)))
            .transpose()?;
        Ok(BatchJournalPaths {
            original: repo.join(&self.original_relative),
            current: repo.join(&self.current_relative),
            sidecar,
            planned_directory,
        })
    }
}

pub(crate) fn create(repo: &Path, journal: &BatchJournal) -> io::Result<PathBuf> {
    let directory = repo.join(BATCH_JOURNAL_DIR);
    ensure_directory_chain(&directory)?;
    let path = directory.join(format!("{}.json", Uuid::new_v4()));
    let bytes = serde_json::to_vec(journal).map_err(io_other)?;
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)?;
    file.write_all(&bytes)?;
    file.sync_all()?;
    sync_directory(&directory);
    Ok(path)
}

/// Updates the directory identity after the directory mutation. The update is
/// an atomic same-directory replace, so a crash leaves either the old,
/// conservative manifest or the complete new one.
pub(crate) fn set_created_directory(
    journal_path: &Path,
    identity: Option<String>,
) -> io::Result<()> {
    let bytes = fs::read(journal_path)?;
    let mut journal: BatchJournal = serde_json::from_slice(&bytes).map_err(io_other)?;
    journal.created_directory_identity = identity;
    let encoded = serde_json::to_vec(&journal).map_err(io_other)?;
    let parent = journal_path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "journal parent missing"))?;
    let temporary = parent.join(format!(".{}.tmp-{}", Uuid::new_v4(), Uuid::new_v4()));
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(&encoded)?;
        file.sync_all()?;
        fs::rename(&temporary, journal_path)?;
        sync_directory(parent);
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

pub(crate) fn remove(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => {
            if let Some(parent) = path.parent() {
                sync_directory(parent);
                // Only remove the private batch directory when it is empty;
                // never remove a user directory or a non-directory alias.
                if let Ok(metadata) = fs::symlink_metadata(parent) {
                    if metadata.is_dir() {
                        let _ = fs::remove_dir(parent);
                    }
                }
            }
            Ok(())
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

pub(crate) fn directory_identity(path: &Path) -> io::Result<String> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "directory is not a real directory",
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        Ok(format!("unix:{}:{}", metadata.dev(), metadata.ino()))
    }
    #[cfg(not(unix))]
    {
        let modified = metadata
            .modified()
            .ok()
            .and_then(|value| value.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|value| value.as_nanos())
            .unwrap_or_default();
        Ok(format!("portable:{}:{}", metadata.len(), modified))
    }
}

pub(crate) fn recover(repo: &Path, warnings: &mut Vec<String>) -> io::Result<u64> {
    let directory = repo.join(BATCH_JOURNAL_DIR);
    let entries = match fs::read_dir(&directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(0),
        Err(error) => return Err(error),
    };
    let mut count = 0_u64;
    for entry in entries {
        let entry = entry?;
        let path = entry.path();
        let file_type = entry.file_type()?;
        if !file_type.is_file() {
            warnings.push(format!(
                "kept non-file batch journal entry {}",
                path.display()
            ));
            continue;
        }
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) => {
                warnings.push(format!(
                    "kept unreadable batch journal {}: {error}",
                    path.display()
                ));
                continue;
            }
        };
        let journal: BatchJournal = match serde_json::from_slice::<BatchJournal>(&bytes) {
            Ok(value) if value.version == JOURNAL_VERSION && value.file_id > 0 => value,
            _ => {
                warnings.push(format!("kept invalid batch journal {}", path.display()));
                continue;
            }
        };
        let paths = match journal.paths(repo) {
            Ok(paths) => paths,
            Err(error) => {
                warnings.push(format!(
                    "kept unsafe batch journal {}: {error}",
                    path.display()
                ));
                continue;
            }
        };
        if !safe_repo_path(repo, &paths.original)
            || !safe_repo_path(repo, &paths.current)
            || paths
                .sidecar
                .as_ref()
                .is_some_and(|(old, new)| !safe_repo_path(repo, old) || !safe_repo_path(repo, new))
            || paths
                .planned_directory
                .as_ref()
                .is_some_and(|directory| !safe_repo_path(repo, directory))
        {
            warnings.push(format!(
                "kept batch journal {} because a path ancestor is unsafe",
                path.display()
            ));
            continue;
        }
        let Some(db_state) = load_db_state(repo, journal.file_id)? else {
            warnings.push(format!(
                "kept batch journal {} because file {} is not active",
                path.display(),
                journal.file_id
            ));
            continue;
        };
        let db_old = db_state.path == journal.original_db_path
            && db_state.name == journal.original_name
            && db_state.category == journal.original_category;
        let db_new = db_state.path == journal.current_db_path
            && db_state.name == journal.current_name
            && db_state.category == journal.current_category;
        if !db_old && !db_new {
            warnings.push(format!(
                "kept ambiguous batch journal {}: database state diverged",
                path.display()
            ));
            continue;
        }

        let main_state = path_state(&paths.original, &paths.current, &journal.file_hash_sha256)?;
        let sidecar_state = sidecar_path_state(&paths, &journal)?;
        // A journal without a sidecar has only one filesystem participant.
        // Treat the absent sidecar as neutral rather than as an old state;
        // otherwise a committed main-file move can never be recognized as
        // fully new and its durable journal would remain forever.
        let has_sidecar = journal.sidecar.is_some();
        let all_old =
            main_state == FsPathState::Old && (!has_sidecar || sidecar_state == FsPathState::Old);
        let all_new =
            main_state == FsPathState::New && (!has_sidecar || sidecar_state == FsPathState::New);
        let no_ambiguous_paths = !matches!(main_state, FsPathState::Ambiguous)
            && (!has_sidecar || !matches!(sidecar_state, FsPathState::Ambiguous));

        if db_new && all_new {
            // The new state is committed. A target directory containing the
            // committed file is intentionally retained; cleanup here would
            // only emit a misleading non-empty-directory warning.
            if remove(&path).is_ok() {
                count = count.saturating_add(1);
            } else {
                warnings.push(format!("kept completed batch journal {}", path.display()));
            }
            continue;
        }
        if db_old && all_old {
            cleanup_created_directory(&paths, &journal, warnings);
            if remove(&path).is_ok() {
                count = count.saturating_add(1);
            } else {
                warnings.push(format!("kept settled batch journal {}", path.display()));
            }
            continue;
        }
        if db_old && no_ambiguous_paths {
            match rollback_paths(&paths, &journal, main_state, sidecar_state) {
                Ok(()) => {
                    cleanup_created_directory(&paths, &journal, warnings);
                    if remove(&path).is_ok() {
                        count = count.saturating_add(1);
                    } else {
                        warnings.push(format!("kept rolled-back batch journal {}", path.display()));
                    }
                }
                Err(error) => warnings.push(format!(
                    "kept batch journal {} after rollback failure: {error}",
                    path.display()
                )),
            }
            continue;
        }
        warnings.push(format!("kept unsafe batch journal {}", path.display()));
    }
    Ok(count)
}

#[derive(Debug)]
struct DbState {
    path: String,
    name: String,
    category: String,
}

fn load_db_state(repo: &Path, file_id: i64) -> io::Result<Option<DbState>> {
    let connection = crate::db::open_repo_read_connection(repo).map_err(core_error_to_io)?;
    connection
        .query_row(
            "SELECT path, current_name, category FROM files WHERE id = ?1 AND status = 'active'",
            [file_id],
            |row| {
                Ok(DbState {
                    path: row.get(0)?,
                    name: row.get(1)?,
                    category: row.get(2)?,
                })
            },
        )
        .optional()
        .map_err(io_other)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum FsPathState {
    Old,
    New,
    /// No filesystem participant exists for this item (for example, a file
    /// without a note sidecar). This must not be conflated with `Old`.
    Neutral,
    Ambiguous,
}

fn rollback_paths(
    paths: &BatchJournalPaths,
    journal: &BatchJournal,
    main_state: FsPathState,
    sidecar_state: FsPathState,
) -> io::Result<()> {
    // Verify every source before the first move. This prevents a user-created
    // replacement from being moved when a previous recovery attempt is retried.
    if main_state == FsPathState::New {
        ensure_hash(&paths.current, &journal.file_hash_sha256)?;
    }
    let sidecar_hash = journal
        .sidecar
        .as_ref()
        .map(|value| value.hash_sha256.as_str());
    if sidecar_state == FsPathState::New {
        let sidecar = paths
            .sidecar
            .as_ref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "sidecar path missing"))?;
        ensure_hash(
            &sidecar.1,
            sidecar_hash.ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidData, "sidecar manifest missing")
            })?,
        )?;
    }
    if sidecar_state == FsPathState::New {
        let sidecar = paths
            .sidecar
            .as_ref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "sidecar path missing"))?;
        crate::storage::move_recoverable_file_with_hash(
            &sidecar.1,
            &sidecar.0,
            sidecar_hash.ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidData, "sidecar manifest missing")
            })?,
        )
        .map_err(core_error_to_io)?;
    }
    if main_state == FsPathState::New {
        crate::storage::move_recoverable_file_with_hash(
            &paths.current,
            &paths.original,
            &journal.file_hash_sha256,
        )
        .map_err(core_error_to_io)?;
    }
    Ok(())
}

fn path_state(original: &Path, current: &Path, hash: &str) -> io::Result<FsPathState> {
    let old = safe_file_matches(original, Some(hash))? && !path_exists_no_follow(current);
    let new = safe_file_matches(current, Some(hash))? && !path_exists_no_follow(original);
    Ok(match (old, new) {
        (true, false) => FsPathState::Old,
        (false, true) => FsPathState::New,
        _ => FsPathState::Ambiguous,
    })
}

fn sidecar_path_state(
    paths: &BatchJournalPaths,
    journal: &BatchJournal,
) -> io::Result<FsPathState> {
    let Some(sidecar) = paths.sidecar.as_ref() else {
        return Ok(FsPathState::Neutral);
    };
    let hash = journal
        .sidecar
        .as_ref()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "sidecar manifest missing"))?
        .hash_sha256
        .as_str();
    path_state(&sidecar.0, &sidecar.1, hash)
}

fn safe_file_matches(path: &Path, expected_hash: Option<&str>) -> io::Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => Ok(false),
        Ok(_) => {
            if let Some(expected_hash) = expected_hash {
                Ok(hash_file(path)? == expected_hash)
            } else {
                Ok(true)
            }
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}

fn ensure_hash(path: &Path, expected: &str) -> io::Result<()> {
    if safe_file_matches(path, Some(expected))? {
        Ok(())
    } else {
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "recovery source identity changed",
        ))
    }
}

fn cleanup_created_directory(
    paths: &BatchJournalPaths,
    journal: &BatchJournal,
    warnings: &mut Vec<String>,
) {
    let Some(directory) = paths.planned_directory.as_ref() else {
        return;
    };
    let Some(expected_identity) = journal.created_directory_identity.as_deref() else {
        return;
    };
    let identity = match directory_identity(directory) {
        Ok(identity) => identity,
        Err(_) => return,
    };
    if identity != expected_identity {
        warnings.push(format!(
            "kept recreated batch target directory {}",
            directory.display()
        ));
        return;
    }
    match fs::read_dir(directory) {
        Ok(mut entries) => {
            if entries.next().is_none() {
                if let Err(error) = fs::remove_dir(directory) {
                    warnings.push(format!(
                        "kept empty batch target directory {}: {error}",
                        directory.display()
                    ));
                }
            } else {
                warnings.push(format!(
                    "kept non-empty batch target directory {}",
                    directory.display()
                ));
            }
        }
        Err(error) => warnings.push(format!(
            "kept batch target directory {}: {error}",
            directory.display()
        )),
    }
}

fn path_exists_no_follow(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

fn safe_repo_path(repo: &Path, path: &Path) -> bool {
    let Ok(relative) = path.strip_prefix(repo) else {
        return false;
    };
    let mut current = repo.to_path_buf();
    for component in relative.components() {
        let Component::Normal(part) = component else {
            return false;
        };
        current.push(part);
        if let Ok(metadata) = fs::symlink_metadata(&current) {
            if metadata.file_type().is_symlink() {
                return false;
            }
            if current != *path && !metadata.is_dir() {
                return false;
            }
        }
    }
    true
}

fn relative_path(repo: &Path, path: &Path) -> io::Result<String> {
    let relative = path
        .strip_prefix(repo)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "path outside repository"))?;
    let value = relative.to_string_lossy().into_owned();
    validate_relative_path(&value)?;
    Ok(value)
}

fn validate_db_relative_path(value: &str) -> io::Result<String> {
    validate_relative_path(value)?;
    Ok(value.to_owned())
}

fn validate_relative_path(value: &str) -> io::Result<PathBuf> {
    let path = Path::new(value);
    if path.as_os_str().is_empty() || path.is_absolute() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid relative path",
        ));
    }
    for component in path.components() {
        match component {
            Component::Normal(part) if part != ".areamatrix" => {}
            _ => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "unsafe relative path",
                ))
            }
        }
    }
    Ok(path.to_path_buf())
}

fn hash_file(path: &Path) -> io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

pub(crate) fn file_hash(path: &Path) -> io::Result<String> {
    hash_file(path)
}

fn ensure_directory_chain(path: &Path) -> io::Result<()> {
    let relative_components = [".areamatrix", "staging", "batch"];
    let repo = path
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "journal root missing"))?;
    let repo_metadata = fs::symlink_metadata(repo)?;
    if repo_metadata.file_type().is_symlink() || !repo_metadata.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "repository root is not a real directory",
        ));
    }
    let mut current = repo.to_path_buf();
    for component in relative_components {
        current.push(component);
        match fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "journal directory is not safe",
                ))
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => fs::create_dir(&current)?,
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

fn sync_directory(path: &Path) {
    if let Ok(file) = File::open(path) {
        let _ = file.sync_all();
    }
}

fn core_error_to_io(error: crate::CoreError) -> io::Error {
    io::Error::other(error.to_string())
}

fn io_other(error: impl std::fmt::Display) -> io::Error {
    io::Error::other(error.to_string())
}
