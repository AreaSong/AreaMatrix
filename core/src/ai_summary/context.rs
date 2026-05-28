use std::{
    fs,
    path::{Component, Path},
};

use crate::{CoreError, CoreResult, FileEntry, StorageMode};

use super::{AiSummaryContextPolicy, AiSummaryInputField};

const MAX_TEXT_BYTES: u64 = 64 * 1024;
const MAX_EXCERPT_CHARS: usize = 640;
const MAX_NOTE_CHARS: usize = 320;
const MAX_EXISTING_SUMMARY_CHARS: usize = 320;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AiSummaryContext {
    pub(super) fields: Vec<AiSummaryInputField>,
    pub(super) filename: String,
    pub(super) repo_relative_path: Option<String>,
    pub(super) extracted_text_excerpt: Option<String>,
    pub(super) existing_ai_summary: Option<String>,
    pub(super) note_summary: Option<String>,
    pub(super) tag_category_context: Option<String>,
}

pub(super) fn build_context(
    repo: &Path,
    file: &FileEntry,
    existing_summary: Option<&str>,
    policy: &AiSummaryContextPolicy,
) -> CoreResult<AiSummaryContext> {
    let mut fields = vec![
        AiSummaryInputField::FileName,
        AiSummaryInputField::RepoRelativePath,
    ];
    let existing_ai_summary =
        existing_summary.and_then(|summary| sanitized_excerpt(summary, MAX_EXISTING_SUMMARY_CHARS));
    if existing_ai_summary.is_some() {
        fields.push(AiSummaryInputField::ExistingAiSummary);
    }

    let extracted_text_excerpt = if allows_text(policy) {
        let excerpt = extracted_text_excerpt(repo, file)?;
        if excerpt.is_some() {
            fields.push(AiSummaryInputField::ExtractedTextExcerpt);
        }
        excerpt
    } else {
        None
    };

    let note_summary = if allows_notes(policy) {
        let summary = crate::db::read_note_content(repo, file.id)?
            .as_deref()
            .and_then(|note| sanitized_excerpt(note, MAX_NOTE_CHARS));
        if summary.is_some() {
            fields.push(AiSummaryInputField::NoteSummary);
        }
        summary
    } else {
        None
    };

    let tag_category_context = if allows_notes(policy) {
        let context = tag_category_context(file);
        fields.push(AiSummaryInputField::TagCategoryContext);
        Some(context)
    } else {
        None
    };

    Ok(AiSummaryContext {
        fields,
        filename: file.current_name.clone(),
        repo_relative_path: Some(file.path.clone()),
        extracted_text_excerpt,
        existing_ai_summary,
        note_summary,
        tag_category_context,
    })
}

fn allows_text(policy: &AiSummaryContextPolicy) -> bool {
    matches!(
        policy,
        AiSummaryContextPolicy::MetadataAndExtractedText
            | AiSummaryContextPolicy::MetadataTextAndNotes
    )
}

fn allows_notes(policy: &AiSummaryContextPolicy) -> bool {
    matches!(policy, AiSummaryContextPolicy::MetadataTextAndNotes)
}

fn extracted_text_excerpt(repo: &Path, file: &FileEntry) -> CoreResult<Option<String>> {
    let Some(path) = readable_file_path(repo, file)? else {
        return Ok(None);
    };
    let metadata = fs::metadata(&path).map_err(map_file_read_error)?;
    if !metadata.is_file() || metadata.len() > MAX_TEXT_BYTES {
        return Ok(None);
    }
    let content = fs::read_to_string(&path).map_err(map_file_read_error)?;
    Ok(sanitized_excerpt(&content, MAX_EXCERPT_CHARS))
}

fn readable_file_path(repo: &Path, file: &FileEntry) -> CoreResult<Option<std::path::PathBuf>> {
    match file.storage_mode {
        StorageMode::Indexed => Ok(file
            .source_path
            .as_deref()
            .map(Path::new)
            .map(Path::to_path_buf)),
        StorageMode::Copied | StorageMode::Moved => {
            let relative = Path::new(&file.path);
            validate_repo_relative_path(relative)?;
            Ok(Some(repo.join(relative)))
        }
    }
}

fn validate_repo_relative_path(path: &Path) -> CoreResult<()> {
    if path.is_absolute() {
        return Err(CoreError::permission_denied(
            "AI summary context path is outside repository",
        ));
    }
    for component in path.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::permission_denied(
                "AI summary context path is outside repository",
            ));
        };
        if part == ".areamatrix" {
            return Err(CoreError::permission_denied(
                "AI summary context must not read repository metadata",
            ));
        }
    }
    Ok(())
}

fn tag_category_context(file: &FileEntry) -> String {
    format!("category: {}", file.category)
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

fn map_file_read_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::file_not_found("AI summary context file"),
        std::io::ErrorKind::PermissionDenied => {
            CoreError::permission_denied("AI summary context file is not readable")
        }
        std::io::ErrorKind::InvalidData => CoreError::internal("AI summary context is not text"),
        _ => CoreError::internal("AI summary context extraction failed"),
    }
}
