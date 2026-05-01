use std::{
    fs,
    path::{Path, PathBuf},
};

use serde_json::json;
use uuid::Uuid;

use crate::{
    classify, db, CoreError, CoreResult, DuplicateStrategy, FileEntry, FileOrigin,
    ImportDestination, ImportOptions, StorageMode,
};

use super::{hash, validate};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const STAGING_DIR: &str = "staging";

pub(crate) fn import_file(
    repo_path: String,
    source_path: String,
    options: ImportOptions,
) -> CoreResult<FileEntry> {
    let prepared = prepare_import(repo_path, source_path, options)?;
    let staged = stage_source(&prepared)?;
    ensure_no_duplicate(&prepared, &staged)?;
    let destination = PreparedDestination::prepare(&prepared)?;
    let file_id = insert_staging_row(&prepared, &staged)?;
    let mut db_guard = DbStagingRowGuard::new(prepared.repo.clone(), file_id);

    commit_filesystem(&staged, &destination)?;
    staged.staging_guard.disarm();
    let mut final_guard = FinalFileGuard::new(destination.final_path.clone());

    promote_import(&prepared, file_id, &destination)?;
    db_guard.disarm();
    final_guard.disarm();
    destination.disarm();
    db::get_active_file_by_id(&prepared.repo, file_id)
}

struct PreparedImport {
    repo: PathBuf,
    source: PathBuf,
    original_name: String,
    target_filename: String,
    target: ImportTarget,
    options: ImportOptions,
}

impl PreparedImport {
    fn new(repo_path: String, source_path: String, options: ImportOptions) -> CoreResult<Self> {
        let repo = validate_repo_path(&repo_path)?;
        db::ensure_initialized(&repo)?;
        let source = PathBuf::from(source_path);
        validate::source_file(&source)?;

        let original_name = source_filename(&source)?;
        let target_filename = options
            .override_filename
            .clone()
            .unwrap_or_else(|| original_name.clone());
        validate::filename(&target_filename)?;

        let target = resolve_import_target(&repo, &repo_path, &original_name, &options)?;
        Ok(Self {
            repo,
            source,
            original_name,
            target_filename,
            target,
            options,
        })
    }
}

fn prepare_import(
    repo_path: String,
    source_path: String,
    options: ImportOptions,
) -> CoreResult<PreparedImport> {
    if options.mode != StorageMode::Copied {
        return Err(CoreError::Internal);
    }
    PreparedImport::new(repo_path, source_path, options)
}

struct StagedImport {
    staging_guard: StagingFileGuard,
    hash_sha256: String,
    size_bytes: i64,
}

fn stage_source(prepared: &PreparedImport) -> CoreResult<StagedImport> {
    let staging_guard = StagingFileGuard::create(&prepared.repo)?;
    let hashed_copy = hash::copy_and_hash(&prepared.source, staging_guard.path())?;
    Ok(StagedImport {
        staging_guard,
        hash_sha256: hashed_copy.hash_sha256,
        size_bytes: hashed_copy.size_bytes,
    })
}

fn ensure_no_duplicate(prepared: &PreparedImport, staged: &StagedImport) -> CoreResult<()> {
    if db::find_active_file_by_hash(&prepared.repo, &staged.hash_sha256)?.is_some() {
        return duplicate_error(&prepared.options.duplicate_strategy);
    }
    Ok(())
}

struct PreparedDestination {
    directory_guard: CreatedDirectoryGuard,
    final_path: PathBuf,
    final_relative_path: String,
}

impl PreparedDestination {
    fn prepare(prepared: &PreparedImport) -> CoreResult<Self> {
        let directory_guard =
            CreatedDirectoryGuard::ensure(&prepared.repo, &prepared.target.relative_dir)?;
        let final_path = directory_guard.path().join(&prepared.target_filename);
        if path_exists(&final_path)? {
            return Err(CoreError::Conflict);
        }

        Ok(Self {
            final_relative_path: relative_repo_path(&prepared.repo, &final_path)?,
            directory_guard,
            final_path,
        })
    }

    fn disarm(mut self) {
        self.directory_guard.disarm();
    }
}

fn insert_staging_row(prepared: &PreparedImport, staged: &StagedImport) -> CoreResult<i64> {
    let imported_at = chrono::Utc::now().timestamp();
    db::insert_import_staging(
        &prepared.repo,
        db::NewImportRow {
            path: relative_repo_path(&prepared.repo, staged.staging_guard.path())?,
            original_name: prepared.original_name.clone(),
            current_name: prepared.target_filename.clone(),
            category: prepared.target.category.clone(),
            size_bytes: staged.size_bytes,
            hash_sha256: staged.hash_sha256.clone(),
            storage_mode: StorageMode::Copied,
            origin: FileOrigin::Imported,
            source_path: Some(prepared.source.to_string_lossy().into_owned()),
            imported_at,
        },
    )
}

fn commit_filesystem(staged: &StagedImport, destination: &PreparedDestination) -> CoreResult<()> {
    persist_staging_to_final(staged.staging_guard.path(), &destination.final_path)
}

fn promote_import(
    prepared: &PreparedImport,
    file_id: i64,
    destination: &PreparedDestination,
) -> CoreResult<()> {
    db::promote_imported_file(
        &prepared.repo,
        file_id,
        &destination.final_relative_path,
        &prepared.target_filename,
        &json!({
            "source": prepared.source.to_string_lossy(),
            "mode": "copied",
            "category": prepared.target.category,
            "destination": destination_detail(&prepared.options.destination),
            "renamed_from_original": prepared.original_name != prepared.target_filename,
            "by": "user",
        }),
    )
}

struct ImportTarget {
    relative_dir: String,
    category: String,
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::InvalidPath);
    }
    Ok(PathBuf::from(repo_path))
}

fn source_filename(source: &Path) -> CoreResult<String> {
    source
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or(CoreError::InvalidPath)
}

fn resolve_import_target(
    repo: &Path,
    repo_path: &str,
    original_name: &str,
    options: &ImportOptions,
) -> CoreResult<ImportTarget> {
    match options.destination {
        ImportDestination::AutoClassify => {
            let category = match &options.override_category {
                Some(category) => category.clone(),
                None => {
                    classify::predict_category(repo_path.to_owned(), original_name.to_owned())?
                        .category
                }
            };
            validate::category_slug(&category)?;
            Ok(ImportTarget {
                relative_dir: category.clone(),
                category,
            })
        }
        ImportDestination::SelectedDirectory => {
            let directory = options
                .target_directory
                .as_deref()
                .ok_or(CoreError::InvalidPath)?;
            validate::relative_directory(directory)?;
            let category = validate::top_level_category(directory)?;
            Ok(ImportTarget {
                relative_dir: directory.to_owned(),
                category,
            })
        }
        ImportDestination::Category => {
            let category = options
                .override_category
                .as_deref()
                .ok_or(CoreError::InvalidPath)?;
            validate::category_slug(category)?;
            let relative_dir = repo
                .join(category)
                .strip_prefix(repo)
                .map_err(|_| CoreError::InvalidPath)?
                .to_string_lossy()
                .into_owned();
            Ok(ImportTarget {
                relative_dir,
                category: category.to_owned(),
            })
        }
    }
}

fn duplicate_error(_strategy: &DuplicateStrategy) -> CoreResult<()> {
    Err(CoreError::DuplicateFile)
}

fn destination_detail(destination: &ImportDestination) -> &'static str {
    match destination {
        ImportDestination::AutoClassify => "auto_classify",
        ImportDestination::SelectedDirectory => "selected_directory",
        ImportDestination::Category => "category",
    }
}

fn persist_staging_to_final(staging: &Path, final_path: &Path) -> CoreResult<()> {
    if path_exists(final_path)? {
        return Err(CoreError::Conflict);
    }

    match fs::hard_link(staging, final_path) {
        Ok(()) => remove_staging_after_persist(staging),
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => Err(CoreError::Conflict),
        Err(_) => copy_staging_to_final(staging, final_path),
    }
}

fn copy_staging_to_final(staging: &Path, final_path: &Path) -> CoreResult<()> {
    let expected_size = staging.metadata().map_err(hash::map_io_error)?.len();
    let copied_size = hash::copy_to_new_file(staging, final_path)?;
    if copied_size != expected_size {
        let _ = fs::remove_file(final_path);
        return Err(CoreError::Io);
    }
    remove_staging_after_persist(staging)
}

fn remove_staging_after_persist(staging: &Path) -> CoreResult<()> {
    fs::remove_file(staging).map_err(hash::map_io_error)
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|_| CoreError::InvalidPath)
        .map(|relative| relative.to_string_lossy().into_owned())
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(hash::map_io_error)
}

struct StagingFileGuard {
    path: PathBuf,
    armed: bool,
}

impl StagingFileGuard {
    fn create(repo: &Path) -> CoreResult<Self> {
        let staging_dir = repo.join(AREA_MATRIX_DIR).join(STAGING_DIR);
        fs::create_dir_all(&staging_dir).map_err(hash::map_io_error)?;
        Ok(Self {
            path: staging_dir.join(format!("import-{}", Uuid::new_v4())),
            armed: true,
        })
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn disarm(mut self) {
        self.armed = false;
    }
}

impl Drop for StagingFileGuard {
    fn drop(&mut self) {
        if self.armed {
            // Best-effort cleanup for the internal staging file created by this import attempt.
            let _cleanup_result = fs::remove_file(&self.path);
        }
    }
}

struct CreatedDirectoryGuard {
    final_path: PathBuf,
    created: Vec<PathBuf>,
    armed: bool,
}

impl CreatedDirectoryGuard {
    fn ensure(repo: &Path, relative_dir: &str) -> CoreResult<Self> {
        let mut current = repo.to_path_buf();
        let mut created = Vec::new();
        for component in Path::new(relative_dir).components() {
            let std::path::Component::Normal(part) = component else {
                return Err(CoreError::InvalidPath);
            };
            current.push(part);
            if path_exists(&current)? {
                if current.is_dir() {
                    continue;
                }
                return Err(CoreError::InvalidPath);
            }
            fs::create_dir(&current).map_err(hash::map_io_error)?;
            created.push(current.clone());
        }

        Ok(Self {
            final_path: current,
            created,
            armed: true,
        })
    }

    fn path(&self) -> &Path {
        &self.final_path
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for CreatedDirectoryGuard {
    fn drop(&mut self) {
        if self.armed {
            for directory in self.created.iter().rev() {
                // Only empty directories created by this import are removed.
                let _cleanup_result = fs::remove_dir(directory);
            }
        }
    }
}

struct FinalFileGuard {
    path: PathBuf,
    armed: bool,
}

impl FinalFileGuard {
    fn new(path: PathBuf) -> Self {
        Self { path, armed: true }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for FinalFileGuard {
    fn drop(&mut self) {
        if self.armed {
            // This path is created from AreaMatrix staging during the current attempt.
            let _cleanup_result = fs::remove_file(&self.path);
        }
    }
}

struct DbStagingRowGuard {
    repo: PathBuf,
    file_id: i64,
    armed: bool,
}

impl DbStagingRowGuard {
    fn new(repo: PathBuf, file_id: i64) -> Self {
        Self {
            repo,
            file_id,
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for DbStagingRowGuard {
    fn drop(&mut self) {
        if self.armed {
            // Best-effort rollback for the staging metadata row owned by this attempt.
            let _cleanup_result = db::delete_file_row(&self.repo, self.file_id);
        }
    }
}
