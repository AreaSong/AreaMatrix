//! C2-14 classifier rule impact-preview contract types and boundary.

use std::{io, path::PathBuf};

use serde::{Deserialize, Serialize};

use crate::{ClassifierRule, CoreResult, FileEntry, StorageMode};

mod config;
mod db;
mod matcher;
mod path;

use config::{ensure_target_category_exists, read_classifier_config, validate_impact_request};
use matcher::match_reasons;
use path::{relative_repo_path, repo_relative_file_path};

const SAMPLE_LIMIT: usize = 50;
const BROAD_IMPACT_WARNING_THRESHOLD: i64 = 20;

/// Why an existing file is included in a classifier rule impact preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RuleImpactMatchReason {
    /// File name or path metadata matched a keyword rule basis.
    Keyword,
    /// File extension matched an extension rule basis.
    Extension,
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
    /// Draft rule used for the preview.
    pub rule: ClassifierRule,
    /// Existing files matched by the draft rule.
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

/// Previews the impact of one classifier rule draft without saving or applying it.
///
/// C2-14 owns the read-only contract for S2-18. The function accepts the same
/// [`ClassifierRule`] draft used by rule save, validates the contract shape,
/// and returns a [`RuleImpactReport`] from repository classifier matcher and
/// active file metadata. It must not save classifier rules, apply category changes,
/// move files, create categories, write undo actions, call AI/network providers,
/// or touch app-layer code.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, invalid
/// classifier config, or invalid rule drafts. Returns `CoreError::Db { message
/// }` when classifier impact metadata cannot be read.
pub fn preview_classifier_rule_impact(
    repo_path: String,
    rule: ClassifierRule,
) -> CoreResult<RuleImpactReport> {
    let repo = validate_impact_request(&repo_path, &rule)?;
    let config = read_classifier_config(&repo)?;
    ensure_target_category_exists(&config, &rule.target_category)?;
    let files = db::list_active_files(&repo)?;
    let mut builder = ReportBuilder::new(rule);
    for file in files {
        if let Some(item) = preview_file(&repo, &config, &builder.rule, file)? {
            builder.push(item);
        }
    }
    Ok(builder.finish())
}

struct ReportBuilder {
    rule: ClassifierRule,
    affected_file_count: i64,
    will_update_count: i64,
    already_correct_count: i64,
    needs_review_count: i64,
    samples: Vec<RuleImpactSample>,
    conflicts: Vec<RuleImpactConflict>,
}

impl ReportBuilder {
    fn new(rule: ClassifierRule) -> Self {
        Self {
            rule,
            affected_file_count: 0,
            will_update_count: 0,
            already_correct_count: 0,
            needs_review_count: 0,
            samples: Vec::new(),
            conflicts: Vec::new(),
        }
    }

    fn push(&mut self, item: ImpactItem) {
        self.affected_file_count += 1;
        match item.sample.status {
            RuleImpactStatus::WillUpdate => self.will_update_count += 1,
            RuleImpactStatus::AlreadyCorrect => self.already_correct_count += 1,
            RuleImpactStatus::NeedsReview | RuleImpactStatus::IndexOnly => {
                self.needs_review_count += 1;
            }
            RuleImpactStatus::Conflict | RuleImpactStatus::Missing => {}
        }
        if self.samples.len() < SAMPLE_LIMIT {
            self.samples.push(item.sample);
        }
        self.conflicts.extend(item.conflicts);
    }

    fn finish(self) -> RuleImpactReport {
        let conflict_count = self.conflicts.len() as i64;
        let warning_required = self.affected_file_count > BROAD_IMPACT_WARNING_THRESHOLD;
        let apply_blocked_reason = apply_blocked_reason(
            self.will_update_count,
            self.needs_review_count,
            conflict_count,
        );
        RuleImpactReport {
            rule: self.rule,
            affected_file_count: self.affected_file_count,
            will_update_count: self.will_update_count,
            already_correct_count: self.already_correct_count,
            needs_review_count: self.needs_review_count,
            conflict_count,
            sample_limit: SAMPLE_LIMIT as i64,
            samples: self.samples,
            conflicts: self.conflicts,
            needs_review: self.needs_review_count > 0,
            warning_required,
            warning: warning_required.then(|| {
                format!(
                    "Rule affects {} existing files; review before applying.",
                    self.affected_file_count
                )
            }),
            can_apply: apply_blocked_reason.is_none(),
            apply_blocked_reason,
        }
    }
}

struct ImpactItem {
    sample: RuleImpactSample,
    conflicts: Vec<RuleImpactConflict>,
}

fn preview_file(
    repo: &std::path::Path,
    config: &config::ClassifierConfig,
    rule: &ClassifierRule,
    entry: FileEntry,
) -> CoreResult<Option<ImpactItem>> {
    let match_reasons = match_reasons(rule, &entry.current_name);
    if match_reasons.is_empty() {
        return Ok(None);
    }
    let mut conflicts = Vec::new();
    let (status, reason) = status_for(repo, config, rule, &entry, &match_reasons, &mut conflicts)?;
    let sample = RuleImpactSample {
        file_id: entry.id,
        path: entry.path.clone(),
        current_category: entry.category.clone(),
        new_category: rule.target_category.clone(),
        match_reasons,
        status,
        reason,
    };
    Ok(Some(ImpactItem { sample, conflicts }))
}

fn status_for(
    repo: &std::path::Path,
    config: &config::ClassifierConfig,
    rule: &ClassifierRule,
    entry: &FileEntry,
    match_reasons: &[RuleImpactMatchReason],
    conflicts: &mut Vec<RuleImpactConflict>,
) -> CoreResult<(RuleImpactStatus, Option<String>)> {
    if !backing_file_is_present(repo, entry)? {
        conflicts.push(conflict(
            entry,
            None,
            RuleImpactConflictKind::MissingFile,
            "backing file is missing",
        ));
        return Ok((
            RuleImpactStatus::Missing,
            Some("backing file is missing".to_owned()),
        ));
    }
    if has_rule_conflict(config, rule, match_reasons) {
        conflicts.push(conflict(
            entry,
            None,
            RuleImpactConflictKind::RuleConflict,
            "existing classifier rule would also match",
        ));
        return Ok((RuleImpactStatus::Conflict, Some("rule conflict".to_owned())));
    }
    if entry.category == rule.target_category {
        return Ok((RuleImpactStatus::AlreadyCorrect, None));
    }
    if matches!(entry.storage_mode, StorageMode::Indexed) {
        return Ok((
            RuleImpactStatus::IndexOnly,
            Some("index-only file requires metadata-only review".to_owned()),
        ));
    }
    if let Some(path) = target_path_conflict(repo, entry, &rule.target_category)? {
        conflicts.push(conflict(
            entry,
            Some(path),
            RuleImpactConflictKind::NameConflict,
            "target path already exists",
        ));
        return Ok((
            RuleImpactStatus::Conflict,
            Some("target path already exists".to_owned()),
        ));
    }
    Ok((RuleImpactStatus::WillUpdate, None))
}

fn has_rule_conflict(
    config: &config::ClassifierConfig,
    rule: &ClassifierRule,
    match_reasons: &[RuleImpactMatchReason],
) -> bool {
    config
        .categories
        .iter()
        .filter(|category| category.slug != rule.target_category)
        .any(|category| {
            (match_reasons.contains(&RuleImpactMatchReason::Keyword)
                && intersects(&category.keywords, &rule.keywords))
                || (match_reasons.contains(&RuleImpactMatchReason::Extension)
                    && intersects(&category.extensions, &rule.extensions))
        })
}

fn intersects(left: &[String], right: &[String]) -> bool {
    left.iter()
        .any(|value| right.iter().any(|other| other == value))
}

fn backing_file_is_present(repo: &std::path::Path, entry: &FileEntry) -> CoreResult<bool> {
    let path = if matches!(entry.storage_mode, StorageMode::Indexed) {
        PathBuf::from(entry.source_path.as_deref().unwrap_or(&entry.path))
    } else {
        repo_relative_file_path(repo, &entry.path)?
    };
    match path.metadata() {
        Ok(metadata) => Ok(metadata.is_file()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(map_impact_metadata_error(error)),
    }
}

fn target_path_conflict(
    repo: &std::path::Path,
    entry: &FileEntry,
    target_category: &str,
) -> CoreResult<Option<String>> {
    let current_path = repo_relative_file_path(repo, &entry.path)?;
    let target_path = repo.join(target_category).join(&entry.current_name);
    if target_path == current_path {
        return Ok(None);
    }
    match target_path.metadata() {
        Ok(_) => relative_repo_path(repo, &target_path).map(Some),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(map_impact_metadata_error(error)),
    }
}

fn map_impact_metadata_error(error: io::Error) -> crate::CoreError {
    crate::CoreError::db(format!(
        "classifier impact metadata is unavailable: {}",
        error.kind()
    ))
}

fn conflict(
    entry: &FileEntry,
    conflicting_path: Option<String>,
    kind: RuleImpactConflictKind,
    reason: &str,
) -> RuleImpactConflict {
    RuleImpactConflict {
        file_id: entry.id,
        path: Some(entry.path.clone()),
        conflicting_path,
        kind,
        reason: reason.to_owned(),
    }
}

fn apply_blocked_reason(
    will_update_count: i64,
    needs_review_count: i64,
    conflict_count: i64,
) -> Option<String> {
    if conflict_count > 0 && needs_review_count > 0 {
        return Some("resolve conflicts and needs review rows".to_owned());
    }
    if conflict_count > 0 {
        return Some(format!(
            "{conflict_count} conflict(s) must be resolved before Apply"
        ));
    }
    if needs_review_count > 0 {
        return Some(format!(
            "{needs_review_count} item(s) need review before Apply"
        ));
    }
    if will_update_count == 0 {
        return Some("No matched files need category changes".to_owned());
    }
    None
}
