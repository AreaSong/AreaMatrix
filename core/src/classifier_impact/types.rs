use serde::{Deserialize, Serialize};

use crate::ClassifierRule;

/// Impact preview mode requested by S2-18.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ClassifierImpactPreviewMode {
    /// Preview adding or editing one classifier rule draft.
    RuleDraft,
    /// Preview removing one keyword from an existing category.
    RemoveKeyword,
    /// Preview removing one extension from an existing category.
    RemoveExtension,
    /// Preview removing an existing category from classifier configuration.
    RemoveCategory,
}

/// Input for the C2-14 classifier impact preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClassifierImpactPreviewRequest {
    /// Preview scenario to evaluate.
    pub mode: ClassifierImpactPreviewMode,
    /// Rule-shaped target and basis payload for the preview.
    pub rule: ClassifierRule,
    /// Whether S2-18 should dry-run repo-owned file moves for changed rows.
    pub move_files: bool,
    /// Replacement category used only when previewing category deletion.
    pub replacement_category: Option<String>,
}

/// Why an existing file is included in a classifier rule impact preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RuleImpactMatchReason {
    /// File name or path metadata matched a keyword rule basis.
    Keyword,
    /// File extension matched an extension rule basis.
    Extension,
    /// File is affected because its category itself is being removed.
    Category,
}

/// Per-file status returned in a classifier rule impact preview sample.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RuleImpactStatus {
    /// Applying the rule would update the file category metadata.
    WillUpdate,
    /// The file already has the target category.
    AlreadyCorrect,
    /// The file requires user review before any bulk apply can proceed.
    NeedsReview,
    /// The preview found a conflict that blocks direct bulk apply.
    Conflict,
    /// The indexed file row no longer has a visible backing file.
    Missing,
    /// The file is index-only and must not be physically moved by this capability.
    IndexOnly,
}

/// Conflict class surfaced by a classifier rule impact preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RuleImpactConflictKind {
    /// A future move would collide with an existing target path.
    NameConflict,
    /// The indexed backing file is missing.
    MissingFile,
    /// The file cannot be moved or applied without review because of storage mode.
    UnsupportedStorage,
    /// Existing classifier state makes the proposed rule ambiguous.
    RuleConflict,
}

/// One file row shown in the S2-18 impact preview table.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RuleImpactSample {
    /// Stable file id for table selection and follow-up apply planning.
    pub file_id: i64,
    /// Current repository-relative or indexed path.
    pub path: String,
    /// Current category before the draft rule is applied.
    pub current_category: String,
    /// Category that the draft rule would assign.
    pub new_category: String,
    /// Matched rule basis values collapsed to stable reason classes.
    pub match_reasons: Vec<RuleImpactMatchReason>,
    /// Table status consumed by S2-18.
    pub status: RuleImpactStatus,
    /// Optional human-readable blocked or review reason.
    pub reason: Option<String>,
}

/// One conflict found while previewing a classifier rule draft.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RuleImpactConflict {
    /// File id that produced the conflict.
    pub file_id: i64,
    /// Current path when metadata can provide it.
    pub path: Option<String>,
    /// Optional conflicting target path for move-aware consumers.
    pub conflicting_path: Option<String>,
    /// Stable conflict class.
    pub kind: RuleImpactConflictKind,
    /// User-visible explanation for disabling direct bulk apply.
    pub reason: String,
}

/// Read-only classifier rule impact preview returned to S2-18.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RuleImpactReport {
    /// Full request used for the preview.
    pub request: ClassifierImpactPreviewRequest,
    /// Existing files matched by the draft rule or delete preview.
    pub affected_file_count: i64,
    /// Matched files whose category would change.
    pub will_update_count: i64,
    /// Matched files that already have the target category.
    pub already_correct_count: i64,
    /// Matched files requiring explicit review.
    pub needs_review_count: i64,
    /// Conflicts that block direct bulk apply.
    pub conflict_count: i64,
    /// Maximum number of sample rows included in this response.
    pub sample_limit: i64,
    /// Representative rows for the impact preview table.
    pub samples: Vec<RuleImpactSample>,
    /// Structured conflicts for disabled reasons and accessibility copy.
    pub conflicts: Vec<RuleImpactConflict>,
    /// True when any matched file requires review before apply.
    pub needs_review: bool,
    /// True when the affected count crosses the broad-impact warning threshold.
    pub warning_required: bool,
    /// Optional warning text for over-broad rules.
    pub warning: Option<String>,
    /// Whether a later apply task may proceed without additional user review.
    pub can_apply: bool,
    /// Stable disabled reason when `can_apply` is false.
    pub apply_blocked_reason: Option<String>,
}
