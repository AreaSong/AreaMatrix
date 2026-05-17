use std::path::{Path, PathBuf};

use sha2::Digest;

use crate::{
    BatchDeleteMode, BatchDeletePreviewItem, BatchDeletePreviewReport, BatchDeletePreviewStatus,
    CoreError, CoreResult, FileEntry, FileOrigin, StorageMode,
};

use super::{
    inspect::{
        inspect_path, path_exists, path_is_writable_dir, InspectedPathState, PathInspection,
    },
    token,
};

mod classify;

#[derive(Clone, Debug)]
pub(super) struct BatchDeletePlan {
    pub(super) requested_file_count: i64,
    pub(super) delete_mode: BatchDeleteMode,
    pub(super) preview_token: String,
    pub(super) items: Vec<BatchDeletePlanItem>,
    trash_available: bool,
}

#[derive(Clone, Debug)]
pub(super) enum BatchDeletePlanItem {
    MoveToTrash(PlannedBatchDeleteItem),
    RemoveFromIndex(PlannedBatchDeleteItem),
    Missing(PlannedBatchDeleteItem),
    Skipped(SkippedBatchDeleteItem),
    Blocked(BlockedBatchDeleteItem),
}

#[derive(Clone, Debug)]
pub(super) struct PlannedBatchDeleteItem {
    pub(super) entry: FileEntry,
    pub(super) current_path: PathBuf,
    inspected_state: InspectedPathState,
}

#[derive(Clone, Debug)]
pub(super) struct SkippedBatchDeleteItem {
    pub(super) file_id: i64,
    pub(super) current_path: Option<String>,
    pub(super) current_name: Option<String>,
    pub(super) storage_mode: Option<StorageMode>,
    inspected_state: Option<InspectedPathState>,
    pub(super) reason: String,
}

#[derive(Clone, Debug)]
pub(super) struct BlockedBatchDeleteItem {
    pub(super) file_id: i64,
    pub(super) current_path: Option<String>,
    pub(super) current_name: Option<String>,
    pub(super) storage_mode: Option<StorageMode>,
    inspected_state: Option<InspectedPathState>,
    pub(super) reason: String,
}

impl BatchDeletePlan {
    pub(super) fn build(
        repo: &Path,
        file_ids: Vec<i64>,
        delete_mode: BatchDeleteMode,
    ) -> CoreResult<Self> {
        let trash_available = classify::preview_trash_available()?;
        let mut items = Vec::with_capacity(file_ids.len());
        for file_id in &file_ids {
            items.push(classify::plan_batch_delete_item(
                repo,
                *file_id,
                &delete_mode,
                trash_available,
            )?);
        }
        let preview_token = token::preview_token(&file_ids, &delete_mode, trash_available, &items);
        Ok(Self {
            requested_file_count: file_ids.len() as i64,
            delete_mode,
            preview_token,
            trash_available,
            items,
        })
    }

    pub(super) fn into_preview_report(self) -> BatchDeletePreviewReport {
        let can_apply = self.can_apply();
        let apply_blocked_reason = if can_apply {
            None
        } else {
            self.apply_blocked_reason()
        };
        let will_trash_count = self.will_trash_count();
        let index_only_count = self.index_only_count();
        let missing_count = self.missing_count();
        let skipped_count = self.skipped_count();
        let blocked_count = self.blocked_count();
        BatchDeletePreviewReport {
            requested_file_count: self.requested_file_count,
            delete_mode: self.delete_mode.clone(),
            preview_token: self.preview_token,
            trash_available: self.trash_available,
            undo_available: self.items.iter().any(BatchDeletePlanItem::creates_undo),
            will_trash_count,
            index_only_count,
            missing_count,
            skipped_count,
            blocked_count,
            items: self
                .items
                .into_iter()
                .map(|item| item.into_preview_item(self.delete_mode.clone()))
                .collect(),
            can_apply,
            apply_blocked_reason,
        }
    }

    pub(super) fn can_apply(&self) -> bool {
        self.blocked_count() == 0 && self.items.iter().any(BatchDeletePlanItem::is_applicable)
    }

    pub(super) fn apply_blocked_reason(&self) -> Option<String> {
        if self.blocked_count() > 0 {
            return Some(format!(
                "{} item(s) must be resolved before Apply",
                self.blocked_count()
            ));
        }
        if !self.items.iter().any(BatchDeletePlanItem::is_applicable) {
            return Some("No selected files can be deleted in this mode".to_owned());
        }
        None
    }

    fn will_trash_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchDeletePlanItem::MoveToTrash(_))
        })
    }

    fn index_only_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchDeletePlanItem::RemoveFromIndex(_))
        })
    }

    fn missing_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchDeletePlanItem::Missing(_))
        })
    }

    fn skipped_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchDeletePlanItem::Skipped(_))
        })
    }

    fn blocked_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchDeletePlanItem::Blocked(_))
        })
    }
}

impl BatchDeletePlanItem {
    fn is_applicable(&self) -> bool {
        matches!(
            self,
            Self::MoveToTrash(_) | Self::RemoveFromIndex(_) | Self::Missing(_)
        )
    }

    fn creates_undo(&self) -> bool {
        matches!(self, Self::MoveToTrash(_))
    }

    fn into_preview_item(self, delete_mode: BatchDeleteMode) -> BatchDeletePreviewItem {
        match self {
            Self::MoveToTrash(item) => item.preview(
                delete_mode,
                BatchDeletePreviewStatus::WillMoveToTrash,
                true,
                false,
                None,
            ),
            Self::RemoveFromIndex(item) => item.preview(
                delete_mode,
                BatchDeletePreviewStatus::IndexOnly,
                false,
                true,
                None,
            ),
            Self::Missing(item) => item.preview(
                delete_mode,
                BatchDeletePreviewStatus::Missing,
                false,
                true,
                Some("Physical file is missing; metadata can be removed".to_owned()),
            ),
            Self::Skipped(item) => BatchDeletePreviewItem {
                file_id: item.file_id,
                current_path: item.current_path,
                current_name: item.current_name,
                storage_mode: item.storage_mode,
                delete_mode,
                will_move_to_trash: false,
                will_remove_index: false,
                status: BatchDeletePreviewStatus::Skipped,
                reason: Some(item.reason),
            },
            Self::Blocked(item) => BatchDeletePreviewItem {
                file_id: item.file_id,
                current_path: item.current_path,
                current_name: item.current_name,
                storage_mode: item.storage_mode,
                delete_mode,
                will_move_to_trash: false,
                will_remove_index: false,
                status: BatchDeletePreviewStatus::Blocked,
                reason: Some(item.reason),
            },
        }
    }

    pub(super) fn feed_preview_token(&self, hasher: &mut sha2::Sha256) {
        match self {
            Self::MoveToTrash(item) => item.feed_preview_token(hasher, "move_to_trash"),
            Self::RemoveFromIndex(item) => item.feed_preview_token(hasher, "remove_from_index"),
            Self::Missing(item) => item.feed_preview_token(hasher, "missing"),
            Self::Skipped(item) => {
                hasher.update(b"skipped");
                hasher.update(item.file_id.to_le_bytes());
                feed_optional(hasher, item.current_path.as_deref());
                feed_optional(hasher, item.current_name.as_deref());
                feed_inspected_state(hasher, item.inspected_state.as_ref());
                hasher.update(item.reason.as_bytes());
            }
            Self::Blocked(item) => {
                hasher.update(b"blocked");
                hasher.update(item.file_id.to_le_bytes());
                feed_optional(hasher, item.current_path.as_deref());
                feed_optional(hasher, item.current_name.as_deref());
                feed_inspected_state(hasher, item.inspected_state.as_ref());
                hasher.update(item.reason.as_bytes());
            }
        }
    }
}

impl PlannedBatchDeleteItem {
    fn preview(
        self,
        delete_mode: BatchDeleteMode,
        status: BatchDeletePreviewStatus,
        will_move_to_trash: bool,
        will_remove_index: bool,
        reason: Option<String>,
    ) -> BatchDeletePreviewItem {
        BatchDeletePreviewItem {
            file_id: self.entry.id,
            current_path: Some(self.entry.path),
            current_name: Some(self.entry.current_name),
            storage_mode: Some(self.entry.storage_mode),
            delete_mode,
            will_move_to_trash,
            will_remove_index,
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
        hasher.update(origin_token(&self.entry.origin));
        hasher.update(self.current_path.to_string_lossy().as_bytes());
        self.inspected_state.feed_preview_token(hasher);
    }
}

fn storage_mode_token(mode: &StorageMode) -> &'static [u8] {
    match mode {
        StorageMode::Moved => b"moved",
        StorageMode::Copied => b"copied",
        StorageMode::Indexed => b"indexed",
    }
}

fn origin_token(origin: &FileOrigin) -> &'static [u8] {
    match origin {
        FileOrigin::Imported => b"imported",
        FileOrigin::Adopted => b"adopted",
        FileOrigin::External => b"external",
    }
}

fn feed_optional(hasher: &mut sha2::Sha256, value: Option<&str>) {
    match value {
        Some(value) => {
            hasher.update(b"\x01");
            hasher.update(value.as_bytes());
        }
        None => hasher.update(b"\x00"),
    }
}

fn feed_inspected_state(hasher: &mut sha2::Sha256, state: Option<&InspectedPathState>) {
    match state {
        Some(state) => {
            hasher.update(b"\x01");
            state.feed_preview_token(hasher);
        }
        None => hasher.update(b"\x00"),
    }
}

fn inspect_current_file_state(current_path: &Path) -> CoreResult<InspectedPathState> {
    match inspect_path(current_path)? {
        PathInspection::File(state) => Ok(state),
        PathInspection::Missing => Ok(InspectedPathState::missing()),
        PathInspection::Other => Err(CoreError::file_not_found(
            current_path.display().to_string(),
        )),
    }
}

fn inspect_current_optional_state(current_path: &Path) -> CoreResult<InspectedPathState> {
    match inspect_optional_state(current_path)? {
        Some(state) => Ok(state),
        None => Ok(InspectedPathState::missing()),
    }
}

fn inspect_optional_state(current_path: &Path) -> CoreResult<Option<InspectedPathState>> {
    match inspect_path(current_path)? {
        PathInspection::File(state) => Ok(Some(state)),
        PathInspection::Missing | PathInspection::Other => Ok(None),
    }
}

fn planned_item(
    entry: FileEntry,
    current_path: PathBuf,
    inspected_state: InspectedPathState,
) -> PlannedBatchDeleteItem {
    PlannedBatchDeleteItem {
        entry,
        current_path,
        inspected_state,
    }
}

fn skipped_from_entry(
    entry: FileEntry,
    inspected_state: Option<InspectedPathState>,
    reason: &str,
) -> BatchDeletePlanItem {
    skipped(
        entry.id,
        Some(entry.path),
        Some(entry.current_name),
        Some(entry.storage_mode),
        inspected_state,
        reason,
    )
}

fn blocked_from_entry(
    entry: FileEntry,
    inspected_state: Option<InspectedPathState>,
    error: CoreError,
) -> BatchDeletePlanItem {
    BatchDeletePlanItem::Blocked(BlockedBatchDeleteItem {
        file_id: entry.id,
        current_path: Some(entry.path),
        current_name: Some(entry.current_name),
        storage_mode: Some(entry.storage_mode),
        inspected_state,
        reason: super::error_message(error),
    })
}

fn skipped(
    file_id: i64,
    current_path: Option<String>,
    current_name: Option<String>,
    storage_mode: Option<StorageMode>,
    inspected_state: Option<InspectedPathState>,
    reason: &str,
) -> BatchDeletePlanItem {
    BatchDeletePlanItem::Skipped(SkippedBatchDeleteItem {
        file_id,
        current_path,
        current_name,
        storage_mode,
        inspected_state,
        reason: reason.to_owned(),
    })
}

fn count_items(
    items: &[BatchDeletePlanItem],
    predicate: impl Fn(&BatchDeletePlanItem) -> bool,
) -> i64 {
    items.iter().filter(|item| predicate(item)).count() as i64
}
