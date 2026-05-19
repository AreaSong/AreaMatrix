//! C2-19 tag suggestion contract types.

use serde::{Deserialize, Serialize};

use super::TagSet;

/// Source that produced one deterministic C2-19 tag suggestion.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum TagSuggestionSource {
    /// The suggestion came from the current file name.
    FileName,
    /// The suggestion came from the repository-relative path.
    Path,
    /// The suggestion came from the imported source directory.
    SourceFolder,
    /// The suggestion reused or mirrored an existing tag pattern.
    ExistingTagPattern,
}

/// Deterministic match strength for one C2-19 tag suggestion.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum TagSuggestionMatch {
    /// Exact normalized token match and safe to preselect.
    Strong,
    /// Partial or inferred deterministic match that needs explicit selection.
    Weak,
}

/// Current write/readiness state for one C2-19 suggestion row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum TagSuggestionStatus {
    /// The suggested tag can be applied.
    NewTag,
    /// The target file already has this tag.
    AlreadyAdded,
    /// The suggested or edited tag is invalid.
    Invalid,
    /// The suggestion is blocked by read-only metadata or another preflight issue.
    Blocked,
}

/// Optional context used when generating deterministic C2-19 suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionContext {
    /// Optional source directory captured by import flows.
    pub source_folder: Option<String>,
    /// Optional importer-provided keywords that already passed privacy review.
    pub source_keywords: Vec<String>,
}

/// Request for deterministic C2-19 tag suggestions for one active file.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionRequest {
    /// Active file whose metadata should be inspected.
    pub file_id: i64,
    /// Optional source context from import-result consumers.
    pub context: Option<TagSuggestionContext>,
    /// Maximum number of suggestions to return after normalization and dedupe.
    pub limit: i64,
}

/// One C2-19 tag suggestion row consumed by S2-23.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestion {
    /// Stable client key for checkbox/edit state.
    pub suggestion_id: String,
    /// Normalized tag slug to create or reuse.
    pub slug: String,
    /// Display label shown in the suggestion row.
    pub display_name: String,
    /// Human-readable explanation for the suggestion.
    pub reason: String,
    /// Source metadata bucket used for deterministic generation.
    pub source: TagSuggestionSource,
    /// Strong suggestions can be preselected; weak suggestions require user choice.
    pub match_strength: TagSuggestionMatch,
    /// Whether an equivalent tag already exists in the repository registry.
    pub already_exists: bool,
    /// Whether applying this row would create a new tag registry entry.
    pub needs_create: bool,
    /// Row state for disabled/error UI.
    pub status: TagSuggestionStatus,
    /// Whether S2-23 may preselect this suggestion by default.
    pub selected_by_default: bool,
    /// Optional user-facing blocked or validation reason.
    pub disabled_reason: Option<String>,
}

/// Result returned when S2-23 asks Core for C2-19 suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionReport {
    /// File whose metadata was inspected.
    pub file_id: i64,
    /// Deterministic suggestions in display order.
    pub suggestions: Vec<TagSuggestion>,
    /// Current tag state, so S2-23 can show already-added rows and avoid duplicate writes.
    pub tag_set: TagSet,
    /// Privacy boundary shown by S2-23: no file content read.
    pub contents_read: bool,
    /// Privacy boundary shown by S2-23: no AI or remote provider called.
    pub ai_used: bool,
    /// Privacy boundary shown by S2-23: no network access.
    pub network_used: bool,
}

/// One selected or edited suggestion submitted for C2-19 apply.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ApplyTagSuggestionItem {
    /// Suggestion identifier returned by `suggest_tags_for_file`.
    pub suggestion_id: String,
    /// Final normalized tag slug after optional editing.
    pub slug: String,
    /// Final display name after optional editing.
    pub display_name: String,
}

/// Request for applying selected C2-19 tag suggestions to one file.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ApplyTagSuggestionsRequest {
    /// Active file that receives the selected tags.
    pub file_id: i64,
    /// Selected or edited suggestions to apply in stable order.
    pub suggestions: Vec<ApplyTagSuggestionItem>,
}

/// Status for one C2-19 apply result row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum TagSuggestionApplyStatus {
    /// The tag relation was newly applied.
    Applied,
    /// The file already had the tag relation.
    AlreadyAdded,
    /// The suggestion failed validation or persistence.
    Failed,
}

/// One C2-19 apply result row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionApplyItemResult {
    /// Suggestion identifier from the apply request.
    pub suggestion_id: String,
    /// Final normalized tag slug attempted.
    pub slug: String,
    /// Per-row result status.
    pub status: TagSuggestionApplyStatus,
    /// Optional failure or skip detail for S2-23 recovery UI.
    pub error: Option<String>,
}

/// Report returned after applying C2-19 selected tag suggestions.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct TagSuggestionApplyReport {
    /// File whose tags were mutated.
    pub file_id: i64,
    /// Number of selected suggestions accepted by the contract.
    pub requested_count: i64,
    /// Number of newly applied tag relations.
    pub applied_count: i64,
    /// Number of already-present relations skipped without duplicate writes.
    pub skipped_count: i64,
    /// Number of failed suggestion rows.
    pub failed_count: i64,
    /// Detailed per-suggestion results for partial failure UI.
    pub item_results: Vec<TagSuggestionApplyItemResult>,
    /// Refreshed tag state after the apply attempt.
    pub tag_set: TagSet,
    /// Undo token for C2-07 toast/history when at least one relation was newly added.
    pub undo_token: Option<String>,
    /// Stable refresh hints for S2-23 and host detail/import-result surfaces.
    pub refresh_targets: Vec<String>,
}
