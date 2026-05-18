//! C2-11 command index contract types and boundary.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";

/// Current command-palette context supplied by the app layer.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CommandIndexContext {
    /// Current text in the command palette search field.
    pub query: Option<String>,
    /// Selected file ids in current UI order.
    pub selected_file_ids: Vec<i64>,
    /// Repository-relative current tree or search path, when one is active.
    pub current_path: Option<String>,
    /// Whether file candidates should be returned with command targets.
    pub include_file_candidates: bool,
}

/// UI grouping for one command-palette target.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum CommandTargetGroup {
    /// General executable commands.
    Commands,
    /// Navigation destinations such as Settings or Smart Lists.
    Navigation,
    /// Commands that depend on the current file selection.
    CurrentSelection,
    /// Recently used command targets.
    Recent,
    /// Saved Smart List targets.
    SmartLists,
    /// File candidates that can be focused from the palette.
    FileCandidates,
}

/// Stable command target kind consumed by S2-15.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum CommandTargetKind {
    /// Built-in application command.
    Command,
    /// Navigation destination.
    Navigation,
    /// Saved Smart List target owned by C2-04.
    SmartList,
    /// File candidate opened by focusing existing metadata.
    FileCandidate,
    /// Recently used command or destination.
    RecentCommand,
}

/// Action boundary for executing a command target.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum CommandTargetAction {
    /// Navigate to an existing app route.
    Navigate,
    /// Open a non-destructive sheet.
    OpenSheet,
    /// Open a confirmation or preview surface before any risky action.
    OpenConfirmation,
    /// Run an existing C2-04 Smart List by id.
    RunSmartList,
    /// Focus an existing file candidate.
    FocusFile,
    /// Open search with the provided query or route metadata.
    OpenSearch,
    /// Execute a low-risk app action that does not mutate user files.
    LowRiskAction,
}

/// One target returned to the command palette.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CommandTarget {
    /// Stable command id, route id, saved-search id wrapper, or file wrapper.
    pub id: String,
    /// User-visible row title.
    pub title: String,
    /// Optional row subtitle or disabled reason detail.
    pub subtitle: Option<String>,
    /// Section where the row should be rendered.
    pub group: CommandTargetGroup,
    /// Target kind used by the app router.
    pub kind: CommandTargetKind,
    /// Execution boundary for the target.
    pub action: CommandTargetAction,
    /// Optional app route or sheet identifier.
    pub route: Option<String>,
    /// Optional shortcut hint, such as `Cmd+I`.
    pub shortcut: Option<String>,
    /// Whether the row is visible but unavailable.
    pub disabled: bool,
    /// Stable disabled reason for accessibility and retry UI.
    pub disabled_reason: Option<String>,
    /// Whether selecting the row must open confirmation instead of executing.
    pub requires_confirmation: bool,
    /// File id for `FileCandidate` targets.
    pub file_id: Option<i64>,
    /// Saved search id for `SmartList` targets.
    pub saved_search_id: Option<i64>,
}

/// Command-palette index returned to S2-15 consumers.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CommandIndex {
    /// General command rows after context and permission filtering.
    pub commands: Vec<CommandTarget>,
    /// Navigation targets such as Settings, Smart Lists, or Needs Review.
    pub navigation_targets: Vec<CommandTarget>,
    /// Selection-dependent command rows.
    pub current_selection_targets: Vec<CommandTarget>,
    /// Recently used commands or destinations.
    pub recent_targets: Vec<CommandTarget>,
    /// Saved Smart List targets discoverable by command palette.
    pub smart_lists: Vec<CommandTarget>,
    /// File candidates returned only when requested by context.
    pub file_candidates: Vec<CommandTarget>,
    /// Unix timestamp for the metadata snapshot.
    pub generated_at: i64,
}

/// Lists C2-11 command-palette targets without executing commands.
///
/// S2-15 uses this read-only contract to obtain grouped command rows, Smart
/// List navigation targets, recent commands, file candidates, disabled reasons,
/// and confirmation boundaries. The caller passes the current selection context
/// so Core can mark selection-only commands as available, disabled, or hidden
/// without letting the command palette bypass the owning confirmation pages.
///
/// This contract must never execute destructive actions, mutate files, write
/// classifier rules, run redo/import-conflict/tag-suggestion behavior, call
/// AI/network providers, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when command metadata, saved-search
/// metadata, recent-command metadata, or file candidate metadata cannot be
/// read. C2-11 exposes only `Db` so consumers use one command-registry failure
/// state instead of parsing lower-level storage details.
pub fn list_command_targets(
    repo_path: String,
    context: CommandIndexContext,
) -> CoreResult<CommandIndex> {
    validate_command_index_request(&repo_path, &context)?;
    Err(CoreError::db("command index metadata is not available"))
}

fn validate_command_index_request(
    repo_path: &str,
    context: &CommandIndexContext,
) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::db("command index repository path is required"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::db("command index repository path is invalid"));
    }
    validate_selection_ids(&context.selected_file_ids)?;
    validate_current_path(context.current_path.as_deref())?;
    Ok(repo)
}

fn validate_selection_ids(file_ids: &[i64]) -> CoreResult<()> {
    if file_ids.iter().any(|file_id| *file_id <= 0) {
        return Err(CoreError::db("command index selection context is invalid"));
    }
    Ok(())
}

fn validate_current_path(path: Option<&str>) -> CoreResult<()> {
    let Some(path) = path else {
        return Ok(());
    };
    if path.trim().is_empty() || path.contains('\0') {
        return Err(CoreError::db("command index current path is invalid"));
    }
    let candidate = PathBuf::from(path);
    if candidate.components().any(is_forbidden_relative_component) {
        return Err(CoreError::db("command index current path is invalid"));
    }
    Ok(())
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}

fn is_forbidden_relative_component(component: Component<'_>) -> bool {
    matches!(
        component,
        Component::ParentDir | Component::RootDir | Component::Prefix(_)
    )
}
