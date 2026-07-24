//! Public FFI classifier entry points.

use crate::{
    classifier_correction, classifier_impact, classifier_rule_editor, classifier_rules,
    ClassifierCorrectionResult, ClassifierImpactPreviewRequest, ClassifierRule,
    ClassifierRuleCreateRequest, ClassifierRuleDeleteRequest, ClassifierRuleEditorSnapshot,
    ClassifierRuleUpdate, ContentLocale, CoreResult, RuleImpactReport,
};

/// Applies one classifier correction for classifier correction surface.
///
/// The correction changes one active file's category and optionally moves a
/// repo-managed file when `move_file` is true. `remember` only asks Core to
/// return a rule draft handoff for classifier save-rule surface/classifier impact preview surface; this entry point must not save
/// classifier rules, preview broad rule impact, create categories, call AI or
/// network providers, or implement adjacent classifier rule save/classifier impact preview/classifier rule editor behavior.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` when the target category is invalid
/// or unavailable, `CoreError::Conflict { path }` when a safe target path
/// cannot be resolved, `CoreError::Io { message }` for file moves, and
/// `CoreError::Db { message }` for metadata or change-log failures.
pub fn correct_file_category(
    repo_path: String,
    file_id: i64,
    category: String,
    move_file: bool,
    remember: bool,
) -> CoreResult<ClassifierCorrectionResult> {
    classifier_correction::correct_file_category(repo_path, file_id, category, move_file, remember)
}

/// Saves one classifier rule for future classification.
///
/// classifier save-rule surface uses this contract after the user chooses keyword and extension
/// basis values from a classifier-correction draft. The input rule maps only to
/// supported classifier configuration fields: target category, independent
/// keyword matches, independent extension matches, priority, and whether the
/// required impact preview has already been confirmed. Extensions must be
/// lowercase values without a leading dot.
///
/// This contract does not create categories, model compound AND rules, preview
/// impact, apply the rule to historical files, reclassify or move files, call
/// AI/network providers, or touch `apps/**`. Successful saves atomically update
/// the repository classifier configuration for future classification only.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, target
/// categories, empty rule basis, duplicate/invalid keywords, dotted or invalid
/// extensions, out-of-range priority, malformed classifier configuration, or a
/// duplicate/over-broad rule that still lacks preview confirmation. Returns
/// `CoreError::PermissionDenied { path }` for blocked metadata writes and
/// `CoreError::Io { message }` for classifier configuration read or atomic
/// write failures.
pub fn save_classifier_rule(repo_path: String, rule: ClassifierRule) -> CoreResult<ClassifierRule> {
    classifier_rules::save_classifier_rule(repo_path, rule)
}

/// Previews classifier rule impact for classifier impact preview surface.
///
/// The contract accepts one explicit preview request and returns counts, sample
/// rows, conflicts, needs-review state, broad-impact warning state, and direct
/// apply availability. It is read-only: it may inspect classifier config and
/// file metadata, but it must not save the rule, apply it to existing files,
/// move files, write undo/change-log state, or implement classifier rule editor rule editing.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths,
/// invalid classifier rule drafts, invalid delete requests, or invalid
/// replacement categories. Returns `CoreError::Db { message }` when classifier
/// impact metadata cannot be read.
pub fn preview_classifier_rule_impact(
    repo_path: String,
    request: ClassifierImpactPreviewRequest,
) -> CoreResult<RuleImpactReport> {
    classifier_impact::preview_classifier_rule_impact(repo_path, request)
}

/// Lists classifier rule editor state for classifier rule editor surface.
///
/// classifier rule editor surface uses this contract to load current classifier categories, matcher
/// values, priority, naming template, and default-category state. The returned
/// snapshot is sufficient for loading, empty, dirty, validation, save/revert,
/// and delete-disabled UI states without reading YAML in the app layer.
///
/// This contract does not preview rule impact, save rules, delete categories,
/// reclassify or move existing files, open YAML, call AI/network providers, or
/// touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths or
/// malformed classifier configuration, `CoreError::PermissionDenied { path }`
/// for blocked classifier metadata reads, and `CoreError::Io { message }` for
/// classifier config read failures.
pub fn list_classifier_rules(
    repo_path: String,
    editing_locale: Option<ContentLocale>,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::list_classifier_rules(repo_path, editing_locale)
}

/// Creates the default classifier only when the managed file is missing.
///
/// # Errors
///
/// Returns `CoreError::Config` when confirmation is absent or the current
/// health does not authorize creation. File permission and durable-write
/// failures are returned without touching user files or database records.
pub fn create_default_classifier(
    repo_path: String,
    confirmed: bool,
    editing_locale: Option<ContentLocale>,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::create_default_classifier(repo_path, confirmed, editing_locale)
}

/// Restores the default classifier over readable invalid managed bytes.
///
/// # Errors
///
/// Returns `CoreError::Config` when confirmation is absent or the current
/// health does not authorize restore. The original bytes are archived before
/// replacement; permission, backup, and durable-write failures are propagated.
pub fn restore_default_classifier(
    repo_path: String,
    confirmed: bool,
    editing_locale: Option<ContentLocale>,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::restore_default_classifier(repo_path, confirmed, editing_locale)
}

/// Restores the newest verified valid classifier backup.
///
/// # Errors
///
/// Returns `CoreError::Config` when confirmation is absent, current health is
/// not invalid, or no verified backup exists. Permission, backup, and durable
/// write failures are propagated without touching user files.
pub fn restore_last_valid_classifier(
    repo_path: String,
    confirmed: bool,
    editing_locale: Option<ContentLocale>,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::restore_last_valid_classifier(repo_path, confirmed, editing_locale)
}

/// Creates one classifier rule editor row for future classification.
///
/// The create request carries a new slug, display metadata, extensions,
/// keywords, priority, and naming template. A successful implementation may
/// atomically update `.areamatrix/classifier.yaml` or equivalent classifier
/// metadata only. It must not move, delete, rename, reindex, retag, write
/// notes, update generated overviews, write undo state, or apply classifier
/// changes to historical files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid row content, duplicate
/// slugs or matcher values, or malformed classifier configuration. Returns
/// `CoreError::PermissionDenied { path }` for blocked classifier metadata
/// writes and `CoreError::Io { message }` for read, backup, atomic write, or
/// restore failures.
pub fn create_classifier_rule(
    repo_path: String,
    request: ClassifierRuleCreateRequest,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::create_classifier_rule(repo_path, request)
}

/// Updates one classifier rule editor row for future classification.
///
/// The update request carries one stable `rule_id` plus replacement slug,
/// display metadata, extensions, keywords, priority, and naming template. A
/// successful implementation may atomically update `.areamatrix/classifier.yaml`
/// or equivalent classifier metadata only. It must not move, delete, rename,
/// reindex, retag, write notes, update generated overviews, write undo state,
/// or apply classifier changes to historical files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid ids, row content,
/// duplicate slugs or matcher values, missing impact preview confirmation, or
/// malformed classifier configuration. Returns `CoreError::PermissionDenied {
/// path }` for blocked classifier metadata writes and `CoreError::Io {
/// message }` for read, backup, atomic write, or restore failures.
pub fn update_classifier_rule(
    repo_path: String,
    request: ClassifierRuleUpdate,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::update_classifier_rule(repo_path, request)
}

/// Deletes one classifier rule editor row after explicit impact confirmation.
///
/// Delete removes only classifier configuration state. It must reject deletion
/// of the default category, the final category, and unpreviewed category/value
/// removals. Existing files are not moved, deleted, renamed, trashed, or
/// reclassified by this contract.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid ids, protected category
/// deletion, missing replacement state, missing impact preview confirmation, or
/// malformed classifier configuration. Returns `CoreError::PermissionDenied {
/// path }` for blocked classifier metadata writes and `CoreError::Io {
/// message }` for read, backup, atomic write, or restore failures.
pub fn delete_classifier_rule(
    repo_path: String,
    request: ClassifierRuleDeleteRequest,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::delete_classifier_rule(repo_path, request)
}
