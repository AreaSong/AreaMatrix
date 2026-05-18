//! C2-12 classifier correction contract types and entry point.

use std::{
    ffi::OsStr,
    path::{Component, Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::{classify, db, storage, CoreError, CoreResult, FileEntry, FileOrigin, StorageMode};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_CATEGORY_SLUG_LEN: usize = 32;
const MAX_RULE_CANDIDATES: usize = 5;
const SUGGESTED_RULE_PRIORITY: i64 = 100;

/// Rule draft handed off from S2-16 to classifier rule confirmation pages.
///
/// This draft is only a proposed rule basis. C2-12 must not persist it; saving
/// and impact preview stay with C2-13 and C2-14.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClassifierRuleDraft {
    /// File that produced the correction suggestion.
    pub source_file_id: i64,
    /// Target category selected in the correction sheet.
    pub target_category: String,
    /// Safe keyword candidates derived from filename or path context.
    pub keyword_candidates: Vec<String>,
    /// Safe extension candidates without leading dots.
    pub extension_candidates: Vec<String>,
    /// Suggested classifier priority for later confirmation.
    pub priority: i64,
}

/// Result returned after applying one C2-12 classifier correction.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ClassifierCorrectionResult {
    /// Updated file row after the correction is committed.
    pub updated_file: FileEntry,
    /// Optional rule draft for S2-17/S2-18 handoff; it is not saved by C2-12.
    pub rule_draft: Option<ClassifierRuleDraft>,
    /// Whether the caller requested a physical move when the entry is repo-managed.
    pub move_file_requested: bool,
    /// Whether the caller requested a future-rule handoff.
    pub remember_requested: bool,
    /// Whether the returned draft still requires explicit rule confirmation.
    pub rule_confirmation_required: bool,
}

/// Applies one classifier correction contract request.
///
/// C2-12 is the quick-correction boundary for S2-16. The contract accepts the
/// target category, an explicit move preference, and a remember flag for rule
/// draft handoff. It must not save classifier rules, preview broad rule impact,
/// create categories, call AI or network providers, or touch app-layer code.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` for invalid target categories.
/// Returns `CoreError::Conflict { path }` when a safe target path cannot be
/// resolved, `CoreError::Io { message }` for file moves, and `CoreError::Db {
/// message }` for metadata or change-log failures.
pub fn correct_file_category(
    repo_path: String,
    file_id: i64,
    category: String,
    move_file: bool,
    remember: bool,
) -> CoreResult<ClassifierCorrectionResult> {
    correct_file_category_inner(repo_path, file_id, category, move_file, remember)
        .map_err(normalize_contract_error)
}

fn correct_file_category_inner(
    repo_path: String,
    file_id: i64,
    category: String,
    move_file: bool,
    remember: bool,
) -> CoreResult<ClassifierCorrectionResult> {
    let repo = validate_correction_repo_path(&repo_path)?;
    validate_correction_file_id(file_id)?;
    let category = normalize_category(&category)?;
    db::ensure_initialized(&repo).map_err(normalize_metadata_error)?;
    classify::ensure_category_exists(&repo, &category)?;

    let entry = db::get_active_file_by_id(&repo, file_id).map_err(normalize_metadata_error)?;
    let rule_draft = remember
        .then(|| build_rule_draft(&entry, &category))
        .filter(ClassifierRuleDraft::has_candidates);
    let updated_file = apply_correction(repo_path, &repo, entry, &category, move_file, remember)?;

    Ok(ClassifierCorrectionResult {
        updated_file,
        rule_draft,
        move_file_requested: move_file,
        remember_requested: remember,
        rule_confirmation_required: remember,
    })
}

fn validate_correction_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::db(
            "classifier correction metadata is unavailable",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::db(
            "classifier correction metadata is unavailable",
        ));
    }
    Ok(repo)
}

fn validate_correction_file_id(file_id: i64) -> CoreResult<()> {
    if file_id <= 0 {
        return Err(CoreError::db(
            "classifier correction file metadata is unavailable",
        ));
    }
    Ok(())
}

fn normalize_category(category: &str) -> CoreResult<String> {
    let trimmed = category.trim();
    if trimmed.is_empty()
        || trimmed.chars().count() > MAX_CATEGORY_SLUG_LEN
        || !is_valid_category_slug(trimmed)
    {
        return Err(CoreError::classify("target category is invalid"));
    }
    Ok(trimmed.to_owned())
}

fn is_valid_category_slug(category: &str) -> bool {
    let mut chars = category.chars();
    match chars.next() {
        Some(first) if first.is_ascii_lowercase() => {}
        _ => return false,
    }
    chars.all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '-')
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}

fn apply_correction(
    repo_path: String,
    repo: &Path,
    entry: FileEntry,
    category: &str,
    move_file: bool,
    remember: bool,
) -> CoreResult<FileEntry> {
    if entry.category == category {
        return Ok(entry);
    }
    if should_move_repo_owned_file(&entry, move_file) {
        return storage::correct_repo_owned_file_category(repo_path, entry.id, category.to_owned())
            .map_err(normalize_move_error);
    }
    db::correct_file_category_metadata_only(
        repo,
        entry.id,
        category,
        &correction_detail(&entry, category, remember),
    )
    .map_err(normalize_metadata_error)?;
    db::get_active_file_by_id(repo, entry.id).map_err(normalize_metadata_error)
}

fn should_move_repo_owned_file(entry: &FileEntry, move_file: bool) -> bool {
    move_file
        && entry.origin == FileOrigin::Imported
        && matches!(entry.storage_mode, StorageMode::Copied | StorageMode::Moved)
}

fn correction_detail(entry: &FileEntry, category: &str, remember: bool) -> Value {
    json!({
        "kind": "classifier_correction",
        "from_category": entry.category,
        "to_category": category,
        "from_path": entry.path,
        "to_path": entry.path,
        "final_name": entry.current_name,
        "name_conflict_resolved": false,
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "origin": origin_detail(&entry.origin),
        "index_only": true,
        "by": "user",
        "remember_requested": remember,
    })
}

fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn origin_detail(origin: &FileOrigin) -> &'static str {
    match origin {
        FileOrigin::Imported => "imported",
        FileOrigin::Adopted => "adopted",
        FileOrigin::External => "external",
    }
}

fn build_rule_draft(entry: &FileEntry, category: &str) -> ClassifierRuleDraft {
    ClassifierRuleDraft {
        source_file_id: entry.id,
        target_category: category.to_owned(),
        keyword_candidates: keyword_candidates(entry),
        extension_candidates: extension_candidates(entry),
        priority: SUGGESTED_RULE_PRIORITY,
    }
}

impl ClassifierRuleDraft {
    fn has_candidates(&self) -> bool {
        !self.keyword_candidates.is_empty() || !self.extension_candidates.is_empty()
    }
}

fn keyword_candidates(entry: &FileEntry) -> Vec<String> {
    let mut candidates = Vec::new();
    collect_keywords_from_path(Path::new(&entry.current_name), &mut candidates);
    collect_keywords_from_path(Path::new(&entry.path), &mut candidates);
    candidates
}

fn collect_keywords_from_path(path: &Path, candidates: &mut Vec<String>) {
    for component in path.components() {
        let Component::Normal(part) = component else {
            continue;
        };
        for token in tokens_from_part(part) {
            push_candidate(candidates, token, MAX_CATEGORY_SLUG_LEN);
        }
    }
}

fn tokens_from_part(part: &OsStr) -> Vec<String> {
    let Some(part) = part.to_str() else {
        return Vec::new();
    };
    let stem = Path::new(part)
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or(part);
    stem.split(is_rule_token_separator)
        .filter_map(normalize_rule_token)
        .collect()
}

fn normalize_rule_token(token: &str) -> Option<String> {
    let token = token.trim().to_lowercase();
    let char_count = token.chars().count();
    if (2..=MAX_CATEGORY_SLUG_LEN).contains(&char_count) {
        Some(token)
    } else {
        None
    }
}

fn extension_candidates(entry: &FileEntry) -> Vec<String> {
    let mut candidates = Vec::new();
    for path in [&entry.current_name, &entry.path] {
        let extension = Path::new(path)
            .extension()
            .and_then(|value| value.to_str())
            .map(str::to_lowercase);
        if let Some(extension) = extension {
            push_candidate(&mut candidates, extension, 16);
        }
    }
    candidates
}

fn push_candidate(candidates: &mut Vec<String>, candidate: String, max_len: usize) {
    if candidates.len() >= MAX_RULE_CANDIDATES
        || candidate.chars().count() > max_len
        || candidate
            .chars()
            .any(|character| matches!(character, '/' | '\\' | ':' | '\0'))
        || candidates.iter().any(|existing| existing == &candidate)
    {
        return;
    }
    candidates.push(candidate);
}

fn is_rule_token_separator(character: char) -> bool {
    matches!(
        character,
        ' ' | '_' | '-' | '.' | '\t' | '/' | '\\' | '(' | ')' | '[' | ']'
    )
}

fn normalize_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. }
        | CoreError::FileNotFound { .. }
        | CoreError::InvalidPath { .. }
        | CoreError::PermissionDenied { .. }
        | CoreError::Internal { .. } => {
            CoreError::db("classifier correction metadata is unavailable")
        }
        CoreError::Io { .. } => CoreError::io("classifier correction metadata io unavailable"),
        other => other,
    }
}

fn normalize_move_error(error: CoreError) -> CoreError {
    match error {
        CoreError::FileNotFound { .. } | CoreError::PermissionDenied { .. } => {
            CoreError::io("classifier correction file move failed")
        }
        CoreError::InvalidPath { .. } => {
            CoreError::conflict("classifier correction target path is unsafe")
        }
        CoreError::RepoNotInitialized { .. } => {
            CoreError::db("classifier correction metadata is unavailable")
        }
        CoreError::Config { .. } => CoreError::classify("classification error"),
        CoreError::DuplicateFile { .. } => CoreError::conflict("path conflict"),
        CoreError::ICloudPlaceholder { .. } | CoreError::Internal { .. } => {
            CoreError::io("classifier correction file move failed")
        }
        other => other,
    }
}

fn normalize_contract_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Classify { .. }
        | CoreError::Conflict { .. }
        | CoreError::Io { .. }
        | CoreError::Db { .. } => error,
        CoreError::Config { .. } => CoreError::classify("classification error"),
        CoreError::DuplicateFile { .. } => CoreError::conflict("path conflict"),
        CoreError::RepoNotInitialized { .. } | CoreError::Internal { .. } => {
            CoreError::db("classifier correction metadata is unavailable")
        }
        CoreError::FileNotFound { .. }
        | CoreError::InvalidPath { .. }
        | CoreError::ICloudPlaceholder { .. }
        | CoreError::PermissionDenied { .. } => {
            CoreError::io("classifier correction file operation failed")
        }
    }
}
