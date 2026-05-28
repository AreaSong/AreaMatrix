use std::path::Path;

use crate::{db, CoreResult, FileEntry};

use super::AiTagSuggestionInputField;

const MAX_SUMMARY_CHARS: usize = 320;
const MAX_TAG_REGISTRY_ITEMS: usize = 32;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AiTagSuggestionContext {
    pub(super) fields: Vec<AiTagSuggestionInputField>,
    pub(super) filename: String,
    pub(super) repo_relative_path: Option<String>,
    pub(super) ai_summary: Option<String>,
    pub(super) existing_tags: Vec<String>,
    pub(super) tag_registry: Vec<String>,
}

pub(super) fn build_context(
    repo: &Path,
    file: &FileEntry,
    candidate_tags: &[String],
) -> CoreResult<AiTagSuggestionContext> {
    let tag_set = db::list_tag_set(repo, file.id)?;
    let mut fields = vec![
        AiTagSuggestionInputField::FileName,
        AiTagSuggestionInputField::RepoRelativePath,
    ];

    let ai_summary = db::load_ai_summary_metadata(repo, file.id)?
        .and_then(|row| sanitized_excerpt(&row.summary_text, MAX_SUMMARY_CHARS));
    if ai_summary.is_some() {
        fields.push(AiTagSuggestionInputField::AiSummary);
    }

    let existing_tags = tag_set
        .file_tags
        .iter()
        .map(|record| record.value.clone())
        .collect::<Vec<_>>();
    if !existing_tags.is_empty() {
        fields.push(AiTagSuggestionInputField::ExistingTags);
    }

    let tag_registry = registry_tags(&tag_set.available_tags, candidate_tags);
    if !tag_registry.is_empty() {
        fields.push(AiTagSuggestionInputField::TagRegistry);
    }

    Ok(AiTagSuggestionContext {
        fields,
        filename: file.current_name.clone(),
        repo_relative_path: Some(file.path.clone()),
        ai_summary,
        existing_tags,
        tag_registry,
    })
}

pub(super) fn has_eligible_input(context: &AiTagSuggestionContext) -> bool {
    !context.filename.trim().is_empty()
        || context
            .repo_relative_path
            .as_deref()
            .is_some_and(|path| !path.trim().is_empty())
        || context.ai_summary.is_some()
        || !context.existing_tags.is_empty()
        || !context.tag_registry.is_empty()
}

fn registry_tags(records: &[crate::TagRecord], candidate_tags: &[String]) -> Vec<String> {
    let mut tags = Vec::new();
    for tag in records.iter().map(|record| record.value.as_str()) {
        push_unique_tag(&mut tags, tag);
    }
    for tag in candidate_tags {
        push_unique_tag(&mut tags, tag);
    }
    tags.truncate(MAX_TAG_REGISTRY_ITEMS);
    tags
}

fn push_unique_tag(tags: &mut Vec<String>, tag: &str) {
    let value = tag.trim();
    if value.is_empty() || tags.iter().any(|existing| existing == value) {
        return;
    }
    tags.push(value.to_owned());
}

fn sanitized_excerpt(content: &str, limit: usize) -> Option<String> {
    let mut summary = String::new();
    for word in content.split_whitespace() {
        if looks_sensitive(word) {
            continue;
        }
        if !summary.is_empty() {
            summary.push(' ');
        }
        summary.push_str(word);
        if summary.chars().count() >= limit {
            break;
        }
    }
    if summary.is_empty() {
        None
    } else {
        Some(summary.chars().take(limit).collect())
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
