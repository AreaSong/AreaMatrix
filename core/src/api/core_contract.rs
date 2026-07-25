//! Public FFI core-contract entry points.

use crate::{
    cross_platform_ffi, platform_capabilities, BindingContractReport, BindingContractRequest,
    CoreError, CoreResult, PlatformCapabilities, PlatformId,
};

/// Inspects the cross-platform UniFFI contract surface for platform shells.
///
/// The report is read-only and lets platform differences surface render supported APIs, type
/// mappings, and missing capability gaps without guessing from UI state.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the requested binding version is
/// outside the supported contract range, and `CoreError::Internal { message }`
/// when the report cannot expose the minimum API and type-mapping surface.
pub fn inspect_binding_contract(
    request: BindingContractRequest,
) -> CoreResult<BindingContractReport> {
    cross_platform_ffi::inspect_binding_contract(request)
}

/// Returns the platform capability matrix for a platform shell.
///
/// `platform differences`, `Linux local-folder notice`, and
/// `repository settings surface` consume this matrix to render watcher, Trash
/// or Recycle Bin, share extension, cloud placeholder, and security bookmark
/// support without guessing from platform UI state. Limited, unavailable, or
/// unknown capability rows carry stable reasons so unsupported dangerous
/// actions are not exposed as available.
/// repository settings composes this matrix with [`load_config`] and
/// [`update_config`] so platform shells can disable unsupported settings before
/// they submit repository configuration changes.
///
/// The contract is read-only and platform-neutral. It does not inspect the
/// repository, start watchers, test Trash/Recycle Bin integration, query cloud
/// SDKs, refresh security-scoped bookmarks, read user files, write diagnostics,
/// or execute adjacent platform abilities.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when `platform` is `Unknown` or
/// `app_version` is empty, too long, or otherwise invalid for the contract.
pub fn get_platform_capabilities(
    platform: PlatformId,
    app_version: String,
) -> CoreResult<PlatformCapabilities> {
    platform_capabilities::get_platform_capabilities(platform, app_version)
}

/// Returns the AreaMatrix core crate version.
pub fn get_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

/// Validates the requested logging level.
///
/// Full subscriber wiring is left for a later observability task so this
/// skeleton remains side-effect light.
pub fn init_logging(level: String, log_dir: String) -> CoreResult<()> {
    let level_filter = match level.as_str() {
        "trace" => tracing::Level::TRACE,
        "debug" => tracing::Level::DEBUG,
        "info" => tracing::Level::INFO,
        "warn" => tracing::Level::WARN,
        "error" => tracing::Level::ERROR,
        _ => return Err(CoreError::config("configuration error")),
    };

    let file_appender = tracing_appender::rolling::daily(log_dir, "core.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);
    
    // Leak the guard intentionally because init_logging is called once globally
    // and we want logging to continue until the process exits.
    Box::leak(Box::new(_guard));

    let subscriber = tracing_subscriber::fmt()
        .with_max_level(level_filter)
        .with_writer(non_blocking)
        .with_ansi(false) // No ANSI color codes for file logging
        .with_file(true)
        .with_line_number(true)
        .with_thread_ids(true)
        .with_target(false) // Target is usually the module path, file/line is better
        .finish();

    // Ignore error if tracing was already initialized
    let _ = tracing::subscriber::set_global_default(subscriber);

    Ok(())
}
