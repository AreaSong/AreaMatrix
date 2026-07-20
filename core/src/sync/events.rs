//! Event normalization and repository-relative path helpers.

use std::{
    collections::BTreeMap,
    fs,
    path::{Component, Path, PathBuf},
};

use crate::{db, CoreError, CoreResult, ExternalEvent, ExternalEventKind};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const ROOT_OVERVIEW_FILE: &str = "AREAMATRIX.md";
const FORBIDDEN_COMPONENT_CHARS: &[char] = &['/', '\\', ':', '*', '?', '"', '<', '>', '|'];

pub(super) struct ResolvedEventPath {
    pub(super) absolute_path: PathBuf,
    pub(super) relative_path: String,
}

struct OrderedExternalEvent {
    event: ExternalEvent,
    input_order: usize,
}

pub(super) fn normalize_and_coalesce_events(
    repo: &Path,
    events: Vec<ExternalEvent>,
) -> CoreResult<(Vec<ExternalEvent>, Option<i64>)> {
    let mut ordered_events = Vec::new();
    let mut coalesced = BTreeMap::<String, ExternalEvent>::new();
    let mut max_sync_event_id = None;

    for (input_order, event) in events.into_iter().enumerate() {
        validate_event_id(event.fs_event_id)?;
        max_sync_event_id = Some(max_event_id(max_sync_event_id, event.fs_event_id));
        let Some(resolved) = resolve_event_path(repo, &event.path)? else {
            continue;
        };
        ordered_events.push(OrderedExternalEvent {
            event: ExternalEvent {
                path: resolved.relative_path,
                kind: event.kind,
                fs_event_id: event.fs_event_id,
            },
            input_order,
        });
    }
    ordered_events.sort_by(|lhs, rhs| {
        lhs.event
            .fs_event_id
            .cmp(&rhs.event.fs_event_id)
            .then_with(|| lhs.input_order.cmp(&rhs.input_order))
    });

    for ordered in ordered_events {
        let event = ordered.event;
        match coalesced.get_mut(&event.path) {
            Some(existing) => merge_coalesced_event(existing, event),
            None => {
                coalesced.insert(event.path.clone(), event);
            }
        }
    }

    let mut events = coalesced.into_values().collect::<Vec<_>>();
    events.sort_by(|lhs, rhs| {
        lhs.fs_event_id
            .cmp(&rhs.fs_event_id)
            .then_with(|| lhs.path.cmp(&rhs.path))
    });
    Ok((events, max_sync_event_id))
}

fn merge_coalesced_event(existing: &mut ExternalEvent, candidate: ExternalEvent) {
    existing.fs_event_id = candidate.fs_event_id;
    // Modified only carries a later watermark when another kind already describes final state.
    if candidate.kind != ExternalEventKind::Modified {
        existing.kind = candidate.kind;
    }
}

pub(super) fn affected_node_for_event(
    repo: &Path,
    event: &ExternalEvent,
) -> CoreResult<Option<String>> {
    resolve_file_event_path(repo, &event.path)
        .map(|resolved| resolved.map(|path| category_for_relative_path(&path.relative_path)))
}

pub(super) fn resolve_file_event_path(
    repo: &Path,
    raw_path: &str,
) -> CoreResult<Option<ResolvedEventPath>> {
    let Some(resolved) = resolve_event_path(repo, raw_path)? else {
        return Ok(None);
    };
    if !has_icloud_placeholder_marker(Path::new(&resolved.relative_path)) {
        return Ok(Some(resolved));
    }

    if fs::symlink_metadata(&resolved.absolute_path).is_err() {
        if let Some(materialized_relative_path) =
            materialized_icloud_relative_path(&resolved.relative_path)
        {
            let materialized_absolute_path = repo.join(&materialized_relative_path);
            if fs::symlink_metadata(&materialized_absolute_path).is_ok() {
                return Ok(Some(ResolvedEventPath {
                    absolute_path: materialized_absolute_path,
                    relative_path: materialized_relative_path,
                }));
            }
        }
    }
    Err(CoreError::icloud_placeholder(resolved.relative_path))
}

pub(super) fn resolve_event_path(
    repo: &Path,
    raw_path: &str,
) -> CoreResult<Option<ResolvedEventPath>> {
    if raw_path.trim().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let raw = Path::new(raw_path);
    let relative_path = if raw.is_absolute() {
        relative_repo_path(repo, raw)?
    } else {
        normalize_relative_path(raw)?
    };
    if should_skip_relative_path(&relative_path) {
        return Ok(None);
    }

    Ok(Some(ResolvedEventPath {
        absolute_path: repo.join(&relative_path),
        relative_path,
    }))
}

pub(super) fn should_skip_event(
    repo: &Path,
    raw_path: &str,
    renamed_file_ids_by_target: &BTreeMap<String, i64>,
) -> CoreResult<bool> {
    let Some(resolved) = resolve_event_path(repo, raw_path)? else {
        return Ok(true);
    };
    is_managed_note_sidecar(repo, &resolved.relative_path, renamed_file_ids_by_target)
}

fn is_managed_note_sidecar(
    repo: &Path,
    relative_path: &str,
    renamed_file_ids_by_target: &BTreeMap<String, i64>,
) -> CoreResult<bool> {
    let Some(file_path) = relative_path.strip_suffix(".md") else {
        return Ok(false);
    };
    let file_id = match renamed_file_ids_by_target.get(file_path) {
        Some(file_id) => *file_id,
        None => match db::find_active_file_by_path(repo, file_path)? {
            Some(file) => file.id,
            None => return Ok(false),
        },
    };
    db::read_note_content(repo, file_id).map(|note| note.is_some())
}

fn normalize_relative_path(path: &Path) -> CoreResult<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let Some(part) = part.to_str() else {
                    return Err(CoreError::invalid_path("invalid path"));
                };
                validate_relative_component(part)?;
                parts.push(part.to_owned());
            }
            _ => return Err(CoreError::invalid_path("invalid path")),
        }
    }
    if parts.is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(parts.join("/"))
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    let relative = path
        .strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))?;
    normalize_relative_path(relative)
}

fn validate_relative_component(component: &str) -> CoreResult<()> {
    if component.is_empty() || component == "." || component == ".." {
        return Err(CoreError::invalid_path("invalid path"));
    }
    if component
        .chars()
        .any(|ch| ch.is_control() || FORBIDDEN_COMPONENT_CHARS.contains(&ch))
    {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(())
}

fn should_skip_relative_path(relative_path: &str) -> bool {
    relative_path == ROOT_OVERVIEW_FILE
        || relative_path
            .split('/')
            .any(|component| component == AREA_MATRIX_DIR)
}

pub(super) fn has_icloud_placeholder_marker(path: &Path) -> bool {
    path.components().any(|component| {
        component
            .as_os_str()
            .to_string_lossy()
            .to_ascii_lowercase()
            .ends_with(".icloud")
    })
}

pub(super) fn materialized_icloud_relative_path(relative_path: &str) -> Option<String> {
    let mut changed = false;
    let mut components = Vec::new();
    for component in relative_path.split('/') {
        let lower = component.to_ascii_lowercase();
        if lower.ends_with(".icloud") {
            let without_suffix = &component[..component.len() - ".icloud".len()];
            let materialized = without_suffix.strip_prefix('.').unwrap_or(without_suffix);
            if materialized.is_empty() {
                return None;
            }
            components.push(materialized);
            changed = true;
        } else {
            components.push(component);
        }
    }
    changed.then(|| components.join("/"))
}

pub(super) fn category_for_relative_path(relative_path: &str) -> String {
    match relative_path.split_once('/') {
        Some((top_level, _)) if !top_level.is_empty() => top_level.to_owned(),
        _ => "__root__".to_owned(),
    }
}

pub(super) fn file_name_from_relative(relative_path: &str) -> CoreResult<String> {
    relative_path
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
}

pub(super) fn validate_event_id(event_id: i64) -> CoreResult<()> {
    if event_id < 0 {
        Err(CoreError::invalid_path("invalid path"))
    } else {
        Ok(())
    }
}

fn max_event_id(current: Option<i64>, candidate: i64) -> i64 {
    current.map_or(candidate, |value| value.max(candidate))
}
