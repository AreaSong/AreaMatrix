use std::{
    collections::{HashMap, HashSet},
    fs, io,
    path::{Component, Path, PathBuf},
};

use serde::Deserialize;

use crate::{ClassifierRule, CoreError, CoreResult};

use super::{ClassifierImpactPreviewMode, ClassifierImpactPreviewRequest};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const CLASSIFIER_FILE: &str = "classifier.yaml";
const MAX_CATEGORY_SLUG_LEN: usize = 32;
const MAX_EXTENSION_LEN: usize = 16;
const MAX_KEYWORD_LEN: usize = 32;
const MIN_PRIORITY: i64 = -1000;
const MAX_PRIORITY: i64 = 1000;
const MAX_CATEGORIES: usize = 64;
const MAX_DISPLAY_NAME_LEN: usize = 32;
const MAX_DESCRIPTION_LEN: usize = 200;
const MAX_NAMING_TEMPLATE_LEN: usize = 200;

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct ClassifierConfig {
    pub(super) version: u32,
    pub(super) default: String,
    pub(super) categories: Vec<CategoryConfig>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct CategoryConfig {
    pub(super) slug: String,
    #[serde(default)]
    pub(super) display_name: HashMap<String, String>,
    #[serde(default)]
    pub(super) description: HashMap<String, String>,
    #[serde(default)]
    pub(super) extensions: Vec<String>,
    #[serde(default)]
    pub(super) keywords: Vec<String>,
    #[serde(default)]
    pub(super) priority: i32,
    #[serde(default)]
    pub(super) naming_template: Option<String>,
}

pub(super) fn validate_impact_request(
    repo_path: &str,
    request: &ClassifierImpactPreviewRequest,
) -> CoreResult<PathBuf> {
    let repo = validate_repo_path(repo_path)?;
    validate_request_shape(request)?;
    ensure_impact_repo_initialized(&repo)?;
    Ok(repo)
}

pub(super) fn read_classifier_config(repo: &Path) -> CoreResult<ClassifierConfig> {
    let path = repo.join(AREA_MATRIX_DIR).join(CLASSIFIER_FILE);
    let yaml = fs::read_to_string(&path).map_err(map_classifier_read_error)?;
    let config =
        serde_yaml::from_str(&yaml).map_err(|error| CoreError::config(error.to_string()))?;
    validate_classifier_config(&config)?;
    Ok(config)
}

pub(super) fn ensure_target_category_exists(
    config: &ClassifierConfig,
    target_category: &str,
) -> CoreResult<()> {
    if config
        .categories
        .iter()
        .any(|category| category.slug == target_category)
    {
        Ok(())
    } else {
        Err(CoreError::config(
            "classifier impact target category does not exist",
        ))
    }
}

pub(super) fn ensure_replacement_category_exists(
    config: &ClassifierConfig,
    source_category: &str,
    replacement_category: &str,
) -> CoreResult<()> {
    if source_category == replacement_category {
        return Err(CoreError::config(
            "classifier impact replacement category must differ",
        ));
    }
    ensure_target_category_exists(config, replacement_category)
        .map_err(|_| CoreError::config("classifier impact replacement category does not exist"))
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::config(
            "classifier impact repository path is required",
        ));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "classifier impact repository path is invalid",
        ));
    }
    Ok(repo)
}

fn ensure_impact_repo_initialized(repo: &Path) -> CoreResult<()> {
    crate::db::ensure_initialized_readable(repo).map_err(|error| match error {
        CoreError::InvalidPath { .. } => {
            CoreError::config("classifier impact repository is not initialized")
        }
        CoreError::RepoNotInitialized { .. } | CoreError::Db { .. } => {
            CoreError::db("classifier impact metadata is unavailable")
        }
        other => other,
    })
}

fn map_classifier_read_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::NotFound => {
            CoreError::config("classifier impact repository is not initialized")
        }
        _ => CoreError::config("classifier schema is unavailable"),
    }
}

fn validate_classifier_config(config: &ClassifierConfig) -> CoreResult<()> {
    if config.version != 1
        || config.categories.is_empty()
        || config.categories.len() > MAX_CATEGORIES
    {
        return Err(CoreError::config("classifier schema version is invalid"));
    }
    let mut seen = HashSet::new();
    for category in &config.categories {
        validate_category(category, &mut seen)?;
    }
    if config
        .categories
        .iter()
        .any(|category| category.slug == config.default)
    {
        Ok(())
    } else {
        Err(CoreError::config("classifier default category is invalid"))
    }
}

fn validate_category(category: &CategoryConfig, seen: &mut HashSet<String>) -> CoreResult<()> {
    if !is_valid_category_slug(&category.slug) || !seen.insert(category.slug.clone()) {
        return Err(CoreError::config("classifier category slug is invalid"));
    }
    validate_locale_values(&category.display_name, 1, MAX_DISPLAY_NAME_LEN)?;
    validate_locale_values(&category.description, 0, MAX_DESCRIPTION_LEN)?;
    validate_category_values(&category.extensions, validate_extension)?;
    validate_category_values(&category.keywords, validate_keyword)?;
    validate_priority(i64::from(category.priority))?;
    if category
        .naming_template
        .as_ref()
        .is_some_and(|value| value.chars().count() > MAX_NAMING_TEMPLATE_LEN)
    {
        return Err(CoreError::config("classifier naming template is invalid"));
    }
    Ok(())
}

fn validate_locale_values(
    values: &HashMap<String, String>,
    min_len: usize,
    max_len: usize,
) -> CoreResult<()> {
    if values.values().any(|value| {
        let len = value.chars().count();
        len < min_len || len > max_len
    }) {
        return Err(CoreError::config("classifier locale value is invalid"));
    }
    Ok(())
}

fn validate_category_values(
    values: &[String],
    validator: fn(&str) -> CoreResult<()>,
) -> CoreResult<()> {
    let mut seen = HashSet::new();
    for value in values {
        validator(value)?;
        if !seen.insert(value.as_str()) {
            return Err(CoreError::config("classifier category values are invalid"));
        }
    }
    Ok(())
}

fn validate_request_shape(request: &ClassifierImpactPreviewRequest) -> CoreResult<()> {
    validate_target_category(&request.rule.target_category)?;
    validate_priority(request.rule.priority)?;
    match request.mode {
        ClassifierImpactPreviewMode::RuleDraft => {
            validate_rule_basis(&request.rule)?;
            reject_replacement_for_rule_basis(request)
        }
        ClassifierImpactPreviewMode::RemoveKeyword => {
            validate_single_keyword_request(request)?;
            reject_replacement_for_rule_basis(request)
        }
        ClassifierImpactPreviewMode::RemoveExtension => {
            validate_single_extension_request(request)?;
            reject_replacement_for_rule_basis(request)
        }
        ClassifierImpactPreviewMode::RemoveCategory => validate_remove_category_request(request),
    }
}

fn validate_single_keyword_request(request: &ClassifierImpactPreviewRequest) -> CoreResult<()> {
    if request.rule.keywords.len() != 1 || !request.rule.extensions.is_empty() {
        return Err(CoreError::config(
            "classifier impact remove keyword request is invalid",
        ));
    }
    validate_keyword(&request.rule.keywords[0])
}

fn validate_single_extension_request(request: &ClassifierImpactPreviewRequest) -> CoreResult<()> {
    if request.rule.extensions.len() != 1 || !request.rule.keywords.is_empty() {
        return Err(CoreError::config(
            "classifier impact remove extension request is invalid",
        ));
    }
    validate_extension(&request.rule.extensions[0])
}

fn validate_remove_category_request(request: &ClassifierImpactPreviewRequest) -> CoreResult<()> {
    if !request.rule.keywords.is_empty() || !request.rule.extensions.is_empty() {
        return Err(CoreError::config(
            "classifier impact remove category request is invalid",
        ));
    }
    if let Some(replacement) = request.replacement_category.as_deref() {
        validate_target_category(replacement)?;
    }
    Ok(())
}

fn reject_replacement_for_rule_basis(request: &ClassifierImpactPreviewRequest) -> CoreResult<()> {
    if request.replacement_category.is_some() {
        return Err(CoreError::config(
            "classifier impact replacement category is only valid for category removal",
        ));
    }
    Ok(())
}

pub(super) fn validate_target_category(category: &str) -> CoreResult<()> {
    if !is_valid_category_slug(category) {
        return Err(CoreError::config(
            "classifier impact target category is invalid",
        ));
    }
    Ok(())
}

pub(super) fn validate_rule_basis(rule: &ClassifierRule) -> CoreResult<()> {
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
        return Err(CoreError::config(
            "classifier impact rule basis is required",
        ));
    }
    ensure_unique(&rule.keywords, "classifier impact keywords must be unique")?;
    ensure_unique(
        &rule.extensions,
        "classifier impact extensions must be unique",
    )
}

pub(super) fn validate_keyword(keyword: &str) -> CoreResult<()> {
    let trimmed = keyword.trim();
    if trimmed.is_empty()
        || trimmed != keyword
        || trimmed.chars().count() > MAX_KEYWORD_LEN
        || contains_forbidden_rule_character(trimmed)
    {
        return Err(CoreError::config("classifier impact keyword is invalid"));
    }
    Ok(())
}

pub(super) fn validate_extension(extension: &str) -> CoreResult<()> {
    if extension.is_empty()
        || extension.chars().count() > MAX_EXTENSION_LEN
        || extension.starts_with('.')
        || !extension
            .chars()
            .all(|character| character.is_ascii_lowercase() || character.is_ascii_digit())
    {
        return Err(CoreError::config("classifier impact extension is invalid"));
    }
    Ok(())
}

fn validate_priority(priority: i64) -> CoreResult<()> {
    if (MIN_PRIORITY..=MAX_PRIORITY).contains(&priority) {
        Ok(())
    } else {
        Err(CoreError::config("classifier impact priority is invalid"))
    }
}

fn ensure_unique(values: &[String], message: &str) -> CoreResult<()> {
    let mut seen = HashSet::new();
    for value in values {
        if !seen.insert(value.as_str()) {
            return Err(CoreError::config(message));
        }
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
