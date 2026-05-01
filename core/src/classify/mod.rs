//! Rule-based classification preview for import flows.

use std::{
    collections::{HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
};

use serde::Deserialize;
use unicode_normalization::UnicodeNormalization;

use crate::{ClassifyReason, ClassifyResult, CoreError, CoreResult};

const DEFAULT_CLASSIFIER_YAML: &str = include_str!("../../resources/classifier.yaml");
const KEYWORD_CONFIDENCE: f32 = 0.9;
const EXTENSION_CONFIDENCE: f32 = 0.7;
const DEFAULT_CONFIDENCE: f32 = 0.0;
const MAX_CATEGORIES: usize = 64;
const MAX_SLUG_LEN: usize = 32;
const MAX_EXTENSION_LEN: usize = 16;
const MAX_KEYWORD_LEN: usize = 32;
const MAX_DISPLAY_NAME_LEN: usize = 32;
const MAX_DESCRIPTION_LEN: usize = 200;
const MAX_NAMING_TEMPLATE_LEN: usize = 200;

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ClassifierConfig {
    version: u32,
    default: String,
    categories: Vec<CategoryConfig>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CategoryConfig {
    slug: String,
    #[serde(default)]
    display_name: HashMap<String, String>,
    #[serde(default)]
    description: HashMap<String, String>,
    #[serde(default)]
    extensions: Vec<String>,
    #[serde(default)]
    keywords: Vec<String>,
    #[serde(default)]
    priority: i32,
    #[serde(default)]
    naming_template: Option<String>,
}

#[derive(Debug)]
struct NormalizedName {
    lowered: String,
    tokens: Vec<String>,
    extension: Option<String>,
}

#[derive(Debug)]
struct KeywordHit<'a> {
    category: &'a CategoryConfig,
    keyword_len: usize,
    category_index: usize,
}

#[derive(Debug)]
struct ExtensionHit<'a> {
    category: &'a CategoryConfig,
    category_index: usize,
}

pub(crate) fn predict_category(repo_path: String, filename: String) -> CoreResult<ClassifyResult> {
    let repo = normalize_repo_path(&repo_path)?;
    let original_name = validate_filename(&filename)?;
    let config = load_classifier_config(&repo)?;
    let normalized = normalize_name(original_name);

    if let Some(hit) = match_keyword(&config, &normalized) {
        return Ok(result_for(
            hit.category,
            original_name,
            ClassifyReason::Keyword,
            KEYWORD_CONFIDENCE,
        ));
    }

    if let Some(hit) = match_extension(&config, &normalized) {
        return Ok(result_for(
            hit.category,
            original_name,
            ClassifyReason::Extension,
            EXTENSION_CONFIDENCE,
        ));
    }

    Ok(ClassifyResult {
        category: config.default,
        suggested_name: original_name.to_owned(),
        reason: ClassifyReason::Default,
        confidence: DEFAULT_CONFIDENCE,
    })
}

fn normalize_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::Config);
    }
    Ok(PathBuf::from(repo_path))
}

fn validate_filename(filename: &str) -> CoreResult<&str> {
    let trimmed = filename.trim();
    if trimmed.is_empty() {
        return Err(CoreError::Config);
    }
    Ok(trimmed)
}

fn load_classifier_config(repo: &Path) -> CoreResult<ClassifierConfig> {
    let yaml = match fs::read_to_string(repo.join(".areamatrix/classifier.yaml")) {
        Ok(content) => content,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            DEFAULT_CLASSIFIER_YAML.to_owned()
        }
        Err(_) => return Err(CoreError::Classify),
    };

    let config: ClassifierConfig = serde_yaml::from_str(&yaml).map_err(|_| CoreError::Config)?;
    validate_classifier_config(config)
}

fn validate_classifier_config(config: ClassifierConfig) -> CoreResult<ClassifierConfig> {
    if config.version != 1
        || config.categories.is_empty()
        || config.categories.len() > MAX_CATEGORIES
    {
        return Err(CoreError::Config);
    }

    let mut seen = HashSet::new();
    for category in &config.categories {
        validate_category(category, &mut seen)?;
    }

    if !config
        .categories
        .iter()
        .any(|category| category.slug == config.default)
    {
        return Err(CoreError::Config);
    }

    Ok(config)
}

fn validate_category(category: &CategoryConfig, seen: &mut HashSet<String>) -> CoreResult<()> {
    if !is_valid_slug(&category.slug) || !seen.insert(category.slug.clone()) {
        return Err(CoreError::Config);
    }

    validate_display_names(category)?;
    validate_descriptions(category)?;
    validate_extensions(category)?;
    validate_keywords(category)?;
    validate_priority(category.priority)?;
    validate_naming_template(category)?;

    Ok(())
}

fn validate_display_names(category: &CategoryConfig) -> CoreResult<()> {
    if category
        .display_name
        .values()
        .any(|value| value.is_empty() || value.chars().count() > MAX_DISPLAY_NAME_LEN)
    {
        return Err(CoreError::Config);
    }

    Ok(())
}

fn validate_descriptions(category: &CategoryConfig) -> CoreResult<()> {
    if category
        .description
        .values()
        .any(|value| value.chars().count() > MAX_DESCRIPTION_LEN)
    {
        return Err(CoreError::Config);
    }

    Ok(())
}

fn validate_extensions(category: &CategoryConfig) -> CoreResult<()> {
    let mut seen = HashSet::new();
    for extension in &category.extensions {
        if !is_valid_extension(extension) || !seen.insert(extension.as_str()) {
            return Err(CoreError::Config);
        }
    }
    Ok(())
}

fn validate_keywords(category: &CategoryConfig) -> CoreResult<()> {
    let mut seen = HashSet::new();
    for keyword in &category.keywords {
        if keyword.trim().is_empty()
            || keyword.chars().count() > MAX_KEYWORD_LEN
            || !seen.insert(keyword.as_str())
        {
            return Err(CoreError::Config);
        }
    }
    Ok(())
}

fn validate_priority(priority: i32) -> CoreResult<()> {
    if (-1000..=1000).contains(&priority) {
        Ok(())
    } else {
        Err(CoreError::Config)
    }
}

fn validate_naming_template(category: &CategoryConfig) -> CoreResult<()> {
    if category
        .naming_template
        .as_ref()
        .is_some_and(|template| template.chars().count() > MAX_NAMING_TEMPLATE_LEN)
    {
        return Err(CoreError::Config);
    }
    Ok(())
}

fn is_valid_slug(slug: &str) -> bool {
    let mut chars = slug.chars();
    match chars.next() {
        Some(first) if first.is_ascii_lowercase() => {}
        _ => return false,
    }

    slug.chars().count() <= MAX_SLUG_LEN
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
}

fn is_valid_extension(extension: &str) -> bool {
    !extension.is_empty()
        && extension.chars().count() <= MAX_EXTENSION_LEN
        && extension
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
}

fn normalize_name(name: &str) -> NormalizedName {
    let lowered: String = name.nfkc().collect::<String>().to_lowercase();
    let extension = Path::new(&lowered)
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_owned);
    let tokens = split_tokens(&lowered);

    NormalizedName {
        lowered,
        tokens,
        extension,
    }
}

fn split_tokens(text: &str) -> Vec<String> {
    text.split(is_separator)
        .filter(|token| !token.is_empty())
        .map(str::to_owned)
        .collect()
}

fn is_separator(character: char) -> bool {
    matches!(
        character,
        ' ' | '_' | '-' | '.' | '\t' | '/' | '\\' | '(' | ')' | '[' | ']'
    )
}

fn match_keyword<'a>(
    config: &'a ClassifierConfig,
    normalized: &NormalizedName,
) -> Option<KeywordHit<'a>> {
    config
        .categories
        .iter()
        .enumerate()
        .flat_map(|(category_index, category)| {
            category.keywords.iter().filter_map(move |keyword| {
                let normalized_keyword = normalize_keyword(keyword);
                keyword_matches(normalized, &normalized_keyword).then_some(KeywordHit {
                    category,
                    keyword_len: normalized_keyword.chars().count(),
                    category_index,
                })
            })
        })
        .min_by(compare_keyword_hits)
}

fn normalize_keyword(keyword: &str) -> String {
    keyword.nfkc().collect::<String>().to_lowercase()
}

fn keyword_matches(name: &NormalizedName, keyword: &str) -> bool {
    if keyword.chars().any(is_cjk) {
        return name.lowered.contains(keyword);
    }
    name.tokens.iter().any(|token| token == keyword)
}

fn is_cjk(character: char) -> bool {
    matches!(
        character,
        '\u{4E00}'..='\u{9FFF}'
            | '\u{3400}'..='\u{4DBF}'
            | '\u{F900}'..='\u{FAFF}'
            | '\u{3040}'..='\u{309F}'
            | '\u{30A0}'..='\u{30FF}'
            | '\u{AC00}'..='\u{D7AF}'
    )
}

fn compare_keyword_hits(left: &KeywordHit<'_>, right: &KeywordHit<'_>) -> std::cmp::Ordering {
    right
        .category
        .priority
        .cmp(&left.category.priority)
        .then_with(|| right.keyword_len.cmp(&left.keyword_len))
        .then_with(|| left.category_index.cmp(&right.category_index))
}

fn match_extension<'a>(
    config: &'a ClassifierConfig,
    normalized: &NormalizedName,
) -> Option<ExtensionHit<'a>> {
    let extension = normalized.extension.as_ref()?;

    config
        .categories
        .iter()
        .enumerate()
        .filter(|(_, category)| {
            category
                .extensions
                .iter()
                .any(|candidate| candidate == extension)
        })
        .map(|(category_index, category)| ExtensionHit {
            category,
            category_index,
        })
        .min_by(compare_extension_hits)
}

fn compare_extension_hits(left: &ExtensionHit<'_>, right: &ExtensionHit<'_>) -> std::cmp::Ordering {
    right
        .category
        .priority
        .cmp(&left.category.priority)
        .then_with(|| left.category_index.cmp(&right.category_index))
}

fn result_for(
    category: &CategoryConfig,
    original_name: &str,
    reason: ClassifyReason,
    confidence: f32,
) -> ClassifyResult {
    ClassifyResult {
        category: category.slug.clone(),
        suggested_name: suggested_name(category, original_name),
        reason,
        confidence,
    }
}

fn suggested_name(category: &CategoryConfig, original_name: &str) -> String {
    let Some(template) = category.naming_template.as_deref() else {
        return original_name.to_owned();
    };
    if template.is_empty() {
        return original_name.to_owned();
    }

    render_template(template, original_name, &category.slug)
}

fn render_template(template: &str, original_name: &str, slug: &str) -> String {
    let path = Path::new(original_name);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or(original_name);
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_owned)
        .unwrap_or_default();
    let date = chrono::Local::now().format("%Y-%m-%d").to_string();
    let date_iso = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);

    template
        .replace("{original}", original_name)
        .replace("{stem}", stem)
        .replace("{ext}", &extension)
        .replace("{date}", &date)
        .replace("{date_iso}", &date_iso)
        .replace("{slug}", slug)
}
