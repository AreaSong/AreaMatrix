//! Generated overview support for repository summaries.

use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::Path,
};

use self::atomic_write::{write_plans_with_rollback, WritePlan};
use crate::{
    db::{self, OverviewChangeRow, OverviewFileRow, OverviewNodeSummary},
    CoreError, CoreResult, FileEntry, OverviewOutput,
};

mod atomic_write;

const BEGIN_TAG: &str =
    "<!-- AREAMATRIX:BEGIN auto-generated content; do NOT edit between markers -->";
const BEGIN_PREFIX: &str = "<!-- AREAMATRIX:BEGIN";
const END_TAG: &str = "<!-- AREAMATRIX:END -->";
const GENERATED_DIR: &str = ".areamatrix/generated";
const NODE_OVERVIEW_LIMIT: i64 = 200;
const NODE_RECENT_DAYS: i64 = 30;
const ROOT_RECENT_DAYS: i64 = 7;
const RECENT_LIMIT: i64 = 20;

pub(crate) fn write_generated_root(generated_dir: &Path, locale: &str) -> CoreResult<()> {
    fs::create_dir_all(generated_dir).map_err(map_io_error)?;
    write_new_file(
        &generated_dir.join("root.md"),
        &root_document(locale, &[], &[]),
    )
}

pub(crate) fn write_root_areamatrix_file(repo_path: &Path, locale: &str) -> CoreResult<()> {
    write_new_file(
        &repo_path.join("AREAMATRIX.md"),
        &root_entry_template(locale, &root_managed_block(locale, &[], &[])),
    )
}

pub(crate) fn regenerate_after_import(repo: &Path, entry: &FileEntry) -> CoreResult<()> {
    regenerate_for_node(repo, &entry.category)
}

pub(crate) fn regenerate_for_node(repo: &Path, node_slug: &str) -> CoreResult<()> {
    validate_node_slug(node_slug)?;
    let config = load_config(repo)?;
    let locale = config.locale.as_str();
    let files = db::list_overview_node_files(repo, node_slug, NODE_OVERVIEW_LIMIT)?;
    let recent =
        db::list_overview_recent_changes(repo, Some(node_slug), NODE_RECENT_DAYS, RECENT_LIMIT)?;
    let summaries = db::list_overview_node_summaries(repo)?;
    let root_recent = db::list_overview_recent_changes(repo, None, ROOT_RECENT_DAYS, RECENT_LIMIT)?;
    let generated_dir = repo.join(GENERATED_DIR);
    let managed = root_managed_block(locale, &summaries, &root_recent);
    let mut plans = vec![
        WritePlan::new(
            generated_dir.join("nodes").join(format!("{node_slug}.md")),
            node_document(node_slug, locale, &files, &recent),
        ),
        WritePlan::new(
            generated_dir.join("root.md"),
            root_document(locale, &summaries, &root_recent),
        ),
    ];
    if config.overview_output == OverviewOutput::RootAreaMatrixFile {
        plans.push(WritePlan::new(
            repo.join("AREAMATRIX.md"),
            root_entry_content(repo, locale, &managed)?,
        ));
    }
    write_plans_with_rollback(&plans)
}

fn root_entry_content(repo: &Path, locale: &str, managed: &str) -> CoreResult<String> {
    let path = repo.join("AREAMATRIX.md");
    match fs::symlink_metadata(&path) {
        Ok(metadata) if metadata.is_file() => {}
        Ok(_) => return Err(CoreError::Config),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(root_entry_template(locale, managed));
        }
        Err(error) => return Err(map_io_error(error)),
    };
    let existing = fs::read_to_string(&path).map_err(map_io_error)?;
    Ok(merge_managed_block(&existing, managed))
}

fn node_document(
    node_slug: &str,
    locale: &str,
    files: &[OverviewFileRow],
    recent: &[OverviewChangeRow],
) -> String {
    let display = node_display(node_slug, locale);
    format!(
        "# {display} ({node_slug})\n\n{}\n",
        node_managed_block(locale, files, recent)
    )
}

fn node_managed_block(
    locale: &str,
    files: &[OverviewFileRow],
    recent: &[OverviewChangeRow],
) -> String {
    let total_bytes = files.iter().map(|file| file.size_bytes).sum();
    let latest = files.iter().map(|file| file.imported_at).max().unwrap_or(0);
    let mut out = String::new();
    push_managed_start(&mut out);
    out.push_str(&format!(
        "**{}**: {} · {} · {}\n\n",
        text("stats", locale),
        file_count(files.len() as i64, locale),
        bytes(total_bytes),
        date(latest)
    ));
    out.push_str(&format!("## {}\n\n", text("files", locale)));
    out.push_str(&format!(
        "| {} | {} | {} |\n|---|---|---|\n",
        text("file", locale),
        text("size", locale),
        text("imported", locale)
    ));
    for file in files {
        out.push_str(&format!(
            "| [{}]({}) | {} | {} |\n",
            file.current_name,
            encode_link(&file.path),
            bytes(file.size_bytes),
            date(file.imported_at)
        ));
    }
    push_recent_section(&mut out, locale, recent, false, "recent_node");
    push_managed_end(&mut out);
    out
}

fn root_document(
    locale: &str,
    summaries: &[OverviewNodeSummary],
    recent: &[OverviewChangeRow],
) -> String {
    format!(
        "# {}\n\n> {}\n\n{}\n",
        root_title(locale),
        root_description(locale),
        root_managed_block(locale, summaries, recent)
    )
}

fn root_managed_block(
    locale: &str,
    summaries: &[OverviewNodeSummary],
    recent: &[OverviewChangeRow],
) -> String {
    let total_files = summaries.iter().map(|summary| summary.file_count).sum();
    let total_bytes = summaries.iter().map(|summary| summary.total_bytes).sum();
    let mut out = String::new();
    push_managed_start(&mut out);
    out.push_str(&format!(
        "**{}**: {} · {} · {} {}\n\n",
        text("summary", locale),
        file_count(total_files, locale),
        bytes(total_bytes),
        summaries.len(),
        text("nodes", locale)
    ));
    out.push_str(&format!(
        "| {} | {} | {} | {} |\n|---|---|---|---|\n",
        text("node", locale),
        text("file_count", locale),
        text("size", locale),
        text("imported", locale)
    ));
    for summary in summaries {
        let display = node_display(&summary.slug, locale);
        out.push_str(&format!(
            "| [{} ({})]({}/) | {} | {} | {} |\n",
            display,
            summary.slug,
            encode_link(&summary.slug),
            summary.file_count,
            bytes(summary.total_bytes),
            date(summary.last_imported_at)
        ));
    }
    push_recent_section(&mut out, locale, recent, true, "recent_root");
    push_managed_end(&mut out);
    out
}

fn push_recent_section(
    out: &mut String,
    locale: &str,
    recent: &[OverviewChangeRow],
    include_category: bool,
    label_key: &str,
) {
    out.push_str(&format!("\n## {}\n\n", text(label_key, locale)));
    if recent.is_empty() {
        out.push_str(&format!("- {}\n", text("no_recent", locale)));
        return;
    }
    for change in recent {
        let name = change_name(change, include_category);
        out.push_str(&format!(
            "- {} {} `{}`\n",
            date(change.occurred_at),
            action_label(&change.action),
            name
        ));
    }
}

fn change_name(change: &OverviewChangeRow, include_category: bool) -> String {
    if include_category && !change.category.is_empty() && !change.filename.is_empty() {
        return format!("{}/{}", change.category, change.filename);
    }
    if change.filename.is_empty() {
        "(unknown)".to_owned()
    } else {
        change.filename.clone()
    }
}

fn push_managed_start(out: &mut String) {
    out.push_str(BEGIN_TAG);
    out.push_str("\n\n");
}

fn push_managed_end(out: &mut String) {
    out.push('\n');
    out.push_str(END_TAG);
}

fn merge_managed_block(existing: &str, managed: &str) -> String {
    match find_managed_block(existing) {
        Some((before, after)) => {
            let mut out = String::with_capacity(before.len() + managed.len() + after.len());
            out.push_str(before);
            out.push_str(managed);
            out.push_str(after);
            out
        }
        None => append_managed_block(existing, managed),
    }
}

fn find_managed_block(existing: &str) -> Option<(&str, &str)> {
    let begin = existing.find(BEGIN_PREFIX)?;
    let end_search_start = begin + BEGIN_PREFIX.len();
    let end_relative = existing[end_search_start..].find(END_TAG)?;
    let end = end_search_start + end_relative + END_TAG.len();
    Some((&existing[..begin], &existing[end..]))
}

fn append_managed_block(existing: &str, managed: &str) -> String {
    let mut out = existing.trim_end().to_owned();
    if !out.is_empty() {
        out.push_str("\n\n");
    }
    out.push_str(managed);
    out.push('\n');
    out
}

fn root_entry_template(locale: &str, managed: &str) -> String {
    format!(
        "# {}\n\n> {}\n\n{}\n",
        root_title(locale),
        root_description(locale),
        managed
    )
}

fn load_config(repo: &Path) -> CoreResult<crate::RepoConfig> {
    db::load_config_or_default(repo.to_string_lossy().into_owned())
}

fn validate_node_slug(node_slug: &str) -> CoreResult<()> {
    if node_slug.is_empty() || node_slug == "." || node_slug == ".." {
        return Err(CoreError::Config);
    }
    if node_slug
        .chars()
        .any(|ch| ch.is_control() || matches!(ch, '/' | '\\' | ':'))
    {
        return Err(CoreError::Config);
    }
    Ok(())
}

fn write_new_file(path: &Path, content: &str) -> CoreResult<()> {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(map_io_error)?;
    match file.write_all(content.as_bytes()) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _remove_result = fs::remove_file(path);
            Err(map_io_error(error))
        }
    }
}

fn write_atomic_replace(path: &Path, content: &str) -> CoreResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(map_io_error)?;
    }
    let tmp = path.with_extension("md.tmp");
    fs::write(&tmp, content).map_err(map_io_error)?;
    match fs::rename(&tmp, path) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _remove_result = fs::remove_file(&tmp);
            Err(map_io_error(error))
        }
    }
}

fn root_title(locale: &str) -> &'static str {
    if locale == "zh-Hans" {
        "AreaMatrix 资料库"
    } else {
        "AreaMatrix Repository"
    }
}

fn root_description(locale: &str) -> &'static str {
    if locale == "zh-Hans" {
        "自动维护，请勿删除 .areamatrix/ 目录。"
    } else {
        "Auto-managed. Do not delete the .areamatrix/ directory."
    }
}

fn text(key: &str, locale: &str) -> &'static str {
    match (locale, key) {
        ("zh-Hans", "stats") => "统计",
        ("zh-Hans", "files") => "文件列表",
        ("zh-Hans", "file") => "文件",
        ("zh-Hans", "recent_node") => "近 30 天改动",
        ("zh-Hans", "recent_root") => "近 7 天跨分类改动",
        ("zh-Hans", "size") => "大小",
        ("zh-Hans", "imported") => "导入时间",
        ("zh-Hans", "summary") => "总览",
        ("zh-Hans", "node") => "节点",
        ("zh-Hans", "nodes") => "节点",
        ("zh-Hans", "file_count") => "文件数",
        ("zh-Hans", "no_recent") => "暂无改动",
        (_, "stats") => "Statistics",
        (_, "files") => "Files",
        (_, "file") => "File",
        (_, "recent_node") => "Recent changes (30 days)",
        (_, "recent_root") => "Recent changes (7 days)",
        (_, "size") => "Size",
        (_, "imported") => "Imported",
        (_, "summary") => "Overview",
        (_, "node") => "Node",
        (_, "nodes") => "nodes",
        (_, "file_count") => "Files",
        (_, "no_recent") => "No recent changes",
        _ => "unknown",
    }
}

fn node_display(node_slug: &str, locale: &str) -> String {
    match (locale, node_slug) {
        ("zh-Hans", "docs") => "文档".to_owned(),
        ("zh-Hans", "code") => "代码".to_owned(),
        ("zh-Hans", "design") => "设计".to_owned(),
        ("zh-Hans", "media") => "媒体".to_owned(),
        ("zh-Hans", "finance") => "财务".to_owned(),
        ("zh-Hans", "inbox") => "未分类".to_owned(),
        _ => capitalize(node_slug),
    }
}

fn capitalize(value: &str) -> String {
    let mut chars = value.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().to_string() + chars.as_str(),
        None => String::new(),
    }
}

fn bytes(value: i64) -> String {
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;
    let value = value.max(0) as f64;
    if value >= GB {
        format!("{:.1} GB", value / GB)
    } else if value >= MB {
        format!("{:.1} MB", value / MB)
    } else if value >= KB {
        format!("{:.0} KB", value / KB)
    } else {
        format!("{} B", value as i64)
    }
}

fn date(timestamp: i64) -> String {
    if timestamp <= 0 {
        return "-".to_owned();
    }
    let Some(utc) = chrono::DateTime::<chrono::Utc>::from_timestamp(timestamp, 0) else {
        return "-".to_owned();
    };
    utc.format("%Y-%m-%d").to_string()
}

fn file_count(value: i64, locale: &str) -> String {
    if locale == "zh-Hans" {
        format!("{} 个文件", value.max(0))
    } else {
        format!("{} files", value.max(0))
    }
}

fn action_label(action: &str) -> &'static str {
    match action {
        "imported" => "imported",
        "renamed" => "renamed",
        "deleted" => "deleted",
        "moved" => "moved",
        "external_modified" => "modified",
        "restored" => "restored",
        "edited_note" => "edited",
        _ => "changed",
    }
}

fn encode_link(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b'/' => {
                encoded.push(*byte as char);
            }
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

fn map_io_error(error: io::Error) -> CoreError {
    match error.kind() {
        io::ErrorKind::AlreadyExists => CoreError::Config,
        io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    }
}
