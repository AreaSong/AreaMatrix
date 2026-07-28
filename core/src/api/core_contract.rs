//! Public FFI core-contract entry points.

use crate::{
    cross_platform_ffi, initialize_observability, observability, platform_capabilities,
    BindingContractReport, BindingContractRequest, CoreObservabilityEvent, CoreObservabilitySink,
    CoreResult, ObservabilitySeverity, PlatformCapabilities, PlatformId,
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

/// Legacy unstructured Core log projection.
pub struct CoreLogRecord {
    pub level: String,
    pub message: String,
    pub target: Option<String>,
    pub thread_name: Option<String>,
    pub repo_path: Option<String>,
}

pub trait CoreLogCallback: Send + Sync {
    fn on_log(&self, record: CoreLogRecord);
}

/// Connects the legacy callback to the structured observability runtime.
///
/// # Errors
///
/// Returns `CoreError::Config` when `level` is not a supported severity.
pub fn init_logging(level: String, callback: Box<dyn CoreLogCallback>) -> CoreResult<()> {
    let minimum_severity = parse_legacy_level(&level)?;
    let config = observability::legacy_configuration(minimum_severity)?;
    initialize_observability(config, Box::new(LegacyObservabilitySink { callback }))?;
    Ok(())
}

struct LegacyObservabilitySink {
    callback: Box<dyn CoreLogCallback>,
}

impl CoreObservabilitySink for LegacyObservabilitySink {
    fn on_event(&self, event: CoreObservabilityEvent) {
        self.callback.on_log(CoreLogRecord {
            level: legacy_level(event.severity).to_owned(),
            message: event.message.unwrap_or(event.action_id),
            target: event.target.or(Some(event.component_id)),
            thread_name: event.thread_name,
            repo_path: None,
        });
    }
}

fn parse_legacy_level(level: &str) -> CoreResult<ObservabilitySeverity> {
    match level {
        "trace" => Ok(ObservabilitySeverity::Trace),
        "debug" => Ok(ObservabilitySeverity::Debug),
        "info" => Ok(ObservabilitySeverity::Info),
        "warn" => Ok(ObservabilitySeverity::Warn),
        "error" => Ok(ObservabilitySeverity::Error),
        _ => Err(crate::CoreError::config(
            "logging level must be trace, debug, info, warn, or error",
        )),
    }
}

const fn legacy_level(severity: ObservabilitySeverity) -> &'static str {
    match severity {
        ObservabilitySeverity::Trace => "trace",
        ObservabilitySeverity::Debug => "debug",
        ObservabilitySeverity::Info => "info",
        ObservabilitySeverity::Warn => "warn",
        ObservabilitySeverity::Error => "error",
    }
}
