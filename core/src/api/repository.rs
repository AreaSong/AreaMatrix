//! Public FFI repository entry points.

use crate::{
    db, overview, recovery, repair, repo_init, repo_path, repo_scan, ContentLocale, CoreResult,
    DiagnosticsSnapshot, ManualRescanPreviewReport, OverviewLanguageStatus,
    OverviewRegenerationPlan, OverviewRegenerationSession, OverviewRegenerationStartRequest,
    RecoveryReport, ReindexReport, RepairMetadataPreflight, RepairOptions, RepairReport,
    RepoConfig, RepoConfigPatch, RepoConfigSnapshot, RepoInitOptions, RepoPathValidation,
    ScanSession,
};

/// Validates a candidate repository path without mutating the filesystem.
///
/// The repository path validation accepts a user-selected repository directory path and
/// returns structured status flags, a recommended initialization mode, and
/// display-ready issues for the Swift UI. This API is read-only: it must not
/// create `.areamatrix/`, initialize a database, move user files, or trigger
/// iCloud placeholder downloads.
///
/// The mobile repository connection contract reuses the same surface
/// after the platform layer has granted access to an iOS security-scoped URL or
/// provider path. Core receives only the authorized filesystem path; picker,
/// bookmark, and cloud-permission lifecycles stay outside the Rust boundary.
///
/// The Linux repository connection contract also reuses this read-only
/// surface. Linux shells can route from `platform_path_kind`, read/write flags,
/// `recommended_mode`, and `issues` to local-folder, init, or adopt confirmation
/// pages without parsing error text. Core does not run or recommend sudo/chmod;
/// path pickers, mount details, file-manager integration, and sync-provider
/// setup stay outside the Rust boundary.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for empty or metadata-internal paths,
/// `CoreError::PermissionDenied { path }` when metadata or directory checks are blocked,
/// or `CoreError::ICloudPlaceholder { path }` for unavailable iCloud-managed paths.
pub fn validate_repo_path(repo_path: String) -> CoreResult<RepoPathValidation> {
    repo_path::validate_repo_path(repo_path)
}

/// Validates that a repository path already has AreaMatrix metadata.
///
/// This read-only variant is for main-window recovery and reopen flows that
/// require an initialized repository. New-repository onboarding should keep
/// using [`validate_repo_path`] so non-empty folders can still be offered as
/// `AdoptExisting` candidates.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when the path is a readable
/// directory but lacks `.areamatrix/` metadata. Other path, permission, iCloud,
/// and metadata-read failures follow [`validate_repo_path`].
pub fn validate_initialized_repo_path(repo_path: String) -> CoreResult<RepoPathValidation> {
    repo_path::validate_initialized_repo_path(repo_path)
}

/// Initializes AreaMatrix metadata for a repository root.
///
/// The empty repository initialization uses `RepoInitOptions { mode: CreateEmpty, .. }` for an
/// empty user-selected directory. A successful call creates only AreaMatrix
/// metadata: `.areamatrix/index.db`, `.areamatrix/staging/`,
/// `.areamatrix/archives/`, `.areamatrix/generated/`, default classifier and
/// ignore config files, and the generated root overview under
/// `.areamatrix/generated/root.md`.
///
/// The adopt-existing repository scan uses `RepoInitOptions { mode: AdoptExisting, .. }` for a
/// non-empty user-selected directory. That mode has the same metadata-write
/// boundary plus an adoption scan session: existing user files remain in place,
/// are indexed with `FileOrigin::Adopted`, and can be resumed through
/// [`get_latest_scan_session`] and [`resume_scan_session`]. Adopt mode must skip
/// `.areamatrix/`, generated overviews, system temporary files, and root
/// `AREAMATRIX.md` while treating `README.md` as normal user content.
///
/// The API returns `Ok(())` after the empty repository can be read through
/// [`load_config`], `list_files`, and [`list_tree_json`]. It must never create,
/// delete, move, rename, or overwrite user-authored files such as `README.md`.
/// When a previous attempt left a recoverable `.areamatrix.init-*` metadata
/// directory, retrying initialization may remove only that internal temporary
/// state before creating the final `.areamatrix/` directory.
///
/// generated overview uses `RepoInitOptions::overview_output` as the initial generated
/// overview policy. `OverviewOutput::GeneratedOnly` writes the generated root
/// overview only under `.areamatrix/generated/`; `RootAreaMatrixFile` also
/// creates a root-level `AREAMATRIX.md` for an empty repository. `README.md`
/// remains user content and is never created or overwritten by this API.
///
/// For mobile repository connection, mobile shells call this only after the shared init/adopt
/// confirmation pages have converted a [`RepoPathValidation`] recommendation
/// into explicit user consent. The API does not bypass those pages and does not
/// perform iOS security-scoped bookmark or cloud-provider permission work.
///
/// For Linux repository connection, Linux shells call this only after local-folder, init, or adopt
/// confirmation pages have converted the [`RepoPathValidation`] result into
/// explicit user consent. The API does not bypass those pages, does not
/// adjust POSIX permissions, and does not configure third-party sync or mount options.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for empty paths or `.areamatrix` internals,
/// `CoreError::PermissionDenied { path }` for unwritable roots, `CoreError::Config { reason }` for
/// invalid init options or repeated initialization, `CoreError::Io { message }` for
/// filesystem failures, and `CoreError::Db { message }` for SQLite initialization failures.
pub fn init_repo(repo_path: String, options: RepoInitOptions) -> CoreResult<()> {
    repo_init::init_repo(repo_path, options)
}

/// Loads repository configuration written during initialization.
///
/// empty repository initialization requires this API to read the `repo_config` state created by
/// [`init_repo`] for an empty repository.
///
/// mobile repository connection uses the same configuration snapshot after a mobile shell has
/// validated or initialized the selected repository. Loading config is read-only
/// and does not refresh platform permissions or create metadata.
///
/// repository settings also reuses this config snapshot for the
/// cross-platform repository settings page. Page consumers combine it with
/// [`get_platform_capabilities`] to render unsupported settings as disabled
/// with structured reasons instead of inferring platform support in the UI.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }`, `CoreError::PermissionDenied { path }`,
/// `CoreError::Io { message }`, or `CoreError::Db { message }` when the initialized metadata
/// cannot be read or decoded.
pub fn load_config(repo_path: String) -> CoreResult<RepoConfig> {
    db::load_config_or_default(repo_path)
}

/// Loads a revisioned repository configuration snapshot.
pub fn load_repo_config(repo_path: String) -> CoreResult<RepoConfigSnapshot> {
    db::load_repo_config_snapshot_or_default(repo_path)
}

/// Updates repository configuration through the `repo_config` table.
///
/// repository configuration update uses this API for settings panes that mutate repository defaults:
/// storage mode, overview output policy, AI feature flag, locale, and iCloud
/// warning preference. The call is transactional: either all config keys are
/// updated with a fresh `updated_at` value, or the previously persisted config
/// remains readable through [`load_config`].
///
/// The API only persists the settings contract. It does not create
/// `AREAMATRIX.md`, rewrite `classifier.yaml`, touch `README.md`, or perform
/// any adjacent import, overview, or classifier behavior.
/// For generated overview, this is the contract boundary for changing the persisted
/// `OverviewOutput` policy: later overview-regeneration triggers read the
/// policy from `repo_config`, while the settings call itself stays free of
/// file side effects.
/// repository settings uses the same transactional update surface for
/// cross-platform shells. Callers must first consult [`get_platform_capabilities`]
/// and keep unsupported rows disabled; this function persists only the supplied
/// repository configuration and does not test, enable, or emulate platform
/// watcher, cloud placeholder, security bookmark, Trash, or account features.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for mismatched or invalid payloads and missing
/// initialized metadata, `CoreError::PermissionDenied { path }` for unwritable metadata,
/// `CoreError::Io { message }` for filesystem inspection failures, and `CoreError::Db { message }` for
/// SQLite persistence failures.
pub fn update_config(repo_path: String, new_config: RepoConfig) -> CoreResult<()> {
    db::update_config(repo_path, new_config)
}

/// Applies a compare-and-swap repository configuration patch.
pub fn update_repo_config(
    repo_path: String,
    patch: RepoConfigPatch,
) -> CoreResult<RepoConfigSnapshot> {
    db::update_repo_config_patch(repo_path, patch)
}
/// Recovers AreaMatrix-owned startup residue before the UI opens.
///
/// startup recovery exposes this API for first-launch initialization, main-window
/// reopening, advanced settings, and error-recovery surfaces. The input is an
/// initialized repository root. The output reports how many safe staging files
/// were removed, how many unfinished `files.status = staging` rows were
/// reverted, and any warnings that error recovery surface can display without parsing logs.
///
/// The only allowed filesystem side effect is cleanup inside the
/// AreaMatrix-owned `.areamatrix/staging/` directory. The API must not delete,
/// move, rename, overwrite, or reclassify any active repository file or other
/// user-authored final content. Startup recovery does not repair corrupted
/// databases, reindex the repository, process FSEvents, or generate overviews;
/// those adjacent capabilities stay with their dedicated API contracts.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is absent,
/// `CoreError::PermissionDenied { path }` when metadata or staging cannot be inspected
/// or updated, `CoreError::Io { message }` for staging filesystem failures, and
/// `CoreError::Db { message }` for SQLite recovery failures.
pub fn recover_on_startup(repo_path: String) -> CoreResult<RecoveryReport> {
    recovery::recover_on_startup(repo_path)
}

/// Previews manual rescan impact without writing metadata or user files.
///
/// rescan confirmation surface calls this before enabling the high-risk confirmation. The preview
/// scans the initialized repository and compares it with existing metadata, but
/// it must not create `scan_sessions`, write `files`, write `change_log`, move,
/// delete, rename, overwrite, Trash, or download user files. The returned
/// summary exposes added, updated, missing, possible rename, conflict,
/// unreadable, unknown, and skipped counts plus bounded sample items so the UI
/// can route unresolved rows to Needs Review.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when metadata cannot be read,
/// `CoreError::PermissionDenied { path }` when repository content or metadata
/// cannot be inspected, `CoreError::Io { message }` for filesystem traversal
/// failures, and `CoreError::Conflict { path }` when another manual rescan is
/// already running.
pub fn preview_manual_rescan(repo_path: String) -> CoreResult<ManualRescanPreviewReport> {
    repo_scan::preview_manual_rescan(repo_path)
}

/// Reindexes repository metadata from the current filesystem state.
///
/// metadata repair exposes this full-rescan API for repair and advanced settings flows.
/// The input is an initialized repository root. Core may create or reuse a
/// `scan_sessions(kind = Reindex)` row, update `.areamatrix/index.db` metadata,
/// and return inserted/updated/skipped counters in [`ReindexReport`].
///
/// manual rescan also uses this entry point for Windows/Linux manual rescan after
/// rescan confirmation has shown [`preview_manual_rescan`] and the high-risk confirmation.
/// The manual rescan scope is the entire repository; partial subtree rescan is not
/// exposed by this contract. Consumers combine the returned [`ReindexReport`]
/// with [`get_latest_scan_session`] to render the rescan summary, persisted
/// session status, counters, timestamps, and errors.
///
/// The API treats filesystem content as read-only input. It must skip
/// `.areamatrix/`, `.areamatrix/generated/`, root `AREAMATRIX.md`, ignored
/// directories, and system temporary files. It must not move, rename, delete,
/// overwrite, trash, or download user files, and it must not overwrite
/// `README.md`.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when scan-session or file metadata cannot
/// be read or written, `CoreError::PermissionDenied { path }` when repository
/// content or metadata cannot be inspected, `CoreError::Io { message }` for
/// filesystem traversal failures, `CoreError::Conflict { path }` when another
/// manual rescan is already running, and `CoreError::Internal { message }` for
/// invariant failures that should be surfaced through error mapping.
pub fn reindex_from_filesystem(repo_path: String) -> CoreResult<ReindexReport> {
    repair::reindex_from_filesystem(repo_path)
}

pub fn prepare_overview_regeneration(
    repo_path: String,
    content_locale: ContentLocale,
) -> CoreResult<OverviewRegenerationPlan> {
    overview::regeneration::prepare(repo_path, content_locale)
}

pub fn start_overview_regeneration(
    repo_path: String,
    request: OverviewRegenerationStartRequest,
) -> CoreResult<OverviewRegenerationSession> {
    overview::regeneration::start(repo_path, request)
}

pub fn commit_overview_regeneration(
    repo_path: String,
    operation_id: String,
) -> CoreResult<OverviewRegenerationSession> {
    overview::regeneration::commit(repo_path, operation_id)
}

pub fn get_overview_regeneration(
    repo_path: String,
    operation_id: String,
) -> CoreResult<OverviewRegenerationSession> {
    overview::regeneration::get(repo_path, operation_id)
}

pub fn recover_overview_regeneration_on_startup(
    repo_path: String,
) -> CoreResult<Option<OverviewRegenerationSession>> {
    overview::regeneration::recover_on_startup(repo_path)
}

pub fn resume_overview_regeneration(
    repo_path: String,
    operation_id: String,
) -> CoreResult<OverviewRegenerationSession> {
    overview::regeneration::resume(repo_path, operation_id)
}

pub fn cancel_overview_regeneration(
    repo_path: String,
    operation_id: String,
) -> CoreResult<OverviewRegenerationSession> {
    overview::regeneration::cancel(repo_path, operation_id)
}

pub fn rollback_overview_regeneration(
    repo_path: String,
    operation_id: String,
) -> CoreResult<OverviewRegenerationSession> {
    overview::regeneration::rollback(repo_path, operation_id)
}

pub fn get_overview_language_status(
    repo_path: String,
    content_locale: ContentLocale,
) -> CoreResult<OverviewLanguageStatus> {
    overview::regeneration::language_status(repo_path, content_locale)
}

/// Creates a diagnostics snapshot for metadata repair.
///
/// The snapshot is AreaMatrix-owned diagnostic metadata that preserves the
/// damaged database or repair context before any mutation. Its returned path
/// must point under `.areamatrix/` so Swift can show or retain the reference
/// without scanning user-authored files.
///
/// This API must not modify repository files, generate overviews, process
/// FSEvents, upload diagnostics, or write outside AreaMatrix metadata.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when metadata cannot be opened or read,
/// `CoreError::PermissionDenied { path }` when diagnostics cannot be written,
/// `CoreError::Io { message }` for filesystem failures, and
/// `CoreError::Internal { message }` for invalid repair invariants.
pub fn create_diagnostics_snapshot(repo_path: String) -> CoreResult<DiagnosticsSnapshot> {
    repair::create_diagnostics_snapshot(repo_path)
}

/// Inspects metadata and locale state without creating or modifying files.
pub fn preflight_repair_metadata(repo_path: String) -> CoreResult<RepairMetadataPreflight> {
    repair::preflight_repair_metadata(repo_path)
}

/// Repairs AreaMatrix metadata without mutating user files.
///
/// metadata repair uses [`RepairOptions::preserve_diagnostics_snapshot`] to decide
/// whether the damaged metadata state is preserved before replacement. It does
/// not start or resume filesystem reindex or overview regeneration operations.
///
/// The only allowed side effects are writes under `.areamatrix/` metadata:
/// diagnostics snapshots and repaired metadata. The
/// function must never move, rename, delete, overwrite, trash, or download user
/// files, and failure must leave any diagnostics reference intact.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` for SQLite corruption or persistence
/// failures, `CoreError::PermissionDenied { path }` for blocked metadata access,
/// `CoreError::Io { message }` for repository traversal or snapshot failures,
/// and `CoreError::Internal { message }` for inconsistent repair state.
pub fn repair_metadata(repo_path: String, options: RepairOptions) -> CoreResult<RepairReport> {
    repair::repair_metadata(repo_path, options)
}

/// Returns the latest adopt or reindex scan session if one exists.
///
/// adopt-existing repository scan consumers use this read-only API to recover the state of an unfinished
/// or recently completed adoption scan. It reports the persisted session kind,
/// lifecycle status, last processed path, counters, timestamps, and recorded
/// errors without touching user files or starting a new scan.
///
/// manual rescan consumers use the same read-only session contract to display manual
/// rescan progress, completion, failure, interruption, and retry state after
/// the rescan confirmation surface confirmation route. This function does not start a scan, resume
/// a scan, or inspect user file contents.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when scan-session metadata cannot be read,
/// `CoreError::Io { message }` when repository metadata cannot be inspected, and
/// `CoreError::InvalidPath { path }` or `CoreError::PermissionDenied { path }` for invalid or
/// inaccessible repository roots.
pub fn get_latest_scan_session(repo_path: String) -> CoreResult<Option<ScanSession>> {
    repo_scan::get_latest_scan_session(repo_path)
}

/// Resumes a paused, interrupted, or failed adopt/reindex scan session.
///
/// For adopt-existing repository scan, this is the continuation path for `AdoptExisting` sessions. The
/// contract is idempotent: already-indexed files are updated in place, new files
/// are inserted with the original layout preserved, and a completed session
/// returns an empty report instead of mutating user files.
///
/// For manual rescan, this resumes an interrupted or failed entire-repository manual
/// rescan only after the UI has routed the user through rescan confirmation recovery flow.
/// It must not bypass confirmation, start a concurrent rescan, or expose
/// Windows/Linux watcher controls.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when the session or indexed rows cannot be persisted,
/// `CoreError::Io { message }` for filesystem inspection failures, `CoreError::InvalidPath { path }`
/// for malformed repository paths, and `CoreError::PermissionDenied { path }` when the
/// repository cannot be inspected or metadata cannot be updated.
pub fn resume_scan_session(repo_path: String, scan_session_id: i64) -> CoreResult<ReindexReport> {
    repo_scan::resume_scan_session(repo_path, scan_session_id)
}
