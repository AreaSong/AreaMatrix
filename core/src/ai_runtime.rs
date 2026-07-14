pub(crate) fn sanitize_response_text(value: &str, fallback: &str, max_chars: usize) -> String {
    let sanitized = value
        .split_whitespace()
        .filter(|part| !looks_sensitive(part))
        .collect::<Vec<_>>()
        .join(" ");
    if sanitized.is_empty() {
        fallback.to_owned()
    } else {
        sanitized.chars().take(max_chars).collect()
    }
}

fn looks_sensitive(value: &str) -> bool {
    let normalized = value.to_ascii_lowercase();
    normalized.starts_with("sk-")
        || normalized.starts_with("sk_")
        || normalized.contains("bearer")
        || normalized.contains("api_key")
        || normalized.contains("apikey")
        || normalized.contains("secret=")
        || normalized.contains("token=")
        || normalized.contains("-----begin")
}

#[cfg(test)]
mod tests {
    use super::sanitize_response_text;

    #[test]
    fn removes_sensitive_tokens_and_preserves_safe_text() {
        assert_eq!(
            sanitize_response_text("safe sk-test-value result", "fallback", 100),
            "safe result"
        );
    }

    #[test]
    fn uses_fallback_when_response_becomes_empty() {
        assert_eq!(
            sanitize_response_text("token=secret", "safe fallback", 100),
            "safe fallback"
        );
    }

    #[test]
    fn applies_feature_specific_length_limit() {
        assert_eq!(sanitize_response_text("abcdefgh", "fallback", 4), "abcd");
    }
}
