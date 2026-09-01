//! Text classification helpers for observability validation.

use super::ObservabilityPrivacy;

pub(super) fn attribute_privacy_floor(key: &str) -> ObservabilityPrivacy {
    let segments = normalized_key_segments(key);
    let locator_segment = segments.iter().any(|segment| {
        matches!(
            segment.as_str(),
            "path" | "url" | "uri" | "filename" | "locator"
        )
    });
    let user_name = segments.last().is_some_and(|segment| segment == "name")
        && segments.first().is_some_and(|segment| {
            matches!(
                segment.as_str(),
                "file" | "repository" | "resource" | "source"
            )
        });
    if locator_segment || user_name {
        ObservabilityPrivacy::Sensitive
    } else {
        ObservabilityPrivacy::Public
    }
}

pub(super) fn is_credential_key(key: &str) -> bool {
    let segments = normalized_key_segments(key);
    let compact = segments.concat();
    let prohibited = [
        "authorization",
        "credential",
        "password",
        "passwd",
        "secret",
        "token",
        "apikey",
        "accesstoken",
        "refreshtoken",
        "clientsecret",
        "privatekey",
    ];
    prohibited.contains(&compact.as_str())
        || segments
            .iter()
            .any(|segment| prohibited.contains(&segment.as_str()))
}

pub(super) fn looks_like_locator(value: &str) -> bool {
    let trimmed = value.trim();
    let bytes = trimmed.as_bytes();
    trimmed.starts_with('/')
        || trimmed.starts_with("~/")
        || trimmed.starts_with("file://")
        || trimmed.starts_with("\\\\")
        || trimmed.contains("://")
        || contains_embedded_absolute_path(trimmed)
        || (bytes.len() >= 3
            && bytes[0].is_ascii_alphabetic()
            && bytes[1] == b':'
            && matches!(bytes[2], b'\\' | b'/'))
        || contains_filename_token(trimmed)
}

fn normalized_key_segments(key: &str) -> Vec<String> {
    let mut segments = Vec::new();
    let mut current = String::new();
    let characters: Vec<_> = key.chars().collect();
    for (index, character) in characters.iter().copied().enumerate() {
        if matches!(character, '.' | '_' | '-') {
            push_key_segment(&mut segments, &mut current);
            continue;
        }
        let previous = index.checked_sub(1).and_then(|index| characters.get(index));
        let next = characters.get(index + 1);
        let camel_boundary = character.is_ascii_uppercase()
            && !current.is_empty()
            && (previous.is_some_and(|value| value.is_ascii_lowercase() || value.is_ascii_digit())
                || (previous.is_some_and(|value| value.is_ascii_uppercase())
                    && next.is_some_and(|value| value.is_ascii_lowercase())));
        if camel_boundary {
            push_key_segment(&mut segments, &mut current);
        }
        current.push(character.to_ascii_lowercase());
    }
    push_key_segment(&mut segments, &mut current);
    segments
}

fn push_key_segment(segments: &mut Vec<String>, current: &mut String) {
    if !current.is_empty() {
        segments.push(std::mem::take(current));
    }
}

fn contains_embedded_absolute_path(value: &str) -> bool {
    let characters: Vec<_> = value.chars().collect();
    for index in 0..characters.len() {
        if !is_locator_boundary(index.checked_sub(1).map(|index| characters[index])) {
            continue;
        }
        if characters[index] == '/'
            && characters
                .get(index + 1)
                .is_some_and(|character| !character.is_whitespace())
        {
            return true;
        }
        if characters[index] == '\\'
            && characters.get(index + 1) == Some(&'\\')
            && characters
                .get(index + 2)
                .is_some_and(|character| !character.is_whitespace())
        {
            return true;
        }
        if characters.get(index).is_some_and(char::is_ascii_alphabetic)
            && characters.get(index + 1) == Some(&':')
            && characters
                .get(index + 2)
                .is_some_and(|character| matches!(character, '\\' | '/'))
        {
            return true;
        }
    }
    false
}

fn is_locator_boundary(previous: Option<char>) -> bool {
    previous.is_none_or(|character| character.is_whitespace() || !character.is_ascii_alphanumeric())
}

fn contains_filename_token(value: &str) -> bool {
    value
        .split(|character: char| !is_filename_character(character))
        .any(looks_like_filename_token)
}

fn is_filename_character(character: char) -> bool {
    character.is_alphanumeric() || matches!(character, '.' | '_' | '-' | '\u{3002}' | '\u{ff0e}')
}

fn looks_like_filename_token(token: &str) -> bool {
    if token.is_empty() || token.len() > 255 {
        return false;
    }
    let normalized = token.replace(['\u{3002}', '\u{ff0e}'], ".");
    if let Some(hidden) = normalized.strip_prefix('.') {
        return !hidden.is_empty()
            && !hidden.contains('.')
            && hidden.len() <= 32
            && hidden.chars().any(|character| character.is_alphabetic());
    }
    let Some((stem, extension)) = normalized.rsplit_once('.') else {
        return false;
    };
    !stem.is_empty()
        && !extension.is_empty()
        && extension.len() <= 32
        && stem.chars().any(char::is_alphanumeric)
        && extension
            .chars()
            .all(|character| character.is_ascii_alphanumeric())
        && extension
            .chars()
            .any(|character| character.is_ascii_alphabetic())
}
