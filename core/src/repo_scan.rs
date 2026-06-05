//! Filesystem scan support for adopting existing repositories.

use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    fs::{self, File},
    io::{self, Read},
    path::{Path, PathBuf},
};

use serde::Deserialize;
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

use crate::{
    db::{self, FileIndexInput, ScanFileChange, ScanFileSnapshot},
    repo_path, CoreError, CoreResult, FileOrigin, ManualRescanPreviewItem,
    ManualRescanPreviewItemKind, ManualRescanPreviewReport, ReindexReport, ScanSession,
    ScanSessionKind, ScanSessionStatus, StorageMode,
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
    ensure_no_running_reindex(&repo)?;
    let scan_session_id = db::create_scan_session(&repo, ScanSessionKind::Reindex)?;
    run_filesystem_scan(&repo, scan_session_id, None, ScanMode::Reindex, true)?;
    let finished = db::scan_session_by_id(&repo, scan_session_id)?;
    Ok(report_from_session(&finished))
}

pub(crate) fn preview_manual_rescan(repo_path: String) -> CoreResult<ManualRescanPreviewReport> {
    let repo = initialized_repo_path(&repo_path)?;
    ensure_no_running_reindex_read_only(&repo)?;
    let plan = collect_scan_files(&repo, None)?;
    preview_from_plan(&repo, &plan)
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
    if session.status == ScanSessionStatus::Running {
        return Err(CoreError::conflict("manual rescan already running"));
    }
    if session.kind == ScanSessionKind::Reindex {
        ensure_no_other_running_reindex(&repo, scan_session_id)?;
    }
    let scan_mode = ScanMode::from_kind(&session.kind);

    db::mark_scan_session_running_for_resume(&repo, scan_session_id)?;
    run_filesystem_scan(
        &repo,
        scan_session_id,
        session.last_path.as_deref(),
        scan_mode,
        session.kind == ScanSessionKind::Reindex,
    )?;
    let finished = db::scan_session_by_id(&repo, scan_session_id)?;
    Ok(report_from_session(&finished))
}

fn run_adopt_scan(
    repo_path: &Path,
    scan_session_id: i64,
    resume_after: Option<&str>,
) -> CoreResult<()> {
    run_filesystem_scan(
        repo_path,
        scan_session_id,
        resume_after,
        ScanMode::Adopt,
        false,
    )
}

fn run_filesystem_scan(
    repo_path: &Path,
    scan_session_id: i64,
    resume_after: Option<&str>,
    mode: ScanMode,
    track_missing_metadata: bool,
) -> CoreResult<()> {
    let plan = match collect_scan_files(repo_path, resume_after) {
        Ok(plan) => plan,
        Err(error) => {
            return finish_failed_scan(repo_path, scan_session_id, "scan setup", error);
        }
    };
    let active_rows = if track_missing_metadata {
        match active_file_snapshots(repo_path) {
            Ok(rows) => rows,
            Err(error) => {
                return finish_failed_scan(repo_path, scan_session_id, "metadata snapshot", error);
            }
        }
    } else {
        Vec::new()
    };
    for _ in 0..plan.skipped {
        db::update_scan_session_progress(repo_path, scan_session_id, "", ScanFileChange::Skipped)?;
    }
    if track_missing_metadata {
        let missing_paths = missing_metadata_paths(repo_path, &plan.files, &active_rows);
        for _ in missing_paths {
            db::update_scan_session_progress(
                repo_path,
                scan_session_id,
                "",
                ScanFileChange::Missing,
            )?;
        }
    }

    for file in plan.files {
        let index_input = match index_input_for_file(&file.path, file.relative_path.clone()) {
            Ok(index_input) => index_input,
            Err(error) => {
                let change = change_for_scan_error(&error);
                db::update_scan_session_progress(repo_path, scan_session_id, "", change)?;
                return finish_failed_scan(repo_path, scan_session_id, &file.relative_path, error);
            }
        };
        if track_missing_metadata
            && has_present_hash_conflict(repo_path, &active_rows, &index_input)
        {
            db::update_scan_session_progress(
                repo_path,
                scan_session_id,
                &index_input.path,
                ScanFileChange::Conflict,
            )?;
        }
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

fn ensure_no_running_reindex(repo_path: &Path) -> CoreResult<()> {
    if db::has_running_reindex_session(repo_path)? {
        return Err(CoreError::conflict("manual rescan already running"));
    }
    Ok(())
}

fn ensure_no_running_reindex_read_only(repo_path: &Path) -> CoreResult<()> {
    if db::has_running_reindex_session_read_only(repo_path)? {
        return Err(CoreError::conflict("manual rescan already running"));
    }
    Ok(())
}

fn ensure_no_other_running_reindex(repo_path: &Path, scan_session_id: i64) -> CoreResult<()> {
    if db::has_running_reindex_session_excluding(repo_path, Some(scan_session_id))? {
        return Err(CoreError::conflict("manual rescan already running"));
    }
    Ok(())
}

fn preview_from_plan(repo_path: &Path, plan: &ScanPlan) -> CoreResult<ManualRescanPreviewReport> {
    let rows = preview_file_snapshots(repo_path)?;
    let rows_by_path = rows
        .iter()
        .map(|row| (row.path.clone(), row))
        .collect::<BTreeMap<_, _>>();
    let current_paths = plan
        .files
        .iter()
        .map(|file| file.relative_path.clone())
        .collect::<BTreeSet<_>>();
    let mut summary = PreviewSummary::new(plan.skipped);

    for file in &plan.files {
        match preview_file(repo_path, file, &rows_by_path, &rows) {
            Ok(item) => summary.push(item),
            Err(error) => summary.push(error_preview_item(&file.relative_path, &error)),
        }
    }

    for row in rows {
        if current_paths.contains(&row.path) {
            continue;
        }
        if row_backing_file_missing(repo_path, &row) {
            summary.push(ManualRescanPreviewItem {
                kind: ManualRescanPreviewItemKind::Missing,
                relative_path: row.path,
                reason: "metadata row has no backing file at the expected path".to_owned(),
                suggested_action: "Open Needs Review or Review missing".to_owned(),
            });
        }
    }

    let created_at = chrono::Utc::now().timestamp();
    Ok(summary.into_report(created_at))
}

fn preview_file(
    repo_path: &Path,
    file: &AdoptFile,
    rows_by_path: &BTreeMap<String, &FileSnapshot>,
    rows: &[FileSnapshot],
) -> CoreResult<ManualRescanPreviewItem> {
    let input = index_input_for_file(&file.path, file.relative_path.clone())?;
    let duplicate_state =
        duplicate_hash_review_state(repo_path, rows, &input.hash_sha256, &input.path);
    let kind = match rows_by_path.get(&input.path) {
        Some(existing) if existing.matches(&input, FileOrigin::External) => match duplicate_state {
            DuplicateHashReviewState::Conflict => ManualRescanPreviewItemKind::Conflict,
            _ => ManualRescanPreviewItemKind::Skipped,
        },
        Some(_) => match duplicate_state {
            DuplicateHashReviewState::Conflict => ManualRescanPreviewItemKind::Conflict,
            _ => ManualRescanPreviewItemKind::Updated,
        },
        None => match duplicate_state {
            DuplicateHashReviewState::Conflict => ManualRescanPreviewItemKind::Conflict,
            DuplicateHashReviewState::RenamedCandidate => {
                ManualRescanPreviewItemKind::RenamedCandidate
            }
            DuplicateHashReviewState::None => ManualRescanPreviewItemKind::Added,
        },
    };
    Ok(ManualRescanPreviewItem {
        reason: reason_for_preview_kind(&kind).to_owned(),
        suggested_action: action_for_preview_kind(&kind).to_owned(),
        kind,
        relative_path: input.path,
    })
}

fn missing_metadata_paths(
    repo_path: &Path,
    files: &[AdoptFile],
    rows: &[FileSnapshot],
) -> Vec<String> {
    let current_paths = files
        .iter()
        .map(|file| file.relative_path.clone())
        .collect::<HashSet<_>>();
    rows.iter()
        .filter(|row| {
            !current_paths.contains(&row.path) && row_backing_file_missing(repo_path, row)
        })
        .map(|row| row.path.clone())
        .collect()
}

fn has_present_hash_conflict(
    repo_path: &Path,
    rows: &[FileSnapshot],
    input: &FileIndexInput,
) -> bool {
    duplicate_hash_review_state(repo_path, rows, &input.hash_sha256, &input.path)
        == DuplicateHashReviewState::Conflict
}

fn active_file_snapshots(repo_path: &Path) -> CoreResult<Vec<FileSnapshot>> {
    Ok(db::active_scan_file_snapshots(repo_path)?
        .into_iter()
        .map(FileSnapshot::from)
        .collect())
}

fn preview_file_snapshots(repo_path: &Path) -> CoreResult<Vec<FileSnapshot>> {
    Ok(db::active_scan_file_snapshots_read_only(repo_path)?
        .into_iter()
        .map(FileSnapshot::from)
        .collect())
}

fn duplicate_hash_review_state(
    repo_path: &Path,
    rows: &[FileSnapshot],
    hash_sha256: &str,
    current_path: &str,
) -> DuplicateHashReviewState {
    let mut saw_missing_match = false;
    for row in rows {
        if row.path == current_path
            || row.hash_sha256 != hash_sha256
            || row.storage_mode != StorageMode::Indexed
        {
            continue;
        }
        if row_backing_file_missing(repo_path, row) {
            saw_missing_match = true;
        } else {
            return DuplicateHashReviewState::Conflict;
        }
    }
    if saw_missing_match {
        DuplicateHashReviewState::RenamedCandidate
    } else {
        DuplicateHashReviewState::None
    }
}

fn row_backing_file_missing(repo_path: &Path, row: &FileSnapshot) -> bool {
    let backing_path = if matches!(row.storage_mode, StorageMode::Copied | StorageMode::Moved) {
        repo_path.join(&row.path)
    } else if let Some(source_path) = &row.source_path {
        PathBuf::from(source_path)
    } else {
        repo_path.join(&row.path)
    };
    matches!(backing_path.try_exists(), Ok(false))
}

fn reason_for_preview_kind(kind: &ManualRescanPreviewItemKind) -> &'static str {
    match kind {
        ManualRescanPreviewItemKind::Added => "file is not indexed yet",
        ManualRescanPreviewItemKind::Updated => "file metadata differs from the index",
        ManualRescanPreviewItemKind::Missing => "metadata row is missing from the filesystem",
        ManualRescanPreviewItemKind::RenamedCandidate => "same content hash exists at another path",
        ManualRescanPreviewItemKind::Conflict => "change requires review before classification",
        ManualRescanPreviewItemKind::Unreadable => "file or metadata cannot be read",
        ManualRescanPreviewItemKind::Unknown => "change could not be classified safely",
        ManualRescanPreviewItemKind::Skipped => "file is ignored or already up to date",
    }
}

fn action_for_preview_kind(kind: &ManualRescanPreviewItemKind) -> &'static str {
    match kind {
        ManualRescanPreviewItemKind::Missing
        | ManualRescanPreviewItemKind::RenamedCandidate
        | ManualRescanPreviewItemKind::Conflict
        | ManualRescanPreviewItemKind::Unreadable
        | ManualRescanPreviewItemKind::Unknown => "Open Needs Review",
        ManualRescanPreviewItemKind::Added | ManualRescanPreviewItemKind::Updated => "Run Rescan",
        ManualRescanPreviewItemKind::Skipped => "No action",
    }
}

fn error_preview_item(relative_path: &str, error: &CoreError) -> ManualRescanPreviewItem {
    let kind = match error {
        CoreError::PermissionDenied { .. } => ManualRescanPreviewItemKind::Unreadable,
        _ => ManualRescanPreviewItemKind::Unknown,
    };
    ManualRescanPreviewItem {
        reason: reason_for_preview_kind(&kind).to_owned(),
        suggested_action: action_for_preview_kind(&kind).to_owned(),
        kind,
        relative_path: relative_path.to_owned(),
    }
}

fn change_for_scan_error(error: &CoreError) -> ScanFileChange {
    match error {
        CoreError::PermissionDenied { .. } => ScanFileChange::Unreadable,
        _ => ScanFileChange::Unknown,
    }
}

fn finish_failed_scan(
    repo_path: &Path,
    scan_session_id: i64,
    relative_path: &str,
    error: CoreError,
) -> CoreResult<()> {
    let errors = vec![format!("{relative_path}: {error}")];
    match db::finish_scan_session(
        repo_path,
        scan_session_id,
        ScanSessionStatus::Failed,
        &errors,
    ) {
        Ok(()) => Err(error),
        Err(persist_error) => Err(CoreError::db(format!(
            "failed to persist failed scan session after {relative_path}: {error}; {persist_error}"
        ))),
    }
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
        missing: 0,
        conflicts: 0,
        unreadable: 0,
        unknown: 0,
        skipped: 0,
        errors: Vec::new(),
    }
}

fn report_from_session(session: &ScanSession) -> ReindexReport {
    ReindexReport {
        scan_session_id: Some(session.id),
        inserted: session.inserted,
        updated: session.updated,
        missing: session.missing,
        conflicts: session.conflicts,
        unreadable: session.unreadable,
        unknown: session.unknown,
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

#[derive(Clone)]
struct FileSnapshot {
    path: String,
    original_name: String,
    current_name: String,
    category: String,
    size_bytes: i64,
    hash_sha256: String,
    storage_mode: StorageMode,
    origin: FileOrigin,
    source_path: Option<String>,
}

impl FileSnapshot {
    fn matches(&self, input: &FileIndexInput, origin: FileOrigin) -> bool {
        self.original_name == input.original_name
            && self.current_name == input.current_name
            && self.category == input.category
            && self.size_bytes == input.size_bytes
            && self.hash_sha256 == input.hash_sha256
            && self.storage_mode == StorageMode::Indexed
            && self.origin == origin
    }
}

impl From<ScanFileSnapshot> for FileSnapshot {
    fn from(entry: ScanFileSnapshot) -> Self {
        Self {
            path: entry.path,
            original_name: entry.original_name,
            current_name: entry.current_name,
            category: entry.category,
            size_bytes: entry.size_bytes,
            hash_sha256: entry.hash_sha256,
            storage_mode: entry.storage_mode,
            origin: entry.origin,
            source_path: entry.source_path,
        }
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum DuplicateHashReviewState {
    None,
    RenamedCandidate,
    Conflict,
}

struct PreviewSummary {
    added: i64,
    updated: i64,
    missing: i64,
    renamed_candidates: i64,
    conflicts: i64,
    unreadable: i64,
    unknown: i64,
    skipped: i64,
    items: Vec<ManualRescanPreviewItem>,
}

impl PreviewSummary {
    fn new(skipped: i64) -> Self {
        Self {
            added: 0,
            updated: 0,
            missing: 0,
            renamed_candidates: 0,
            conflicts: 0,
            unreadable: 0,
            unknown: 0,
            skipped,
            items: Vec::new(),
        }
    }

    fn push(&mut self, item: ManualRescanPreviewItem) {
        match item.kind {
            ManualRescanPreviewItemKind::Added => self.added += 1,
            ManualRescanPreviewItemKind::Updated => self.updated += 1,
            ManualRescanPreviewItemKind::Missing => self.missing += 1,
            ManualRescanPreviewItemKind::RenamedCandidate => self.renamed_candidates += 1,
            ManualRescanPreviewItemKind::Conflict => self.conflicts += 1,
            ManualRescanPreviewItemKind::Unreadable => self.unreadable += 1,
            ManualRescanPreviewItemKind::Unknown => self.unknown += 1,
            ManualRescanPreviewItemKind::Skipped => self.skipped += 1,
        }
        if self.items.len() < 5 {
            self.items.push(item);
        }
    }

    fn into_report(self, created_at: i64) -> ManualRescanPreviewReport {
        ManualRescanPreviewReport {
            added: self.added,
            updated: self.updated,
            missing_or_deleted_from_fs: self.missing,
            renamed_candidates: self.renamed_candidates,
            conflicts: self.conflicts,
            unreadable: self.unreadable,
            unknown: self.unknown,
            skipped: self.skipped,
            snapshot_id: format!(
                "manual-rescan:{created_at}:{}:{}:{}:{}",
                self.added, self.updated, self.missing, self.skipped
            ),
            created_at,
            is_stale: false,
            items: self.items,
        }
    }
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
