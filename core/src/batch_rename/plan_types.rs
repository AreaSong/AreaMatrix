use sha2::Digest;

use crate::{
    BatchRenameConflict, BatchRenamePreviewItem, BatchRenamePreviewReport,
    BatchRenamePreviewStatus, BatchRenameRule, FileEntry, StorageMode,
};

#[derive(Clone, Debug)]
pub(super) struct BatchRenamePlan {
    pub(super) requested_file_count: i64,
    pub(super) rule: BatchRenameRule,
    pub(super) preview_token: String,
    pub(super) items: Vec<BatchRenamePlanItem>,
    pub(super) conflicts: Vec<BatchRenameConflict>,
}

#[derive(Clone, Debug)]
pub(super) enum BatchRenamePlanItem {
    Rename(PlannedRenameChange),
    DisplayOnly(PlannedRenameChange),
    Unchanged(PlannedRenameChange),
    Blocked(BlockedRenameChange),
}

#[derive(Clone, Debug)]
pub(super) struct PlannedRenameChange {
    pub(super) entry: FileEntry,
    pub(super) current_path: std::path::PathBuf,
    pub(super) final_path: Option<std::path::PathBuf>,
    pub(super) final_relative_path: Option<String>,
    pub(super) new_name: String,
    pub(super) index_only: bool,
    pub(super) will_rename_file: bool,
    pub(super) note_sidecar: Option<PlannedRenameSidecar>,
}

#[derive(Clone, Debug)]
pub(super) struct PlannedRenameSidecar {
    pub(super) current_path: std::path::PathBuf,
    pub(super) final_path: std::path::PathBuf,
}

#[derive(Clone, Debug)]
pub(super) struct BlockedRenameChange {
    pub(super) file_id: i64,
    pub(super) current_path: Option<String>,
    pub(super) original_name: Option<String>,
    pub(super) new_name: Option<String>,
    pub(super) target_path: Option<String>,
    pub(super) storage_mode: Option<StorageMode>,
    pub(super) status: BatchRenamePreviewStatus,
    pub(super) reason: String,
}

impl BatchRenamePlan {
    pub(super) fn can_apply(&self) -> bool {
        self.blocked_count() == 0 && self.items.iter().any(BatchRenamePlanItem::is_applicable)
    }

    pub(super) fn apply_blocked_reason(&self) -> Option<String> {
        if self.blocked_count() > 0 {
            return Some(format!(
                "{} item(s) must be resolved before Apply",
                self.blocked_count()
            ));
        }
        if !self.items.iter().any(BatchRenamePlanItem::is_applicable) {
            return Some("No filename changes.".to_owned());
        }
        None
    }

    pub(super) fn into_preview_report(self) -> BatchRenamePreviewReport {
        let can_apply = self.can_apply();
        let apply_blocked_reason = if can_apply {
            None
        } else {
            self.apply_blocked_reason()
        };
        let will_rename_count = self.will_rename_count();
        let display_only_count = self.display_only_count();
        let unchanged_count = self.unchanged_count();
        let blocked_count = self.blocked_count();
        let conflict_count = self.conflicts.len() as i64;
        BatchRenamePreviewReport {
            requested_file_count: self.requested_file_count,
            rule: self.rule,
            preview_token: self.preview_token,
            will_rename_count,
            display_only_count,
            unchanged_count,
            blocked_count,
            conflict_count,
            items: self
                .items
                .into_iter()
                .map(BatchRenamePlanItem::preview)
                .collect(),
            conflicts: self.conflicts,
            can_apply,
            apply_blocked_reason,
        }
    }

    fn will_rename_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchRenamePlanItem::Rename(_))
        })
    }

    fn display_only_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchRenamePlanItem::DisplayOnly(_))
        })
    }

    fn unchanged_count(&self) -> i64 {
        count_items(&self.items, |item| {
            matches!(item, BatchRenamePlanItem::Unchanged(_))
        })
    }

    fn blocked_count(&self) -> i64 {
        count_items(&self.items, BatchRenamePlanItem::is_blocked)
    }
}

impl BatchRenamePlanItem {
    pub(super) fn is_applicable(&self) -> bool {
        matches!(self, Self::Rename(_) | Self::DisplayOnly(_))
    }

    fn is_blocked(&self) -> bool {
        matches!(self, Self::Blocked(_))
    }

    fn preview(self) -> BatchRenamePreviewItem {
        match self {
            Self::Rename(change) => change.preview(BatchRenamePreviewStatus::Ok, None),
            Self::DisplayOnly(change) => {
                change.preview(BatchRenamePreviewStatus::DisplayOnly, None)
            }
            Self::Unchanged(change) => change.preview(
                BatchRenamePreviewStatus::Unchanged,
                Some("Already matches generated name".to_owned()),
            ),
            Self::Blocked(change) => BatchRenamePreviewItem {
                file_id: change.file_id,
                current_path: change.current_path,
                original_name: change.original_name,
                new_name: change.new_name,
                target_path: change.target_path,
                storage_mode: change.storage_mode,
                index_only: false,
                will_rename_file: false,
                status: change.status,
                reason: Some(change.reason),
            },
        }
    }

    pub(super) fn feed_preview_token(&self, hasher: &mut sha2::Sha256) {
        match self {
            Self::Rename(change) => change.feed_preview_token(hasher, "rename"),
            Self::DisplayOnly(change) => change.feed_preview_token(hasher, "display_only"),
            Self::Unchanged(change) => change.feed_preview_token(hasher, "unchanged"),
            Self::Blocked(change) => {
                hasher.update(b"blocked");
                hasher.update(preview_status_token(&change.status));
                hasher.update(change.file_id.to_le_bytes());
                feed_optional(hasher, change.current_path.as_deref());
                feed_optional(hasher, change.original_name.as_deref());
                feed_optional(hasher, change.new_name.as_deref());
                feed_optional(hasher, change.target_path.as_deref());
                if let Some(mode) = &change.storage_mode {
                    hasher.update(storage_mode_token(mode));
                }
                hasher.update(change.reason.as_bytes());
            }
        }
    }
}

impl PlannedRenameChange {
    fn preview(
        self,
        status: BatchRenamePreviewStatus,
        reason: Option<String>,
    ) -> BatchRenamePreviewItem {
        BatchRenamePreviewItem {
            file_id: self.entry.id,
            current_path: Some(self.entry.path),
            original_name: Some(self.entry.current_name),
            new_name: Some(self.new_name),
            target_path: self.final_relative_path,
            storage_mode: Some(self.entry.storage_mode),
            index_only: self.index_only,
            will_rename_file: self.will_rename_file,
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
        hasher.update(self.new_name.as_bytes());
        feed_optional(hasher, self.final_relative_path.as_deref());
        hasher.update(if self.index_only { b"\x01" } else { b"\x00" });
        hasher.update(if self.will_rename_file {
            b"\x01"
        } else {
            b"\x00"
        });
    }
}

fn storage_mode_token(mode: &StorageMode) -> &'static [u8] {
    match mode {
        StorageMode::Moved => b"moved",
        StorageMode::Copied => b"copied",
        StorageMode::Indexed => b"indexed",
    }
}

fn preview_status_token(status: &BatchRenamePreviewStatus) -> &'static [u8] {
    match status {
        BatchRenamePreviewStatus::Ok => b"ok",
        BatchRenamePreviewStatus::Error => b"error",
        BatchRenamePreviewStatus::NameConflict => b"name_conflict",
        BatchRenamePreviewStatus::Missing => b"missing",
        BatchRenamePreviewStatus::ReadOnly => b"read_only",
        BatchRenamePreviewStatus::DisplayOnly => b"display_only",
        BatchRenamePreviewStatus::Unchanged => b"unchanged",
        BatchRenamePreviewStatus::ExternalChange => b"external_change",
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

fn count_items(
    items: &[BatchRenamePlanItem],
    predicate: impl Fn(&BatchRenamePlanItem) -> bool,
) -> i64 {
    items.iter().filter(|item| predicate(item)).count() as i64
}
