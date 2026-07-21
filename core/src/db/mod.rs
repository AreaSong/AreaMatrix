//! SQLite helpers for repository metadata.

mod ai_call_log;
mod ai_privacy_rules;
mod ai_settings;
mod ai_summary;
mod change_log;
mod codec;
mod command_index;
mod connection;
mod delete;
mod icloud_conflicts;
mod import;
mod import_conflicts;
mod local_model_status;
mod missing_file_recovery;
mod move_to_category;
mod note;
mod overview;
mod platform_watcher_status;
mod read_models;
mod redo;
mod remote_provider_config;
mod rename;
mod repo_config;
mod saved_search;
mod scan;
mod schema;
mod staging_recovery;
mod sync;
mod sync_conflicts;
mod tags;
mod undo;
pub(crate) use ai_call_log::{
    clear_ai_call_log_rows, ensure_ai_call_log_record_insertable, insert_ai_call_log_record,
    insert_ai_call_log_record_in_tx, list_ai_call_log_rows, AiCallLogClearSpec,
    AiCallLogInsertRecord, AiCallLogListFilter, AiCallLogPagination, AiCallLogRow,
};
pub(crate) use ai_privacy_rules::{load_ai_privacy_rules_record, update_ai_privacy_rules_record};
pub(crate) use ai_settings::{load_ai_config_record, update_ai_config_record};
pub(crate) use ai_summary::{
    clear_ai_summary_metadata, load_ai_summary_metadata, upsert_ai_summary_metadata,
    AiSummaryUpsert,
};
pub(crate) use change_log::list_changes;
pub(crate) use codec::{
    bool_from_db, bool_to_db, origin_from_db, overview_output_from_db, overview_output_to_db,
    storage_mode_from_db, storage_mode_to_db,
};
pub(crate) use command_index::{
    count_active_command_selection_files, list_command_file_candidate_rows,
    list_recent_command_rows,
};
pub(crate) use connection::{
    configure_connection, db_path, ensure_initialized, ensure_initialized_readable,
    open_repo_connection, open_repo_read_connection, path_exists, AREA_MATRIX_DIR,
};
pub(crate) use delete::{
    insert_batch_delete_undo_action, purge_expired_soft_deleted_files,
    remove_batch_delete_index_entry_row, remove_index_entry_row, rollback_deleted_repo_owned_file,
    rollback_removed_index_entry_row, soft_delete_batch_repo_owned_file,
    soft_delete_repo_owned_file, BatchDeleteUndoItem,
};
pub(crate) use icloud_conflicts::{
    list_icloud_conflict_statuses, record_icloud_conflict_resolution,
};
pub(crate) use import::{
    delete_file_row, file_entry_from_row, find_active_file_by_hash, find_active_file_by_path,
    get_active_file_by_id, insert_active_indexed_import, insert_import_staging,
    insert_replacing_active_indexed_import, promote_imported_file, promote_replacing_imported_file,
    rollback_replacing_imported_file, NewImportRow, ReplacementImportRow,
};
pub(crate) use import_conflicts::{
    ensure_import_conflict_schema, get_import_session_status, get_staging_file_snapshot,
    insert_import_conflict_undo_action, list_import_conflicts_for_session,
    mark_import_conflict_failed, preflight_import_conflict_undo_action,
    queue_import_conflict_for_per_item, resolve_import_conflict_item,
    rollback_import_conflict_decision, rollback_import_conflict_keep_both,
    rollback_import_conflict_replace, ImportConflictApplyItem, ImportConflictKind,
    ImportConflictReplacement, ImportConflictRow, ImportConflictStatus,
};
pub(crate) use local_model_status::update_local_model_status_record;
pub(crate) use missing_file_recovery::{
    load_missing_file_recovery_entry, mark_missing_file_record_removed, relink_missing_file_record,
    MissingFileRecoveryEntry, MissingFileRelinkUpdate,
};
pub(crate) use move_to_category::{
    batch_update_category_metadata_only_in_tx, batch_update_category_repo_owned_in_tx,
    correct_file_category_metadata_only, correct_repo_owned_file_category,
    insert_batch_category_undo_action_in_tx, load_batch_category_active_file,
    move_indexed_file_to_category, move_repo_owned_file_to_category,
    with_batch_category_transaction, BatchCategoryUndoItem,
};
pub(crate) use note::{read_note_content, upsert_note_and_log};
pub(crate) use overview::{
    list_overview_node_files, list_overview_node_summaries, list_overview_recent_changes,
    OverviewChangeRow, OverviewFileRow, OverviewNodeSummary,
};
pub(crate) use platform_watcher_status::upsert_platform_watcher_health;
pub(crate) use read_models::{list_files, with_availability_status};
pub(crate) use redo::clear_redo_stack_in_tx;
pub(crate) use remote_provider_config::{
    delete_remote_provider_test_record, load_remote_provider_config_record,
    load_remote_provider_test_record, save_remote_provider_test_record,
    update_remote_provider_config_record,
};
pub(crate) use rename::{
    batch_update_rename_indexed_in_tx, batch_update_rename_repo_owned_in_tx,
    insert_batch_rename_undo_action_in_tx, load_batch_rename_active_file, rename_active_file,
    rename_indexed_display_name, rollback_renamed_active_file, with_batch_rename_transaction,
    BatchRenameUndoItem,
};
pub(crate) use repo_config::{
    ensure_config_storage_writable, initialize_repository_db, load_config_or_default,
    load_repo_config_record, map_update_open_error, update_config, upsert_repo_config_record,
    with_write_transaction,
};
pub(crate) use saved_search::{
    create_saved_search_row, delete_saved_search_row, get_saved_search_row, list_saved_search_rows,
    update_saved_search_row,
};
pub(crate) use scan::*;
pub(crate) use schema::INITIAL_SCHEMA;
pub(crate) use staging_recovery::{
    delete_staging_file_row, list_protected_staging_paths, list_staging_file_rows, StagingFileRow,
};
pub(crate) use sync::*;
pub(crate) use sync_conflicts::{
    list_active_sync_conflict_files, load_sync_conflict_state, preflight_sync_conflict_resolution,
    record_sync_conflict_resolution, replace_sync_conflict_state, ActiveSyncConflictFile,
    SyncConflictCanonicalUpdate, SyncConflictResolutionRecord, SyncConflictRetainedFileRecord,
};
pub(crate) use tags::{
    add_tag_row, apply_ai_tag_suggestion_rows, apply_tag_suggestion_rows, batch_add_tags_rows,
    list_tag_set, load_tag_suggestion_snapshot, remove_tag_row, AiTagSuggestionApplyProvenance,
    AiTagSuggestionApplyRow, TagSuggestionApplyRow, TagSuggestionSnapshot,
};
pub(crate) use undo::update_delete_undo_trash_path;
