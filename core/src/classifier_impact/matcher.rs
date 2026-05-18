use std::path::Path;

use unicode_normalization::UnicodeNormalization;

use crate::ClassifierRule;

use super::RuleImpactMatchReason;

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
