use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

use sha2::Digest;

use crate::{
    storage, BatchCategoryPreviewItem, BatchCategoryPreviewReport, BatchCategoryPreviewStatus,
    CategoryDistributionItem, CoreError, CoreResult, FileEntry, StorageMode,
};

use super::{
    path_plan::resolve_repo_owned_target,
    path_plan::{
        ensure_category_directory_writable, ensure_repo_owned_file, plan_note_sidecar,
        preview_category_directory,
    },
    token,
};

#[derive(Clone, Debug)]
pub(super) struct BatchCategoryPlan {
    pub(super) requested_file_count: i64,
    pub(super) target_category: String,
    pub(super) move_repo_owned_files: bool,
    pub(super) preview_token: String,
    pub(super) category_distribution: Vec<CategoryDistributionItem>,
    pub(super) items: Vec<BatchCategoryPlanItem>,
}

#[derive(Clone, Debug)]
pub(super) enum BatchCategoryPlanItem {
    WillMove(PlannedCategoryChange),
    MetadataOnly(PlannedCategoryChange),
    Unchanged(PlannedCategoryChange),
    Skipped(SkippedCategoryChange),
    Blocked(BlockedCategoryChange),
}

#[derive(Clone, Debug)]
pub(super) struct PlannedCategoryChange {
    pub(super) entry: FileEntry,
    pub(super) target_category: String,
    pub(super) final_relative_path: String,
    pub(super) final_name: String,
    pub(super) current_path: PathBuf,
    pub(super) final_path: PathBuf,
    pub(super) index_only: bool,
    pub(super) will_move_file: bool,
    pub(super) note_sidecar: Option<PlannedSidecarMove>,
}

#[derive(Clone, Debug)]
pub(super) struct PlannedSidecarMove {
    pub(super) current_path: PathBuf,
    pub(super) final_path: PathBuf,
}

#[derive(Clone, Debug)]
pub(super) struct SkippedCategoryChange {
    pub(super) file_id: i64,
    pub(super) target_category: String,
    pub(super) reason: String,
}

#[derive(Clone, Debug)]
pub(super) struct BlockedCategoryChange {
    pub(super) file_id: i64,
    pub(super) from_category: Option<String>,
    pub(super) target_category: String,
    pub(super) current_path: Option<String>,
    pub(super) storage_mode: Option<StorageMode>,
    pub(super) reason: String,
}

pub(super) fn build_batch_category_plan(
    repo: &Path,
    file_ids: &[i64],
    target_category: &str,
    move_repo_owned_files: bool,
) -> CoreResult<BatchCategoryPlan> {
    let target_directory = preview_category_directory(repo, target_category)?;
    let mut items = Vec::with_capacity(file_ids.len());
    for file_id in file_ids {
        items.push(plan_item(
            repo,
            &target_directory,
            *file_id,
            target_category,
            move_repo_owned_files,
        )?);
    }
    let category_distribution = category_distribution(&items);
    let preview_token =
        token::preview_token(file_ids, target_category, move_repo_owned_files, &items);
    Ok(BatchCategoryPlan {
        requested_file_count: file_ids.len() as i64,
        target_category: target_category.to_owned(),
        move_repo_owned_files,
        preview_token,
        category_distribution,
        items,
    })
}

impl BatchCategoryPlan {
    pub(super) fn can_apply(&self) -> bool {
        self.blocked_count() == 0 && self.items.iter().any(BatchCategoryPlanItem::is_applicable)
    }

    pub(super) fn apply_blocked_reason(&self) -> Option<String> {
        if self.blocked_count() > 0 {
            return Some(format!(
                "{} item(s) must be resolved before Apply",
                self.blocked_count()
            ));
        }
        if !self.items.iter().any(BatchCategoryPlanItem::is_applicable) {
            return Some("No selected files need category changes".to_owned());
        }
        None
    }

    pub(super) fn into_preview_report(self) -> BatchCategoryPreviewReport {
        let can_apply = self.can_apply();
        let apply_blocked_reason = if can_apply {
            None
        } else {
            self.apply_blocked_reason()
        };
        let will_move_count = self.will_move_count();
        let metadata_only_count = self.metadata_only_count();
        let unchanged_count = self.unchanged_count();
        let skipped_count = self.skipped_count();
        let blocked_count = self.blocked_count();
        BatchCategoryPreviewReport {
            requested_file_count: self.requested_file_count,
            target_category: self.target_category,
            move_repo_owned_files: self.move_repo_owned_files,
            preview_token: self.preview_token,
            category_distribution: self.category_distribution,
            will_move_count,
            metadata_only_count,
            unchanged_count,
            skipped_count,
            blocked_count,
            items: self
                .items
                .into_iter()
                .map(BatchCategoryPlanItem::preview)
                .collect(),
            can_apply,
            apply_blocked_reason,
        }
    }

    fn will_move_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchCategoryPlanItem::WillMove(_))
        })
    }

    fn metadata_only_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchCategoryPlanItem::MetadataOnly(_))
        })
    }

    fn unchanged_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchCategoryPlanItem::Unchanged(_))
        })
    }

    fn skipped_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchCategoryPlanItem::Skipped(_))
        })
    }

    fn blocked_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchCategoryPlanItem::Blocked(_))
        })
    }
}

impl BatchCategoryPlanItem {
    pub(super) fn is_applicable(&self) -> bool {
        matches!(self, Self::WillMove(_) | Self::MetadataOnly(_))
    }

    pub(super) fn preview(self) -> BatchCategoryPreviewItem {
        match self {
            Self::WillMove(change) => change.preview(BatchCategoryPreviewStatus::WillMove, None),
            Self::MetadataOnly(change) => {
                change.preview(BatchCategoryPreviewStatus::MetadataOnly, None)
            }
            Self::Unchanged(change) => change.preview(
                BatchCategoryPreviewStatus::Unchanged,
                Some("Already in target category".to_owned()),
            ),
            Self::Skipped(change) => BatchCategoryPreviewItem {
                file_id: change.file_id,
                from_category: None,
                to_category: change.target_category,
                current_path: None,
                target_path: None,
                target_name: None,
                storage_mode: None,
                index_only: false,
                will_move_file: false,
                status: BatchCategoryPreviewStatus::Skipped,
                reason: Some(change.reason),
            },
            Self::Blocked(change) => BatchCategoryPreviewItem {
                file_id: change.file_id,
                from_category: change.from_category,
                to_category: change.target_category,
                current_path: change.current_path,
                target_path: None,
                target_name: None,
                storage_mode: change.storage_mode,
                index_only: false,
                will_move_file: false,
                status: BatchCategoryPreviewStatus::Blocked,
                reason: Some(change.reason),
            },
        }
    }

    pub(super) fn feed_preview_token(&self, hasher: &mut sha2::Sha256) {
        match self {
            Self::WillMove(change) => change.feed_preview_token(hasher, "will_move"),
            Self::MetadataOnly(change) => change.feed_preview_token(hasher, "metadata_only"),
            Self::Unchanged(change) => change.feed_preview_token(hasher, "unchanged"),
            Self::Skipped(change) => {
                hasher.update(b"skipped");
                hasher.update(change.file_id.to_le_bytes());
                hasher.update(change.reason.as_bytes());
            }
            Self::Blocked(change) => {
                hasher.update(b"blocked");
                hasher.update(change.file_id.to_le_bytes());
                feed_optional(hasher, change.current_path.as_deref());
                feed_optional(hasher, change.from_category.as_deref());
                hasher.update(change.reason.as_bytes());
            }
        }
    }
}

impl PlannedCategoryChange {
    fn preview(
        self,
        status: BatchCategoryPreviewStatus,
        reason: Option<String>,
    ) -> BatchCategoryPreviewItem {
        BatchCategoryPreviewItem {
            file_id: self.entry.id,
            from_category: Some(self.entry.category),
            to_category: self.target_category,
            current_path: Some(self.entry.path),
            target_path: Some(self.final_relative_path),
            target_name: Some(self.final_name),
            storage_mode: Some(self.entry.storage_mode),
            index_only: self.index_only,
            will_move_file: self.will_move_file,
            status,
            reason,
        }
    }

    fn feed_preview_token(&self, hasher: &mut sha2::Sha256, status: &str) {
        hasher.update(status.as_bytes());
        hasher.update(self.entry.id.to_le_bytes());
        hasher.update(self.entry.path.as_bytes());
        hasher.update(self.entry.current_name.as_bytes());
        hasher.update(self.entry.category.as_bytes());
        hasher.update(self.entry.updated_at.to_le_bytes());
        hasher.update(storage_mode_token(&self.entry.storage_mode));
        hasher.update(self.final_relative_path.as_bytes());
        hasher.update(self.final_name.as_bytes());
        hasher.update(if self.index_only { b"\x01" } else { b"\x00" });
        hasher.update(if self.will_move_file {
            b"\x01"
        } else {
            b"\x00"
        });
    }
}

fn plan_item(
    repo: &Path,
    target_directory: &Path,
    file_id: i64,
    target_category: &str,
    move_repo_owned_files: bool,
) -> CoreResult<BatchCategoryPlanItem> {
    let entry = match db_entry(repo, file_id)? {
        Some(entry) => entry,
        None => {
            return Ok(BatchCategoryPlanItem::Skipped(SkippedCategoryChange {
                file_id,
                target_category: target_category.to_owned(),
                reason: "File is no longer active".to_owned(),
            }))
        }
    };

    if entry.category == target_category {
        return unchanged_item(repo, entry, target_category);
    }
    if matches!(entry.storage_mode, StorageMode::Indexed) || !move_repo_owned_files {
        return Ok(BatchCategoryPlanItem::MetadataOnly(metadata_only_change(
            &entry,
            target_category,
        )));
    }
    plan_repo_owned_move(repo, target_directory, entry, target_category)
}

fn unchanged_item(
    repo: &Path,
    entry: FileEntry,
    target_category: &str,
) -> CoreResult<BatchCategoryPlanItem> {
    if storage::dedup::is_repo_owned(&entry) {
        match ensure_repo_owned_file(repo, &entry) {
            Ok(()) => {}
            Err(error) => {
                return Ok(blocked_from_entry(entry, target_category, error));
            }
        }
    }
    Ok(BatchCategoryPlanItem::Unchanged(metadata_only_change(
        &entry,
        target_category,
    )))
}

fn plan_repo_owned_move(
    repo: &Path,
    target_directory: &Path,
    entry: FileEntry,
    target_category: &str,
) -> CoreResult<BatchCategoryPlanItem> {
    if !storage::dedup::is_repo_owned(&entry) {
        return Ok(blocked_from_entry(
            entry,
            target_category,
            CoreError::invalid_path("invalid path"),
        ));
    }
    if let Err(error) = ensure_category_directory_writable(target_directory) {
        return Ok(blocked_from_entry(entry, target_category, error));
    }

    let planned = match resolve_repo_owned_target(repo, target_directory, &entry) {
        Ok(target) => target,
        Err(error) => return Ok(blocked_from_entry(entry, target_category, error)),
    };
    let note_sidecar =
        match plan_note_sidecar(repo, entry.id, &planned.current_path, &planned.final_path) {
            Ok(note_sidecar) => note_sidecar,
            Err(error) => return Ok(blocked_from_entry(entry, target_category, error)),
        };
    Ok(BatchCategoryPlanItem::WillMove(PlannedCategoryChange {
        entry,
        target_category: target_category.to_owned(),
        final_relative_path: planned.final_relative_path,
        final_name: planned.final_name,
        current_path: planned.current_path,
        final_path: planned.final_path,
        index_only: false,
        will_move_file: true,
        note_sidecar,
    }))
}

fn metadata_only_change(entry: &FileEntry, target_category: &str) -> PlannedCategoryChange {
    PlannedCategoryChange {
        entry: entry.clone(),
        target_category: target_category.to_owned(),
        final_relative_path: entry.path.clone(),
        final_name: entry.current_name.clone(),
        current_path: PathBuf::from(&entry.path),
        final_path: PathBuf::from(&entry.path),
        index_only: matches!(entry.storage_mode, StorageMode::Indexed),
        will_move_file: false,
        note_sidecar: None,
    }
}

fn blocked_from_entry(
    entry: FileEntry,
    target_category: &str,
    error: CoreError,
) -> BatchCategoryPlanItem {
    BatchCategoryPlanItem::Blocked(BlockedCategoryChange {
        file_id: entry.id,
        from_category: Some(entry.category),
        target_category: target_category.to_owned(),
        current_path: Some(entry.path),
        storage_mode: Some(entry.storage_mode),
        reason: preview_failure_message(error),
    })
}

fn db_entry(repo: &Path, file_id: i64) -> CoreResult<Option<FileEntry>> {
    match crate::db::get_active_file_by_id(repo, file_id) {
        Ok(entry) => Ok(Some(entry)),
        Err(CoreError::FileNotFound { .. }) => Ok(None),
        Err(error) => Err(error),
    }
}

fn category_distribution(items: &[BatchCategoryPlanItem]) -> Vec<CategoryDistributionItem> {
    let mut counts: BTreeMap<String, i64> = BTreeMap::new();
    for item in items {
        if let Some(category) = item.source_category() {
            *counts.entry(category.to_owned()).or_default() += 1;
        }
    }
    counts
        .into_iter()
        .map(|(category, count)| CategoryDistributionItem { category, count })
        .collect()
}

impl BatchCategoryPlanItem {
    fn source_category(&self) -> Option<&str> {
        match self {
            Self::WillMove(change) | Self::MetadataOnly(change) | Self::Unchanged(change) => {
                Some(&change.entry.category)
            }
            Self::Blocked(change) => change.from_category.as_deref(),
            Self::Skipped(_) => None,
        }
    }
}

fn preview_failure_message(error: CoreError) -> String {
    match error {
        CoreError::Conflict { path } => format!("Conflict: {path}"),
        CoreError::FileNotFound { path } => format!("FileNotFound: {path}"),
        CoreError::PermissionDenied { path } => format!("PermissionDenied: {path}"),
        CoreError::Io { message } => format!("Io: {message}"),
        CoreError::Db { message } => format!("Db: {message}"),
        CoreError::InvalidPath { path } => format!("InvalidPath: {path}"),
        other => other.to_string(),
    }
}

fn storage_mode_token(mode: &StorageMode) -> &'static [u8] {
    match mode {
        StorageMode::Moved => b"moved",
        StorageMode::Copied => b"copied",
        StorageMode::Indexed => b"indexed",
    }
}

fn feed_optional(hasher: &mut sha2::Sha256, value: Option<&str>) {
    if let Some(value) = value {
        hasher.update(b"\x01");
        hasher.update(value.as_bytes());
    } else {
        hasher.update(b"\x00");
    }
}

fn count_items(
    items: &[BatchCategoryPlanItem],
    predicate: impl Fn(&BatchCategoryPlanItem) -> bool,
) -> i64 {
    items.iter().filter(|item| predicate(item)).count() as i64
}
