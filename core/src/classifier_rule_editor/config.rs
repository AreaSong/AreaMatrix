use std::{
    collections::{BTreeMap, HashSet},
    ffi::OsStr,
    fs, io,
    io::Write,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{db, CoreError, CoreResult};

use super::{
    validate_category_slug, validate_description, validate_display_name, validate_extension,
    validate_keyword, validate_naming_template, validate_priority, ClassifierRuleDeleteRequest,
    ClassifierRuleEditorSnapshot, ClassifierRuleRecord, ClassifierRuleUpdate, AREA_MATRIX_DIR,
};

const CLASSIFIER_FILE: &str = "classifier.yaml";
const CLASSIFIER_VERSION: u32 = 1;
const MAX_CATEGORIES: usize = 64;
const DEFAULT_DISPLAY_LOCALE: &str = "en";
const SECONDARY_DISPLAY_LOCALE: &str = "zh-Hans";

fn is_zero_i32(value: &i32) -> bool {
    *value == 0
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct ClassifierConfig {
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

pub(super) fn read_classifier_config(repo: &Path) -> CoreResult<ClassifierConfig> {
    ensure_editor_repo_initialized(repo)?;
    let path = classifier_path(repo);
    ensure_classifier_config_file(&path)?;
    let yaml = fs::read_to_string(&path).map_err(|error| map_read_io_error(error, &path))?;
    let config =
        serde_yaml::from_str(&yaml).map_err(|error| CoreError::config(error.to_string()))?;
    validate_classifier_config(&config)?;
    Ok(config)
}

pub(super) fn snapshot_from_config(
    config: &ClassifierConfig,
    updated_rule_id: Option<String>,
    warning: Option<String>,
) -> ClassifierRuleEditorSnapshot {
    ClassifierRuleEditorSnapshot {
        rules: config
            .categories
            .iter()
            .map(|category| rule_record(category, &config.default))
            .collect(),
        default_rule_id: config.default.clone(),
        updated_rule_id,
        warning,
    }
}

pub(super) fn apply_update(
    config: &mut ClassifierConfig,
    request: &ClassifierRuleUpdate,
) -> CoreResult<String> {
    let index = find_category_index(config, &request.rule_id)?;
    reject_duplicate_slug(config, &request.slug, index)?;
    let previous = config.categories[index].clone();
    reject_unpreviewed_impactful_update(&previous, request)?;

    let category = &mut config.categories[index];
    category.slug = request.slug.clone();
    set_display_name(&mut category.display_name, &request.display_name)?;
    set_description(&mut category.description, &request.description)?;
    category.extensions = request.extensions.clone();
    category.keywords = request.keywords.clone();
    category.priority = request.priority as i32;
    category.naming_template = normalized_template(request.naming_template.as_deref());

    if config.default == previous.slug {
        config.default = request.slug.clone();
    }
    Ok(request.slug.clone())
}

pub(super) fn apply_delete(
    config: &mut ClassifierConfig,
    request: &ClassifierRuleDeleteRequest,
) -> CoreResult<String> {
    let index = find_category_index(config, &request.rule_id)?;
    if config.categories.len() == 1 {
        return Err(CoreError::config(
            "classifier rule editor cannot delete the final category",
        ));
    }
    if config.default == request.rule_id {
        return Err(CoreError::config(
            "classifier rule editor cannot delete the default category",
        ));
    }
    if !request.preview_confirmed {
        return Err(CoreError::config(
            "classifier rule impact preview is required",
        ));
    }
    let replacement = request
        .replacement_category
        .as_deref()
        .ok_or_else(|| CoreError::config("classifier rule replacement category is required"))?;
    if replacement == request.rule_id {
        return Err(CoreError::config(
            "classifier rule replacement category must differ",
        ));
    }
    ensure_category_exists(config, replacement)?;
    config.categories.remove(index);
    Ok(replacement.to_owned())
}

pub(super) fn validate_classifier_config(config: &ClassifierConfig) -> CoreResult<()> {
    if config.version != CLASSIFIER_VERSION
        || config.categories.is_empty()
        || config.categories.len() > MAX_CATEGORIES
    {
        return Err(CoreError::config("classifier schema version is invalid"));
    }
    validate_category_slug(&config.default)?;
    let mut seen = HashSet::new();
    for category in &config.categories {
        validate_category(category, &mut seen)?;
    }
    ensure_category_exists(config, &config.default)
}

pub(super) fn write_classifier_config_atomically(
    repo: &Path,
    config: &ClassifierConfig,
) -> CoreResult<()> {
    let path = classifier_path(repo);
    let content = serde_yaml::to_string(config)
        .map_err(|error| CoreError::config(format!("classifier yaml encode failed: {error}")))?;
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::config("classifier config path is invalid"))?;
    let previous_content = fs::read(&path).map_err(|error| map_read_io_error(error, &path))?;
    let temp_path = temporary_classifier_path(&path)?;

    let write_result =
        write_temp_file(&temp_path, &content).and_then(|()| rename_temp(&temp_path, &path));
    if let Err(error) = write_result {
        return match cleanup_temp_file(&temp_path) {
            Ok(()) => Err(error),
            Err(cleanup_error) => Err(cleanup_error),
        };
    }
    if let Err(error) = sync_directory(parent) {
        restore_classifier_config(parent, &path, &previous_content)?;
        return Err(error);
    }
    Ok(())
}

fn ensure_editor_repo_initialized(repo: &Path) -> CoreResult<()> {
    db::ensure_initialized(repo).map_err(|error| match error {
        CoreError::RepoNotInitialized { .. } | CoreError::InvalidPath { .. } => {
            CoreError::config("classifier rule editor repository is not initialized")
        }
        other => other,
    })
}

fn ensure_classifier_config_file(path: &Path) -> CoreResult<()> {
    match fs::metadata(path) {
        Ok(metadata) if metadata.is_file() => Ok(()),
        Ok(_) => Err(CoreError::io("classifier config io error")),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Err(CoreError::config(
            "classifier rule editor repository is not initialized",
        )),
        Err(error) => Err(map_read_io_error(error, path)),
    }
}

fn classifier_path(repo: &Path) -> PathBuf {
    repo.join(AREA_MATRIX_DIR).join(CLASSIFIER_FILE)
}

fn rule_record(category: &CategoryConfig, default: &str) -> ClassifierRuleRecord {
    ClassifierRuleRecord {
        rule_id: category.slug.clone(),
        slug: category.slug.clone(),
        display_name: localized_text(&category.display_name, &category.slug),
        description: localized_text(&category.description, ""),
        extensions: category.extensions.clone(),
        keywords: category.keywords.clone(),
        priority: i64::from(category.priority),
        naming_template: category
            .naming_template
            .as_ref()
            .filter(|value| !value.is_empty())
            .cloned(),
        is_default: category.slug == default,
    }
}

fn localized_text(values: &BTreeMap<String, String>, fallback: &str) -> String {
    values
        .get(DEFAULT_DISPLAY_LOCALE)
        .or_else(|| values.get(SECONDARY_DISPLAY_LOCALE))
        .or_else(|| values.values().next())
        .cloned()
        .unwrap_or_else(|| fallback.to_owned())
}

fn validate_category(category: &CategoryConfig, seen: &mut HashSet<String>) -> CoreResult<()> {
    validate_category_slug(&category.slug)?;
    if !seen.insert(category.slug.clone()) {
        return Err(CoreError::config("classifier category slug is invalid"));
    }
    validate_locale_values(&category.display_name, validate_display_name)?;
    validate_locale_values(&category.description, validate_description)?;
    validate_category_values(&category.extensions, validate_extension)?;
    validate_category_values(&category.keywords, validate_keyword)?;
    validate_priority(i64::from(category.priority))?;
    validate_naming_template(category.naming_template.as_deref())
}

fn validate_locale_values(
    values: &BTreeMap<String, String>,
    validator: fn(&str) -> CoreResult<()>,
) -> CoreResult<()> {
    for value in values.values() {
        validator(value)?;
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

fn find_category_index(config: &ClassifierConfig, rule_id: &str) -> CoreResult<usize> {
    config
        .categories
        .iter()
        .position(|category| category.slug == rule_id)
        .ok_or_else(|| CoreError::config("classifier rule id does not exist"))
}

fn reject_duplicate_slug(
    config: &ClassifierConfig,
    slug: &str,
    current_index: usize,
) -> CoreResult<()> {
    let duplicate = config
        .categories
        .iter()
        .enumerate()
        .any(|(index, category)| index != current_index && category.slug == slug);
    if duplicate {
        return Err(CoreError::config("classifier rule slug already exists"));
    }
    Ok(())
}

fn reject_unpreviewed_impactful_update(
    previous: &CategoryConfig,
    request: &ClassifierRuleUpdate,
) -> CoreResult<()> {
    let needs_preview = previous.slug != request.slug
        || has_removed_values(&previous.extensions, &request.extensions)
        || has_removed_values(&previous.keywords, &request.keywords);
    if needs_preview && !request.preview_confirmed {
        return Err(CoreError::config(
            "classifier rule impact preview is required",
        ));
    }
    Ok(())
}

fn has_removed_values(previous: &[String], next: &[String]) -> bool {
    previous.iter().any(|value| !next.contains(value))
}

fn set_display_name(values: &mut BTreeMap<String, String>, display_name: &str) -> CoreResult<()> {
    validate_display_name(display_name)?;
    values.clear();
    values.insert(DEFAULT_DISPLAY_LOCALE.to_owned(), display_name.to_owned());
    Ok(())
}

fn set_description(values: &mut BTreeMap<String, String>, description: &str) -> CoreResult<()> {
    validate_description(description)?;
    values.clear();
    if description.is_empty() {
        Ok(())
    } else {
        values.insert(DEFAULT_DISPLAY_LOCALE.to_owned(), description.to_owned());
        Ok(())
    }
}

fn normalized_template(template: Option<&str>) -> Option<String> {
    template
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn ensure_category_exists(config: &ClassifierConfig, slug: &str) -> CoreResult<()> {
    if config
        .categories
        .iter()
        .any(|category| category.slug == slug)
    {
        Ok(())
    } else {
        Err(CoreError::config("classifier category does not exist"))
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
    write_temp_bytes(path, content.as_bytes())
}

fn write_temp_bytes(path: &Path, content: &[u8]) -> CoreResult<()> {
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|error| map_write_io_error(error, path))?;
    file.write_all(content)
        .map_err(|error| map_write_io_error(error, path))?;
    file.sync_all()
        .map_err(|error| map_write_io_error(error, path))
}

fn rename_temp(temp_path: &Path, final_path: &Path) -> CoreResult<()> {
    fs::rename(temp_path, final_path).map_err(|error| map_write_io_error(error, final_path))
}

fn restore_classifier_config(
    parent: &Path,
    path: &Path,
    previous_content: &[u8],
) -> CoreResult<()> {
    let restore_path = temporary_classifier_path(path)?;
    let restore_result = write_temp_bytes(&restore_path, previous_content)
        .and_then(|()| rename_temp(&restore_path, path));
    if let Err(error) = restore_result {
        return match cleanup_temp_file(&restore_path) {
            Ok(()) => Err(error),
            Err(cleanup_error) => Err(cleanup_error),
        };
    }

    // Directory sync errors happen after the active path was replaced, so put
    // the old classifier back before surfacing the failed save.
    sync_directory(parent)
}

fn cleanup_temp_file(path: &Path) -> CoreResult<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(map_write_io_error(error, path)),
    }
}

fn sync_directory(path: &Path) -> CoreResult<()> {
    let directory = fs::File::open(path).map_err(|error| map_read_io_error(error, path))?;
    directory
        .sync_all()
        .map_err(|error| map_read_io_error(error, path))
}

fn map_read_io_error(error: io::Error, path: &Path) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied(path_string(path)),
        _ => CoreError::io("classifier config io error"),
    }
}

fn map_write_io_error(error: io::Error, path: &Path) -> CoreError {
    match error.kind() {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied(path_string(path)),
        _ => CoreError::io("classifier config write failed"),
    }
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}
