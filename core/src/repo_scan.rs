//! Filesystem scan support for adopting existing repositories.

use std::{
    fs::{self, File},
    io::{self, Read},
    path::{Path, PathBuf},
};

use serde::Deserialize;
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

use crate::{
    db::{self, FileIndexInput, ScanFileChange},
    repo_path, CoreError, CoreResult, ReindexReport, ScanSession, ScanSessionKind,
    ScanSessionStatus,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const DEFAULT_IGNORE_PATTERNS: &[&str] = &[
    ".DS_Store",
    ".areamatrix/",
    ".git/",
    ".hg/",
    ".svn/",
    "node_modules/",
    ".venv/",
    "venv/",
    "target/",
    "build/",
    "dist/",
    ".next/",
    ".cache/",
    "*.tmp",
    "*.swp",
];

pub(crate) fn start_adopt_scan(repo_path: &Path) -> CoreResult<()> {
    let scan_session_id = db::create_scan_session(repo_path, ScanSessionKind::Adopt)?;
    run_adopt_scan(repo_path, scan_session_id, None)
}

pub(crate) fn reindex_from_filesystem(repo_path: String) -> CoreResult<ReindexReport> {
    let repo = initialized_repo_path(&repo_path)?;
    let scan_session_id = db::create_scan_session(&repo, ScanSessionKind::Reindex)?;
    run_filesystem_scan(&repo, scan_session_id, None, ScanMode::Reindex)?;
    let finished = db::scan_session_by_id(&repo, scan_session_id)?;
    Ok(report_from_session(&finished))
}

pub(crate) fn get_latest_scan_session(repo_path: String) -> CoreResult<Option<ScanSession>> {
    let repo = initialized_repo_path(&repo_path)?;
    db::latest_scan_session(&repo)
}

pub(crate) fn resume_scan_session(
    repo_path: String,
    scan_session_id: i64,
) -> CoreResult<ReindexReport> {
    let repo = initialized_repo_path(&repo_path)?;
    let session = db::scan_session_by_id(&repo, scan_session_id)?;
    if session.status == ScanSessionStatus::Completed {
        return Ok(empty_report(scan_session_id));
    }
    let scan_mode = ScanMode::from_kind(&session.kind);

    db::mark_scan_session_running_for_resume(&repo, scan_session_id)?;
    run_filesystem_scan(
        &repo,
        scan_session_id,
        session.last_path.as_deref(),
        scan_mode,
    )?;
    let finished = db::scan_session_by_id(&repo, scan_session_id)?;
    Ok(report_from_session(&finished))
}

fn run_adopt_scan(
    repo_path: &Path,
    scan_session_id: i64,
    resume_after: Option<&str>,
) -> CoreResult<()> {
    run_filesystem_scan(repo_path, scan_session_id, resume_after, ScanMode::Adopt)
}

fn run_filesystem_scan(
    repo_path: &Path,
    scan_session_id: i64,
    resume_after: Option<&str>,
    mode: ScanMode,
) -> CoreResult<()> {
    let plan = match collect_scan_files(repo_path, resume_after) {
        Ok(plan) => plan,
        Err(error) => {
            return finish_failed_scan(repo_path, scan_session_id, "scan setup", error);
        }
    };
    for _ in 0..plan.skipped {
        db::update_scan_session_progress(repo_path, scan_session_id, "", ScanFileChange::Skipped)?;
    }

    for file in plan.files {
        let index_input = match index_input_for_file(&file.path, file.relative_path.clone()) {
            Ok(index_input) => index_input,
            Err(error) => {
                return finish_failed_scan(repo_path, scan_session_id, &file.relative_path, error);
            }
        };
        let change = match upsert_scan_file(repo_path, &index_input, mode) {
            Ok(change) => change,
            Err(error) => {
                return finish_failed_scan(repo_path, scan_session_id, &index_input.path, error);
            }
        };
        db::update_scan_session_progress(repo_path, scan_session_id, &index_input.path, change)?;
    }

    db::finish_scan_session(
        repo_path,
        scan_session_id,
        ScanSessionStatus::Completed,
        &[],
    )
}

fn collect_scan_files(repo_path: &Path, resume_after: Option<&str>) -> CoreResult<ScanPlan> {
    let matcher = IgnoreMatcher::load(repo_path)?;
    let mut files = Vec::new();
    let mut skipped = 0;

    for entry in WalkDir::new(repo_path)
        .follow_links(false)
        .same_file_system(true)
        .into_iter()
        .filter_entry(|entry| should_descend(repo_path, entry.path(), &matcher))
    {
        let entry = entry.map_err(map_walkdir_error)?;
        let path = entry.path();
        if path == repo_path || entry.file_type().is_dir() {
            continue;
        }

        let relative_path = relative_repo_path(repo_path, path)?;
        if has_icloud_placeholder_marker(&relative_path) {
            if should_process_after_resume(&relative_path, resume_after) {
                skipped += 1;
            }
            continue;
        }
        if matcher.is_ignored(&relative_path, entry.file_type().is_dir()) {
            if should_process_after_resume(&relative_path, resume_after) {
                skipped += 1;
            }
            continue;
        }
        if !entry.file_type().is_file() {
            if should_process_after_resume(&relative_path, resume_after) {
                skipped += 1;
            }
            continue;
        }
        if !should_process_after_resume(&relative_path, resume_after) {
            continue;
        }

        files.push(AdoptFile {
            path: path.to_path_buf(),
            relative_path,
        });
    }

    files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok(ScanPlan { files, skipped })
}

fn upsert_scan_file(
    repo_path: &Path,
    input: &FileIndexInput,
    mode: ScanMode,
) -> CoreResult<ScanFileChange> {
    match mode {
        ScanMode::Adopt => db::upsert_adopted_file(repo_path, input),
        ScanMode::Reindex => db::upsert_reindexed_file(repo_path, input),
    }
}

fn finish_failed_scan(
    repo_path: &Path,
    scan_session_id: i64,
    relative_path: &str,
    error: CoreError,
) -> CoreResult<()> {
    let errors = vec![format!("{relative_path}: {error}")];
    db::finish_scan_session(
        repo_path,
        scan_session_id,
        ScanSessionStatus::Failed,
        &errors,
    )?;
    Err(error)
}

fn should_process_after_resume(relative_path: &str, resume_after: Option<&str>) -> bool {
    match resume_after {
        Some(last_path) if !last_path.is_empty() => relative_path > last_path,
        _ => true,
    }
}

fn should_descend(repo_path: &Path, path: &Path, matcher: &IgnoreMatcher) -> bool {
    if path == repo_path {
        return true;
    }
    if !path.is_dir() {
        return true;
    }
    match relative_repo_path(repo_path, path) {
        Ok(relative_path) => !matcher.is_ignored(&relative_path, true),
        Err(_) => false,
    }
}

fn index_input_for_file(path: &Path, relative_path: String) -> CoreResult<FileIndexInput> {
    let metadata = path.metadata().map_err(map_io_error)?;
    let current_name = file_name(path)?;
    Ok(FileIndexInput {
        category: category_for_relative_path(&relative_path),
        path: relative_path,
        original_name: current_name.clone(),
        current_name,
        size_bytes: metadata.len() as i64,
        hash_sha256: sha256_file(path)?,
    })
}

fn initialized_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    repo_path::validate_initialized_repo_path(repo_path.to_owned())?;
    Ok(PathBuf::from(repo_path))
}

fn relative_repo_path(repo_path: &Path, path: &Path) -> CoreResult<String> {
    let relative = path
        .strip_prefix(repo_path)
        .map_err(|error| CoreError::invalid_path(error.to_string()))?;
    Ok(relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/"))
}

fn category_for_relative_path(relative_path: &str) -> String {
    match relative_path.split_once('/') {
        Some((top_level, _)) if !top_level.is_empty() => top_level.to_owned(),
        _ => "__root__".to_owned(),
    }
}

fn file_name(path: &Path) -> CoreResult<String> {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .filter(|name| !name.is_empty())
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
}

fn sha256_file(path: &Path) -> CoreResult<String> {
    let mut file = File::open(path).map_err(map_io_error)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 8192];
    loop {
        let bytes_read = file.read(&mut buffer).map_err(map_io_error)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn empty_report(scan_session_id: i64) -> ReindexReport {
    ReindexReport {
        scan_session_id: Some(scan_session_id),
        inserted: 0,
        updated: 0,
        skipped: 0,
        errors: Vec::new(),
    }
}

fn report_from_session(session: &ScanSession) -> ReindexReport {
    ReindexReport {
        scan_session_id: Some(session.id),
        inserted: session.inserted,
        updated: session.updated,
        skipped: session.skipped,
        errors: session.errors.clone(),
    }
}

fn map_io_error(error: io::Error) -> CoreError {
    map_io_kind(error.kind())
}

fn map_walkdir_error(error: walkdir::Error) -> CoreError {
    error
        .io_error()
        .map(|error| map_io_kind(error.kind()))
        .unwrap_or_else(|| CoreError::io("io error"))
}

fn map_io_kind(kind: io::ErrorKind) -> CoreError {
    match kind {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

struct ScanPlan {
    files: Vec<AdoptFile>,
    skipped: i64,
}

struct AdoptFile {
    path: PathBuf,
    relative_path: String,
}

#[derive(Debug, Deserialize)]
struct IgnoreConfig {
    ignore: Option<Vec<String>>,
    patterns: Option<Vec<String>>,
}

struct IgnoreMatcher {
    patterns: Vec<String>,
}

impl IgnoreMatcher {
    fn load(repo_path: &Path) -> CoreResult<Self> {
        let path = repo_path.join(AREA_MATRIX_DIR).join("ignore.yaml");
        let content = match fs::read_to_string(path) {
            Ok(content) => content,
            Err(error) if error.kind() == io::ErrorKind::NotFound => String::new(),
            Err(error) => return Err(map_io_error(error)),
        };
        let mut patterns = DEFAULT_IGNORE_PATTERNS
            .iter()
            .map(|pattern| (*pattern).to_owned())
            .collect::<Vec<_>>();
        if let Ok(config) = serde_yaml::from_str::<IgnoreConfig>(&content) {
            if let Some(ignore) = config.ignore {
                patterns.extend(ignore);
            }
            if let Some(extra_patterns) = config.patterns {
                patterns.extend(extra_patterns);
            }
        }
        Ok(Self { patterns })
    }

    fn is_ignored(&self, relative_path: &str, is_dir: bool) -> bool {
        if relative_path == "AREAMATRIX.md" || relative_path.starts_with(".areamatrix/generated/") {
            return true;
        }
        self.patterns
            .iter()
            .any(|pattern| matches_pattern(pattern, relative_path, is_dir))
    }
}

fn matches_pattern(pattern: &str, relative_path: &str, is_dir: bool) -> bool {
    if pattern.ends_with('/') {
        let directory = pattern.trim_end_matches('/');
        return relative_path
            .split('/')
            .any(|component| component == directory)
            || (is_dir && relative_path == directory);
    }
    if let Some(suffix) = pattern.strip_prefix('*') {
        return file_name_from_relative(relative_path).is_some_and(|name| name.ends_with(suffix));
    }
    relative_path == pattern || file_name_from_relative(relative_path) == Some(pattern)
}

fn file_name_from_relative(relative_path: &str) -> Option<&str> {
    relative_path
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
}

fn has_icloud_placeholder_marker(relative_path: &str) -> bool {
    relative_path
        .split('/')
        .any(|component| component.to_ascii_lowercase().ends_with(".icloud"))
}

#[derive(Clone, Copy)]
enum ScanMode {
    Adopt,
    Reindex,
}

impl ScanMode {
    fn from_kind(kind: &ScanSessionKind) -> Self {
        match kind {
            ScanSessionKind::Adopt => Self::Adopt,
            ScanSessionKind::Reindex => Self::Reindex,
        }
    }
}
