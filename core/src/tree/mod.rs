//! Read-only repository tree JSON for the Stage 1 main window.

use std::{
    collections::BTreeMap,
    fs, io,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};
use walkdir::{DirEntry, WalkDir};

use crate::{db, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const CLASSIFIER_FILE: &str = "classifier.yaml";
const IGNORE_FILE: &str = "ignore.yaml";
const ROOT_SLUG: &str = "__root__";
const ROOT_DISPLAY_ZH_HANS: &str = "资料库";
const ROOT_DISPLAY_EN: &str = "Repository";
const GENERATED_ROOT_OVERVIEW: &str = "AREAMATRIX.md";
const GENERATED_DIR_PREFIX: &str = ".areamatrix/generated/";
const DEFAULT_CLASSIFIER_YAML: &str = include_str!("../../resources/classifier.yaml");
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

#[derive(Debug, Serialize)]
struct TreeNode {
    slug: String,
    display_name: String,
    kind: NodeKind,
    relative_path: String,
    file_count: i64,
    size_bytes: i64,
    depth: i32,
    children: Vec<TreeNode>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
enum NodeKind {
    RepositoryRoot,
    SystemCategory,
    UserFolder,
    Subdir,
}

#[derive(Debug, Default)]
struct RawNode {
    relative_path: String,
    file_count: i64,
    size_bytes: i64,
    children: BTreeMap<String, RawNode>,
}

#[derive(Debug, Deserialize)]
struct ClassifierConfig {
    categories: Vec<TreeCategory>,
}

#[derive(Debug, Deserialize)]
struct TreeCategory {
    slug: String,
    #[serde(default)]
    display_name: BTreeMap<String, String>,
}

#[derive(Debug, Default)]
struct CategoryDisplay {
    names_by_slug: BTreeMap<String, BTreeMap<String, String>>,
}

#[derive(Debug, Deserialize)]
struct IgnoreConfig {
    ignore: Option<Vec<String>>,
    patterns: Option<Vec<String>>,
}

struct IgnoreMatcher {
    patterns: Vec<String>,
}

pub(crate) fn list_tree_json(repo_path: String, locale: String) -> CoreResult<String> {
    let repo = PathBuf::from(repo_path);
    build_tree_json(&repo, &locale).map_err(normalize_contract_error)
}

fn build_tree_json(repo: &Path, locale: &str) -> CoreResult<String> {
    let tree = build_tree(repo, locale)?;
    serde_json::to_string(&tree).map_err(|error| CoreError::io(error.to_string()))
}

fn build_tree(repo: &Path, locale: &str) -> CoreResult<TreeNode> {
    db::ensure_initialized_readable(repo)?;

    let categories = load_categories(repo)?;
    let raw = walk_repository(repo)?;
    Ok(TreeNode {
        slug: ROOT_SLUG.to_owned(),
        display_name: root_display_name(locale),
        kind: NodeKind::RepositoryRoot,
        relative_path: String::new(),
        file_count: raw.file_count,
        size_bytes: raw.size_bytes,
        depth: 0,
        children: build_children(&raw, &categories, locale, 1),
    })
}

fn load_categories(repo: &Path) -> CoreResult<CategoryDisplay> {
    let path = repo.join(AREA_MATRIX_DIR).join(CLASSIFIER_FILE);
    let yaml = match fs::read_to_string(path) {
        Ok(content) => content,
        Err(error) if error.kind() == io::ErrorKind::NotFound => DEFAULT_CLASSIFIER_YAML.to_owned(),
        Err(error) => return Err(map_io_error(error)),
    };

    parse_categories(&yaml)
        .or_else(|| parse_categories(DEFAULT_CLASSIFIER_YAML))
        .ok_or_else(|| CoreError::io("io error"))
}

fn parse_categories(yaml: &str) -> Option<CategoryDisplay> {
    let config = serde_yaml::from_str::<ClassifierConfig>(yaml).ok()?;
    let names_by_slug = config
        .categories
        .into_iter()
        .filter(|category| !category.slug.trim().is_empty())
        .map(|category| (category.slug, category.display_name))
        .collect();
    Some(CategoryDisplay { names_by_slug })
}

fn walk_repository(repo: &Path) -> CoreResult<RawNode> {
    let matcher = IgnoreMatcher::load(repo)?;
    let mut root = RawNode::default();
    for entry in WalkDir::new(repo)
        .follow_links(false)
        .same_file_system(true)
        .into_iter()
        .filter_entry(|entry| should_descend(repo, entry, &matcher))
    {
        let entry = entry.map_err(map_walkdir_error)?;
        if entry.path() == repo {
            continue;
        }

        let relative_path = relative_repo_path(repo, entry.path())?;
        if matcher.is_ignored(&relative_path, entry.file_type().is_dir()) {
            continue;
        }
        if entry.file_type().is_dir() {
            insert_directory(&mut root, &relative_path);
        } else if entry.file_type().is_file() {
            let size = metadata_len(&entry)?;
            insert_file(&mut root, &relative_path, size);
        }
    }
    Ok(root)
}

fn should_descend(repo: &Path, entry: &DirEntry, matcher: &IgnoreMatcher) -> bool {
    if entry.path() == repo || !entry.file_type().is_dir() {
        return true;
    }
    relative_repo_path(repo, entry.path())
        .map(|relative_path| !matcher.is_ignored(&relative_path, true))
        .unwrap_or(false)
}

fn insert_directory(root: &mut RawNode, relative_path: &str) {
    let mut node = root;
    let mut path_parts = Vec::new();
    for part in path_components(relative_path) {
        path_parts.push(part);
        let node_path = path_parts.join("/");
        node = node
            .children
            .entry(part.to_owned())
            .or_insert_with(|| RawNode::new(node_path));
    }
}

fn insert_file(root: &mut RawNode, relative_path: &str, size_bytes: i64) {
    root.file_count += 1;
    root.size_bytes += size_bytes;

    let parts = path_components(relative_path);
    let mut node = root;
    let mut path_parts = Vec::new();
    for part in parts.iter().take(parts.len().saturating_sub(1)) {
        path_parts.push(*part);
        let node_path = path_parts.join("/");
        let child = node
            .children
            .entry((*part).to_owned())
            .or_insert_with(|| RawNode::new(node_path));
        child.file_count += 1;
        child.size_bytes += size_bytes;
        node = child;
    }
}

fn build_children(
    raw: &RawNode,
    categories: &CategoryDisplay,
    locale: &str,
    depth: i32,
) -> Vec<TreeNode> {
    raw.children
        .iter()
        .map(|(slug, child)| {
            let kind = node_kind(categories, slug, depth);
            TreeNode {
                slug: slug.to_owned(),
                display_name: display_name_for(categories, slug, locale, kind),
                kind,
                relative_path: child.relative_path.clone(),
                file_count: child.file_count,
                size_bytes: child.size_bytes,
                depth,
                children: build_children(child, categories, locale, depth + 1),
            }
        })
        .collect()
}

impl RawNode {
    fn new(relative_path: String) -> Self {
        Self {
            relative_path,
            file_count: 0,
            size_bytes: 0,
            children: BTreeMap::new(),
        }
    }
}

impl CategoryDisplay {
    fn display_name(&self, slug: &str, locale: &str) -> String {
        let Some(names) = self.names_by_slug.get(slug) else {
            return slug.to_owned();
        };
        if let Some(name) = names.get(locale) {
            return name.clone();
        }
        if locale == "en" {
            return names.get("en").cloned().unwrap_or_else(|| slug.to_owned());
        }
        if locale == "zh-Hans" {
            return names
                .get("zh-Hans")
                .cloned()
                .unwrap_or_else(|| slug.to_owned());
        }
        slug.to_owned()
    }

    fn contains(&self, slug: &str) -> bool {
        self.names_by_slug.contains_key(slug)
    }
}

impl IgnoreMatcher {
    fn load(repo: &Path) -> CoreResult<Self> {
        let path = repo.join(AREA_MATRIX_DIR).join(IGNORE_FILE);
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

    fn is_ignored(&self, relative_path: &str, is_dir: bool) -> bool {
        if relative_path == GENERATED_ROOT_OVERVIEW
            || relative_path.starts_with(GENERATED_DIR_PREFIX)
        {
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

fn node_kind(categories: &CategoryDisplay, slug: &str, depth: i32) -> NodeKind {
    if depth > 1 {
        NodeKind::Subdir
    } else if categories.contains(slug) {
        NodeKind::SystemCategory
    } else {
        NodeKind::UserFolder
    }
}

fn display_name_for(
    categories: &CategoryDisplay,
    slug: &str,
    locale: &str,
    kind: NodeKind,
) -> String {
    if kind == NodeKind::SystemCategory {
        categories.display_name(slug, locale)
    } else {
        slug.to_owned()
    }
}

fn metadata_len(entry: &DirEntry) -> CoreResult<i64> {
    let len = entry.metadata().map_err(map_walkdir_error)?.len();
    i64::try_from(len).map_err(|error| CoreError::io(error.to_string()))
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    let relative = path
        .strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))?;
    Ok(relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/"))
}

fn path_components(relative_path: &str) -> Vec<&str> {
    relative_path
        .split('/')
        .filter(|component| !component.is_empty())
        .collect()
}

fn file_name_from_relative(relative_path: &str) -> Option<&str> {
    relative_path
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
}

fn root_display_name(locale: &str) -> String {
    if locale == "en" {
        ROOT_DISPLAY_EN.to_owned()
    } else {
        ROOT_DISPLAY_ZH_HANS.to_owned()
    }
}

fn map_io_error(error: io::Error) -> CoreError {
    map_io_kind(error.kind())
}

fn map_walkdir_error(error: walkdir::Error) -> CoreError {
    error
        .io_error()
        .map(|error| map_io_kind(error.kind()))
        .unwrap_or_else(|| CoreError::io("io error"))
}

fn map_io_kind(kind: io::ErrorKind) -> CoreError {
    match kind {
        io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

fn normalize_contract_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } | CoreError::Db { .. } => error,
        _ => CoreError::io("io error"),
    }
}
