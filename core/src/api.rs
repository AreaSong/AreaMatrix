//! Public functions exposed through the UniFFI boundary.

use std::path::PathBuf;

use crate::{
    batch_category, batch_delete, batch_rename as batch_rename_mod, classifier_correction,
    classifier_impact, classifier_rule_editor, classifier_rules, classify, db, icloud_conflicts,
    note, recovery, repair, repo_init, repo_path, repo_scan, storage, sync, tree,
    BatchCategoryChangeReport, BatchCategoryPreviewReport, BatchDeleteMode,
    BatchDeletePreviewReport, BatchDeleteReport, BatchRenamePreviewReport, BatchRenameReport,
    BatchRenameRule, ChangeFilter, ChangeLogEntry, ClassifierCorrectionResult,
    ClassifierImpactPreviewRequest, ClassifierRule, ClassifierRuleDeleteRequest,
    ClassifierRuleEditorSnapshot, ClassifierRuleUpdate, ClassifyResult, CoreError, CoreResult,
    DiagnosticsSnapshot, ExternalEvent, FileEntry, FileFilter, ICloudConflictPair, ImportOptions,
    MoveToCategoryPreview, RecoveryReport, ReindexReport, RepairOptions, RepairReport, RepoConfig,
    RepoInitOptions, RepoPathValidation, RuleImpactReport, ScanSession, SyncResult,
};

fn not_implemented<T>() -> CoreResult<T> {
    Err(CoreError::internal("internal error"))
}

/// Returns the AreaMatrix core crate version.
pub fn get_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

/// Validates the requested logging level.
///
/// Full subscriber wiring is left for a later observability task so this
/// skeleton remains side-effect light.
pub fn init_logging(level: String) -> CoreResult<()> {
    match level.as_str() {
        "trace" | "debug" | "info" | "warn" | "error" => Ok(()),
        _ => Err(CoreError::config("configuration error")),
    }
}

/// Validates a candidate repository path without mutating the filesystem.
///
/// The C1-01 contract accepts a user-selected repository directory path and
/// returns structured status flags, a recommended initialization mode, and
/// display-ready issues for the Swift UI. This API is read-only: it must not
/// create `.areamatrix/`, initialize a database, move user files, or trigger
/// iCloud placeholder downloads.
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
/// The C1-02 contract uses `RepoInitOptions { mode: CreateEmpty, .. }` for an
/// empty user-selected directory. A successful call creates only AreaMatrix
/// metadata: `.areamatrix/index.db`, `.areamatrix/staging/`,
/// `.areamatrix/archives/`, `.areamatrix/generated/`, default classifier and
/// ignore config files, and the generated root overview under
/// `.areamatrix/generated/root.md`.
///
/// The C1-03 contract uses `RepoInitOptions { mode: AdoptExisting, .. }` for a
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
/// C1-20 uses `RepoInitOptions::overview_output` as the initial generated
/// overview policy. `OverviewOutput::GeneratedOnly` writes the generated root
/// overview only under `.areamatrix/generated/`; `RootAreaMatrixFile` also
/// creates a root-level `AREAMATRIX.md` for an empty repository. `README.md`
/// remains user content and is never created or overwritten by this API.
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
/// C1-02 requires this API to read the `repo_config` state created by
/// [`init_repo`] for an empty repository.
///
/// # Errors
///
/// Returns `CoreError::Io { message }`, `CoreError::Config { reason }`, or `CoreError::Db { message }` when the
/// initialized metadata cannot be read or decoded.
pub fn load_config(repo_path: String) -> CoreResult<RepoConfig> {
    db::load_config_or_default(repo_path)
}

/// Updates repository configuration through the `repo_config` table.
///
/// C1-04 uses this API for settings panes that mutate repository defaults:
/// storage mode, overview output policy, AI feature flag, locale, and iCloud
/// warning preference. The call is transactional: either all config keys are
/// updated with a fresh `updated_at` value, or the previously persisted config
/// remains readable through [`load_config`].
///
/// The API only persists the settings contract. It does not create
/// `AREAMATRIX.md`, rewrite `classifier.yaml`, touch `README.md`, or perform
/// any adjacent import, overview, or classifier behavior.
/// For C1-20, this is the contract boundary for changing the persisted
/// `OverviewOutput` policy: later overview-regeneration triggers read the
/// policy from `repo_config`, while the settings call itself stays free of
/// file side effects.
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

/// Recovers AreaMatrix-owned startup residue before the UI opens.
///
/// C1-16 exposes this API for first-launch initialization, main-window
/// reopening, advanced settings, and error-recovery surfaces. The input is an
/// initialized repository root. The output reports how many safe staging files
/// were removed, how many unfinished `files.status = staging` rows were
/// reverted, and any warnings that S1-32 can display without parsing logs.
///
/// The only allowed filesystem side effect is cleanup inside the
/// AreaMatrix-owned `.areamatrix/staging/` directory. The API must not delete,
/// move, rename, overwrite, or reclassify any active repository file or other
/// user-authored final content. Startup recovery does not repair corrupted
/// databases, reindex the repository, process FSEvents, or generate overviews;
/// those adjacent capabilities stay with their own C1 tasks.
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

/// Reindexes repository metadata from the current filesystem state.
///
/// C1-26 exposes this full-rescan API for repair and advanced settings flows.
/// The input is an initialized repository root. Core may create or reuse a
/// `scan_sessions(kind = Reindex)` row, update `.areamatrix/index.db` metadata,
/// and return inserted/updated/skipped counters in [`ReindexReport`].
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
/// filesystem traversal failures, and `CoreError::Internal { message }` for
/// invariant failures that should be surfaced through C1-21 error mapping.
pub fn reindex_from_filesystem(repo_path: String) -> CoreResult<ReindexReport> {
    repair::reindex_from_filesystem(repo_path)
}

/// Creates a diagnostics snapshot for C1-26 metadata repair.
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

/// Repairs AreaMatrix metadata without mutating user files.
///
/// C1-26 uses [`RepairOptions::preserve_diagnostics_snapshot`] to decide
/// whether the damaged metadata state is preserved before repair. When
/// [`RepairOptions::full_rescan`] is true, repair may run the same metadata
/// rescan boundary as [`reindex_from_filesystem`] and report the scan session.
///
/// The only allowed side effects are writes under `.areamatrix/` metadata:
/// diagnostics snapshots, scan-session rows, and repaired file metadata. The
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
/// C1-03 consumers use this read-only API to recover the state of an unfinished
/// or recently completed adoption scan. It reports the persisted session kind,
/// lifecycle status, last processed path, counters, timestamps, and recorded
/// errors without touching user files or starting a new scan.
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
/// For C1-03, this is the continuation path for `AdoptExisting` sessions. The
/// contract is idempotent: already-indexed files are updated in place, new files
/// are inserted with the original layout preserved, and a completed session
/// returns an empty report instead of mutating user files.
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

/// Predicts a category for a filename without importing or mutating files.
///
/// C1-05 uses this API for import previews and classifier settings. It reads
/// classifier rules from `.areamatrix/classifier.yaml`, falls back to the
/// bundled default rules when the file is absent, and returns a suggested
/// category/name pair. It must not create repository metadata, touch the
/// database, import files, or move user content.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the repository path, filename, YAML syntax,
/// or classifier schema is invalid. Returns `CoreError::Classify { reason }` when the
/// classifier rule source cannot be read as a file.
pub fn predict_category(repo_path: String, filename: String) -> CoreResult<ClassifyResult> {
    classify::predict_category(repo_path, filename)
}

/// Imports one source file into repository storage.
///
/// C1-06 defines the copied-file contract for `ImportOptions` values whose
/// `mode` is `StorageMode::Copied`. The source path is read as immutable input,
/// file bytes are copied through `.areamatrix/staging/`, the content hash is
/// used for duplicate detection, and a successful call returns the active
/// `FileEntry` persisted in `files` with a matching `change_log` import event.
/// The original source file must remain unchanged.
///
/// C1-07 defines the moved-file contract for `ImportOptions` values whose
/// `mode` is `StorageMode::Moved`. The source path is validated, staged under
/// AreaMatrix-owned metadata, atomically renamed into the final repository
/// destination, and recorded with `files.storage_mode = Moved`,
/// `files.source_path` set to the original source, and `change_log.action =
/// imported`. A successful moved import removes the original source path and
/// leaves the final file, DB row, and change log consistent. A failed moved
/// import must keep the original source readable or leave only recoverable
/// internal staging state; it must not cross unconfirmed user directory
/// boundaries.
///
/// C1-08 owns index-only semantics. C1-08 defines the indexed-file contract
/// for `ImportOptions` values whose `mode` is `StorageMode::Indexed`. The
/// source path is validated and may be read for metadata and hashing, but Core
/// must not copy, move, rename, or delete the source file, and must not create
/// a final repository-owned file copy. A successful indexed import records
/// `files.storage_mode = Indexed`, preserves `files.source_path`, and writes a
/// `change_log.action = imported` event so list/detail/log consumers can
/// surface the external reference. This entry point keeps copied, moved, and
/// indexed contracts explicit instead of hiding adjacent behavior behind a
/// generic import success path.
///
/// C1-09 owns duplicate detection for this entry point. Core hashes the source
/// bytes before committing a final destination. `Skip` and `Ask` return
/// `CoreError::DuplicateFile { existing_path }` with the first active path that
/// already owns the hash, and must leave the attempted source, final
/// destination, active rows, and change log unchanged. `KeepBoth` allows a
/// second active row with the same hash when the resolved destination path is
/// distinct. `Overwrite` is accepted only after the UI has made the dangerous
/// replace decision; it moves a recoverable copy of the old repo-owned file to
/// the system Trash, soft-deletes the old active row, promotes the new import,
/// and writes deleted/imported change-log entries in the same metadata
/// transition.
///
/// C1-10 owns same-name conflict handling for this entry point. The target
/// name comes from the source filename or `ImportOptions::override_filename`;
/// the output `FileEntry.path` and `FileEntry.current_name` must report the
/// final conflict-free name that was actually written. Same-name imports with
/// different content must not overwrite an existing user file by default:
/// Core resolves a safe numbered name such as `name_1.ext`, while
/// `CoreError::Conflict { path }` is reserved for exhausted or raced resolution.
/// Dangerous replacement remains explicit through `DuplicateStrategy::Overwrite`
/// after S1-24 has confirmed the user decision.
///
/// C1-20 uses a successful import as a generated-overview trigger. The trigger
/// has no extra FFI input: Core derives the changed node/category from the
/// committed [`FileEntry`] and the current [`RepoConfig::overview_output`].
/// Its allowed filesystem side effects are limited to generated markdown under
/// `.areamatrix/generated/` and, only when explicitly configured,
/// `AREAMATRIX.md`; `README.md` remains user-authored content.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for an empty, metadata-internal, or unsafe
/// source or destination path, `CoreError::FileNotFound { path }` when the source cannot
/// be found, `CoreError::DuplicateFile { existing_path }` for duplicate hashes
/// when the selected strategy requires user choice or skip behavior,
/// `CoreError::ICloudPlaceholder { path }` for unavailable iCloud placeholders,
/// `CoreError::PermissionDenied { path }` for unreadable sources or unwritable metadata,
/// `CoreError::Io { message }` for filesystem failures, and `CoreError::Db { message }` for metadata
/// persistence failures.
/// Failed imports must not leave active file rows or final destination half-products;
/// staging residue is reserved for later recovery cleanup.
pub fn import_file(
    repo_path: String,
    source_path: String,
    options: ImportOptions,
) -> CoreResult<FileEntry> {
    storage::import_file(repo_path, source_path, options)
}

/// Moves a repo-owned file entry to the system Trash and soft-deletes metadata.
///
/// C1-23 owns the user-visible delete/remove-index contract for S1-34.
/// `delete_file` is only for AreaMatrix-managed `Copied` / `Moved` active rows.
/// A successful implementation must send the target file to the system Trash,
/// mark the matching row as `files.status = deleted`, refresh `deleted_at` and
/// `updated_at`, and write `change_log.action = deleted`.
///
/// This entry point intentionally has no `hard` or permanent-delete flag. Indexed,
/// adopted, external, or missing references must use [`remove_index_entry`] so
/// external source files are never deleted as an index cleanup side effect.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when the active row or repo-owned
/// file is absent, `CoreError::PermissionDenied { path }` when Trash or metadata
/// writes are blocked, `CoreError::Io { message }` for filesystem failures,
/// `CoreError::Db { message }` for metadata persistence failures, and
/// `CoreError::Internal { message }` for unexpected Trash or state-transition failures.
pub fn delete_file(repo_path: String, file_id: i64) -> CoreResult<()> {
    storage::delete_file(repo_path, file_id)
}

/// Removes an indexed file entry from AreaMatrix without touching the source file.
///
/// C1-23 uses this explicit index-only entry point for Indexed / Adopted /
/// External / Missing references. A successful implementation must make the
/// entry disappear from default list/detail queries and write
/// `change_log.action = removed_from_index`, while leaving `files.source_path`
/// targets and other user files untouched. It must not move anything to Trash,
/// trigger iCloud downloads, or perform permanent deletion.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when the active removable row is
/// absent, `CoreError::PermissionDenied { path }` when metadata writes are blocked,
/// `CoreError::Db { message }` for SQLite failures, and
/// `CoreError::Internal { message }` for unexpected state-transition failures.
pub fn remove_index_entry(repo_path: String, file_id: i64) -> CoreResult<()> {
    storage::remove_index_entry(repo_path, file_id)
}

/// Renames a file entry to a conflict-free filename in its current category.
///
/// C1-22 owns the user-visible rename contract for S1-33. The input name is a
/// filename, not a path, and must use the same validation boundary as
/// `ImportOptions::override_filename`. For repository-owned `Copied` and
/// `Moved` rows, Core performs a safe in-directory rename, persists matching
/// `files.path` and `files.current_name`, and records `change_log.action =
/// renamed` without changing `file_id`, category, tags, notes, hash, storage
/// mode, origin, or source path. It never overwrites an existing same-directory
/// user file; C1-10 conflict-free numbering is reused to choose a safe final
/// name.
///
/// Indexed rows are display-name only: Core updates `files.current_name` and
/// writes a `renamed` change-log entry, but leaves `files.path`,
/// `files.source_path`, and the external source file untouched. This preserves
/// C1-08 index-only semantics while allowing S1-33 to show the requested name.
///
/// Repository-owned rename also triggers C1-20 generated-overview
/// regeneration for the affected category. Those generated-overview writes
/// are limited to `.areamatrix/generated/` and, only when explicitly
/// configured, root-level `AREAMATRIX.md`; `README.md` remains user-authored
/// content. Indexed display-name rename leaves external source files untouched
/// and only commits metadata plus change-log state.
///
/// C1-10 exposes this entry point for manual name-conflict resolution from
/// S1-23. Replace flows remain guarded by S1-24 rather than becoming a default
/// rename branch.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for empty or unsafe names,
/// `CoreError::FileNotFound { path }` when the file row or repo-owned file is missing,
/// `CoreError::Conflict { path }` when a safe final name cannot be resolved,
/// `CoreError::PermissionDenied { path }` for blocked filesystem writes,
/// `CoreError::Io { message }` for filesystem or generated-overview write failures,
/// `CoreError::Db { message }` for metadata persistence failures, and
/// `CoreError::Config { reason }` for invalid generated-overview configuration.
pub fn rename_file(repo_path: String, file_id: i64, new_name: String) -> CoreResult<FileEntry> {
    storage::rename_file(repo_path, file_id, new_name)
}

/// Previews the final destination for a C1-24 category move.
///
/// This read-only entry point exists for S1-35 so the UI can show the exact
/// target path, C1-10 numbering result, and index-only behavior before the
/// user confirms. It must not create category directories, move files, rename
/// files, write `files`, or write `change_log`; confirmation remains owned by
/// [`move_to_category`].
///
/// # Errors
///
/// Returns the same preflight errors as [`move_to_category`]: `CoreError::Classify { reason }`
/// for unknown or unreadable categories, `CoreError::FileNotFound { path }` for missing rows or
/// repo-owned files, `CoreError::Conflict { path }` when the target category path or safe final
/// name cannot be resolved, `CoreError::PermissionDenied { path }` for blocked metadata or
/// filesystem inspection, `CoreError::Io { message }` for filesystem inspection failures, and
/// `CoreError::Db { message }` for metadata reads.
pub fn preview_move_to_category(
    repo_path: String,
    file_id: i64,
    new_category: String,
) -> CoreResult<MoveToCategoryPreview> {
    storage::preview_move_to_category(repo_path, file_id, new_category)
}

/// Moves one active file entry to a target category.
///
/// C1-24 owns the user-visible change-category contract for S1-35. The input
/// category is a classifier category slug, not an arbitrary directory. Core
/// must validate it against the repository classifier rules and must not
/// create undeclared categories as a side effect.
///
/// For repository-owned `Copied` and `Moved` rows, Core moves the file into
/// the target category directory, persists matching `files.category`,
/// `files.path`, and `updated_at`, and records `change_log.action = moved`.
/// Same-name targets reuse C1-10 conflict-free numbering and never overwrite
/// existing files.
///
/// Indexed rows are metadata-only: Core updates `files.category` and writes a
/// `moved` change-log entry while leaving `files.path`, `files.source_path`,
/// and the external source file untouched. Successful category moves preserve
/// `file_id`, filenames, tags, notes, hash, storage mode, origin, and source
/// path.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` when the target category is not in
/// classifier rules or classifier rules cannot be read, `CoreError::FileNotFound { path }`
/// when the active row or repo-owned file is missing, `CoreError::Conflict { path }`
/// when a safe destination cannot be resolved, `CoreError::PermissionDenied { path }`
/// for blocked filesystem or metadata writes, `CoreError::Io { message }` for
/// filesystem failures, and `CoreError::Db { message }` for metadata persistence
/// failures.
pub fn move_to_category(
    repo_path: String,
    file_id: i64,
    new_category: String,
) -> CoreResult<FileEntry> {
    storage::move_to_category(repo_path, file_id, new_category)
}

/// Previews a C2-08 batch category change for S2-12 without side effects.
///
/// The report gives Swift enough state to show selected-file category
/// distribution, per-file target paths, metadata-only rows, skipped rows,
/// blocked rows, and whether Apply can be enabled. `move_repo_owned_files`
/// controls whether repository-owned `Copied` and `Moved` files are planned as
/// filesystem moves; Indexed rows must remain metadata-only either way.
///
/// This preview must not create category folders, move files, update `files`,
/// write `change_log`, create undo actions, update generated overviews, call AI
/// providers, or touch user file contents.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` for invalid target categories,
/// `CoreError::FileNotFound { path }` for empty or invalid selections,
/// `CoreError::PermissionDenied { path }` for blocked metadata or filesystem
/// inspection, `CoreError::Io { message }` for preview filesystem failures,
/// and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_move_to_category(
    repo_path: String,
    file_ids: Vec<i64>,
    target_category: String,
    move_repo_owned_files: bool,
) -> CoreResult<BatchCategoryPreviewReport> {
    batch_category::preview_batch_move_to_category(
        repo_path,
        file_ids,
        target_category,
        move_repo_owned_files,
    )
}

/// Applies a previously previewed C2-08 batch category change.
///
/// `preview_token` binds Apply to the latest preview for the same selection,
/// target category, move option, and inspected state. Successful rows update
/// `files.category`, optionally update `files.path` for repository-owned
/// files, write `change_log`, and create a C2-07 undo action token. Partial
/// failures must be represented per item rather than silently treated as
/// success.
///
/// The operation is limited to C2-08. It must not create new categories,
/// implement classifier rule editing, delete or trash files, rename unrelated
/// files, save searches, retag files, call AI/network providers, or touch
/// `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` for invalid target categories,
/// `CoreError::Conflict { path }` for stale previews or unsafe target
/// conflicts, `CoreError::FileNotFound { path }` for invalid selections,
/// `CoreError::PermissionDenied { path }` for blocked filesystem or metadata
/// writes, `CoreError::Io { message }` for file moves, and
/// `CoreError::Db { message }` for metadata, change-log, or undo writes.
pub fn batch_move_to_category(
    repo_path: String,
    file_ids: Vec<i64>,
    target_category: String,
    move_repo_owned_files: bool,
    preview_token: String,
) -> CoreResult<BatchCategoryChangeReport> {
    batch_category::batch_move_to_category(
        repo_path,
        file_ids,
        target_category,
        move_repo_owned_files,
        preview_token,
    )
}

/// Previews a C2-09 batch delete operation without side effects.
///
/// S2-13 uses this contract to display selected-file impact before enabling a
/// destructive button: repository-owned rows that can move to Trash,
/// index-only or missing rows that can be removed from metadata, blocked rows,
/// Trash availability, and Undo availability. The preview must not move files,
/// remove index rows, write metadata, create undo actions, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` for empty selections or invalid
/// file ids, `CoreError::PermissionDenied { path }` when Trash or metadata
/// inspection is blocked, `CoreError::Io { message }` for filesystem preview
/// failures, and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_delete(
    repo_path: String,
    file_ids: Vec<i64>,
    delete_mode: BatchDeleteMode,
) -> CoreResult<BatchDeletePreviewReport> {
    batch_delete::preview_batch_delete(repo_path, file_ids, delete_mode)
}

/// Applies C2-09 batch deletion for the mode confirmed by S2-13.
///
/// `preview_token` must come from the last confirmed C2-09 preview for the
/// same selection, delete mode, Trash availability, and inspected file state.
/// `MoveToTrash` handles only repository-owned files and must never perform
/// permanent deletion. `RemoveFromIndex` handles index-only or missing rows
/// without touching external source files. Successful writes report per-item
/// status, update metadata/change log, and return an Undo token when C2-07 can
/// reverse the operation.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` for empty selections or invalid
/// ids, `CoreError::Conflict { path }` when Apply is not bound to the current
/// preview state, `CoreError::PermissionDenied { path }` when Trash or metadata
/// writes are blocked, `CoreError::Io { message }` for Trash or filesystem
/// failures, and `CoreError::Db { message }` for metadata, change-log, or undo
/// writes.
pub fn batch_delete_to_trash(
    repo_path: String,
    file_ids: Vec<i64>,
    delete_mode: BatchDeleteMode,
    preview_token: String,
) -> CoreResult<BatchDeleteReport> {
    batch_delete::batch_delete_to_trash(repo_path, file_ids, delete_mode, preview_token)
}

/// Previews a C2-10 batch rename operation without side effects.
///
/// S2-14 uses this contract to display each selected row's original name,
/// generated new name, blocking status, index-only display-name behavior,
/// conflicts, and whether Apply can be enabled. `file_ids` order represents
/// the current list order and is part of the preview state for sequence naming.
/// The preview must not rename files, update metadata, write change log, create
/// undo actions, change extensions, delete or Trash files, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for invalid repo paths or rename
/// rules, `CoreError::FileNotFound { path }` for empty selections or invalid
/// file ids, `CoreError::Conflict { path }` when a conflict cannot be returned
/// as row state, `CoreError::PermissionDenied { path }` for blocked metadata or
/// filesystem inspection, `CoreError::Io { message }` for preview filesystem
/// failures, and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_rename(
    repo_path: String,
    file_ids: Vec<i64>,
    rule: BatchRenameRule,
) -> CoreResult<BatchRenamePreviewReport> {
    batch_rename_mod::preview_batch_rename(repo_path, file_ids, rule)
}

/// Applies a previously previewed C2-10 batch rename operation.
///
/// `preview_token` must come from the last C2-10 preview for the same
/// selection order, rename rule, and inspected file state. Successful rows
/// rename repository-owned files or update index-only display names, update
/// metadata, write change-log rows, and return a C2-07 undo token when Undo can
/// reverse the operation.
///
/// This operation is limited to C2-10. It must not implement AI naming, change
/// file extensions, overwrite existing files, delete or Trash files,
/// recategorize files, retag files, save searches, reindex, call AI/network
/// providers, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for invalid repo paths or rename
/// rules, `CoreError::Conflict { path }` for stale previews or unsafe target
/// conflicts, `CoreError::FileNotFound { path }` for invalid selections,
/// `CoreError::PermissionDenied { path }` for blocked filesystem or metadata
/// writes, `CoreError::Io { message }` for rename failures, and
/// `CoreError::Db { message }` for metadata, change-log, or undo writes.
pub fn batch_rename(
    repo_path: String,
    file_ids: Vec<i64>,
    rule: BatchRenameRule,
    preview_token: String,
) -> CoreResult<BatchRenameReport> {
    batch_rename_mod::batch_rename(repo_path, file_ids, rule, preview_token)
}

/// Applies one C2-12 classifier correction for S2-16.
///
/// The correction changes one active file's category and optionally moves a
/// repo-managed file when `move_file` is true. `remember` only asks Core to
/// return a rule draft handoff for S2-17/S2-18; this entry point must not save
/// classifier rules, preview broad rule impact, create categories, call AI or
/// network providers, or implement adjacent C2-13/C2-14/C2-15 behavior.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` when the target category is invalid
/// or unavailable, `CoreError::Conflict { path }` when a safe target path
/// cannot be resolved, `CoreError::Io { message }` for file moves, and
/// `CoreError::Db { message }` for metadata or change-log failures.
pub fn correct_file_category(
    repo_path: String,
    file_id: i64,
    category: String,
    move_file: bool,
    remember: bool,
) -> CoreResult<ClassifierCorrectionResult> {
    classifier_correction::correct_file_category(repo_path, file_id, category, move_file, remember)
}

/// Saves one C2-13 classifier rule for future classification.
///
/// S2-17 uses this contract after the user chooses keyword and extension
/// basis values from a classifier-correction draft. The input rule maps only to
/// supported classifier configuration fields: target category, independent
/// keyword matches, independent extension matches, priority, and whether the
/// required impact preview has already been confirmed. Extensions must be
/// lowercase values without a leading dot.
///
/// This contract does not create categories, model compound AND rules, preview
/// impact, apply the rule to historical files, reclassify or move files, call
/// AI/network providers, or touch `apps/**`. Successful saves atomically update
/// the repository classifier configuration for future classification only.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths, target
/// categories, empty rule basis, duplicate/invalid keywords, dotted or invalid
/// extensions, out-of-range priority, malformed classifier configuration, or a
/// duplicate/over-broad rule that still lacks preview confirmation. Returns
/// `CoreError::PermissionDenied { path }` for blocked metadata writes and
/// `CoreError::Io { message }` for classifier configuration read or atomic
/// write failures.
pub fn save_classifier_rule(repo_path: String, rule: ClassifierRule) -> CoreResult<ClassifierRule> {
    classifier_rules::save_classifier_rule(repo_path, rule)
}

/// Previews C2-14 classifier rule impact for S2-18.
///
/// The contract accepts one explicit preview request and returns counts, sample
/// rows, conflicts, needs-review state, broad-impact warning state, and direct
/// apply availability. It is read-only: it may inspect classifier config and
/// file metadata, but it must not save the rule, apply it to existing files,
/// move files, write undo/change-log state, or implement C2-15 rule editing.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths,
/// invalid classifier rule drafts, invalid delete requests, or invalid
/// replacement categories. Returns `CoreError::Db { message }` when classifier
/// impact metadata cannot be read.
pub fn preview_classifier_rule_impact(
    repo_path: String,
    request: ClassifierImpactPreviewRequest,
) -> CoreResult<RuleImpactReport> {
    classifier_impact::preview_classifier_rule_impact(repo_path, request)
}

/// Lists C2-15 classifier rule editor state for S2-19.
///
/// S2-19 uses this contract to load current classifier categories, matcher
/// values, priority, naming template, and default-category state. The returned
/// snapshot is sufficient for loading, empty, dirty, validation, save/revert,
/// and delete-disabled UI states without reading YAML in the app layer.
///
/// This contract does not preview rule impact, save rules, delete categories,
/// reclassify or move existing files, open YAML, call AI/network providers, or
/// touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid repository paths or
/// malformed classifier configuration, `CoreError::PermissionDenied { path }`
/// for blocked classifier metadata reads, and `CoreError::Io { message }` for
/// classifier config read failures.
pub fn list_classifier_rules(repo_path: String) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::list_classifier_rules(repo_path)
}

/// Updates one C2-15 classifier editor row for future classification.
///
/// The update request carries one stable `rule_id` plus replacement slug,
/// display metadata, extensions, keywords, priority, and naming template. A
/// successful implementation may atomically update `.areamatrix/classifier.yaml`
/// or equivalent classifier metadata only. It must not move, delete, rename,
/// reindex, retag, write notes, update generated overviews, write undo state,
/// or apply classifier changes to historical files.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid ids, row content,
/// duplicate slugs or matcher values, missing impact preview confirmation, or
/// malformed classifier configuration. Returns `CoreError::PermissionDenied {
/// path }` for blocked classifier metadata writes and `CoreError::Io {
/// message }` for read, backup, atomic write, or restore failures.
pub fn update_classifier_rule(
    repo_path: String,
    request: ClassifierRuleUpdate,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::update_classifier_rule(repo_path, request)
}

/// Deletes one C2-15 classifier editor row after explicit impact confirmation.
///
/// Delete removes only classifier configuration state. It must reject deletion
/// of the default category, the final category, and unpreviewed category/value
/// removals. Existing files are not moved, deleted, renamed, trashed, or
/// reclassified by this contract.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` for invalid ids, protected category
/// deletion, missing replacement state, missing impact preview confirmation, or
/// malformed classifier configuration. Returns `CoreError::PermissionDenied {
/// path }` for blocked classifier metadata writes and `CoreError::Io {
/// message }` for read, backup, atomic write, or restore failures.
pub fn delete_classifier_rule(
    repo_path: String,
    request: ClassifierRuleDeleteRequest,
) -> CoreResult<ClassifierRuleEditorSnapshot> {
    classifier_rule_editor::delete_classifier_rule(repo_path, request)
}

/// Restores a deleted file entry.
pub fn restore_file(_repo_path: String, _file_id: i64) -> CoreResult<FileEntry> {
    not_implemented()
}

/// Lists file entries from repository metadata.
///
/// C1-11 defines this as the read-only file-list query used by the Stage 1
/// main window and multi-selection summary. The public contract accepts a
/// [`FileFilter`] for exact category filtering, optional deleted-row inclusion,
/// import-time bounds, `limit` clamping, and offset pagination. Returned rows
/// are ordered by `imported_at DESC`.
///
/// This API must not write repository metadata or mutate user files. Search,
/// tag filtering, smart lists, and single-file detail aggregation belong to
/// later capabilities and must not be hidden behind this entry point.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when the repository metadata is
/// missing and `CoreError::Db { message }` when SQLite rows cannot be read.
pub fn list_files(repo_path: String, filter: FileFilter) -> CoreResult<Vec<FileEntry>> {
    db::list_files(repo_path, filter)
}

/// Gets a single active file entry from repository metadata.
///
/// C1-12 defines this as the read-only detail query used by Stage 1 detail
/// panes. The caller supplies a repository path and stable `file_id`; the
/// contract returns exactly one active [`FileEntry`] and must not infer
/// metadata from the filesystem path in the UI layer.
///
/// This API has no write side effects. Implementations may inspect target
/// metadata to detect stale rows, but they must not create, delete, move,
/// rename, or overwrite user files. File preview, Quick Look, OCR metadata,
/// change-log aggregation, and note aggregation belong to adjacent capabilities
/// and must not be hidden behind this entry point.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is missing,
/// `CoreError::FileNotFound { path }` when the requested active file row is absent or
/// not visible to detail consumers, and `CoreError::Db { message }` when SQLite rows cannot
/// be read.
pub fn get_file(repo_path: String, file_id: i64) -> CoreResult<FileEntry> {
    let repo = PathBuf::from(repo_path);
    db::get_active_file_by_id(&repo, file_id)
}

/// Lists change-log entries from repository metadata.
///
/// C1-13 defines this as the read-only change-log query used by Stage 1 detail
/// log, import result, and error recovery surfaces. The public contract accepts
/// a [`ChangeFilter`] for optional `file_id`, `category`, `action`,
/// `occurred_at` bounds, `limit`, and `offset`. Returned rows are ordered by
/// `occurred_at DESC`, and each [`ChangeLogEntry::detail_json`] value must
/// remain parseable JSON for action-specific UI rendering.
///
/// This API has no write side effects: it must not mutate repository metadata,
/// create files, rename files, or probe user file contents. Undo history,
/// rollback, and batch revert behavior belong to Stage 2 and must not be
/// hidden behind this query entry point.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is missing
/// and `CoreError::Db { message }` when SQLite rows or persisted change-log details cannot
/// be read as the documented contract.
pub fn list_changes(repo_path: String, filter: ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>> {
    db::list_changes(repo_path, filter)
}

/// Returns repository tree data as JSON.
///
/// C1-15 defines this as the read-only tree query for the Stage 1 main window.
/// The caller supplies an initialized repository path and a display locale such
/// as `zh-Hans` or `en`. The output is a single JSON string so Swift can decode
/// one `TreeNode` snapshot without repeated FFI crossings. Tree nodes must use
/// stable path keys, stable sibling ordering, and a Swift-compatible `children`
/// array shape. The query may read repository file paths and classifier config
/// to build display names, but it must not create generated overviews, mutate
/// repository metadata, or modify user files.
///
/// Virtual smart lists, search result trees, and Stage 2 tree projections remain
/// outside this API boundary.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when metadata is missing,
/// `CoreError::Db { message }` when the tree cannot be read from SQLite, and
/// `CoreError::Io { message }` when repository file paths, file metadata, or classifier
/// config cannot be inspected.
pub fn list_tree_json(repo_path: String, locale: String) -> CoreResult<String> {
    tree::list_tree_json(repo_path, locale)
}

/// Lists iCloud conflicted copy pairs without resolving them.
///
/// C1-25 owns the read-only contract for S1-36. The caller supplies an
/// initialized repository root and receives one row per detected conflicted
/// copy pair. The output preserves the original path when Core can identify
/// it, the conflicted copy path, both modification timestamps when available,
/// and a status value. Ambiguous pairings must be returned as
/// `ICloudConflictStatus::NeedsReview` instead of being silently merged.
///
/// This API must not delete, move, rename, overwrite, merge, or download any
/// file. Single-item resolution remains a later explicit action and is not
/// hidden behind this list query.
///
/// # Errors
///
/// Returns `CoreError::ICloudPlaceholder { path }` for unavailable iCloud
/// metadata, `CoreError::PermissionDenied { path }` for blocked inspection,
/// `CoreError::Io { message }` for filesystem scan failures, and
/// `CoreError::Db { message }` for optional conflict-state reads.
pub fn list_icloud_conflicts(repo_path: String) -> CoreResult<Vec<ICloudConflictPair>> {
    icloud_conflicts::list_icloud_conflicts(repo_path)
}

/// Reads the markdown note associated with one active file entry.
///
/// C1-14 exposes this read-only query for the S1-14 detail-note surface. The
/// caller supplies a repository path and stable `file_id`; the result is
/// `Some(markdown)` when a note exists and `None` when the file has no note.
/// This API must not create note rows, write sidecar files, insert change-log
/// entries, or mutate user files.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is missing,
/// `CoreError::FileNotFound { path }` when the active file row is absent,
/// `CoreError::PermissionDenied { path }` or `CoreError::Io { message }` for blocked sidecar or
/// metadata reads, and `CoreError::Db { message }` when note metadata cannot be queried.
pub fn read_note(repo_path: String, file_id: i64) -> CoreResult<Option<String>> {
    note::read_note(repo_path, file_id)
}

/// Writes markdown note content for one active file entry.
///
/// C1-14 writes exactly one note for the target file. A successful call upserts
/// the `notes` row, writes the same-directory sidecar markdown file, and records
/// `change_log.action = edited_note` only after DB state and sidecar content are
/// consistent. The app layer owns `InFlightTracker` marking so watcher events
/// from the sidecar write are not treated as external changes.
///
/// The call must not delete, move, rename, or overwrite the target file or any
/// unconfirmed user-authored file. Failed writes must preserve the previous note
/// content and must not leave a successful change-log entry without matching DB
/// and sidecar state.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` when repository metadata is missing,
/// `CoreError::FileNotFound { path }` when the active file row is absent,
/// `CoreError::PermissionDenied { path }` for blocked writes, `CoreError::Io { message }` for
/// filesystem failures, and `CoreError::Db { message }` for transactional metadata failures.
pub fn write_note(repo_path: String, file_id: i64, content_md: String) -> CoreResult<()> {
    note::write_note(repo_path, file_id, content_md)
}

/// Synchronizes external filesystem changes after app-layer filtering.
///
/// C1-17 owns the `ExternalEventKind::Created` contract.
/// The platform layer is responsible for FSEvents startup, debounce,
/// in-flight filtering, and iCloud placeholder download coordination.
/// Created sync reads only metadata/hash, inserts an active `FileEntry` with
/// `storage_mode = StorageMode::Indexed`, `origin = FileOrigin::External`, and
/// writes a queryable change-log entry with `change_log.action =
/// external_modified` and `kind = create`. It increments
/// `SyncResult::detected_creates` and must skip `.areamatrix/` plus generated overview output.
/// It must not move, delete, rename, overwrite, copy, or download the
/// external user file.
///
/// C1-18 owns the `ExternalEventKind::Renamed` contract. A rename event's
/// `path` is the repository-relative or absolute new path after app-layer
/// FSEvents pairing/debounce. The contract result is a `files.path` and
/// `files.current_name` update, `updated_at` refresh, `change_log.action =
/// renamed` with old/new path detail, and `SyncResult::detected_renames`
/// increment. The sync branch only confirms the new path exists and must not
/// rename, move, delete, overwrite, copy, or download a user file. If a rename
/// cannot be paired, callers may replay it as removed + created; the rename
/// branch must then avoid claiming a detected rename.
///
/// C1-19 owns the `ExternalEventKind::Removed` contract. A removed event's
/// `path` is the repository-relative or absolute path after app-layer debounce and rename pairing.
/// The sync branch only confirms the path is absent,
/// marks the matching active row as `status = deleted`, refreshes `deleted_at`
/// and `updated_at`, writes `change_log.action = deleted` with external deletion detail,
/// and increments `SyncResult::detected_deletes`. It must not
/// remove, trash, move, rename, overwrite, copy, or download a user file.
/// Deleted rows are not visible to default `list_files` and return `CoreError::FileNotFound { path }`
/// through `get_file`.
///
/// Cursor persistence is part of the batch success contract.
///
/// # Errors
/// Returns `CoreError::InvalidPath { path }`, `CoreError::ICloudPlaceholder { path }`,
/// `CoreError::PermissionDenied { path }`, `CoreError::Io { message }`, or `CoreError::Db { message }` for
/// path, placeholder, metadata/hash, or transactional persistence failures.
/// Returns `CoreError::FileNotFound { path }` when a renamed target no longer exists and
/// when a deleted row is later opened through detail APIs. Returns
/// `CoreError::Conflict { path }` when a renamed target cannot be paired without
/// colliding with another active row.
pub fn sync_external_changes(
    repo_path: String,
    events: Vec<ExternalEvent>,
) -> CoreResult<SyncResult> {
    sync::sync_external_changes(repo_path, events)
}

/// Returns the latest processed filesystem event cursor, or `None` before the first durable batch.
/// # Errors
/// Returns `CoreError::RepoNotInitialized { path }` or `CoreError::Db { message }`.
pub fn get_fs_event_cursor(repo_path: String) -> CoreResult<Option<i64>> {
    sync::get_fs_event_cursor(repo_path)
}

/// Persists the latest processed filesystem event cursor in `.areamatrix/index.db`.
/// Prefer [`sync_external_changes`] for batch-success cursor advancement.
/// This must not inspect, create, move, delete, rename, overwrite, copy, or download user files.
/// # Errors
/// Returns `CoreError::RepoNotInitialized { path }`, `CoreError::InvalidPath { path }`, or `CoreError::Db { message }`.
pub fn set_fs_event_cursor(repo_path: String, last_event_id: i64) -> CoreResult<()> {
    sync::set_fs_event_cursor(repo_path, last_event_id)
}
