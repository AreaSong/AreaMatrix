use serde::Deserialize;

use super::SemanticSearchRoute;

#[derive(Clone, Debug, Default)]
pub(super) struct PrivacyEvaluator {
    rules: Vec<PrivacyRule>,
}

#[derive(Clone, Debug)]
pub(super) struct PrivacyInput<'a> {
    pub(super) route: &'a SemanticSearchRoute,
    pub(super) path: &'a str,
    pub(super) name: &'a str,
    pub(super) category: &'a str,
    pub(super) extension: Option<&'a str>,
    pub(super) tags: &'a [String],
    pub(super) searchable_texts: &'a [&'a str],
}

#[derive(Clone, Debug)]
struct PrivacyRule {
    id: String,
    kind: RuleKind,
    pattern: String,
    applies_to: AppliesTo,
    enabled: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum RuleKind {
    Folder,
    Category,
    Keyword,
    Extension,
    Tag,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum AppliesTo {
    Remote,
    Local,
    LocalAndRemote,
}

#[derive(Deserialize)]
struct RulesDocument {
    rules: Vec<RawRule>,
}

#[derive(Deserialize)]
struct RawRule {
    id: Option<String>,
    #[serde(alias = "type", alias = "rule_type")]
    kind: String,
    pattern: String,
    enabled: Option<bool>,
    applies_to: Option<serde_json::Value>,
}

impl PrivacyEvaluator {
    pub(super) fn from_rules_json(raw: Option<&str>) -> crate::CoreResult<Self> {
        let Some(raw) = raw.filter(|value| !value.trim().is_empty()) else {
            return Ok(Self::default());
        };
        let value: serde_json::Value = serde_json::from_str(raw)
            .map_err(|_| crate::CoreError::db("AI privacy rules metadata is invalid"))?;
        let raw_rules = parse_raw_rules(value)?;
        let rules = raw_rules
            .into_iter()
            .filter_map(PrivacyRule::from_raw)
            .collect::<Vec<_>>();
        Ok(Self { rules })
    }

    pub(super) fn blocking_rule(&self, input: &PrivacyInput<'_>) -> Option<String> {
        self.rules
            .iter()
            .find(|rule| rule.blocks(input))
            .map(|rule| rule.id.clone())
    }
}

impl PrivacyRule {
    fn from_raw(raw: RawRule) -> Option<Self> {
        let kind = RuleKind::parse(&raw.kind)?;
        let pattern = normalize_pattern(&raw.pattern, &kind)?;
        let id = raw
            .id
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| generated_rule_id(&kind, &pattern));
        Some(Self {
            id,
            kind,
            pattern,
            applies_to: AppliesTo::parse(raw.applies_to.as_ref()),
            enabled: raw.enabled.unwrap_or(true),
        })
    }

    fn blocks(&self, input: &PrivacyInput<'_>) -> bool {
        self.enabled
            && self.applies_to.matches(input.route)
            && self.kind.matches(&self.pattern, input)
    }
}

impl RuleKind {
    fn parse(value: &str) -> Option<Self> {
        match normalized_token(value).as_str() {
            "folder" => Some(Self::Folder),
            "category" => Some(Self::Category),
            "keyword" => Some(Self::Keyword),
            "extension" => Some(Self::Extension),
            "tag" => Some(Self::Tag),
            _ => None,
        }
    }

    fn matches(&self, pattern: &str, input: &PrivacyInput<'_>) -> bool {
        match self {
            Self::Folder => folder_matches(pattern, input.path),
            Self::Category => normalized_text(input.category) == pattern,
            Self::Keyword => keyword_matches(pattern, input),
            Self::Extension => input
                .extension
                .is_some_and(|extension| normalized_extension(extension) == pattern),
            Self::Tag => input.tags.iter().any(|tag| normalized_text(tag) == pattern),
        }
    }

    fn id_segment(&self) -> &'static str {
        match self {
            Self::Folder => "folder",
            Self::Category => "category",
            Self::Keyword => "keyword",
            Self::Extension => "extension",
            Self::Tag => "tag",
        }
    }
}

impl AppliesTo {
    fn parse(value: Option<&serde_json::Value>) -> Self {
        let Some(value) = value else {
            return Self::LocalAndRemote;
        };
        if route_tokens(value)
            .iter()
            .any(|token| is_local_and_remote(token))
        {
            return Self::LocalAndRemote;
        }
        let has_local = route_tokens(value).iter().any(|token| token == "local");
        let has_remote = route_tokens(value).iter().any(|token| token == "remote");
        match (has_local, has_remote) {
            (true, true) => Self::LocalAndRemote,
            (true, false) => Self::Local,
            (false, true) => Self::Remote,
            (false, false) => Self::LocalAndRemote,
        }
    }

    fn matches(&self, route: &SemanticSearchRoute) -> bool {
        matches!(
            (self, route),
            (Self::LocalAndRemote, _)
                | (Self::Local, SemanticSearchRoute::Local)
                | (Self::Remote, SemanticSearchRoute::Remote)
        )
    }
}

fn parse_raw_rules(value: serde_json::Value) -> crate::CoreResult<Vec<RawRule>> {
    if value.is_array() {
        return serde_json::from_value(value)
            .map_err(|_| crate::CoreError::db("AI privacy rules metadata is invalid"));
    }
    let document: RulesDocument = serde_json::from_value(value)
        .map_err(|_| crate::CoreError::db("AI privacy rules metadata is invalid"))?;
    Ok(document.rules)
}

fn normalize_pattern(value: &str, kind: &RuleKind) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    match kind {
        RuleKind::Folder => normalize_folder_pattern(trimmed),
        RuleKind::Extension => Some(normalized_extension(trimmed)),
        RuleKind::Category | RuleKind::Keyword | RuleKind::Tag => Some(normalized_text(trimmed)),
    }
}

fn normalize_folder_pattern(value: &str) -> Option<String> {
    if value.starts_with('/') || value.contains('\\') || value.split('/').any(|part| part == "..") {
        return None;
    }
    let trimmed = value.trim_matches('/');
    (!trimmed.is_empty()).then(|| normalized_text(trimmed))
}

fn folder_matches(pattern: &str, path: &str) -> bool {
    let path = normalized_text(path.trim_matches('/'));
    path == pattern || path.starts_with(&format!("{pattern}/"))
}

fn keyword_matches(pattern: &str, input: &PrivacyInput<'_>) -> bool {
    [input.path, input.name, input.category]
        .into_iter()
        .chain(input.tags.iter().map(String::as_str))
        .chain(input.searchable_texts.iter().copied())
        .any(|value| normalized_text(value).contains(pattern))
}

fn route_tokens(value: &serde_json::Value) -> Vec<String> {
    match value {
        serde_json::Value::String(text) => split_route_tokens(text),
        serde_json::Value::Array(values) => values
            .iter()
            .filter_map(serde_json::Value::as_str)
            .flat_map(split_route_tokens)
            .collect(),
        _ => Vec::new(),
    }
}

fn split_route_tokens(value: &str) -> Vec<String> {
    value
        .split(|ch: char| !ch.is_ascii_alphanumeric())
        .map(normalized_token)
        .filter(|token| !token.is_empty() && token != "ai")
        .collect()
}

fn is_local_and_remote(token: &str) -> bool {
    matches!(token, "all" | "both" | "localandremote")
}

fn generated_rule_id(kind: &RuleKind, pattern: &str) -> String {
    format!("rule:{}:{}", kind.id_segment(), pattern.replace(':', "-"))
}

fn normalized_extension(value: &str) -> String {
    normalized_text(value.trim_start_matches('.'))
}

fn normalized_token(value: &str) -> String {
    value
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric())
        .collect::<String>()
        .to_ascii_lowercase()
}

fn normalized_text(value: &str) -> String {
    value.to_lowercase()
}
