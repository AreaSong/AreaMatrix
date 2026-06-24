use serde_json::{json, Value};

use crate::{FileEntry, MoveToCategoryPreview, StorageMode};

use super::paths::storage_mode_detail;

pub(super) fn preview_for_entry(
    entry: &FileEntry,
    new_category: &str,
    target_path: &str,
    target_name: &str,
    index_only: bool,
    will_move_file: bool,
) -> MoveToCategoryPreview {
    MoveToCategoryPreview {
        file_id: entry.id,
        from_category: entry.category.clone(),
        to_category: new_category.to_owned(),
        current_path: entry.path.clone(),
        target_path: target_path.to_owned(),
        target_name: target_name.to_owned(),
        storage_mode: entry.storage_mode.clone(),
        index_only,
        name_conflict_resolved: target_name != entry.current_name,
        will_move_file,
    }
}

pub(super) fn move_detail(
    entry: &FileEntry,
    new_category: &str,
    final_path: &str,
    final_name: &str,
    index_only: bool,
) -> Value {
    let mut detail = json!({
        "from_category": entry.category,
        "to_category": new_category,
        "from_path": entry.path,
        "to_path": final_path,
        "final_name": final_name,
        "name_conflict_resolved": final_name != entry.current_name,
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "index_only": index_only,
        "by": "user",
    });

    if final_name != entry.current_name {
        detail["renamed_to"] = json!(final_name);
    }
    detail
}

pub(super) fn is_indexed(mode: &StorageMode) -> bool {
    *mode == StorageMode::Indexed
}
