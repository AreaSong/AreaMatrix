//! Public FFI AI fallback entry points.

use crate::{ai_fallback, AiFallbackStatus, AiFallbackStatusRequest, CoreResult};

/// Normalizes AI fallback metadata into a display-ready status.
///
/// AI fallback surface uses this contract after AI classification or semantic search returns
/// skipped, unavailable, or failed metadata. The request carries only stable
/// operation, provider-error, privacy-decision, and traceability fields. It
/// must not include raw provider output, prompts, file contents, API keys, or
/// absolute user paths. Returned actions are semantic commands; the host page
/// remains responsible for rendering concrete labels such as `Classify
/// manually` or `Use normal search`.
///
/// This contract does not execute AI calls, switch providers, enable remote AI,
/// evaluate privacy rules, write user files, or mutate AI results. The AI fallback
/// implementation records one sanitized AI call log row when the caller did
/// not already provide a `call_log_id`, keeping sent fields empty and result
/// summary display-safe.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, missing
/// fallback reason metadata, unsafe provider-error codes, unsafe privacy rule
/// ids, invalid call-log ids, invalid retry timestamps, or missing initialized
/// repository metadata. Returns `CoreError::PermissionDenied { path }` when
/// fallback metadata cannot be inspected and `CoreError::Internal { message }`
/// when call-log persistence or status resolution fails after sanitization.
pub fn get_ai_fallback_status(
    repo_path: String,
    request: AiFallbackStatusRequest,
) -> CoreResult<AiFallbackStatus> {
    ai_fallback::get_ai_fallback_status(repo_path, request)
}
