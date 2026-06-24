mod json;
mod queries;
mod resolve;
mod rollback;
mod schema;
mod status;
mod types;
mod undo;

pub(crate) use queries::{
    get_import_session_status, get_staging_file_snapshot, list_import_conflicts_for_session,
};
pub(crate) use resolve::{
    mark_import_conflict_failed, queue_import_conflict_for_per_item, resolve_import_conflict_item,
};
pub(crate) use rollback::{
    rollback_import_conflict_decision, rollback_import_conflict_keep_both,
    rollback_import_conflict_replace,
};
pub(crate) use schema::ensure_import_conflict_schema;
pub(crate) use types::{
    ImportConflictApplyItem, ImportConflictKind, ImportConflictReplacement, ImportConflictRow,
    ImportConflictStatus,
};
pub(crate) use undo::{insert_import_conflict_undo_action, preflight_import_conflict_undo_action};
