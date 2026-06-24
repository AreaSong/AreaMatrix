//! Public FFI AI audit entry points.

use crate::{
    ai_call_log, AiCallLogClearReport, AiCallLogClearRequest, AiCallLogFilter, AiCallLogPage,
    AiCallLogPagination, CoreResult,
};

/// Lists redacted AI call log rows for AI call log surface.
///
/// The contract exposes only audit metadata: feature, local/remote route,
/// provider/model display names, status, duration, sent field categories,
/// privacy rule snapshots, error codes, and sanitized result summaries. It must
/// never return API keys, key fragments, full file contents, full prompts, full
/// model outputs, full notes, provider raw responses, Keychain reference
/// values, or absolute user paths.
///
/// Listing is read-only. It must not execute AI calls, clear logs, export files,
/// reveal files, mutate AI settings, edit privacy rules, or touch user files.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` for invalid filter/pagination shape or
/// AI call log metadata query failures, and `CoreError::PermissionDenied {
/// path }` when repository metadata cannot be inspected.
pub fn list_ai_calls(
    repo_path: String,
    filter: AiCallLogFilter,
    pagination: AiCallLogPagination,
) -> CoreResult<AiCallLogPage> {
    ai_call_log::list_ai_calls(repo_path, filter, pagination)
}

/// Clears local AI call log rows without deleting user data.
///
/// This contract deletes only `ai_call_log` audit rows in the requested scope.
/// It must not delete, move, rename, trash, overwrite, or reclassify user
/// files, and it must not remove AI settings, provider metadata, Keychain
/// credentials, summaries, tags, notes, classifier rules, generated overviews,
/// change log, undo/redo state, or any AI results.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` for invalid clear scope, selected ids,
/// retention cutoff, or SQLite write failures. Returns
/// `CoreError::PermissionDenied { path }` when repository metadata is not
/// writable.
pub fn clear_ai_call_log(
    repo_path: String,
    request: AiCallLogClearRequest,
) -> CoreResult<AiCallLogClearReport> {
    ai_call_log::clear_ai_call_log(repo_path, request)
}
