//! C2-14 classifier rule impact-preview contract types and boundary.

use std::{io, path::PathBuf};

use crate::{CoreResult, FileEntry, StorageMode};

mod config;
mod db;
mod matcher;
mod path;
mod types;

pub use types::{
    ClassifierImpactPreviewMode, ClassifierImpactPreviewRequest, RuleImpactConflict,
    RuleImpactConflictKind, RuleImpactMatchReason, RuleImpactReport, RuleImpactSample,
    RuleImpactStatus,
};

use config::{
    ensure_replacement_category_exists, ensure_target_category_exists, read_classifier_config,
    validate_impact_request,
};
use matcher::{
    classify_after_removed_extension, classify_after_removed_keyword, classify_after_rule_draft,
    match_reasons,
};
use path::{relative_repo_path, repo_relative_file_path};

const SAMPLE_LIMIT: usize = 50;
const BROAD_IMPACT_WARNING_THRESHOLD: i64 = 20;

/// Previews classifier rule or delete impact without saving or applying it.
///
/// C2-14 owns the read-only contract for S2-18. The function accepts the same
/// rule-shaped payload used by rule save plus an explicit preview mode, then
/// returns a [`RuleImpactReport`] from repository classifier matcher and active
/// file metadata. It must not save classifier rules, apply category changes,
/// move files, create categories, write undo actions, call AI/network providers,
/// or touch app-layer code.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, invalid
/// classifier config, invalid rule drafts, invalid delete preview requests, or
/// invalid replacement categories. Returns `CoreError::Db { message }` when
/// classifier impact metadata cannot be read.
pub fn preview_classifier_rule_impact(
    repo_path: String,
    request: ClassifierImpactPreviewRequest,
) -> CoreResult<RuleImpactReport> {
    let repo = validate_impact_request(&repo_path, &request)?;
    let config = read_classifier_config(&repo)?;
    validate_config_for_request(&config, &request)?;
    let files = db::list_active_files(&repo)?;
    let blocked_reason = extra_apply_blocked_reason(&request);
    let mut builder = ReportBuilder::new(request);
    for file in files {
        if let Some(item) = preview_file(&repo, &config, &builder.request, file)? {
            builder.push(item);
        }
    }
    Ok(builder.finish(blocked_reason))
}

struct ReportBuilder {
    request: ClassifierImpactPreviewRequest,
    affected_file_count: i64,
    will_update_count: i64,
    already_correct_count: i64,
    needs_review_count: i64,
    samples: Vec<RuleImpactSample>,
    conflicts: Vec<RuleImpactConflict>,
}

impl ReportBuilder {
    fn new(request: ClassifierImpactPreviewRequest) -> Self {
        Self {
            request,
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

    fn finish(self, extra_blocked_reason: Option<String>) -> RuleImpactReport {
        let conflict_count = self.conflicts.len() as i64;
        let warning_required = self.affected_file_count > BROAD_IMPACT_WARNING_THRESHOLD;
        let apply_blocked_reason = extra_blocked_reason.or_else(|| {
            apply_blocked_reason(
                self.will_update_count,
                self.needs_review_count,
                conflict_count,
            )
        });
        RuleImpactReport {
            request: self.request,
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
    request: &ClassifierImpactPreviewRequest,
    entry: FileEntry,
) -> CoreResult<Option<ImpactItem>> {
    let match_reasons = request_match_reasons(request, &entry);
    if match_reasons.is_empty() {
        return Ok(None);
    }
    let mut conflicts = Vec::new();
    let new_category = new_category_for_request(config, request, &entry);
    let (status, reason) = status_for(repo, request, &entry, &new_category, &mut conflicts)?;
    let sample = RuleImpactSample {
        file_id: entry.id,
        path: entry.path.clone(),
        current_category: entry.category.clone(),
        new_category,
        match_reasons,
        status,
        reason,
    };
    Ok(Some(ImpactItem { sample, conflicts }))
}

fn validate_config_for_request(
    config: &config::ClassifierConfig,
    request: &ClassifierImpactPreviewRequest,
) -> CoreResult<()> {
    match request.mode {
        ClassifierImpactPreviewMode::RuleDraft => {
            ensure_target_category_exists(config, &request.rule.target_category)
        }
        ClassifierImpactPreviewMode::RemoveKeyword => ensure_category_has_keyword(
            config,
            &request.rule.target_category,
            &request.rule.keywords[0],
        ),
        ClassifierImpactPreviewMode::RemoveExtension => ensure_category_has_extension(
            config,
            &request.rule.target_category,
            &request.rule.extensions[0],
        ),
        ClassifierImpactPreviewMode::RemoveCategory => {
            validate_remove_category_config(config, request)
        }
    }
}

fn validate_remove_category_config(
    config: &config::ClassifierConfig,
    request: &ClassifierImpactPreviewRequest,
) -> CoreResult<()> {
    ensure_target_category_exists(config, &request.rule.target_category)?;
    if let Some(replacement) = request.replacement_category.as_deref() {
        ensure_replacement_category_exists(config, &request.rule.target_category, replacement)?;
    }
    Ok(())
}

fn ensure_category_has_keyword(
    config: &config::ClassifierConfig,
    category: &str,
    keyword: &str,
) -> CoreResult<()> {
    let category = category_config(config, category)?;
    if category
        .keywords
        .iter()
        .any(|candidate| candidate == keyword)
    {
        Ok(())
    } else {
        Err(crate::CoreError::config(
            "classifier impact keyword does not exist",
        ))
    }
}

fn ensure_category_has_extension(
    config: &config::ClassifierConfig,
    category: &str,
    extension: &str,
) -> CoreResult<()> {
    let category = category_config(config, category)?;
    if category
        .extensions
        .iter()
        .any(|candidate| candidate == extension)
    {
        Ok(())
    } else {
        Err(crate::CoreError::config(
            "classifier impact extension does not exist",
        ))
    }
}

fn category_config<'a>(
    config: &'a config::ClassifierConfig,
    category: &str,
) -> CoreResult<&'a config::CategoryConfig> {
    config
        .categories
        .iter()
        .find(|candidate| candidate.slug == category)
        .ok_or_else(|| crate::CoreError::config("classifier impact target category does not exist"))
}

fn request_match_reasons(
    request: &ClassifierImpactPreviewRequest,
    entry: &FileEntry,
) -> Vec<RuleImpactMatchReason> {
    match request.mode {
        ClassifierImpactPreviewMode::RuleDraft => match_reasons(&request.rule, &entry.current_name),
        ClassifierImpactPreviewMode::RemoveKeyword
        | ClassifierImpactPreviewMode::RemoveExtension => {
            remove_basis_match_reasons(request, entry)
        }
        ClassifierImpactPreviewMode::RemoveCategory => {
            remove_category_match_reasons(request, entry)
        }
    }
}

fn remove_basis_match_reasons(
    request: &ClassifierImpactPreviewRequest,
    entry: &FileEntry,
) -> Vec<RuleImpactMatchReason> {
    if entry.category != request.rule.target_category {
        return Vec::new();
    }
    let reasons = match_reasons(&request.rule, &entry.current_name);
    match request.mode {
        ClassifierImpactPreviewMode::RemoveKeyword => {
            matching_single_reason(&reasons, RuleImpactMatchReason::Keyword)
        }
        ClassifierImpactPreviewMode::RemoveExtension => {
            matching_single_reason(&reasons, RuleImpactMatchReason::Extension)
        }
        ClassifierImpactPreviewMode::RuleDraft | ClassifierImpactPreviewMode::RemoveCategory => {
            reasons
        }
    }
}

fn matching_single_reason(
    reasons: &[RuleImpactMatchReason],
    reason: RuleImpactMatchReason,
) -> Vec<RuleImpactMatchReason> {
    if reasons.contains(&reason) {
        vec![reason]
    } else {
        Vec::new()
    }
}

fn remove_category_match_reasons(
    request: &ClassifierImpactPreviewRequest,
    entry: &FileEntry,
) -> Vec<RuleImpactMatchReason> {
    if entry.category != request.rule.target_category {
        return Vec::new();
    }
    vec![RuleImpactMatchReason::Category]
}

fn new_category_for_request(
    config: &config::ClassifierConfig,
    request: &ClassifierImpactPreviewRequest,
    entry: &FileEntry,
) -> String {
    match request.mode {
        ClassifierImpactPreviewMode::RuleDraft => {
            classify_after_rule_draft(config, &request.rule, &entry.current_name)
        }
        ClassifierImpactPreviewMode::RemoveKeyword => classify_after_removed_keyword(
            config,
            &request.rule.target_category,
            &request.rule.keywords[0],
            &entry.current_name,
        ),
        ClassifierImpactPreviewMode::RemoveExtension => classify_after_removed_extension(
            config,
            &request.rule.target_category,
            &request.rule.extensions[0],
            &entry.current_name,
        ),
        ClassifierImpactPreviewMode::RemoveCategory => request
            .replacement_category
            .clone()
            .unwrap_or_else(|| request.rule.target_category.clone()),
    }
}

fn extra_apply_blocked_reason(request: &ClassifierImpactPreviewRequest) -> Option<String> {
    (matches!(request.mode, ClassifierImpactPreviewMode::RemoveCategory)
        && request.replacement_category.is_none())
    .then(|| "replacement category is required before Apply".to_owned())
}

fn status_for(
    repo: &std::path::Path,
    request: &ClassifierImpactPreviewRequest,
    entry: &FileEntry,
    new_category: &str,
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
    if matches!(request.mode, ClassifierImpactPreviewMode::RemoveCategory)
        && request.replacement_category.is_none()
    {
        return Ok((
            RuleImpactStatus::NeedsReview,
            Some("replacement category is required".to_owned()),
        ));
    }
    if entry.category == new_category {
        return Ok((RuleImpactStatus::AlreadyCorrect, None));
    }
    if matches!(entry.storage_mode, StorageMode::Indexed) {
        return Ok((
            RuleImpactStatus::IndexOnly,
            Some("index-only file requires metadata-only review".to_owned()),
        ));
    }
    if request.move_files {
        if let Some(path) = target_path_conflict(repo, entry, new_category)? {
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
    }
    Ok((RuleImpactStatus::WillUpdate, None))
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
