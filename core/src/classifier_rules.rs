//! C2-13 classifier rule save contract types and boundary.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_CATEGORY_SLUG_LEN: usize = 32;
const MAX_EXTENSION_LEN: usize = 16;
const MAX_KEYWORD_LEN: usize = 32;
const MIN_PRIORITY: i64 = -1000;
const MAX_PRIORITY: i64 = 1000;

/// Classifier rule payload shared by S2-17, S2-18, and C2-13.
///
/// The shape maps directly to the supported `classifier.yaml` fields for one
/// target category: `keywords`, `extensions`, and `priority`. It intentionally
/// does not model path, source-folder, enabled flags, compound AND rules, or
/// history-application state because those are outside the Stage 2 save-rule
/// contract.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClassifierRule {
    /// Existing classifier category slug that receives the selected rule basis.
    pub target_category: String,
    /// Filename keywords to append as independent keyword matches.
    pub keywords: Vec<String>,
    /// File extensions to append without a leading dot and in lowercase.
    pub extensions: Vec<String>,
    /// Classifier priority for the target category.
    pub priority: i64,
}

/// Saves one C2-13 classifier rule contract request.
///
/// This contract entry point exposes the stable API, FFI type, and validation
/// boundary for the later implementation task. It validates the request shape
/// and then fails instead of returning a fabricated saved rule until C2-13
/// persistence is implemented.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, target
/// categories, rule basis, or priority values. The implementation task will add
/// `CoreError::PermissionDenied { path }` and `CoreError::Io { message }` for
/// atomic classifier configuration writes.
pub fn save_classifier_rule(repo_path: String, rule: ClassifierRule) -> CoreResult<ClassifierRule> {
    validate_classifier_rule_request(&repo_path, &rule)?;
    Err(CoreError::config(
        "classifier rule persistence is not implemented",
    ))
}

fn validate_classifier_rule_request(repo_path: &str, rule: &ClassifierRule) -> CoreResult<PathBuf> {
    let repo = validate_rule_repo_path(repo_path)?;
    validate_target_category(&rule.target_category)?;
    validate_rule_basis(rule)?;
    validate_priority(rule.priority)?;
    Ok(repo)
}

fn validate_rule_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::config(
            "classifier rule repository path is required",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "classifier rule repository path is invalid",
        ));
    }
    Ok(repo)
}

fn validate_target_category(category: &str) -> CoreResult<()> {
    if !is_valid_category_slug(category) {
        return Err(CoreError::config(
            "classifier rule target category is invalid",
        ));
    }
    Ok(())
}

fn validate_rule_basis(rule: &ClassifierRule) -> CoreResult<()> {
    let mut has_basis = false;
    for keyword in &rule.keywords {
        validate_keyword(keyword)?;
        has_basis = true;
    }
    for extension in &rule.extensions {
        validate_extension(extension)?;
        has_basis = true;
    }
    if !has_basis {
        return Err(CoreError::config("classifier rule basis is required"));
    }
    ensure_unique(&rule.keywords, "classifier rule keywords must be unique")?;
    ensure_unique(
        &rule.extensions,
        "classifier rule extensions must be unique",
    )?;
    Ok(())
}

fn validate_keyword(keyword: &str) -> CoreResult<()> {
    let trimmed = keyword.trim();
    if trimmed.is_empty()
        || trimmed != keyword
        || trimmed.chars().count() > MAX_KEYWORD_LEN
        || contains_forbidden_rule_character(trimmed)
    {
        return Err(CoreError::config("classifier rule keyword is invalid"));
    }
    Ok(())
}

fn validate_extension(extension: &str) -> CoreResult<()> {
    if extension.is_empty()
        || extension.chars().count() > MAX_EXTENSION_LEN
        || extension.starts_with('.')
        || !extension
            .chars()
            .all(|character| character.is_ascii_lowercase() || character.is_ascii_digit())
    {
        return Err(CoreError::config("classifier rule extension is invalid"));
    }
    Ok(())
}

fn validate_priority(priority: i64) -> CoreResult<()> {
    if (MIN_PRIORITY..=MAX_PRIORITY).contains(&priority) {
        Ok(())
    } else {
        Err(CoreError::config("classifier rule priority is invalid"))
    }
}

fn ensure_unique(values: &[String], message: &str) -> CoreResult<()> {
    let mut seen = Vec::new();
    for value in values {
        if seen.iter().any(|existing| *existing == value) {
            return Err(CoreError::config(message));
        }
        seen.push(value);
    }
    Ok(())
}

fn is_valid_category_slug(category: &str) -> bool {
    let mut chars = category.chars();
    match chars.next() {
        Some(first) if first.is_ascii_lowercase() => {}
        _ => return false,
    }
    category.chars().count() <= MAX_CATEGORY_SLUG_LEN
        && chars.all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '-')
}

fn contains_forbidden_rule_character(value: &str) -> bool {
    value
        .chars()
        .any(|character| matches!(character, '/' | '\\' | ':' | '\0' | '\n' | '\r' | '\t'))
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
