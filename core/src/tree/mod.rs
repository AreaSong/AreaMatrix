//! Read-only repository tree JSON for the Stage 1 main window.

use std::{
    collections::BTreeMap,
    fs, io,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::{db, CoreError, CoreResult};

const DEFAULT_CLASSIFIER_YAML: &str = include_str!("../../resources/classifier.yaml");
const ROOT_SLUG: &str = "__root__";
const ROOT_DISPLAY_ZH_HANS: &str = "资料库";
const ROOT_DISPLAY_EN: &str = "Repository";
const GENERATED_ROOT_OVERVIEW: &str = "AREAMATRIX.md";

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

pub(crate) fn list_tree_json(repo_path: String, locale: String) -> CoreResult<String> {
    let repo = PathBuf::from(repo_path);
    build_tree_json(&repo, &locale).map_err(normalize_contract_error)
}

fn build_tree_json(repo: &Path, locale: &str) -> CoreResult<String> {
    db::ensure_initialized(repo)?;
    let categories = load_categories(repo)?;
    let raw = walk_directory(repo)?;
    let tree = TreeNode {
        slug: ROOT_SLUG.to_owned(),
        display_name: root_display_name(locale),
        kind: NodeKind::RepositoryRoot,
        relative_path: String::new(),
        file_count: raw.file_count,
        size_bytes: raw.size_bytes,
        depth: 0,
        children: build_children(&raw, &categories, locale, 1, ""),
    };
    serde_json::to_string(&tree).map_err(|_| CoreError::Io)
}

fn load_categories(repo: &Path) -> CoreResult<CategoryDisplay> {
    let yaml = match fs::read_to_string(repo.join(".areamatrix/classifier.yaml")) {
        Ok(content) => content,
        Err(error) if error.kind() == io::ErrorKind::NotFound => DEFAULT_CLASSIFIER_YAML.to_owned(),
        Err(error) => return Err(map_io_error(error)),
    };
    let config: ClassifierConfig = serde_yaml::from_str(&yaml).map_err(|_| CoreError::Io)?;
    let names_by_slug = config
        .categories
        .into_iter()
        .map(|category| (category.slug, category.display_name))
        .collect();
    Ok(CategoryDisplay { names_by_slug })
}

fn walk_directory(path: &Path) -> CoreResult<RawNode> {
    let mut node = RawNode::default();
    for entry in fs::read_dir(path).map_err(map_io_error)? {
        let entry = entry.map_err(map_io_error)?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if should_skip_entry(&name) {
            continue;
        }

        let file_type = entry.file_type().map_err(map_io_error)?;
        if file_type.is_dir() {
            let child = walk_directory(&entry.path())?;
            node.file_count += child.file_count;
            node.size_bytes += child.size_bytes;
            node.children.insert(name, child);
        } else if file_type.is_file() {
            node.file_count += 1;
            node.size_bytes += metadata_len(entry.path())?;
        }
    }
    Ok(node)
}

fn build_children(
    raw: &RawNode,
    categories: &CategoryDisplay,
    locale: &str,
    depth: i32,
    parent_path: &str,
) -> Vec<TreeNode> {
    raw.children
        .iter()
        .map(|(slug, child)| {
            let relative_path = child_relative_path(parent_path, slug);
            let kind = node_kind(categories, slug, depth);
            TreeNode {
                slug: slug.to_owned(),
                display_name: display_name_for(categories, slug, locale, kind),
                kind,
                relative_path: relative_path.clone(),
                file_count: child.file_count,
                size_bytes: child.size_bytes,
                depth,
                children: build_children(child, categories, locale, depth + 1, &relative_path),
            }
        })
        .collect()
}

impl CategoryDisplay {
    fn display_name(&self, slug: &str, locale: &str) -> String {
        self.names_by_slug
            .get(slug)
            .and_then(|names| names.get(locale).or_else(|| names.get("en")))
            .cloned()
            .unwrap_or_else(|| slug.to_owned())
    }

    fn contains(&self, slug: &str) -> bool {
        self.names_by_slug.contains_key(slug)
    }
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

fn child_relative_path(parent_path: &str, slug: &str) -> String {
    if parent_path.is_empty() {
        slug.to_owned()
    } else {
        format!("{parent_path}/{slug}")
    }
}

fn metadata_len(path: PathBuf) -> CoreResult<i64> {
    let len = path.metadata().map_err(map_io_error)?.len();
    i64::try_from(len).map_err(|_| CoreError::Io)
}

fn should_skip_entry(name: &str) -> bool {
    name.starts_with('.') || name == GENERATED_ROOT_OVERVIEW
}

fn root_display_name(locale: &str) -> String {
    if locale == "en" {
        ROOT_DISPLAY_EN.to_owned()
    } else {
        ROOT_DISPLAY_ZH_HANS.to_owned()
    }
}

fn map_io_error(_error: io::Error) -> CoreError {
    CoreError::Io
}

fn normalize_contract_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized | CoreError::Db => error,
        _ => CoreError::Io,
    }
}
