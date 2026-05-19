use sha2::{Digest, Sha256};

use crate::StorageMode;

use super::{
    conflict_type_detail, storage_mode_detail, strategy_detail, ImportConflictBatchPreviewStatus,
    PlannedImportConflict,
};

pub(super) fn preview_token_for(
    import_session_id: &str,
    requested_ids: &[String],
    plan: &[PlannedImportConflict],
) -> String {
    let mut hasher = Sha256::new();
    feed(&mut hasher, import_session_id);
    for conflict_id in requested_ids {
        feed(&mut hasher, conflict_id);
    }
    if let Some(item) = plan.first() {
        feed_bool(&mut hasher, item.trash_available);
    }
    for item in plan {
        feed(&mut hasher, &item.row.conflict_id);
        feed(&mut hasher, conflict_type_detail(&item.row.conflict_type));
        feed(&mut hasher, strategy_detail(&item.strategy));
        feed(&mut hasher, preview_status_token(&item.status));
        feed_bool(&mut hasher, item.included);
        feed_i64(&mut hasher, item.row.staging_file_id);
        feed_optional_i64(&mut hasher, item.row.existing_file_id);
        if let Some(staging) = item.staging.as_ref() {
            feed_bool(&mut hasher, true);
            feed(&mut hasher, &staging.path);
            feed(&mut hasher, &staging.hash_sha256);
            feed_i64(&mut hasher, staging.updated_at);
            feed_storage_mode(&mut hasher, &staging.storage_mode);
        } else {
            feed_bool(&mut hasher, false);
        }
        feed_optional(
            &mut hasher,
            item.existing.as_ref().map(|entry| entry.path.as_str()),
        );
        feed_optional(
            &mut hasher,
            item.existing
                .as_ref()
                .map(|entry| entry.hash_sha256.as_str()),
        );
        feed_optional_i64(
            &mut hasher,
            item.existing.as_ref().map(|entry| entry.updated_at),
        );
        feed_optional(&mut hasher, item.final_relative_path.as_deref());
        feed_optional(&mut hasher, item.reason.as_deref());
    }
    format!("preview:import-conflict:{:x}", hasher.finalize())
}

fn preview_status_token(status: &ImportConflictBatchPreviewStatus) -> &'static str {
    match status {
        ImportConflictBatchPreviewStatus::Ready => "ready",
        ImportConflictBatchPreviewStatus::Pending => "pending",
        ImportConflictBatchPreviewStatus::NeedsConfirmation => "needs_confirmation",
        ImportConflictBatchPreviewStatus::Blocked => "blocked",
        ImportConflictBatchPreviewStatus::Failed => "failed",
    }
}

fn feed(hasher: &mut Sha256, value: &str) {
    hasher.update(value.as_bytes());
    hasher.update(b"\0");
}

fn feed_bool(hasher: &mut Sha256, value: bool) {
    hasher.update([u8::from(value)]);
}

fn feed_i64(hasher: &mut Sha256, value: i64) {
    hasher.update(value.to_le_bytes());
}

fn feed_optional_i64(hasher: &mut Sha256, value: Option<i64>) {
    match value {
        Some(value) => {
            hasher.update(b"\x01");
            feed_i64(hasher, value);
        }
        None => hasher.update(b"\x00"),
    }
}

fn feed_optional(hasher: &mut Sha256, value: Option<&str>) {
    match value {
        Some(value) => {
            hasher.update(b"\x01");
            feed(hasher, value);
        }
        None => hasher.update(b"\x00"),
    }
}

fn feed_storage_mode(hasher: &mut Sha256, mode: &StorageMode) {
    feed(hasher, storage_mode_detail(mode));
}
