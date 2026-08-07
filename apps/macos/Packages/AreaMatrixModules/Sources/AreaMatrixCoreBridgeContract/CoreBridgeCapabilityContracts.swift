import AreaMatrixCoreContracts

/// Stable capability protocols consumed by App composition and feature models.
///
/// Implementations remain App-owned because they depend on tracked UniFFI
/// bindings; the protocol surface itself is independent of generated code.
public protocol CoreBindingContractInspecting: Sendable {
    func inspectBindingContract(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64
    ) async throws -> BindingContractReportSnapshot
}

public protocol CorePlatformCapabilitiesLoading: Sendable {
    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot
}
