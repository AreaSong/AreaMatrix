use crate::{SearchDiagnosticKind, SearchDiagnosticSeverity, SearchQueryDiagnostic};

const FIELD_NAMES: &[&str] = &["kind", "cat", "category", "after", "before", "tag", "note"];

pub(super) struct SearchQuery {
    pub(super) raw: String,
    pub(super) terms: Vec<QueryTerm>,
    pub(super) diagnostics: Vec<SearchQueryDiagnostic>,
}

pub(super) struct QueryTerm {
    pub(super) field: Option<QueryField>,
    pub(super) value: String,
}

#[derive(Clone, Copy, Eq, PartialEq)]
pub(super) enum QueryField {
    Kind,
    Category,
    After,
    Before,
    Tag,
    Note,
}

pub(super) fn parse_query(query: String) -> SearchQuery {
    let diagnostics = parse_diagnostics(&query);
    let terms = if has_error_diagnostic(&diagnostics) {
        Vec::new()
    } else {
        tokenize(&query).into_iter().map(parse_token).collect()
    };

    SearchQuery {
        raw: query,
        terms,
        diagnostics,
    }
}

pub(super) fn has_error_diagnostic(diagnostics: &[SearchQueryDiagnostic]) -> bool {
    diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == SearchDiagnosticSeverity::Error)
}

fn parse_diagnostics(query: &str) -> Vec<SearchQueryDiagnostic> {
    let mut diagnostics = Vec::new();
    if let Some(position) = unclosed_quote_position(query) {
        diagnostics.push(diagnostic(
            SearchDiagnosticKind::UnclosedQuote,
            "Unclosed quote",
            None,
            Some(position),
            Some(position + 1),
            None,
        ));
    }

    if let Some(position) = unbalanced_parenthesis_position(query) {
        diagnostics.push(diagnostic(
            SearchDiagnosticKind::UnbalancedParentheses,
            "Unbalanced parentheses",
            None,
            Some(position),
            Some(position + 1),
            None,
        ));
    }

    for token in tokenize(query) {
        inspect_token(&token, &mut diagnostics);
    }
    diagnostics
}

fn diagnostic(
    kind: SearchDiagnosticKind,
    message: impl Into<String>,
    token: Option<String>,
    start: Option<i64>,
    end: Option<i64>,
    suggestion: Option<String>,
) -> SearchQueryDiagnostic {
    SearchQueryDiagnostic {
        kind,
        severity: SearchDiagnosticSeverity::Error,
        message: message.into(),
        token,
        start,
        end,
        suggestion,
    }
}

fn unclosed_quote_position(query: &str) -> Option<i64> {
    let mut escaped = false;
    let mut open_quote: Option<usize> = None;
    for (index, character) in query.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        if character == '\\' {
            escaped = true;
            continue;
        }
        if character == '"' {
            open_quote = open_quote.is_none().then_some(index);
        }
    }
    open_quote.and_then(|index| i64::try_from(index).ok())
}

fn unbalanced_parenthesis_position(query: &str) -> Option<i64> {
    let mut depth = 0_i64;
    let mut first_open: Option<usize> = None;
    let mut quote_state = QuoteState::default();

    for (index, character) in query.char_indices() {
        if quote_state.consume(character) || quote_state.in_quote {
            continue;
        }
        if character == '(' {
            first_open.get_or_insert(index);
            depth += 1;
        } else if character == ')' {
            if depth == 0 {
                return i64::try_from(index).ok();
            }
            depth -= 1;
        }
    }

    (depth > 0)
        .then_some(first_open)
        .flatten()
        .and_then(|index| i64::try_from(index).ok())
}

#[derive(Default)]
struct QuoteState {
    in_quote: bool,
    escaped: bool,
}

impl QuoteState {
    fn consume(&mut self, character: char) -> bool {
        if self.escaped {
            self.escaped = false;
            return true;
        }
        if character == '\\' {
            self.escaped = true;
            return true;
        }
        if character == '"' {
            self.in_quote = !self.in_quote;
            return true;
        }
        false
    }
}

fn inspect_token(token: &str, diagnostics: &mut Vec<SearchQueryDiagnostic>) {
    let Some((field, value)) = advanced_token_parts(token) else {
        return;
    };

    if let Some(known_field) = parse_field(field) {
        inspect_known_field(known_field, value, token, diagnostics);
    } else if looks_like_unknown_field(field) {
        diagnostics.push(diagnostic(
            SearchDiagnosticKind::UnknownField,
            format!("Unknown field `{field}`"),
            Some(field.to_owned()),
            None,
            None,
            closest_field(field),
        ));
    }
}

fn inspect_known_field(
    field: QueryField,
    value: &str,
    token: &str,
    diagnostics: &mut Vec<SearchQueryDiagnostic>,
) {
    if value.trim().is_empty() {
        diagnostics.push(diagnostic(
            SearchDiagnosticKind::InvalidOperator,
            "Missing field value",
            Some(token.to_owned()),
            None,
            None,
            None,
        ));
        return;
    }

    if matches!(field, QueryField::After | QueryField::Before) && !is_valid_date(value) {
        diagnostics.push(diagnostic(
            SearchDiagnosticKind::InvalidDate,
            format!("Invalid date `{value}`"),
            Some(value.to_owned()),
            None,
            None,
            Some("YYYY-MM-DD".to_owned()),
        ));
    }
}

pub(super) fn advanced_token_parts(token: &str) -> Option<(&str, &str)> {
    let index = token.find(':')?;
    if index == 0 || token[..index].ends_with('\\') {
        return None;
    }
    Some((&token[..index], &token[index + 1..]))
}

fn parse_token(token: String) -> QueryTerm {
    if let Some((field, value)) = advanced_token_parts(&token) {
        if let Some(field) = parse_field(field) {
            return QueryTerm {
                field: Some(field),
                value: value.to_owned(),
            };
        }
    }

    QueryTerm {
        field: None,
        value: token,
    }
}

fn parse_field(field: &str) -> Option<QueryField> {
    match field.to_ascii_lowercase().as_str() {
        "kind" => Some(QueryField::Kind),
        "cat" | "category" => Some(QueryField::Category),
        "after" => Some(QueryField::After),
        "before" => Some(QueryField::Before),
        "tag" => Some(QueryField::Tag),
        "note" => Some(QueryField::Note),
        _ => None,
    }
}

fn looks_like_unknown_field(field: &str) -> bool {
    field
        .chars()
        .all(|character| character.is_ascii_alphabetic() || character == '_')
}

fn is_valid_date(value: &str) -> bool {
    let parts: Vec<&str> = value.split('-').collect();
    let [year, month, day] = parts.as_slice() else {
        return false;
    };
    let Ok(year) = year.parse::<i64>() else {
        return false;
    };
    let Ok(month) = month.parse::<i64>() else {
        return false;
    };
    let Ok(day) = day.parse::<i64>() else {
        return false;
    };
    if !(1..=9999).contains(&year) || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return false;
    }
    let year = i32::try_from(year).ok();
    let month = u32::try_from(month).ok();
    let day = u32::try_from(day).ok();
    match (year, month, day) {
        (Some(year), Some(month), Some(day)) => {
            chrono::NaiveDate::from_ymd_opt(year, month, day).is_some()
        }
        _ => false,
    }
}

fn closest_field(field: &str) -> Option<String> {
    FIELD_NAMES
        .iter()
        .min_by_key(|candidate| edit_distance(field, candidate))
        .filter(|candidate| edit_distance(field, candidate) <= 2)
        .map(|candidate| (*candidate).to_owned())
}

pub(super) fn edit_distance(left: &str, right: &str) -> usize {
    let left_chars: Vec<char> = left.chars().collect();
    let right_chars: Vec<char> = right.chars().collect();
    let mut costs: Vec<usize> = (0..=right_chars.len()).collect();

    for (left_index, left_char) in left_chars.iter().enumerate() {
        let mut previous = costs[0];
        costs[0] = left_index + 1;
        for (right_index, right_char) in right_chars.iter().enumerate() {
            let current = costs[right_index + 1];
            let substitution_cost = usize::from(left_char != right_char);
            costs[right_index + 1] = (costs[right_index + 1] + 1)
                .min(costs[right_index] + 1)
                .min(previous + substitution_cost);
            previous = current;
        }
    }

    costs[right_chars.len()]
}

fn tokenize(query: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut in_quote = false;
    let mut escaped = false;

    for character in query.chars() {
        if escaped {
            current.push(character);
            escaped = false;
            continue;
        }
        if character == '\\' {
            escaped = true;
            continue;
        }
        if character == '"' {
            in_quote = !in_quote;
            continue;
        }
        if character.is_whitespace() && !in_quote {
            push_token(&mut current, &mut tokens);
        } else {
            current.push(character);
        }
    }
    push_token(&mut current, &mut tokens);
    tokens
}

fn push_token(current: &mut String, tokens: &mut Vec<String>) {
    let token = current.trim();
    if !token.is_empty() {
        tokens.push(token.to_owned());
    }
    current.clear();
}
