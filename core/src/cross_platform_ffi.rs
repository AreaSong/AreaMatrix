//! C4-01 cross-platform FFI contract types.

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const MIN_BINDING_VERSION: i64 = 1;
const MAX_BINDING_VERSION: i64 = 1;

/// Target binding family requested by a platform shell.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BindingTargetPlatform {
    /// Swift binding used by macOS and iOS shells.
    Swift,
    /// Kotlin binding reserved for later Android or desktop shells.
    Kotlin,
    /// Python binding reserved for CLI, test, and automation consumers.
    Python,
}

/// Availability of one API, type mapping, or capability in a binding report.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BindingSupportStatus {
    /// The item is available for the requested binding version.
    Supported,
    /// The item is exposed but has documented platform or runtime limits.
    Limited,
    /// The item is not exposed for the requested binding version.
    Missing,
}

/// Stable API entry exposed by the cross-platform binding contract.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BindingApiContract {
    /// Public UniFFI function name.
    pub name: String,
    /// Contract capability that owns this API.
    pub capability: String,
    /// Whether the API is available for the requested binding version.
    pub status: BindingSupportStatus,
    /// Stable disabled or limitation reason for UI and diagnostics.
    pub reason: Option<String>,
}

/// Stable type mapping exposed by the cross-platform binding contract.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BindingTypeMapping {
    /// Rust type or primitive.
    pub rust_type: String,
    /// UDL type or primitive.
    pub udl_type: String,
    /// Target-language type for the requested platform.
    pub target_type: String,
    /// Whether the mapping is available for the requested binding version.
    pub status: BindingSupportStatus,
    /// Stable limitation reason for UI and diagnostics.
    pub reason: Option<String>,
}

/// Missing or limited capability surfaced to S4-X-02.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BindingMissingCapability {
    /// Capability identifier such as `C4-01`.
    pub capability: String,
    /// User-visible short label.
    pub label: String,
    /// Whether the capability is missing or only partially available.
    pub status: BindingSupportStatus,
    /// Stable reason shown without platform-side guessing.
    pub reason: String,
}

/// Input for the C4-01 binding contract inspection.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BindingContractRequest {
    /// Target binding family to inspect.
    pub target_platform: BindingTargetPlatform,
    /// Stable binding contract version requested by the platform shell.
    pub binding_version: i64,
}

/// C4-01 contract report consumed by platform-differences UI and later checks.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BindingContractReport {
    /// Target binding family that was inspected.
    pub target_platform: BindingTargetPlatform,
    /// Binding contract version used for the report.
    pub binding_version: i64,
    /// AreaMatrix core crate version.
    pub core_version: String,
    /// Public APIs available through this binding contract.
    pub supported_apis: Vec<BindingApiContract>,
    /// Cross-language type mappings for this binding contract.
    pub type_mappings: Vec<BindingTypeMapping>,
    /// Missing or limited capabilities that pages can render without guessing.
    pub missing_capabilities: Vec<BindingMissingCapability>,
}

/// Returns the C4-01 cross-platform FFI contract report.
///
/// The report is read-only and platform neutral. It describes the current UDL
/// API surface, target-language type mappings, and binding capability gaps for
/// `S4-X-02 platform-differences`. It does not inspect a repository, touch the
/// filesystem, query platform UI APIs, generate bindings, or execute adjacent
/// Stage 4 capabilities.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when `binding_version` is outside
/// the supported contract version range, and `CoreError::Internal { message }`
/// if the report cannot expose the minimum API and type-mapping surface.
pub fn inspect_binding_contract(
    request: BindingContractRequest,
) -> CoreResult<BindingContractReport> {
    validate_binding_version(request.binding_version)?;
    let report = BindingContractReport {
        target_platform: request.target_platform.clone(),
        binding_version: request.binding_version,
        core_version: env!("CARGO_PKG_VERSION").to_owned(),
        supported_apis: supported_apis(),
        type_mappings: type_mappings(&request.target_platform),
        missing_capabilities: missing_capabilities(&request.target_platform),
    };
    validate_report(&report)?;
    Ok(report)
}

fn validate_binding_version(binding_version: i64) -> CoreResult<()> {
    if (MIN_BINDING_VERSION..=MAX_BINDING_VERSION).contains(&binding_version) {
        Ok(())
    } else {
        Err(CoreError::config("unsupported binding contract version"))
    }
}

fn validate_report(report: &BindingContractReport) -> CoreResult<()> {
    if report.supported_apis.is_empty() || report.type_mappings.is_empty() {
        Err(CoreError::internal("binding contract report is incomplete"))
    } else {
        Ok(())
    }
}

fn supported_apis() -> Vec<BindingApiContract> {
    [
        ("get_version", "C4-01"),
        ("init_logging", "C4-01"),
        ("inspect_binding_contract", "C4-01"),
    ]
    .into_iter()
    .map(|(name, capability)| BindingApiContract {
        name: name.to_owned(),
        capability: capability.to_owned(),
        status: BindingSupportStatus::Supported,
        reason: None,
    })
    .collect()
}

fn type_mappings(target_platform: &BindingTargetPlatform) -> Vec<BindingTypeMapping> {
    let mappings = [
        ("String", "string", "String", "String", "str"),
        (
            "Option<String>",
            "string?",
            "String?",
            "String?",
            "Optional[str]",
        ),
        ("i64", "i64", "Int64", "Long", "int"),
        ("bool", "boolean", "Bool", "Boolean", "bool"),
        ("Vec<T>", "sequence<T>", "[T]", "List<T>", "list[T]"),
        ("enum", "enum", "enum", "enum class", "Enum"),
        ("struct", "dictionary", "struct", "data class", "dataclass"),
        (
            "Result<T, CoreError>",
            "[Throws=CoreError] T",
            "throws",
            "@Throws",
            "raise",
        ),
    ];
    mappings
        .into_iter()
        .map(
            |(rust_type, udl_type, swift, kotlin, python)| BindingTypeMapping {
                rust_type: rust_type.to_owned(),
                udl_type: udl_type.to_owned(),
                target_type: target_type_for(target_platform, swift, kotlin, python).to_owned(),
                status: BindingSupportStatus::Supported,
                reason: None,
            },
        )
        .collect()
}

fn target_type_for<'a>(
    target_platform: &BindingTargetPlatform,
    swift: &'a str,
    kotlin: &'a str,
    python: &'a str,
) -> &'a str {
    match target_platform {
        BindingTargetPlatform::Swift => swift,
        BindingTargetPlatform::Kotlin => kotlin,
        BindingTargetPlatform::Python => python,
    }
}

fn missing_capabilities(target_platform: &BindingTargetPlatform) -> Vec<BindingMissingCapability> {
    let mut capabilities = Vec::new();
    if matches!(target_platform, BindingTargetPlatform::Kotlin) {
        capabilities.push(BindingMissingCapability {
            capability: "C4-01".to_owned(),
            label: "Generated Kotlin binding packaging".to_owned(),
            status: BindingSupportStatus::Limited,
            reason: "Stage 4 contract defines the UDL surface; packaging is verified by later platform tasks".to_owned(),
        });
    }
    capabilities
}
