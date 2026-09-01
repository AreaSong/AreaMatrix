use std::{
    fs,
    path::{Component, Path},
};

use crate::{AiPrivacyInputField, CoreError, CoreResult, FileEntry, StorageMode};

use super::{AiCategorySuggestionContextField, AiCategorySuggestionContextPolicy};

const MAX_TEXT_BYTES: u64 = 64 * 1024;
const MAX_SUMMARY_CHARS: usize = 240;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AiSuggestionContext {
    pub(super) fields: Vec<AiCategorySuggestionContextField>,
    pub(super) filename: String,
    pub(super) extension: Option<String>,
    pub(super) repo_relative_path: Option<String>,
    pub(super) limited_text_summary: Option<String>,
}

pub(super) fn build_context(
    repo: &Path,
    file: &FileEntry,
    policy: &AiCategorySuggestionContextPolicy,
    allowed_fields: &[AiPrivacyInputField],
) -> CoreResult<AiSuggestionContext> {
    let mut fields = Vec::new();
    let filename = if allowed_fields.contains(&AiPrivacyInputField::FileName) {
        fields.push(AiCategorySuggestionContextField::FileName);
        file.current_name.clone()
    } else {
        String::new()
    };
    let extension = allowed_fields
        .contains(&AiPrivacyInputField::Extension)
        .then(|| file_extension(&file.current_name))
        .flatten();
    if extension.is_some() {
        fields.push(AiCategorySuggestionContextField::Extension);
    }

    let repo_relative_path = match policy {
        AiCategorySuggestionContextPolicy::FileNameOnly => None,
        AiCategorySuggestionContextPolicy::FileNameAndPath
        | AiCategorySuggestionContextPolicy::LimitedTextSummary
            if allowed_fields.contains(&AiPrivacyInputField::RepoRelativePath) =>
        {
            fields.push(AiCategorySuggestionContextField::RepoRelativePath);
            Some(file.path.clone())
        }
        _ => None,
    };

    let limited_text_summary = if matches!(
        policy,
        AiCategorySuggestionContextPolicy::LimitedTextSummary
    ) && allowed_fields
        .contains(&AiPrivacyInputField::ExtractedTextExcerpt)
    {
        let summary = limited_text_summary(repo, file)?;
        if summary.is_some() {
            fields.push(AiCategorySuggestionContextField::LimitedTextSummary);
        }
        summary
    } else {
        None
    };

    Ok(AiSuggestionContext {
        fields,
        filename,
        extension,
        repo_relative_path,
        limited_text_summary,
    })
}

fn file_extension(filename: &str) -> Option<String> {
    Path::new(filename)
        .extension()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase())
}

fn limited_text_summary(repo: &Path, file: &FileEntry) -> CoreResult<Option<String>> {
    let Some(path) = readable_file_path(repo, file)? else {
        return Ok(None);
    };
    let metadata = fs::metadata(&path).map_err(map_file_read_error)?;
    if !metadata.is_file() || metadata.len() > MAX_TEXT_BYTES {
        return Ok(None);
    }
    let content = fs::read_to_string(&path).map_err(map_file_read_error)?;
    Ok(sanitize_summary(&content))
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
            "AI context path is outside repository",
        ));
    }
    for component in path.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::permission_denied(
                "AI context path is outside repository",
            ));
        };
        if part == ".areamatrix" {
            return Err(CoreError::permission_denied(
                "AI context must not read repository metadata",
            ));
        }
    }
    Ok(())
}

fn sanitize_summary(content: &str) -> Option<String> {
    let mut summary = String::new();
    for word in content.split_whitespace() {
        if looks_sensitive(word) {
            continue;
        }
        if !summary.is_empty() {
            summary.push(' ');
        }
        summary.push_str(word);
        if summary.chars().count() >= MAX_SUMMARY_CHARS {
            break;
        }
    }
    if summary.is_empty() {
        None
    } else {
        Some(summary.chars().take(MAX_SUMMARY_CHARS).collect())
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
        std::io::ErrorKind::NotFound => CoreError::permission_denied("AI context file is missing"),
        std::io::ErrorKind::PermissionDenied => {
            CoreError::permission_denied("AI context file is not readable")
        }
        std::io::ErrorKind::InvalidData => CoreError::internal("AI context is not text"),
        _ => CoreError::internal("AI context extraction failed"),
    }
}
