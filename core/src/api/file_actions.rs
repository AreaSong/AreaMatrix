//! Public FFI file-actions entry points.

use crate::{
    classify, storage, ClassifyResult, CoreResult, FileEntry, ImportOptions, ImportResult,
    MoveToCategoryPreview,
};

/// Predicts a category for a filename without importing or mutating files.
///
/// category prediction uses this API for import previews and classifier settings. It reads
/// classifier rules from `.areamatrix/classifier.yaml`, falls back to the
/// bundled default rules when the file is absent, and returns a suggested
/// category/name pair. It must not create repository metadata, touch the
/// database, import files, or move user content.
///
/// camera import reuses this read-only preview surface after the
/// platform layer has captured a photo and generated a candidate filename.
/// Camera permission prompts, capture cancellation, retake flow, thumbnail
/// generation, and temporary-file lifetime management remain outside Core.
///
/// share extension import reuses this read-only preview surface after
/// the Share Extension has parsed an `NSExtensionItem` and derived a safe
/// candidate filename. Share-sheet parsing, app-group queue persistence,
/// security-scoped bookmark refresh, URL materialization, and Extension
/// timeout handling stay in the platform layer.
///
/// files import reuses this read-only preview surface after the iOS
/// Files provider or document picker has granted access and exposed a display
/// filename. Provider browsing, security-scoped access lifetime, iCloud
/// placeholder download orchestration, and multi-file progress stay in the
/// platform layer; Core only predicts a category/name from the authorized
/// filename and repository classifier rules.
///
/// desktop import flow reuses this read-only preview surface for
/// Windows and Linux import dialogs after the platform picker, drag-and-drop
/// adapter, or optional shell entry has produced display names. Directory
/// expansion, platform permission preflight, Trash/Recycle Bin capability
/// checks, and multi-item progress stay in the desktop shell. Core only reads
/// the repository classifier rules and returns a [`ClassifyResult`] that
/// `Windows import surface` and `Linux import surface` can show as suggested category state before the
/// final [`import_file`] call.
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
/// copied-file import defines the copied-file contract for `ImportOptions` values whose
/// `mode` is `StorageMode::Copied`. The source path is read as immutable input,
/// file bytes are copied through `.areamatrix/staging/`, the content hash is
/// used for duplicate detection, and a successful call returns the active
/// `FileEntry` persisted in `files` with a matching `change_log` import event.
/// The original source file must remain unchanged.
///
/// moved-file import defines the moved-file contract for `ImportOptions` values whose
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
/// indexed-file import owns index-only semantics. indexed-file import defines the indexed-file contract
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
/// duplicate detection owns duplicate detection for this entry point. Core hashes the source
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
/// name-conflict resolution owns same-name conflict handling for this entry point. The target
/// name comes from the source filename or `ImportOptions::override_filename`;
/// the output `FileEntry.path` and `FileEntry.current_name` must report the
/// final conflict-free name that was actually written. Same-name imports with
/// different content must not overwrite an existing user file by default:
/// Core resolves a safe numbered name such as `name_1.ext`, while
/// `CoreError::Conflict { path }` is reserved for exhausted or raced resolution.
/// Dangerous replacement remains explicit through `DuplicateStrategy::Overwrite`
/// after replace confirmation has confirmed the user decision and recoverable
/// old-version handling.
///
/// generated overview uses a successful import as a generated-overview trigger. The trigger
/// has no extra FFI input: Core derives the changed node/category from the
/// committed [`FileEntry`] and the current [`RepoConfig::overview_output`].
/// Its allowed filesystem side effects are limited to generated markdown under
/// `.areamatrix/generated/` and, only when explicitly configured,
/// `AREAMATRIX.md`; `README.md` remains user-authored content.
///
/// camera import reuses `StorageMode::Copied` import semantics for a
/// platform-saved temporary photo path. Core receives only the authorized
/// filesystem path plus [`ImportOptions`]; it does not request camera
/// permissions, drive the capture UI, delete photos outside AreaMatrix-owned
/// staging, or clean up the final repository file. A successful call returns
/// the committed [`FileEntry`] so mobile consumers can refresh the library row,
/// show the copied storage mode, and route duplicate or name-conflict states
/// without adding a camera-specific Core API.
///
/// share extension import reuses `StorageMode::Copied` import semantics
/// after the platform has materialized a share payload into a Core-readable app
/// group staged file. Core receives only that staged file path plus
/// [`ImportOptions`]; it does not parse `NSExtensionItem`, store the deferred
/// import ticket, open the main app, resolve security-scoped permissions, or
/// log external app payload bytes. A successful call returns the committed
/// [`FileEntry`] so `mobile share import surface` can render completed imports. When the
/// Extension must defer, the platform-owned ticket records queued,
/// needs-review, or permission-expired takeover state and the main app later
/// calls this same Core import contract.
///
/// files import reuses `StorageMode::Copied` import semantics for iOS
/// Files provider selections after the platform layer has granted access to a
/// readable file URL. Core receives only the authorized path plus
/// [`ImportOptions`]; it does not open the document picker, retain
/// security-scoped bookmarks, trigger provider downloads, move source files, or
/// perform replace confirmation. `iOS files import surface` can derive its preview and
/// result states from [`predict_category`], [`ImportOptions`], the returned
/// [`FileEntry`], and structured `ICloudPlaceholder`, `PermissionDenied`,
/// `DuplicateFile`, and `Conflict` errors. Cancelled selections stay in the
/// platform sheet and must not call this API.
///
/// desktop import flow keeps this same import contract available for
/// existing callers, but `Windows import surface` and `Linux import surface` should use
/// [`import_file_with_result`] when they need Move source-removal state.
/// Desktop shells pass the picker or drop source path plus [`ImportOptions`]
/// for a single committed item; folder recursion, batching, drag-and-drop,
/// Explorer/Nautilus integration, platform permission preflight, and
/// Trash/Recycle Bin availability checks remain outside Core.
/// `StorageMode::Copied` is the safe default. `StorageMode::Moved` must not be
/// silently downgraded by the UI; source-impact confirmation and per-item
/// progress are platform/UI responsibilities. `DuplicateStrategy::KeepBoth`,
/// `Skip`, and `Ask` expose duplicate or same-name state through the returned
/// [`FileEntry`] or structured `DuplicateFile` / `Conflict` errors.
/// `DuplicateStrategy::Overwrite` is only valid after the separate replace confirmation /
/// `replace confirmation surface` has proven a recoverable old-file path; this
/// API does not perform that confirmation, detect platform Trash support, or
/// add a desktop-only replace capability. A failed pre-commit desktop import
/// must surface an error instead of a success state and must not leave active
/// file rows or final destination half-products.
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

/// Imports one source file and returns desktop-ready result state.
///
/// desktop import flow uses this wrapper for `Windows import surface` and `Linux import surface` after the desktop
/// shell has completed picker/drop parsing, Move confirmation, and platform
/// preflight. It reuses the same transactional repository import path as
/// [`import_file`] and adds only the source-removal outcome required by desktop
/// result pages. `StorageMode::Copied` and `StorageMode::Indexed` return
/// `ImportSourceRemovalStatus::NotRequested`. `StorageMode::Moved` first commits
/// the repository file, database row, change log, and generated overview; only
/// after those writes are safe does Core try to remove the original source.
///
/// If post-commit source removal fails, the API still returns the committed
/// [`FileEntry`] with `ImportSourceRemovalStatus::Retained` plus a structured
/// failure reason. That lets Windows and Linux show `Imported, original
/// retained` without rolling back the already-safe repository file or marking
/// the item as fully moved. Replace confirmation, Trash/Recycle Bin detection,
/// folder batching, drag-and-drop, and multi-item progress remain outside this
/// entry point and continue to belong to separate platform capabilities.
///
/// # Errors
///
/// Returns the same pre-commit errors as [`import_file`]: invalid paths, missing
/// or unreadable sources, duplicate or name conflicts, unavailable iCloud
/// placeholders, permission failures, IO failures, database failures, and
/// internal errors. Pre-commit failures do not create active file rows or final
/// destination half-products.
pub fn import_file_with_result(
    repo_path: String,
    source_path: String,
    options: ImportOptions,
) -> CoreResult<ImportResult> {
    storage::import_file_with_result(repo_path, source_path, options)
}

/// Moves a repo-owned file entry to the system Trash and soft-deletes metadata.
///
/// delete/remove-index owns the user-visible delete/remove-index contract for delete/remove-index surface.
/// `delete_file` is only for AreaMatrix-managed `Copied` / `Moved` active rows.
/// A successful implementation must send the target file to the system Trash,
/// mark the matching row as `files.status = deleted`, refresh `deleted_at` and
/// `updated_at`, and write `change_log.action = deleted`.
///
/// This entry point intentionally has no `hard` or permanent-delete flag. Indexed,
/// adopted, external, or missing references must use [`remove_index_entry`] so
/// external source files are never deleted as an index cleanup side effect.
/// replace confirmation replace-confirm-cross-platform composes the same Trash-only safety
/// boundary for discarded versions: callers may route destructive confirmation
/// through this contract only when a repo-owned file is being recoverably moved
/// to Trash, never when a platform would require permanent deletion.
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
/// delete/remove-index uses this explicit index-only entry point for Indexed / Adopted /
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
/// file rename owns the user-visible rename contract for rename surface. The input name is a
/// filename, not a path, and must use the same validation boundary as
/// `ImportOptions::override_filename`. For repository-owned `Copied` and
/// `Moved` rows, Core performs a safe in-directory rename, persists matching
/// `files.path` and `files.current_name`, and records `change_log.action =
/// renamed` without changing `file_id`, category, tags, notes, hash, storage
/// mode, origin, or source path. It never overwrites an existing same-directory
/// user file; name-conflict numbering is reused to choose a safe final
/// name.
///
/// Indexed rows are display-name only: Core updates `files.current_name` and
/// writes a `renamed` change-log entry, but leaves `files.path`,
/// `files.source_path`, and the external source file untouched. This preserves
/// indexed-file import index-only semantics while allowing rename surface to show the requested name.
///
/// Repository-owned rename also triggers generated overview
/// regeneration for the affected category. Those generated-overview writes
/// are limited to `.areamatrix/generated/` and, only when explicitly
/// configured, root-level `AREAMATRIX.md`; `README.md` remains user-authored
/// content. Indexed display-name rename leaves external source files untouched
/// and only commits metadata plus change-log state.
///
/// name-conflict resolution exposes this entry point for manual name-conflict resolution from
/// name-conflict review. Replace flows remain guarded by replace confirmation rather than becoming a default
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
pub fn rename_file(
    repo_path: String,
    file_id: i64,
    new_name: String,
    content_locale: impl crate::ContentLocaleInput,
) -> CoreResult<FileEntry> {
    let content_locale = content_locale.into_content_locale()?;
    storage::rename_file(
        repo_path,
        file_id,
        new_name,
        content_locale.as_str().to_owned(),
    )
}

/// Previews the final destination for a category move.
///
/// This read-only entry point exists for category move confirmation so the UI can show the exact
/// target path, name-conflict resolution numbering result, and index-only behavior before the
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
/// category move owns the user-visible change-category contract for category move confirmation. The input
/// category is a classifier category slug, not an arbitrary directory. Core
/// must validate it against the repository classifier rules and must not
/// create undeclared categories as a side effect.
///
/// For repository-owned `Copied` and `Moved` rows, Core moves the file into
/// the target category directory, persists matching `files.category`,
/// `files.path`, and `updated_at`, and records `change_log.action = moved`.
/// Same-name targets reuse name-conflict numbering and never overwrite
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
