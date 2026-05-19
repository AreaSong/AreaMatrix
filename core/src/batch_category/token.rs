use sha2::{Digest, Sha256};

use super::plan::BatchCategoryPlanItem;

pub(super) fn preview_token(
    file_ids: &[i64],
    target_category: &str,
    move_repo_owned_files: bool,
    items: &[BatchCategoryPlanItem],
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"area-matrix:c2-08:preview:v1");
    hasher.update(target_category.as_bytes());
    hasher.update(if move_repo_owned_files {
        b"\x01"
    } else {
        b"\x00"
    });
    for file_id in file_ids {
        hasher.update(file_id.to_le_bytes());
    }
    for item in items {
        item.feed_preview_token(&mut hasher);
    }
    format!("preview:batch-category:{:x}", hasher.finalize())
}
