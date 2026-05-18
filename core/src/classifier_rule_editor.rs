//! C2-15 classifier rule editor contract types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_RULE_ID_LEN: usize = 64;
const MAX_CATEGORY_SLUG_LEN: usize = 32;
const MAX_DISPLAY_NAME_LEN: usize = 64;
const MAX_DESCRIPTION_LEN: usize = 200;
const MAX_EXTENSION_LEN: usize = 16;
const MAX_KEYWORD_LEN: usize = 32;
const MAX_NAMING_TEMPLATE_LEN: usize = 200;
const MIN_PRIORITY: i64 = -1000;
const MAX_PRIORITY: i64 = 1000;

/// One classifier editor row for S2-19.
///
/// `rule_id` is the stable id of the currently persisted classifier category.
/// `slug` is editable content and may differ during a rename request.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClassifierRuleRecord {
    /// Stable classifier rule id used by update and delete calls.
    pub rule_id: String,
    /// Classifier category slug represented by this editor row.
    pub slug: String,
    /// User-visible display name for the editor locale fallback.
    pub display_name: String,
    /// User-visible category description for the editor locale fallback.
    pub description: String,
    /// Extension matcher values without a leading dot.
    pub extensions: Vec<String>,
    /// Filename keyword matcher values.
    pub keywords: Vec<String>,
    /// Classifier priority for this category.
    pub priority: i64,
    /// Optional naming template supported by `classifier.yaml`.
    pub naming_template: Option<String>,
    /// Whether this row is the classifier default category.
    pub is_default: bool,
}

/// Snapshot returned after listing or mutating classifier editor state.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClassifierRuleEditorSnapshot {
    /// Current classifier rows in persisted order.
    pub rules: Vec<ClassifierRuleRecord>,
    /// Rule id of the default category.
    pub default_rule_id: String,
    /// Rule id changed by the last update/delete call, when applicable.
    pub updated_rule_id: Option<String>,
    /// Save/delete warning shown by S2-19 when impact preview is still required.
    pub warning: Option<String>,
}

/// Update payload for one classifier editor row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClassifierRuleUpdate {
    /// Stable id of the row being updated.
    pub rule_id: String,
    /// Replacement classifier category slug.
    pub slug: String,
    /// Replacement display name.
    pub display_name: String,
    /// Replacement description.
    pub description: String,
    /// Replacement extension matcher values without leading dots.
    pub extensions: Vec<String>,
    /// Replacement keyword matcher values.
    pub keywords: Vec<String>,
    /// Replacement classifier priority.
    pub priority: i64,
    /// Replacement naming template, if any.
    pub naming_template: Option<String>,
    /// Whether the UI already completed the required impact preview.
    pub preview_confirmed: bool,
}

/// Delete payload for one classifier editor row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClassifierRuleDeleteRequest {
    /// Stable id of the classifier row to delete.
    pub rule_id: String,
    /// Replacement category used by impact preview when deleting a category.
    pub replacement_category: Option<String>,
    /// Whether the UI already completed the required delete impact preview.
    pub preview_confirmed: bool,
}

/// Lists C2-15 classifier rule editor state for S2-19.
///
/// This contract returns the persisted classifier categories and their editable
/// matcher fields. It must not preview impact, apply changes to existing files,
/// open YAML, call AI/network providers, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths or
/// malformed classifier configuration, `CoreError::PermissionDenied { path }`
/// for blocked classifier metadata reads, and `CoreError::Io { message }` for
/// classifier config read failures.
pub fn list_classifier_rules(repo_path: String) -> CoreResult<ClassifierRuleEditorSnapshot> {
    let _repo = validate_editor_repo_path(&repo_path)?;
    Err(CoreError::config(
        "classifier rule editor implementation pending",
    ))
}

/// Updates one C2-15 classifier rule editor row.
///
/// The update replaces category slug, display metadata, matcher values,
/// priority, and naming template for one existing row. It must atomically write
/// classifier configuration only; it must not move, delete, rename, reindex,
/// retag, write notes, update generated overviews, or apply rules to history.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid ids, rule content,
/// missing preview confirmation, duplicate rows, or malformed classifier
/// configuration. Returns `CoreError::PermissionDenied { path }` for blocked
/// classifier metadata writes and `CoreError::Io { message }` for read,
/// backup, atomic write, or restore failures.
pub fn update_classifier_rule(
    repo_path: String,
    request: ClassifierRuleUpdate,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    let _repo = validate_editor_repo_path(&repo_path)?;
    validate_update_request(&request)?;
    Err(CoreError::config(
        "classifier rule editor implementation pending",
    ))
}

/// Deletes one C2-15 classifier rule editor row.
///
/// Delete only removes the classifier configuration row after the UI has
/// completed the required impact preview. It must not move, delete, rename,
/// trash, or reclassify existing files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid ids, attempts to delete
/// the default or final category, missing impact preview, missing replacement
/// state, or malformed classifier configuration. Returns
/// `CoreError::PermissionDenied { path }` for blocked classifier metadata
/// writes and `CoreError::Io { message }` for read, backup, atomic write, or
/// restore failures.
pub fn delete_classifier_rule(
    repo_path: String,
    request: ClassifierRuleDeleteRequest,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    let _repo = validate_editor_repo_path(&repo_path)?;
    validate_delete_request(&request)?;
    Err(CoreError::config(
        "classifier rule editor implementation pending",
    ))
}

fn validate_editor_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::config(
            "classifier rule editor repository path is required",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "classifier rule editor repository path is invalid",
        ));
    }
    Ok(repo)
}

fn validate_update_request(request: &ClassifierRuleUpdate) -> CoreResult<()> {
    validate_rule_id(&request.rule_id)?;
    validate_category_slug(&request.slug)?;
    validate_display_name(&request.display_name)?;
    validate_description(&request.description)?;
    validate_rule_basis(&request.keywords, &request.extensions)?;
    validate_priority(request.priority)?;
    validate_naming_template(request.naming_template.as_deref())
}

fn validate_delete_request(request: &ClassifierRuleDeleteRequest) -> CoreResult<()> {
    validate_rule_id(&request.rule_id)?;
    if let Some(replacement) = &request.replacement_category {
        validate_category_slug(replacement)?;
    }
    Ok(())
}

fn validate_rule_id(rule_id: &str) -> CoreResult<()> {
    if rule_id.trim().is_empty() || rule_id.contains('\0') || rule_id.len() > MAX_RULE_ID_LEN {
        return Err(CoreError::config("classifier rule id is invalid"));
    }
    Ok(())
}

fn validate_category_slug(slug: &str) -> CoreResult<()> {
    if !is_valid_category_slug(slug) {
        return Err(CoreError::config("classifier rule slug is invalid"));
    }
    Ok(())
}

fn validate_display_name(display_name: &str) -> CoreResult<()> {
    let len = display_name.chars().count();
    if len == 0 || len > MAX_DISPLAY_NAME_LEN || display_name.contains('\0') {
        return Err(CoreError::config("classifier rule display name is invalid"));
    }
    Ok(())
}

fn validate_description(description: &str) -> CoreResult<()> {
    if description.chars().count() > MAX_DESCRIPTION_LEN || description.contains('\0') {
        return Err(CoreError::config("classifier rule description is invalid"));
    }
    Ok(())
}

fn validate_rule_basis(keywords: &[String], extensions: &[String]) -> CoreResult<()> {
    ensure_unique(keywords, "classifier rule keywords must be unique")?;
    ensure_unique(extensions, "classifier rule extensions must be unique")?;
    for keyword in keywords {
        validate_keyword(keyword)?;
    }
    for extension in extensions {
        validate_extension(extension)?;
    }
    Ok(())
}

fn validate_keyword(keyword: &str) -> CoreResult<()> {
    if keyword.trim().is_empty()
        || keyword.trim() != keyword
        || keyword.chars().count() > MAX_KEYWORD_LEN
        || contains_forbidden_matcher_character(keyword)
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

fn validate_naming_template(template: Option<&str>) -> CoreResult<()> {
    if template.is_some_and(|value| {
        value.contains('\0') || value.chars().count() > MAX_NAMING_TEMPLATE_LEN
    }) {
        return Err(CoreError::config(
            "classifier rule naming template is invalid",
        ));
    }
    Ok(())
}

fn ensure_unique(values: &[String], message: &str) -> CoreResult<()> {
    let mut sorted = values.to_vec();
    sorted.sort();
    if sorted.windows(2).any(|window| window[0] == window[1]) {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn is_valid_category_slug(slug: &str) -> bool {
    let mut chars = slug.chars();
    match chars.next() {
        Some(first) if first.is_ascii_lowercase() => {}
        _ => return false,
    }
    slug.chars().count() <= MAX_CATEGORY_SLUG_LEN
        && chars.all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '-')
}

fn contains_forbidden_matcher_character(value: &str) -> bool {
    value
        .chars()
        .any(|character| matches!(character, '/' | '\\' | ':' | '\0' | '\n' | '\r' | '\t'))
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
