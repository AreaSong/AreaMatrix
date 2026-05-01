//! Empty repository initialization for C1-02.

use std::{
    ffi::OsStr,
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};

use serde_yaml::Value;
use uuid::Uuid;

use crate::{
    config, db, overview, repo_entries, repo_path, CoreError, CoreResult, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INIT_DIR_PREFIX: &str = ".areamatrix.init-";
const DEFAULT_CLASSIFIER_YAML: &str = include_str!("../resources/classifier.yaml");
const DEFAULT_IGNORE_YAML: &str = r#"version: 1
ignore:
  - ".DS_Store"
  - ".areamatrix/"
"#;

pub(crate) fn init_repo(repo_path: String, options: RepoInitOptions) -> CoreResult<()> {
    if options.mode != RepoInitMode::CreateEmpty {
        return Err(CoreError::Config);
    }

    let repo = PathBuf::from(&repo_path);
    preflight_create_empty(&repo_path, &repo)?;

    let init_dir = repo.join(format!("{INIT_DIR_PREFIX}{}", Uuid::new_v4()));
    let mut rollback = InitRollback::new(repo.clone(), init_dir.clone());
    let result = init_repo_inner(&repo_path, &repo, &init_dir, &options, &mut rollback);
    if result.is_err() {
        rollback.rollback();
    }
    result
}

fn init_repo_inner(
    repo_path: &str,
    repo: &Path,
    init_dir: &Path,
    options: &RepoInitOptions,
    rollback: &mut InitRollback,
) -> CoreResult<()> {
    fs::create_dir(init_dir).map_err(map_io_error)?;
    fs::create_dir(init_dir.join("staging")).map_err(map_io_error)?;
    fs::create_dir(init_dir.join("archives")).map_err(map_io_error)?;
    fs::create_dir(init_dir.join("generated")).map_err(map_io_error)?;

    write_new_file(&init_dir.join("classifier.yaml"), DEFAULT_CLASSIFIER_YAML)?;
    write_new_file(&init_dir.join("ignore.yaml"), DEFAULT_IGNORE_YAML)?;

    let config = config::default_repo_config(repo_path.to_owned(), options.overview_output.clone());
    db::initialize_repository_db(&init_dir.join("index.db"), &config)?;
    overview::write_generated_root(&init_dir.join("generated"), &config.locale)?;

    let init_dir_name = init_dir.file_name().ok_or(CoreError::Config)?;
    ensure_no_user_content_entries(repo, Some(init_dir_name))?;
    fs::rename(init_dir, repo.join(AREA_MATRIX_DIR)).map_err(map_io_error)?;
    rollback.mark_metadata_committed();

    if options.create_default_categories {
        create_default_category_dirs(repo, rollback)?;
    }
    if config.overview_output == OverviewOutput::RootAreaMatrixFile {
        overview::write_root_areamatrix_file(repo, &config.locale)?;
        rollback.mark_root_entry_created();
    }

    rollback.mark_complete();
    Ok(())
}

fn preflight_create_empty(repo_path: &str, repo: &Path) -> CoreResult<()> {
    let mut validation = repo_path::validate_repo_path(repo_path.to_owned())?;
    if validation.exists
        && validation.is_directory
        && validation.is_writable
        && !validation.is_initialized
        && cleanup_recoverable_init_dirs(repo)?
    {
        validation = repo_path::validate_repo_path(repo_path.to_owned())?;
    }

    if !validation.exists || !validation.is_directory {
        return Err(CoreError::InvalidPath);
    }
    if !validation.is_writable {
        return Err(CoreError::PermissionDenied);
    }
    if validation.is_initialized || validation.has_unfinished_scan_session || !validation.is_empty {
        return Err(CoreError::Config);
    }
    ensure_no_user_content_entries(repo, None)
}

fn cleanup_recoverable_init_dirs(repo: &Path) -> CoreResult<bool> {
    let mut cleaned = false;
    for entry in fs::read_dir(repo).map_err(map_io_error)? {
        let entry = entry.map_err(map_io_error)?;
        let entry_name = entry.file_name();
        let Some(entry_name) = entry_name.to_str() else {
            continue;
        };
        if !entry_name.starts_with(INIT_DIR_PREFIX) {
            continue;
        }

        let path = entry.path();
        if !is_recoverable_init_dir(&path)? {
            return Err(CoreError::Config);
        }

        fs::remove_dir_all(path).map_err(map_io_error)?;
        cleaned = true;
    }
    Ok(cleaned)
}

fn is_recoverable_init_dir(path: &Path) -> CoreResult<bool> {
    let metadata = fs::symlink_metadata(path).map_err(map_io_error)?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Ok(false);
    }

    for entry in fs::read_dir(path).map_err(map_io_error)? {
        let entry = entry.map_err(map_io_error)?;
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            return Ok(false);
        };
        let file_type = entry.file_type().map_err(map_io_error)?;
        if file_type.is_symlink() {
            return Ok(false);
        }

        let path = entry.path();
        let recoverable = match name {
            "staging" | "archives" => file_type.is_dir() && is_empty_dir(&path)?,
            "generated" => file_type.is_dir() && is_recoverable_generated_dir(&path)?,
            "classifier.yaml" | "ignore.yaml" | "index.db" | "index.db-wal" | "index.db-shm" => {
                file_type.is_file()
            }
            _ => false,
        };
        if !recoverable {
            return Ok(false);
        }
    }
    Ok(true)
}

fn is_empty_dir(path: &Path) -> CoreResult<bool> {
    let mut entries = fs::read_dir(path).map_err(map_io_error)?;
    match entries.next() {
        None => Ok(true),
        Some(Ok(_)) => Ok(false),
        Some(Err(error)) => Err(map_io_error(error)),
    }
}

fn is_recoverable_generated_dir(path: &Path) -> CoreResult<bool> {
    for entry in fs::read_dir(path).map_err(map_io_error)? {
        let entry = entry.map_err(map_io_error)?;
        if entry.file_name() != "root.md" {
            return Ok(false);
        }
        let file_type = entry.file_type().map_err(map_io_error)?;
        if !file_type.is_file() {
            return Ok(false);
        }
    }
    Ok(true)
}

fn ensure_no_user_content_entries(
    repo: &Path,
    allowed_entry_name: Option<&OsStr>,
) -> CoreResult<()> {
    for entry in fs::read_dir(repo).map_err(map_io_error)? {
        let entry = entry.map_err(map_io_error)?;
        let entry_name = entry.file_name();
        if allowed_entry_name.is_some_and(|allowed| entry_name == allowed) {
            continue;
        }
        if repo_entries::is_user_content_entry(&entry).map_err(map_io_error)? {
            return Err(CoreError::Config);
        }
    }
    Ok(())
}

fn create_default_category_dirs(repo: &Path, rollback: &mut InitRollback) -> CoreResult<()> {
    for slug in default_category_slugs()? {
        let category_dir = repo.join(&slug);
        fs::create_dir(&category_dir).map_err(map_io_error)?;
        rollback.track_category_dir(category_dir);
    }
    Ok(())
}

fn default_category_slugs() -> CoreResult<Vec<String>> {
    let value: Value =
        serde_yaml::from_str(DEFAULT_CLASSIFIER_YAML).map_err(|_| CoreError::Config)?;
    let categories = value
        .get("categories")
        .and_then(Value::as_sequence)
        .ok_or(CoreError::Config)?;

    let mut slugs = Vec::with_capacity(categories.len());
    for category in categories {
        let slug = category
            .get("slug")
            .and_then(Value::as_str)
            .ok_or(CoreError::Config)?;
        if !is_safe_category_slug(slug) {
            return Err(CoreError::Config);
        }
        slugs.push(slug.to_owned());
    }
    Ok(slugs)
}

fn is_safe_category_slug(slug: &str) -> bool {
    !slug.is_empty()
        && slug != "."
        && slug != ".."
        && !slug.starts_with('.')
        && !slug.contains('/')
        && !slug.contains('\\')
}

fn write_new_file(path: &Path, content: &str) -> CoreResult<()> {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(map_io_error)?;
    file.write_all(content.as_bytes()).map_err(map_io_error)
}

fn map_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::AlreadyExists => CoreError::Config,
        io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    }
}

struct InitRollback {
    repo: PathBuf,
    init_dir: PathBuf,
    metadata_committed: bool,
    root_entry_created: bool,
    created_category_dirs: Vec<PathBuf>,
    complete: bool,
}

impl InitRollback {
    fn new(repo: PathBuf, init_dir: PathBuf) -> Self {
        Self {
            repo,
            init_dir,
            metadata_committed: false,
            root_entry_created: false,
            created_category_dirs: Vec::new(),
            complete: false,
        }
    }

    fn mark_metadata_committed(&mut self) {
        self.metadata_committed = true;
    }

    fn mark_root_entry_created(&mut self) {
        self.root_entry_created = true;
    }

    fn track_category_dir(&mut self, path: PathBuf) {
        self.created_category_dirs.push(path);
    }

    fn mark_complete(&mut self) {
        self.complete = true;
    }

    fn rollback(&mut self) {
        if self.complete {
            return;
        }
        for path in self.created_category_dirs.iter().rev() {
            let _ = fs::remove_dir(path);
        }
        if self.root_entry_created {
            let _ = fs::remove_file(self.repo.join("AREAMATRIX.md"));
        }
        if self.metadata_committed {
            let _ = fs::remove_dir_all(self.repo.join(AREA_MATRIX_DIR));
        } else {
            let _ = fs::remove_dir_all(&self.init_dir);
        }
    }
}
