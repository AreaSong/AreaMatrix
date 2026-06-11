use serde_json::{json, Value};

use crate::{ImportDestination, StorageMode};

use super::{ImportDestinationPlan, PreparedImport};

pub(super) fn import_change_detail(
    prepared: &PreparedImport,
    destination: &ImportDestinationPlan,
) -> Value {
    match destination.replacement() {
        Some(replacement) => json!({
            "source": prepared.source.to_string_lossy(),
            "mode": storage_mode_detail(&prepared.options.mode),
            "category": destination.category,
            "destination": destination_detail(&prepared.options.destination),
            "renamed_from_original": prepared.original_name != destination.final_name,
            "requested_name": prepared.target_filename,
            "final_name": destination.final_name,
            "final_path": destination.final_relative_path,
            "name_conflict_resolved": prepared.target_filename != destination.final_name,
            "duplicate_strategy": "overwrite",
            "replace_reason": replacement.reason_detail(),
            "replaced_file_id": replacement.replaced_file_id(),
            "replaced_path": replacement.replaced_path(),
            "by": "user",
        }),
        None => json!({
            "source": prepared.source.to_string_lossy(),
            "mode": storage_mode_detail(&prepared.options.mode),
            "category": destination.category,
            "destination": destination_detail(&prepared.options.destination),
            "renamed_from_original": prepared.original_name != destination.final_name,
            "requested_name": prepared.target_filename,
            "final_name": destination.final_name,
            "final_path": destination.final_relative_path,
            "name_conflict_resolved": prepared.target_filename != destination.final_name,
            "by": "user",
        }),
    }
}

pub(super) fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

pub(super) fn destination_detail(destination: &ImportDestination) -> &'static str {
    match destination {
        ImportDestination::AutoClassify => "auto_classify",
        ImportDestination::SelectedDirectory => "selected_directory",
        ImportDestination::Category => "category",
    }
}
