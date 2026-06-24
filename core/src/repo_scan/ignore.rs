use std::{fs, io, path::Path};

use serde::Deserialize;

use crate::CoreResult;

use super::files::map_io_error;

const AREA_MATRIX_DIR: &str = ".areamatrix";
const DEFAULT_IGNORE_PATTERNS: &[&str] = &[
    ".DS_Store",
    ".areamatrix/",
    ".git/",
    ".hg/",
    ".svn/",
    "node_modules/",
    ".venv/",
    "venv/",
    "target/",
    "build/",
    "dist/",
    ".next/",
    ".cache/",
    "*.tmp",
    "*.swp",
];

#[derive(Debug, Deserialize)]
struct IgnoreConfig {
    ignore: Option<Vec<String>>,
    patterns: Option<Vec<String>>,
}

pub(super) struct IgnoreMatcher {
    patterns: Vec<String>,
}

impl IgnoreMatcher {
    pub(super) fn load(repo_path: &Path) -> CoreResult<Self> {
        let path = repo_path.join(AREA_MATRIX_DIR).join("ignore.yaml");
        let content = match fs::read_to_string(path) {
            Ok(content) => content,
            Err(error) if error.kind() == io::ErrorKind::NotFound => String::new(),
            Err(error) => return Err(map_io_error(error)),
        };
        let mut patterns = DEFAULT_IGNORE_PATTERNS
            .iter()
            .map(|pattern| (*pattern).to_owned())
            .collect::<Vec<_>>();
        if let Ok(config) = serde_yaml::from_str::<IgnoreConfig>(&content) {
            if let Some(ignore) = config.ignore {
                patterns.extend(ignore);
            }
            if let Some(extra_patterns) = config.patterns {
                patterns.extend(extra_patterns);
            }
        }
        Ok(Self { patterns })
    }

    pub(super) fn is_ignored(&self, relative_path: &str, is_dir: bool) -> bool {
        if relative_path == "AREAMATRIX.md" || relative_path.starts_with(".areamatrix/generated/") {
            return true;
        }
        self.patterns
            .iter()
            .any(|pattern| matches_pattern(pattern, relative_path, is_dir))
    }
}

fn matches_pattern(pattern: &str, relative_path: &str, is_dir: bool) -> bool {
    if pattern.ends_with('/') {
        let directory = pattern.trim_end_matches('/');
        return relative_path
            .split('/')
            .any(|component| component == directory)
            || (is_dir && relative_path == directory);
    }
    if let Some(suffix) = pattern.strip_prefix('*') {
        return file_name_from_relative(relative_path).is_some_and(|name| name.ends_with(suffix));
    }
    relative_path == pattern || file_name_from_relative(relative_path) == Some(pattern)
}

fn file_name_from_relative(relative_path: &str) -> Option<&str> {
    relative_path
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
}

pub(super) fn has_icloud_placeholder_marker(relative_path: &str) -> bool {
    relative_path
        .split('/')
        .any(|component| component.to_ascii_lowercase().ends_with(".icloud"))
}
