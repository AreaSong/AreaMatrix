//! C2-13 classifier rule save types and persistence.

use std::{
    collections::{BTreeMap, HashSet},
    ffi::OsStr,
    fs, io,
    io::Write,
    path::{Component, Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{db, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_CATEGORY_SLUG_LEN: usize = 32;
const MAX_EXTENSION_LEN: usize = 16;
const MAX_KEYWORD_LEN: usize = 32;
const MIN_PRIORITY: i64 = -1000;
const MAX_PRIORITY: i64 = 1000;
const CLASSIFIER_FILE: &str = "classifier.yaml";
const MIN_BROAD_EXTENSION_COUNT: usize = 1;

fn is_zero_i32(value: &i32) -> bool {
    *value == 0
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ClassifierConfig {
    version: u32,
    default: String,
    categories: Vec<CategoryConfig>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct CategoryConfig {
    slug: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    display_name: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    description: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    extensions: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    keywords: Vec<String>,
    #[serde(default, skip_serializing_if = "is_zero_i32")]
    priority: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    naming_template: Option<String>,
}

/// Classifier rule payload shared by S2-17, S2-18, and C2-13.
///
/// The shape maps directly to the supported `classifier.yaml` fields for one
/// target category: `keywords`, `extensions`, `priority`, and preview
/// confirmation state. It intentionally does not model path, source-folder,
/// enabled flags, compound AND rules, or history-application state because
/// those are outside the Stage 2 save-rule contract.
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
    /// True after S2-17/S2-18 has confirmed the required impact preview.
    pub preview_confirmed: bool,
}

/// Saves one C2-13 classifier rule request.
///
/// The save appends independent keyword and extension basis values to an
/// existing classifier category in `.areamatrix/classifier.yaml`, updates that
/// category priority, and returns the persisted rule summary. It does not
/// reclassify, move, rename, delete, preview impact, or touch user files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, target
/// categories, rule basis, priority values, malformed classifier config,
/// duplicate rules, or over-broad extension-only rules that still need preview
/// confirmation.
/// Returns `CoreError::PermissionDenied { path }` for blocked classifier config
/// writes and `CoreError::Io { message }` for read or atomic write failures.
pub fn save_classifier_rule(repo_path: String, rule: ClassifierRule) -> CoreResult<ClassifierRule> {
    let repo = validate_classifier_rule_request(&repo_path, &rule)?;
    let classifier_path = repo.join(AREA_MATRIX_DIR).join(CLASSIFIER_FILE);
    let mut config = read_classifier_config(&classifier_path)?;
    let category = target_category_mut(&mut config, &rule.target_category)?;
    reject_duplicate_rule(category, &rule)?;
    reject_unpreviewed_broad_rule(&rule)?;
    append_rule_basis(category, &rule);
    category.priority = rule.priority as i32;
    validate_classifier_config(&config)?;
    write_classifier_config_atomically(&classifier_path, &config)?;
    Ok(rule)
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
    ensure_rule_repo_initialized(&repo)?;
    ensure_classifier_config_file(&repo.join(AREA_MATRIX_DIR).join(CLASSIFIER_FILE))?;
    Ok(repo)
}

fn ensure_rule_repo_initialized(repo: &Path) -> CoreResult<()> {
    db::ensure_initialized(repo).map_err(|error| match error {
        CoreError::RepoNotInitialized { .. } | CoreError::InvalidPath { .. } => {
            CoreError::config("classifier rule repository is not initialized")
        }
        other => other,
    })
}

fn ensure_classifier_config_file(path: &Path) -> CoreResult<()> {
    match fs::metadata(path) {
        Ok(metadata) if metadata.is_file() => Ok(()),
        Ok(_) => Err(CoreError::io("classifier config io error")),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Err(CoreError::config(
            "classifier rule repository is not initialized",
        )),
        Err(error) => Err(map_read_io_error(error)),
    }
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
    let mut seen: HashSet<&str> = HashSet::new();
    for value in values {
        if !seen.insert(value.as_str()) {
            return Err(CoreError::config(message));
        }
    }
    Ok(())
}

fn read_classifier_config(path: &Path) -> CoreResult<ClassifierConfig> {
    let yaml = fs::read_to_string(path).map_err(map_read_io_error)?;
    let config =
        serde_yaml::from_str(&yaml).map_err(|error| CoreError::config(error.to_string()))?;
    validate_classifier_config(&config)?;
    Ok(config)
}

fn target_category_mut<'a>(
    config: &'a mut ClassifierConfig,
    target_category: &str,
) -> CoreResult<&'a mut CategoryConfig> {
    config
        .categories
        .iter_mut()
        .find(|category| category.slug == target_category)
        .ok_or_else(|| CoreError::config("classifier rule target category does not exist"))
}

fn reject_duplicate_rule(category: &CategoryConfig, rule: &ClassifierRule) -> CoreResult<()> {
    if rule
        .keywords
        .iter()
        .any(|keyword| category.keywords.iter().any(|existing| existing == keyword))
        || rule.extensions.iter().any(|extension| {
            category
                .extensions
                .iter()
                .any(|existing| existing == extension)
        })
    {
        return Err(CoreError::config("classifier rule already exists"));
    }
    Ok(())
}

fn reject_unpreviewed_broad_rule(rule: &ClassifierRule) -> CoreResult<()> {
    if rule.keywords.is_empty()
        && rule.extensions.len() >= MIN_BROAD_EXTENSION_COUNT
        && !rule.preview_confirmed
    {
        return Err(CoreError::config(
            "classifier rule impact preview is required",
        ));
    }
    Ok(())
}

fn append_rule_basis(category: &mut CategoryConfig, rule: &ClassifierRule) {
    category.keywords.extend(rule.keywords.iter().cloned());
    category.extensions.extend(rule.extensions.iter().cloned());
}

fn validate_classifier_config(config: &ClassifierConfig) -> CoreResult<()> {
    if config.version != 1 {
        return Err(CoreError::config("classifier schema version is invalid"));
    }
    if config.categories.is_empty() || config.categories.len() > 64 {
        return Err(CoreError::config("classifier categories are invalid"));
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
    validate_locale_values(
        &category.display_name,
        1,
        32,
        "classifier display name is invalid",
    )?;
    validate_locale_values(
        &category.description,
        0,
        200,
        "classifier description is invalid",
    )?;
    validate_category_extensions(&category.extensions)?;
    validate_category_keywords(&category.keywords)?;
    validate_priority(i64::from(category.priority))?;
    if category
        .naming_template
        .as_ref()
        .is_some_and(|value| value.chars().count() > 200)
    {
        return Err(CoreError::config("classifier naming template is invalid"));
    }
    Ok(())
}

fn validate_locale_values(
    values: &BTreeMap<String, String>,
    min_len: usize,
    max_len: usize,
    message: &str,
) -> CoreResult<()> {
    if values.values().any(|value| {
        let len = value.chars().count();
        len < min_len || len > max_len
    }) {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn validate_category_extensions(extensions: &[String]) -> CoreResult<()> {
    ensure_unique(extensions, "classifier category extensions must be unique")?;
    for extension in extensions {
        validate_extension(extension)?;
    }
    Ok(())
}

fn validate_category_keywords(keywords: &[String]) -> CoreResult<()> {
    ensure_unique(keywords, "classifier category keywords must be unique")?;
    for keyword in keywords {
        validate_keyword(keyword)?;
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

fn write_classifier_config_atomically(path: &Path, config: &ClassifierConfig) -> CoreResult<()> {
    let content = serde_yaml::to_string(config)
        .map_err(|error| CoreError::config(format!("classifier yaml encode failed: {error}")))?;
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::config("classifier config path is invalid"))?;
    let temp_path = temporary_classifier_path(path)?;
    let result = write_temp_file(&temp_path, &content).and_then(|()| rename_temp(&temp_path, path));
    match result {
        Ok(()) => sync_directory(parent),
        Err(error) => {
            cleanup_temp_file(&temp_path)?;
            Err(error)
        }
    }
}

fn temporary_classifier_path(path: &Path) -> CoreResult<PathBuf> {
    let file_name = path
        .file_name()
        .and_then(OsStr::to_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| CoreError::config("classifier config path is invalid"))?;
    Ok(path.with_file_name(format!(".{file_name}.{}.tmp", Uuid::new_v4())))
}

fn write_temp_file(path: &Path, content: &str) -> CoreResult<()> {
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(map_write_io_error)?;
    file.write_all(content.as_bytes())
        .map_err(map_write_io_error)?;
    file.sync_all().map_err(map_write_io_error)
}

fn rename_temp(temp_path: &Path, final_path: &Path) -> CoreResult<()> {
    fs::rename(temp_path, final_path).map_err(map_write_io_error)
}

fn cleanup_temp_file(path: &Path) -> CoreResult<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(map_write_io_error(error)),
    }
}

fn sync_directory(path: &Path) -> CoreResult<()> {
    let directory = fs::File::open(path).map_err(map_read_io_error)?;
    directory.sync_all().map_err(map_read_io_error)
}

fn map_read_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        _ => CoreError::io("classifier config io error"),
    }
}

fn map_write_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        _ => CoreError::io("classifier config write failed"),
    }
}
