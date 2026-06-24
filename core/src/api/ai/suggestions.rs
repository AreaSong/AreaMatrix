//! Public FFI AI suggestions entry points.

use crate::{
    ai_classification_suggestion, ai_summary, ai_tags_suggestion, AiCategorySuggestion,
    AiCategorySuggestionRequest, AiSummaryClearReport, AiSummaryClearRequest, AiSummaryDraft,
    AiSummaryGenerationRequest, AiSummarySaveReport, AiSummarySaveRequest,
    AiTagSuggestionApplyReport, AiTagSuggestionReport, AiTagSuggestionRequest,
    ApplyAiTagSuggestionsRequest, CoreResult,
};

/// Requests an AI category suggestion without applying it.
///
/// AI category suggestion surface uses this contract for `Ask AI for suggestion...`, and AI fallback surface uses
/// its structured status and skipped reason for fallback rendering. The
/// request identifies one active file and the maximum context extraction policy
/// the caller allows. Returned suggestions are drafts only: consumers must keep
/// category writes, file moves, rule creation, and rejection feedback in their
/// own explicit confirmation flows.
/// The `requires_user_confirmation` field is part of the stable contract and
/// must stay true for suggested, skipped, unavailable, and no-suggestion states.
///
/// This contract may inspect only file metadata and privacy/settings/provider
/// gate state. It must not overwrite classifier rules, change
/// `files.category`, move files, write user-authored content, leak API keys, or
/// send data to a remote provider unless AI settings, remote provider configuration, and AI privacy rules gates later
/// allow it. The contract shape includes call-log and privacy-rule ids for
/// traceability, but log persistence and privacy-rule CRUD remain owned by
/// AI call log and AI privacy rules.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid request shape or disabled
/// AI configuration, `CoreError::PermissionDenied { path }` when metadata,
/// allowed content, or provider credentials cannot be inspected, and
/// `CoreError::Internal { message }` for unavailable AI runtime or sanitized
/// provider failures.
pub fn suggest_category_with_ai(
    repo_path: String,
    request: AiCategorySuggestionRequest,
) -> CoreResult<AiCategorySuggestion> {
    ai_classification_suggestion::suggest_category_with_ai(repo_path, request)
}

/// Generates an AI summary draft without saving it.
///
/// AI summary editor surface uses this contract for `Generate summary` and confirmed
/// `Regenerate...` flows. The returned [`AiSummaryDraft`] is explicitly a draft
/// until the caller invokes [`save_ai_summary`]. It carries source route,
/// model/provider display state, used field categories, privacy rule id, call
/// log id, and skipped/unavailable reasons so the page can render Draft,
/// generated locally/remotely, skipped-by-privacy, and fallback states without
/// parsing errors.
///
/// This contract must not persist a summary, overwrite notes, write user
/// files, modify tags/categories/searches, enable remote AI, or bypass AI privacy rules
/// privacy rules. Remote generation remains gated by AI settings, remote provider configuration
/// provider scope, AI privacy evaluation, and AI call log availability.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths,
/// request shape, provider scope, privacy reference, or AI gate configuration.
/// Returns `CoreError::FileNotFound { path }` when the file id is missing,
/// `CoreError::PermissionDenied { path }` when metadata, allowed input fields,
/// or provider credentials cannot be inspected, and `CoreError::Db {
/// message }` when summary or call-log metadata cannot be read or written.
pub fn generate_ai_summary(
    repo_path: String,
    request: AiSummaryGenerationRequest,
) -> CoreResult<AiSummaryDraft> {
    ai_summary::generate_ai_summary(repo_path, request)
}

/// Saves an AI summary draft as AreaMatrix-owned metadata.
///
/// AI summary editor surface uses this after the user explicitly clicks `Save`. The request may
/// contain AI-generated or user-edited text, but it remains derived summary
/// metadata: it must not overwrite the original file, user note, extracted
/// text, tags, categories, generated overview, AI call log, or provider state.
/// The returned [`AiSummarySaveReport`] gives the page saved text, provenance,
/// timestamps, edited-by-user state, and character count for badges, source
/// rows, VoiceOver labels, and retry/dirty-state recovery.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, file
/// ids, empty or oversized summary text, unsafe draft ids, or unsafe provenance
/// fields. Returns `CoreError::FileNotFound { path }` when the file id no
/// longer exists, `CoreError::PermissionDenied { path }` when summary metadata
/// cannot be written, and `CoreError::Db { message }` for persistence failures.
pub fn save_ai_summary(
    repo_path: String,
    request: AiSummarySaveRequest,
) -> CoreResult<AiSummarySaveReport> {
    ai_summary::save_ai_summary(repo_path, request)
}

/// Clears AI summary metadata for one file after confirmation.
///
/// This contract backs AI summary editor surface `Clear summary...`. It may clear only the
/// AreaMatrix-owned AI summary value. It must not delete, move, rename, trash,
/// or overwrite the original file, and must not delete user notes, extracted
/// text, tags, AI call logs, provider metadata, privacy rules, change log,
/// undo/redo state, or generated overviews.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, file
/// ids, or missing confirmation. Returns `CoreError::FileNotFound { path }`
/// when the file id no longer exists, `CoreError::PermissionDenied { path }`
/// when summary metadata cannot be written, and `CoreError::Db { message }`
/// for persistence failures.
pub fn clear_ai_summary(
    repo_path: String,
    request: AiSummaryClearRequest,
) -> CoreResult<AiSummaryClearReport> {
    ai_summary::clear_ai_summary(repo_path, request)
}

/// Generates AI tag suggestions without applying them.
///
/// AI tag suggestion surface uses this contract to populate review chips before any tag write.
/// The request identifies one active file, caller-provided candidate tags, and
/// a privacy policy reference. Returned suggestions include confidence,
/// display-safe reasons, merge hints, local/remote route, used context, privacy
/// rule id, and call-log id so the page can render AI off, skipped, empty,
/// low-confidence, merge, and traceability states without parsing provider
/// responses.
///
/// This contract must not create or attach tags, write change log or undo
/// rows, save AI settings, enable remote providers, edit privacy rules, or
/// move, rename, delete, read, upload, or overwrite user files. Remote AI
/// remains gated by AI settings, remote provider scope, AI privacy
/// evaluation, and AI call log availability.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths,
/// candidate tags, privacy references, or AI gate configuration. Returns
/// `CoreError::FileNotFound { path }` when the target file id is invalid or
/// missing, and `CoreError::Db { message }` when tag, file, or AI call-log
/// metadata cannot be read. Returns `CoreError::PermissionDenied { path }` or
/// `CoreError::Io { message }` when repository metadata or allowed local
/// context cannot be inspected.
pub fn suggest_tags_with_ai(
    repo_path: String,
    request: AiTagSuggestionRequest,
) -> CoreResult<AiTagSuggestionReport> {
    ai_tags_suggestion::suggest_tags_with_ai(repo_path, request)
}

/// Applies reviewed AI tag suggestions after explicit confirmation.
///
/// AI tag suggestion surface calls this only for selected or edited suggestions. Rejected or
/// cancelled rows stay in UI state and are not submitted. The implementation
/// may later create or reuse normalized tags, write file/tag relations, record
/// change-log rows, carry AI call provenance, and return an undo token for the
/// tag write. It must never apply unselected suggestions or auto-write tags
/// from generation output.
///
/// This contract does not generate AI suggestions, retry providers, change
/// privacy rules, enable remote AI, or mutate files. It only defines the
/// reviewed tag-apply boundary for AI tag suggestions.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths,
/// missing confirmation, duplicate or invalid suggestion rows, unsafe
/// provenance ids, or invalid tag names. Returns `CoreError::FileNotFound {
/// path }` when the target file id is invalid or missing, and
/// `CoreError::PermissionDenied { path }` when tag metadata cannot be written,
/// and `CoreError::Db { message }` when tag metadata, change log, undo, or AI
/// call-log provenance cannot be persisted.
pub fn apply_ai_tag_suggestions(
    repo_path: String,
    request: ApplyAiTagSuggestionsRequest,
) -> CoreResult<AiTagSuggestionApplyReport> {
    ai_tags_suggestion::apply_ai_tag_suggestions(repo_path, request)
}
