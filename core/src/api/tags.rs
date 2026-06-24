//! Public FFI tags entry points.

use crate::{
    ApplyTagSuggestionsRequest, CoreResult, TagSuggestionApplyReport, TagSuggestionReport,
    TagSuggestionRequest,
};

/// Suggests deterministic tags for tag suggestions surface without reading file contents.
///
/// The contract inspects only repository metadata, file name, relative path,
/// optional import source context, and existing tag registry state. The output
/// tells tag suggestions surface which suggestions are strong/weak, already added, invalid, or
/// blocked, plus privacy flags proving no AI, network, or content read was
/// used.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when the active file is missing,
/// `CoreError::Validation { reason }` for invalid limits or context,
/// `CoreError::Conflict { path }` when metadata cannot produce a deterministic
/// suggestion set, and `CoreError::Db { message }` when file or tag metadata
/// cannot be read.
pub fn suggest_tags_for_file(
    repo_path: String,
    request: TagSuggestionRequest,
) -> CoreResult<TagSuggestionReport> {
    crate::tags::suggest_tags_for_file(repo_path, request)
}

/// Applies selected or edited deterministic tag suggestions for one active file.
///
/// A successful implementation creates or reuses normalized tags, writes only
/// the selected file/tag relations, records change-log rows, and returns a
/// undo action log token when new relations were added. It must not apply ignored
/// suggestions, alter filters, move/rename/delete files, read file contents, or
/// call AI/network providers.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when the active file is missing,
/// `CoreError::Validation { reason }` for empty or invalid submitted
/// suggestions, `CoreError::Conflict { path }` for duplicate edited rows that
/// cannot be applied deterministically, and `CoreError::Db { message }` when
/// tag metadata, change-log, or undo writes fail.
pub fn apply_tag_suggestions(
    repo_path: String,
    request: ApplyTagSuggestionsRequest,
) -> CoreResult<TagSuggestionApplyReport> {
    crate::tags::apply_tag_suggestions(repo_path, request)
}
