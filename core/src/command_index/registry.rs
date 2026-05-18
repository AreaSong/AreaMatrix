use std::path::PathBuf;

use crate::{db, CommandIndexContext, CoreError, CoreResult, SavedSearch};

use super::{CommandTarget, CommandTargetAction, CommandTargetGroup, CommandTargetKind};

pub(super) fn selected_active_count(
    repo: &PathBuf,
    context: &CommandIndexContext,
) -> CoreResult<usize> {
    let count = db::count_active_command_selection_files(repo, &context.selected_file_ids)?;
    usize::try_from(count).map_err(|_| CoreError::db("command index selection count is invalid"))
}

pub(super) fn command_targets() -> Vec<CommandTarget> {
    vec![
        target(
            "command.import-files",
            "Import files...",
            "Open the import sheet",
            CommandTargetGroup::Commands,
            CommandTargetKind::Command,
            CommandTargetAction::OpenSheet,
            Some("import"),
        )
        .with_shortcut("Cmd+I"),
        target(
            "command.open-repository",
            "Open repository...",
            "Choose an AreaMatrix repository",
            CommandTargetGroup::Commands,
            CommandTargetKind::Command,
            CommandTargetAction::OpenSheet,
            Some("open-repository"),
        )
        .with_shortcut("Cmd+O"),
        target(
            "command.search-files",
            "Search files...",
            "Open repository search",
            CommandTargetGroup::Commands,
            CommandTargetKind::Command,
            CommandTargetAction::OpenSearch,
            Some("search"),
        )
        .with_shortcut("Cmd+F"),
        target(
            "command.help",
            "Help",
            "Open AreaMatrix help",
            CommandTargetGroup::Commands,
            CommandTargetKind::Command,
            CommandTargetAction::Navigate,
            Some("help"),
        ),
    ]
}

pub(super) fn navigation_targets() -> Vec<CommandTarget> {
    vec![
        target(
            "nav.settings",
            "Settings",
            "Open repository settings",
            CommandTargetGroup::Navigation,
            CommandTargetKind::Navigation,
            CommandTargetAction::Navigate,
            Some("settings"),
        )
        .with_shortcut("Cmd+,"),
        target(
            "nav.smart-lists",
            "Smart Lists",
            "Open Smart Lists",
            CommandTargetGroup::Navigation,
            CommandTargetKind::Navigation,
            CommandTargetAction::Navigate,
            Some("smart-lists"),
        ),
        target(
            "nav.needs-review",
            "Needs Review",
            "Open review queue",
            CommandTargetGroup::Navigation,
            CommandTargetKind::Navigation,
            CommandTargetAction::Navigate,
            Some("needs-review"),
        ),
    ]
}

pub(super) fn current_selection_targets(
    requested_count: usize,
    active_count: usize,
) -> Vec<CommandTarget> {
    let state = SelectionCommandState::new(requested_count, active_count);
    vec![
        selection_target(
            "selection.add-tags",
            add_tags_title(requested_count),
            "Open tag editor",
            CommandTargetAction::OpenSheet,
            "S2-09",
            false,
            &state,
        ),
        selection_target(
            "selection.change-category",
            change_category_title(requested_count),
            "Preview category change",
            CommandTargetAction::OpenConfirmation,
            "S2-12",
            true,
            &state,
        ),
        selection_target(
            "selection.rename",
            rename_title(requested_count),
            "Preview rename",
            CommandTargetAction::OpenConfirmation,
            "S2-14",
            true,
            &state,
        ),
        selection_target(
            "selection.delete",
            delete_title(requested_count),
            "Open delete confirmation",
            CommandTargetAction::OpenConfirmation,
            "S2-13",
            true,
            &state,
        ),
    ]
}

pub(super) fn smart_list_targets(
    repo: &PathBuf,
    query: Option<&str>,
) -> CoreResult<Vec<CommandTarget>> {
    let targets = db::list_saved_search_rows(repo)?
        .into_iter()
        .map(smart_list_target)
        .collect();
    Ok(filter_targets(targets, query))
}

pub(super) fn file_candidate_targets(
    repo: &PathBuf,
    context: &CommandIndexContext,
    query: Option<&str>,
) -> CoreResult<Vec<CommandTarget>> {
    if !context.include_file_candidates {
        return Ok(Vec::new());
    }

    let rows = db::list_command_file_candidate_rows(
        repo,
        query,
        context.current_path.as_deref(),
        file_candidate_limit(query),
    )?;
    Ok(rows
        .into_iter()
        .map(|row| {
            let mut target = target(
                format!("file:{}", row.id),
                row.current_name,
                file_candidate_subtitle(&row.path, &row.category),
                CommandTargetGroup::FileCandidates,
                CommandTargetKind::FileCandidate,
                CommandTargetAction::FocusFile,
                None::<String>,
            );
            target.file_id = Some(row.id);
            target
        })
        .collect())
}

pub(super) fn filter_targets(
    targets: Vec<CommandTarget>,
    query: Option<&str>,
) -> Vec<CommandTarget> {
    let Some(query) = query else {
        return targets;
    };
    targets
        .into_iter()
        .filter(|target| target_matches(target, query))
        .collect()
}

pub(super) fn normalized_query(query: Option<&str>) -> Option<String> {
    query
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_lowercase)
}

fn smart_list_target(saved: SavedSearch) -> CommandTarget {
    let mut target = target(
        format!("smart-list:{}", saved.id),
        saved.name,
        "Run Smart List",
        CommandTargetGroup::SmartLists,
        CommandTargetKind::SmartList,
        CommandTargetAction::RunSmartList,
        None::<String>,
    );
    target.saved_search_id = Some(saved.id);
    target.shortcut = saved.pinned.then(|| "Cmd+4".to_owned());
    target
}

fn file_candidate_limit(query: Option<&str>) -> i64 {
    if query.is_some() {
        20
    } else {
        8
    }
}

fn file_candidate_subtitle(path: &str, category: &str) -> String {
    if category.trim().is_empty() {
        path.to_owned()
    } else {
        format!("{path} · {category}")
    }
}

fn target_matches(target: &CommandTarget, query: &str) -> bool {
    target.id.to_lowercase().contains(query)
        || target.title.to_lowercase().contains(query)
        || target
            .subtitle
            .as_deref()
            .is_some_and(|subtitle| subtitle.to_lowercase().contains(query))
        || target
            .route
            .as_deref()
            .is_some_and(|route| route.to_lowercase().contains(query))
}

fn selection_target(
    id: &str,
    title: String,
    subtitle: &str,
    action: CommandTargetAction,
    route: &str,
    requires_confirmation: bool,
    state: &SelectionCommandState,
) -> CommandTarget {
    let mut target = target(
        id,
        title,
        subtitle,
        CommandTargetGroup::CurrentSelection,
        CommandTargetKind::Command,
        action,
        Some(route),
    );
    target.requires_confirmation = requires_confirmation;
    target.disabled = state.disabled;
    target.disabled_reason = state.disabled_reason.clone();
    if let Some(reason) = &target.disabled_reason {
        target.subtitle = Some(reason.clone());
    }
    target
}

fn target(
    id: impl Into<String>,
    title: impl Into<String>,
    subtitle: impl Into<String>,
    group: CommandTargetGroup,
    kind: CommandTargetKind,
    action: CommandTargetAction,
    route: Option<impl Into<String>>,
) -> CommandTarget {
    CommandTarget {
        id: id.into(),
        title: title.into(),
        subtitle: Some(subtitle.into()),
        group,
        kind,
        action,
        route: route.map(Into::into),
        shortcut: None,
        disabled: false,
        disabled_reason: None,
        requires_confirmation: false,
        file_id: None,
        saved_search_id: None,
    }
}

fn add_tags_title(count: usize) -> String {
    selection_count_title("Add tags", count)
}

fn change_category_title(count: usize) -> String {
    selection_count_title("Change category", count)
}

fn rename_title(count: usize) -> String {
    selection_count_title("Rename", count)
}

fn delete_title(count: usize) -> String {
    selection_count_title("Delete", count)
}

fn selection_count_title(prefix: &str, count: usize) -> String {
    match count {
        0 => prefix.to_owned(),
        1 => format!("{prefix} selected file..."),
        value => format!("{prefix} {value} selected files..."),
    }
}

#[derive(Clone)]
struct SelectionCommandState {
    disabled: bool,
    disabled_reason: Option<String>,
}

impl SelectionCommandState {
    fn new(requested_count: usize, active_count: usize) -> Self {
        if requested_count == 0 {
            return Self::disabled("Select files first.");
        }
        if requested_count != active_count {
            return Self::disabled("Selected files are unavailable.");
        }
        Self {
            disabled: false,
            disabled_reason: None,
        }
    }

    fn disabled(reason: &str) -> Self {
        Self {
            disabled: true,
            disabled_reason: Some(reason.to_owned()),
        }
    }
}

trait CommandTargetExt {
    fn with_shortcut(self, shortcut: &str) -> Self;
}

impl CommandTargetExt for CommandTarget {
    fn with_shortcut(mut self, shortcut: &str) -> Self {
        self.shortcut = Some(shortcut.to_owned());
        self
    }
}
