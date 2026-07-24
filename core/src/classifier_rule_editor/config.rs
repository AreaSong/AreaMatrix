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
    validate_keyword, validate_naming_template, validate_priority, ClassifierConfigHealth,
    ClassifierLocaleValue, ClassifierRuleCreateRequest, ClassifierRuleDeleteRequest,
    ClassifierRuleEditorSnapshot, ClassifierRuleRecord, ClassifierRuleUpdate, AREA_MATRIX_DIR,
};

const CLASSIFIER_FILE: &str = "classifier.yaml";
const CLASSIFIER_ARCHIVE_DIR: &str = "classifier";
const DEFAULT_CLASSIFIER_YAML: &str = include_str!("../../resources/classifier.yaml");
const CLASSIFIER_VERSION: u32 = 1;
const MAX_CATEGORIES: usize = 64;
const MAX_BACKUP_SEQUENCE: u32 = 999_999;
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

impl ClassifierConfig {
    pub(super) fn category_slugs(&self) -> Vec<String> {
        self.categories
            .iter()
            .map(|category| category.slug.clone())
            .collect()
    }
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

pub(super) enum ClassifierConfigState {
    Valid(ClassifierConfig),
    Missing,
    Unreadable,
    Invalid,
}

pub(super) fn inspect_classifier_config(repo: &Path) -> CoreResult<ClassifierConfigState> {
    ensure_editor_repo_initialized(repo)?;
    let path = classifier_path(repo);
    let metadata = match fs::symlink_metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(ClassifierConfigState::Missing);
        }
        Err(_) => return Ok(ClassifierConfigState::Unreadable),
    };
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Ok(ClassifierConfigState::Unreadable);
    }
    let yaml = match fs::read_to_string(&path) {
        Ok(yaml) => yaml,
        Err(_) => return Ok(ClassifierConfigState::Unreadable),
    };
    let config = match serde_yaml::from_str(&yaml) {
        Ok(config) => config,
        Err(_) => return Ok(ClassifierConfigState::Invalid),
    };
    match validate_classifier_config(&config) {
        Ok(()) => Ok(ClassifierConfigState::Valid(config)),
        Err(_) => Ok(ClassifierConfigState::Invalid),
    }
}

pub(super) fn read_classifier_config(repo: &Path) -> CoreResult<ClassifierConfig> {
    match inspect_classifier_config(repo)? {
        ClassifierConfigState::Valid(config) => Ok(config),
        ClassifierConfigState::Missing => Err(CoreError::config("classifier config is missing")),
        ClassifierConfigState::Unreadable => Err(CoreError::io("classifier config is unreadable")),
        ClassifierConfigState::Invalid => Err(CoreError::config("classifier config is invalid")),
    }
}

pub(super) fn snapshot_from_config(
    config: &ClassifierConfig,
    repository_locale_policy: String,
    editing_locale: Option<crate::ContentLocale>,
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
        repository_locale_policy,
        editing_locale,
        health: ClassifierConfigHealth::Valid,
        recovery_actions: Vec::new(),
        warning,
    }
}

pub(super) fn apply_create(
    config: &mut ClassifierConfig,
    request: &ClassifierRuleCreateRequest,
) -> CoreResult<String> {
    reject_duplicate_new_slug(config, &request.slug)?;
    let category = category_from_create_request(request)?;
    config.categories.push(category);
    Ok(request.slug.clone())
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
    set_display_name(
        &mut category.display_name,
        request.editing_locale.as_str(),
        &request.display_name,
    )?;
    set_description(
        &mut category.description,
        request.editing_locale.as_str(),
        &request.description,
    )?;
    category.extensions = request.extensions.clone();
    category.keywords = request.keywords.clone();
    category.priority = request.priority as i32;
    category.naming_template = normalized_template(request.naming_template.as_deref());

    if config.default == previous.slug {
        config.default = request.slug.clone();
    }
    Ok(request.slug.clone())
}

pub(super) fn validate_observed_update(
    config: &ClassifierConfig,
    request: &ClassifierRuleUpdate,
) -> CoreResult<()> {
    let index = config
        .categories
        .iter()
        .position(|category| category.slug == request.rule_id)
        .ok_or_else(|| CoreError::conflict("classifier_rule_observed_state"))?;
    let current = &config.categories[index];
    let locale = request.editing_locale.as_str();
    let current_display_name = current
        .display_name
        .get(locale)
        .map(String::as_str)
        .unwrap_or("");
    let current_description = current
        .description
        .get(locale)
        .map(String::as_str)
        .unwrap_or("");
    let observed = &request.observed;
    let matches = current.slug == observed.slug
        && current_display_name == observed.display_name
        && current_description == observed.description
        && current.extensions == observed.extensions
        && current.keywords == observed.keywords
        && i64::from(current.priority) == observed.priority
        && current.naming_template == observed.naming_template;
    if matches {
        Ok(())
    } else {
        Err(CoreError::conflict("classifier_rule_observed_state"))
    }
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
    let content = serde_yaml::to_string(config)
        .map_err(|error| CoreError::config(format!("classifier yaml encode failed: {error}")))?;
    let previous_content = read_regular_classifier_bytes(repo)?;
    create_numbered_classifier_backup(repo, &previous_content)?;
    replace_classifier_bytes(repo, content.as_bytes(), Some(&previous_content), false)
}

pub(super) fn write_classifier_yaml_atomically(repo: &Path, content: &[u8]) -> CoreResult<()> {
    let config: ClassifierConfig = serde_yaml::from_slice(content)
        .map_err(|error| CoreError::config(format!("classifier yaml encode failed: {error}")))?;
    validate_classifier_config(&config)?;
    let previous_content = read_regular_classifier_bytes(repo)?;
    create_numbered_classifier_backup(repo, &previous_content)?;
    replace_classifier_bytes(repo, content, Some(&previous_content), false)
}

pub(super) fn create_default_classifier(repo: &Path) -> CoreResult<()> {
    match inspect_classifier_config(repo)? {
        ClassifierConfigState::Missing => {}
        _ => {
            return Err(CoreError::config(
                "classifier create-default action is unavailable",
            ))
        }
    }
    let content = verified_default_classifier_bytes()?;
    replace_classifier_bytes(repo, &content, None, true)
}

pub(super) fn restore_default_classifier(repo: &Path) -> CoreResult<()> {
    match inspect_classifier_config(repo)? {
        ClassifierConfigState::Invalid => {}
        _ => {
            return Err(CoreError::config(
                "classifier restore-default action is unavailable",
            ))
        }
    }
    let previous_content = read_regular_classifier_bytes(repo)?;
    let content = verified_default_classifier_bytes()?;
    create_numbered_classifier_backup(repo, &previous_content)?;
    replace_classifier_bytes(repo, &content, Some(&previous_content), false)
}

pub(super) fn restore_last_valid_classifier(repo: &Path) -> CoreResult<()> {
    match inspect_classifier_config(repo)? {
        ClassifierConfigState::Invalid => {}
        _ => {
            return Err(CoreError::config(
                "classifier restore-last-valid action is unavailable",
            ));
        }
    }
    let restored_content = newest_valid_classifier_backup(repo)?
        .ok_or_else(|| CoreError::config("classifier last-valid backup is unavailable"))?;
    let previous_content = read_regular_classifier_bytes(repo)?;
    create_numbered_classifier_backup(repo, &previous_content)?;
    replace_classifier_bytes(repo, &restored_content, Some(&previous_content), false)
}

pub(super) fn has_valid_classifier_backup(repo: &Path) -> CoreResult<bool> {
    Ok(newest_valid_classifier_backup(repo)?.is_some())
}

fn ensure_editor_repo_initialized(repo: &Path) -> CoreResult<()> {
    db::ensure_initialized(repo).map_err(|error| match error {
        CoreError::RepoNotInitialized { .. } | CoreError::InvalidPath { .. } => {
            CoreError::config("classifier rule editor repository is not initialized")
        }
        other => other,
    })
}

fn classifier_path(repo: &Path) -> PathBuf {
    repo.join(AREA_MATRIX_DIR).join(CLASSIFIER_FILE)
}

fn classifier_archive_dir(repo: &Path) -> PathBuf {
    repo.join(AREA_MATRIX_DIR)
        .join("archives")
        .join(CLASSIFIER_ARCHIVE_DIR)
}

fn verified_default_classifier_bytes() -> CoreResult<Vec<u8>> {
    let config: ClassifierConfig = serde_yaml::from_str(DEFAULT_CLASSIFIER_YAML)
        .map_err(|_| CoreError::internal("embedded classifier config is invalid"))?;
    validate_classifier_config(&config)
        .map_err(|_| CoreError::internal("embedded classifier config is invalid"))?;
    Ok(DEFAULT_CLASSIFIER_YAML.as_bytes().to_vec())
}

fn read_regular_classifier_bytes(repo: &Path) -> CoreResult<Vec<u8>> {
    let path = classifier_path(repo);
    ensure_regular_file(&path)?;
    fs::read(&path).map_err(|error| map_read_io_error(error, &path))
}

fn ensure_regular_file(path: &Path) -> CoreResult<()> {
    let metadata = fs::symlink_metadata(path).map_err(|error| map_read_io_error(error, path))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(CoreError::io(
            "classifier config path is not a regular file",
        ));
    }
    Ok(())
}

fn ensure_regular_directory(path: &Path) -> CoreResult<()> {
    let metadata = fs::symlink_metadata(path).map_err(|error| map_read_io_error(error, path))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(CoreError::io(
            "classifier archive path is not a regular directory",
        ));
    }
    Ok(())
}

fn prepare_classifier_archive_dir(repo: &Path) -> CoreResult<PathBuf> {
    let metadata_dir = repo.join(AREA_MATRIX_DIR);
    let archives_dir = metadata_dir.join("archives");
    ensure_regular_directory(&metadata_dir)?;
    ensure_regular_directory(&archives_dir)?;
    let archive_dir = classifier_archive_dir(repo);
    match fs::symlink_metadata(&archive_dir) {
        Ok(_) => ensure_regular_directory(&archive_dir)?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            fs::create_dir(&archive_dir)
                .map_err(|error| map_write_io_error(error, &archive_dir))?;
            sync_directory(&archives_dir)?;
        }
        Err(error) => return Err(map_read_io_error(error, &archive_dir)),
    }
    Ok(archive_dir)
}

fn create_numbered_classifier_backup(repo: &Path, content: &[u8]) -> CoreResult<PathBuf> {
    let archive_dir = prepare_classifier_archive_dir(repo)?;
    for sequence in 1..=MAX_BACKUP_SEQUENCE {
        let path = archive_dir.join(format!("{CLASSIFIER_FILE}.{sequence:06}.bak"));
        let mut file = match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
        {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(map_write_io_error(error, &path)),
        };
        let result = file
            .write_all(content)
            .and_then(|()| file.sync_all())
            .map_err(|error| map_write_io_error(error, &path));
        if let Err(error) = result {
            let _ = fs::remove_file(&path);
            return Err(error);
        }
        sync_directory(&archive_dir)?;
        return Ok(path);
    }
    Err(CoreError::io("classifier backup sequence is exhausted"))
}

fn newest_valid_classifier_backup(repo: &Path) -> CoreResult<Option<Vec<u8>>> {
    let archive_dir = classifier_archive_dir(repo);
    match fs::symlink_metadata(&archive_dir) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(map_read_io_error(error, &archive_dir)),
        Ok(_) => ensure_regular_directory(&archive_dir)?,
    }
    let mut candidates = Vec::new();
    for entry in
        fs::read_dir(&archive_dir).map_err(|error| map_read_io_error(error, &archive_dir))?
    {
        let entry = entry.map_err(|error| map_read_io_error(error, &archive_dir))?;
        let name = entry.file_name();
        let Some(sequence) = classifier_backup_sequence(&name) else {
            continue;
        };
        let path = entry.path();
        ensure_regular_file(&path)?;
        candidates.push((sequence, path));
    }
    candidates.sort_by(|left, right| right.0.cmp(&left.0));
    for (_, path) in candidates {
        let content = fs::read(&path).map_err(|error| map_read_io_error(error, &path))?;
        let Ok(config) = serde_yaml::from_slice::<ClassifierConfig>(&content) else {
            continue;
        };
        if validate_classifier_config(&config).is_ok() {
            return Ok(Some(content));
        }
    }
    Ok(None)
}

fn classifier_backup_sequence(name: &OsStr) -> Option<u32> {
    let name = name.to_str()?;
    let middle = name
        .strip_prefix("classifier.yaml.")?
        .strip_suffix(".bak")?;
    if middle.len() != 6 || !middle.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    middle.parse().ok()
}

fn rule_record(category: &CategoryConfig, default: &str) -> ClassifierRuleRecord {
    ClassifierRuleRecord {
        rule_id: category.slug.clone(),
        slug: category.slug.clone(),
        display_names: locale_values(&category.display_name),
        descriptions: locale_values(&category.description),
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

fn locale_values(values: &BTreeMap<String, String>) -> Vec<ClassifierLocaleValue> {
    values
        .iter()
        .map(|(locale, value)| ClassifierLocaleValue {
            locale: locale.clone(),
            value: value.clone(),
        })
        .collect()
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

fn category_from_create_request(
    request: &ClassifierRuleCreateRequest,
) -> CoreResult<CategoryConfig> {
    let mut display_name = BTreeMap::new();
    let mut description = BTreeMap::new();
    set_display_name(
        &mut display_name,
        request.editing_locale.as_str(),
        &request.display_name,
    )?;
    set_description(
        &mut description,
        request.editing_locale.as_str(),
        &request.description,
    )?;
    Ok(CategoryConfig {
        slug: request.slug.clone(),
        display_name,
        description,
        extensions: request.extensions.clone(),
        keywords: request.keywords.clone(),
        priority: request.priority as i32,
        naming_template: normalized_template(request.naming_template.as_deref()),
    })
}

fn reject_duplicate_new_slug(config: &ClassifierConfig, slug: &str) -> CoreResult<()> {
    if config
        .categories
        .iter()
        .any(|category| category.slug == slug)
    {
        Err(CoreError::config("classifier rule slug already exists"))
    } else {
        Ok(())
    }
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

fn set_display_name(
    values: &mut BTreeMap<String, String>,
    locale: &str,
    display_name: &str,
) -> CoreResult<()> {
    validate_display_name(display_name)?;
    values.insert(locale.to_owned(), display_name.to_owned());
    Ok(())
}

fn set_description(
    values: &mut BTreeMap<String, String>,
    locale: &str,
    description: &str,
) -> CoreResult<()> {
    validate_description(description)?;
    if description.is_empty() {
        values.remove(locale);
        Ok(())
    } else {
        values.insert(locale.to_owned(), description.to_owned());
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

fn replace_classifier_bytes(
    repo: &Path,
    content: &[u8],
    previous_content: Option<&[u8]>,
    create_only: bool,
) -> CoreResult<()> {
    let path = classifier_path(repo);
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::config("classifier config path is invalid"))?;
    ensure_regular_directory(parent)?;
    validate_active_precondition(&path, previous_content, create_only)?;
    let temp_path = temporary_classifier_path(&path)?;
    if let Err(error) = write_temp_bytes(&temp_path, content) {
        cleanup_temp_file(&temp_path)?;
        return Err(error);
    }

    let commit_result = if create_only {
        fs::hard_link(&temp_path, &path).map_err(|error| map_write_io_error(error, &path))
    } else {
        fs::rename(&temp_path, &path).map_err(|error| map_write_io_error(error, &path))
    };
    if let Err(error) = commit_result {
        cleanup_temp_file(&temp_path)?;
        return Err(error);
    }
    if create_only {
        cleanup_temp_file(&temp_path)?;
    }
    if let Err(error) = sync_directory(parent) {
        rollback_classifier_replace(parent, &path, content, previous_content)?;
        return Err(error);
    }
    Ok(())
}

fn validate_active_precondition(
    path: &Path,
    previous_content: Option<&[u8]>,
    create_only: bool,
) -> CoreResult<()> {
    if create_only {
        return match fs::symlink_metadata(path) {
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(map_read_io_error(error, path)),
            Ok(_) => Err(CoreError::conflict(
                "classifier config appeared during recovery",
            )),
        };
    }
    ensure_regular_file(path)?;
    let current = fs::read(path).map_err(|error| map_read_io_error(error, path))?;
    if previous_content.is_some_and(|previous| previous == current) {
        Ok(())
    } else {
        Err(CoreError::conflict(
            "classifier config changed during atomic save",
        ))
    }
}

fn rollback_classifier_replace(
    parent: &Path,
    path: &Path,
    committed_content: &[u8],
    previous_content: Option<&[u8]>,
) -> CoreResult<()> {
    let current = fs::read(path).map_err(|error| map_read_io_error(error, path))?;
    if current != committed_content {
        return Err(CoreError::conflict(
            "classifier config changed before rollback",
        ));
    }
    if let Some(previous) = previous_content {
        restore_classifier_config(parent, path, previous)
    } else {
        fs::remove_file(path).map_err(|error| map_write_io_error(error, path))?;
        sync_directory(parent)
    }
}

fn restore_classifier_config(
    parent: &Path,
    path: &Path,
    previous_content: &[u8],
) -> CoreResult<()> {
    let restore_path = temporary_classifier_path(path)?;
    let restore_result = write_temp_bytes(&restore_path, previous_content).and_then(|()| {
        fs::rename(&restore_path, path).map_err(|error| map_write_io_error(error, path))
    });
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
