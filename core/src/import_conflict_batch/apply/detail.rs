use std::{fs, path::Path};

use serde_json::{json, Value};

use crate::{CoreResult, FileEntry};

use crate::import_conflict_batch::{
    conflict_type_detail, path, storage_mode_detail, strategy_detail, PlannedImportConflict,
};

pub(super) fn strategy_detail_for_item(item: &PlannedImportConflict) -> &'static str {
    strategy_detail(&item.strategy)
}

pub(super) fn import_detail(
    item: &PlannedImportConflict,
    staging: &FileEntry,
    final_path: &str,
    decision: &str,
    existing: Option<&FileEntry>,
) -> Value {
    json!({
        "source": staging.source_path.clone().unwrap_or_else(|| item.row.incoming_path.clone()),
        "mode": storage_mode_detail(&staging.storage_mode),
        "category": staging.category,
        "destination": "import_conflict_batch",
        "requested_name": staging.current_name,
        "final_name": item.final_name.clone().unwrap_or_else(|| staging.current_name.clone()),
        "final_path": final_path,
        "name_conflict_resolved": item.row.target_path != final_path,
        "duplicate_strategy": decision,
        "conflict_id": item.row.conflict_id,
        "conflict_type": conflict_type_detail(&item.row.conflict_type),
        "replaced_file_id": existing.map(|entry| entry.id),
        "replaced_path": existing.map(|entry| entry.path.clone()),
        "by": "user",
    })
}

pub(super) fn deleted_detail(existing: &FileEntry, archived_path: &str) -> Value {
    json!({
        "hard": false,
        "by": "user",
        "reason": "import_conflict_batch_replace",
        "from_path": existing.path,
        "archived_path": archived_path,
        "trash_location": "recovery",
        "trashed": true,
        "storage_mode": storage_mode_detail(&existing.storage_mode),
        "safe_replace": true,
    })
}

pub(super) fn ensure_parent_dir(path: &Path) -> CoreResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(path::map_io_error)?;
    }
    Ok(())
}
