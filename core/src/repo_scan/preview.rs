use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    path::{Path, PathBuf},
};

use crate::{
    db::{self, FileIndexInput},
    CoreError, CoreResult, FileOrigin, ManualRescanPreviewItem, ManualRescanPreviewItemKind,
    ManualRescanPreviewReport, StorageMode,
};

use super::{
    files::index_input_for_file,
    types::{AdoptFile, DuplicateHashReviewState, FileSnapshot, ScanPlan},
};

pub(super) fn preview_from_plan(
    repo_path: &Path,
    plan: &ScanPlan,
) -> CoreResult<ManualRescanPreviewReport> {
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

pub(super) fn missing_metadata_paths(
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

pub(super) fn has_present_hash_conflict(
    repo_path: &Path,
    rows: &[FileSnapshot],
    input: &FileIndexInput,
) -> bool {
    duplicate_hash_review_state(repo_path, rows, &input.hash_sha256, &input.path)
        == DuplicateHashReviewState::Conflict
}

pub(super) fn active_file_snapshots(repo_path: &Path) -> CoreResult<Vec<FileSnapshot>> {
    Ok(db::active_scan_file_snapshots(repo_path)?
        .into_iter()
        .map(FileSnapshot::from)
        .collect())
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
