//! Sanitized local model diagnostics summary helpers.

const DIAGNOSTICS_MAX_LEN: usize = 240;

pub(super) fn diagnostics(
    manifest_status: &str,
    runtime_status: &str,
    folder_status: &str,
    size_bytes: Option<i64>,
    last_error: Option<&str>,
) -> String {
    let error = last_error
        .and_then(sanitize_str)
        .unwrap_or_else(|| "none".to_owned());
    let raw = format!(
        "manifest={manifest_status}; runtime={runtime_status}; folder={folder_status}; size_bytes={}; last_error={error}",
        size_bytes
            .map(|size| size.to_string())
            .unwrap_or_else(|| "unknown".to_owned())
    );
    truncate(sanitize_text(&raw))
}

pub(super) fn sanitize_optional_str(value: Option<&str>) -> Option<String> {
    value.and_then(sanitize_str)
}

fn sanitize_str(value: &str) -> Option<String> {
    let sanitized = sanitize_text(value);
    if sanitized.is_empty() {
        None
    } else {
        Some(sanitized)
    }
}

fn sanitize_text(value: &str) -> String {
    let mut cleaned = value.replace(['\0', '\n', '\r', '\t'], " ");
    while cleaned.contains("  ") {
        cleaned = cleaned.replace("  ", " ");
    }
    if super::looks_sensitive(&cleaned) {
        return "redacted sensitive local model detail".to_owned();
    }
    truncate(cleaned)
}

fn truncate(value: String) -> String {
    if value.len() <= DIAGNOSTICS_MAX_LEN {
        return value;
    }
    value
        .chars()
        .take(DIAGNOSTICS_MAX_LEN)
        .collect::<String>()
        .trim_end()
        .to_owned()
}
