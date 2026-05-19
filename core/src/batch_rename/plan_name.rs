use std::{path::Path, time::SystemTime};

use chrono::{DateTime, Utc};
use regex::RegexBuilder;

use crate::{
    BatchRenameDateSource, BatchRenameMode, BatchRenameRule, CoreError, CoreResult, FileEntry,
    StorageMode,
};

use super::plan_path::{map_io_error, repo_relative_file_path};

const MAX_FILENAME_CHARS: usize = 255;

pub(super) fn generate_name(
    repo: &Path,
    entry: &FileEntry,
    index: usize,
    sequence_width: usize,
    rule: &BatchRenameRule,
) -> CoreResult<String> {
    let (stem, extension) = split_stem_extension(&entry.current_name);
    let renamed_stem = match rule.mode {
        BatchRenameMode::Prefix => {
            format!("{}{}", rule.prefix.as_deref().unwrap_or_default(), stem)
        }
        BatchRenameMode::DatePrefix => {
            let date = formatted_date(repo, entry, rule)?;
            format!(
                "{}{}{}",
                date,
                rule.separator.as_deref().unwrap_or("_"),
                stem
            )
        }
        BatchRenameMode::KeepBaseSequence => {
            let sequence = rule.start_number.unwrap_or(1) + index as i64;
            format!(
                "{}{}{:0width$}",
                stem,
                rule.separator.as_deref().unwrap_or("_"),
                sequence,
                width = sequence_width
            )
        }
        BatchRenameMode::ReplaceText => replace_stem_text(stem, rule)?,
    };
    Ok(format!("{renamed_stem}{extension}"))
}

fn formatted_date(repo: &Path, entry: &FileEntry, rule: &BatchRenameRule) -> CoreResult<String> {
    let source = rule
        .date_source
        .as_ref()
        .ok_or_else(|| CoreError::invalid_path("date source is required"))?;
    let date = match source {
        BatchRenameDateSource::Imported => datetime_from_unix(entry.imported_at)?,
        BatchRenameDateSource::Modified => modified_datetime(repo, entry)?,
        BatchRenameDateSource::Today => Utc::now(),
    };
    let format = chrono_date_format(
        rule.date_format
            .as_deref()
            .ok_or_else(|| CoreError::invalid_path("date format is required"))?,
    )?;
    Ok(date.format(&format).to_string())
}

fn modified_datetime(repo: &Path, entry: &FileEntry) -> CoreResult<DateTime<Utc>> {
    let path = if matches!(entry.storage_mode, StorageMode::Indexed) {
        std::path::PathBuf::from(&entry.path)
    } else {
        repo_relative_file_path(repo, &entry.path)?
    };
    let modified = path
        .metadata()
        .map_err(map_io_error)?
        .modified()
        .map_err(map_io_error)?;
    datetime_from_system_time(modified)
}

fn datetime_from_unix(timestamp: i64) -> CoreResult<DateTime<Utc>> {
    DateTime::<Utc>::from_timestamp(timestamp, 0)
        .ok_or_else(|| CoreError::invalid_path("date source is invalid"))
}

fn datetime_from_system_time(time: SystemTime) -> CoreResult<DateTime<Utc>> {
    Ok(DateTime::<Utc>::from(time))
}

fn chrono_date_format(format: &str) -> CoreResult<String> {
    let mut converted = String::new();
    let mut index = 0;
    while index < format.len() {
        let rest = &format[index..];
        let (token, width) = if rest.starts_with("yyyy") {
            ("%Y", 4)
        } else if rest.starts_with("yy") {
            ("%y", 2)
        } else if rest.starts_with("MM") {
            ("%m", 2)
        } else if rest.starts_with('M') {
            ("%-m", 1)
        } else if rest.starts_with("dd") {
            ("%d", 2)
        } else if rest.starts_with('d') {
            ("%-d", 1)
        } else if rest.starts_with("HH") {
            ("%H", 2)
        } else if rest.starts_with("mm") {
            ("%M", 2)
        } else if rest.starts_with("ss") {
            ("%S", 2)
        } else {
            let character = rest
                .chars()
                .next()
                .ok_or_else(|| CoreError::invalid_path("date format is invalid"))?;
            if character.is_ascii_alphabetic() || character == '%' {
                return Err(CoreError::invalid_path("date format is invalid"));
            }
            converted.push(character);
            index += character.len_utf8();
            continue;
        };
        converted.push_str(token);
        index += width;
    }
    if converted.trim().is_empty() {
        return Err(CoreError::invalid_path("date format is invalid"));
    }
    Ok(converted)
}

fn replace_stem_text(stem: &str, rule: &BatchRenameRule) -> CoreResult<String> {
    let find = rule
        .find
        .as_deref()
        .ok_or_else(|| CoreError::invalid_path("find text is required"))?;
    let replacement = rule.replacement.as_deref().unwrap_or_default();
    RegexBuilder::new(&regex::escape(find))
        .case_insensitive(!rule.case_sensitive)
        .build()
        .map(|regex| regex.replace_all(stem, replacement).into_owned())
        .map_err(|error| CoreError::invalid_path(error.to_string()))
}

fn split_stem_extension(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(index) if index > 0 => (&name[..index], &name[index..]),
        _ => (name, ""),
    }
}

pub(super) fn sequence_width(count: usize, rule: &BatchRenameRule) -> usize {
    if !matches!(rule.mode, BatchRenameMode::KeepBaseSequence) {
        return 0;
    }
    let start = rule.start_number.unwrap_or(1).max(1);
    let max_sequence = start + count.saturating_sub(1) as i64;
    let actual_digits = max_sequence.to_string().len();
    (rule.padding.unwrap_or(0).max(0) as usize).max(actual_digits)
}

pub(super) fn validate_filename(name: &str) -> CoreResult<()> {
    if name.is_empty() || name == "." || name == ".." {
        return Err(CoreError::invalid_path("invalid path"));
    }
    if name.chars().count() > MAX_FILENAME_CHARS {
        return Err(CoreError::invalid_path("invalid path"));
    }
    if name.chars().any(is_invalid_filename_character) {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(())
}

fn is_invalid_filename_character(character: char) -> bool {
    character.is_control()
        || matches!(
            character,
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\0'
        )
}
