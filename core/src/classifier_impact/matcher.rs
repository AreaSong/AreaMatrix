use std::path::Path;

use unicode_normalization::UnicodeNormalization;

use crate::ClassifierRule;

use super::{config::CategoryConfig, config::ClassifierConfig, RuleImpactMatchReason};

#[derive(Debug)]
struct NormalizedName {
    lowered: String,
    tokens: Vec<String>,
    extension: Option<String>,
}

pub(super) fn match_reasons(rule: &ClassifierRule, filename: &str) -> Vec<RuleImpactMatchReason> {
    let normalized = normalize_name(filename);
    let mut reasons = Vec::new();
    if rule
        .keywords
        .iter()
        .any(|keyword| keyword_matches(&normalized, &normalize_keyword(keyword)))
    {
        reasons.push(RuleImpactMatchReason::Keyword);
    }
    if normalized.extension.as_ref().is_some_and(|extension| {
        rule.extensions
            .iter()
            .any(|candidate| candidate == extension)
    }) {
        reasons.push(RuleImpactMatchReason::Extension);
    }
    reasons
}

pub(super) fn classify_after_removed_keyword(
    config: &ClassifierConfig,
    target_category: &str,
    removed_keyword: &str,
    filename: &str,
) -> String {
    classify_with_removed_basis(config, filename, |category, value, _| {
        category.slug == target_category && value == removed_keyword
    })
}

pub(super) fn classify_after_removed_extension(
    config: &ClassifierConfig,
    target_category: &str,
    removed_extension: &str,
    filename: &str,
) -> String {
    classify_with_removed_basis(config, filename, |category, _, value| {
        category.slug == target_category && value == removed_extension
    })
}

pub(super) fn classify_after_rule_draft(
    config: &ClassifierConfig,
    rule: &ClassifierRule,
    filename: &str,
) -> String {
    let mut preview_config = config.clone();
    if let Some(category) = preview_config
        .categories
        .iter_mut()
        .find(|category| category.slug == rule.target_category)
    {
        category.keywords.extend(rule.keywords.iter().cloned());
        category.extensions.extend(rule.extensions.iter().cloned());
        category.priority = rule.priority as i32;
    }
    classify_with_removed_basis(&preview_config, filename, |_, _, _| false)
}

fn classify_with_removed_basis(
    config: &ClassifierConfig,
    filename: &str,
    removed: impl Fn(&CategoryConfig, &str, &str) -> bool,
) -> String {
    let normalized = normalize_name(filename);
    if let Some(category) = keyword_category(config, &normalized, &removed) {
        return category.slug.clone();
    }
    extension_category(config, &normalized, &removed)
        .map(|category| category.slug.clone())
        .unwrap_or_else(|| config.default.clone())
}

fn keyword_category<'a>(
    config: &'a ClassifierConfig,
    normalized: &NormalizedName,
    removed: &impl Fn(&CategoryConfig, &str, &str) -> bool,
) -> Option<&'a CategoryConfig> {
    config
        .categories
        .iter()
        .enumerate()
        .flat_map(|(category_index, category)| {
            category.keywords.iter().filter_map(move |keyword| {
                if removed(category, keyword, "") {
                    return None;
                }
                let normalized_keyword = normalize_keyword(keyword);
                keyword_matches(normalized, &normalized_keyword).then_some((
                    category,
                    normalized_keyword.chars().count(),
                    category_index,
                ))
            })
        })
        .min_by(compare_keyword_hits)
        .map(|(category, _, _)| category)
}

fn extension_category<'a>(
    config: &'a ClassifierConfig,
    normalized: &NormalizedName,
    removed: &impl Fn(&CategoryConfig, &str, &str) -> bool,
) -> Option<&'a CategoryConfig> {
    let extension = normalized.extension.as_ref()?;
    config
        .categories
        .iter()
        .enumerate()
        .filter(|(_, category)| {
            category
                .extensions
                .iter()
                .any(|candidate| candidate == extension && !removed(category, "", candidate))
        })
        .min_by(compare_extension_hits)
        .map(|(_, category)| category)
}

fn compare_keyword_hits(
    left: &(&CategoryConfig, usize, usize),
    right: &(&CategoryConfig, usize, usize),
) -> std::cmp::Ordering {
    right
        .0
        .priority
        .cmp(&left.0.priority)
        .then_with(|| right.1.cmp(&left.1))
        .then_with(|| left.2.cmp(&right.2))
}

fn compare_extension_hits(
    left: &(usize, &CategoryConfig),
    right: &(usize, &CategoryConfig),
) -> std::cmp::Ordering {
    right
        .1
        .priority
        .cmp(&left.1.priority)
        .then_with(|| left.0.cmp(&right.0))
}

fn normalize_name(name: &str) -> NormalizedName {
    let lowered: String = name.nfkc().collect::<String>().to_lowercase();
    let extension = Path::new(&lowered)
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_owned);
    let tokens = lowered
        .split(is_separator)
        .filter(|token| !token.is_empty())
        .map(str::to_owned)
        .collect();
    NormalizedName {
        lowered,
        tokens,
        extension,
    }
}

fn keyword_matches(name: &NormalizedName, keyword: &str) -> bool {
    if keyword.chars().any(is_cjk) {
        return name.lowered.contains(keyword);
    }
    name.tokens.iter().any(|token| token == keyword)
}

fn normalize_keyword(keyword: &str) -> String {
    keyword.nfkc().collect::<String>().to_lowercase()
}

fn is_separator(character: char) -> bool {
    matches!(
        character,
        ' ' | '_' | '-' | '.' | '\t' | '/' | '\\' | '(' | ')' | '[' | ']'
    )
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
