use sha2::{Digest, Sha256};

use crate::BatchDeleteMode;

use super::plan::BatchDeletePlanItem;

pub(super) fn preview_token(
    file_ids: &[i64],
    delete_mode: &BatchDeleteMode,
    trash_available: bool,
    items: &[BatchDeletePlanItem],
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"area-matrix:c2-09:preview:v1");
    hasher.update(delete_mode_token(delete_mode));
    hasher.update(if trash_available { b"\x01" } else { b"\x00" });
    for file_id in file_ids {
        hasher.update(file_id.to_le_bytes());
    }
    for item in items {
        item.feed_preview_token(&mut hasher);
    }
    format!("preview:batch-delete:{:x}", hasher.finalize())
}

fn delete_mode_token(mode: &BatchDeleteMode) -> &'static [u8] {
    match mode {
        BatchDeleteMode::MoveToTrash => b"move_to_trash",
        BatchDeleteMode::RemoveFromIndex => b"remove_from_index",
    }
}
