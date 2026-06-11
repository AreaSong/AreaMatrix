import Foundation

protocol CoreBindingContractInspecting: Sendable {
    func inspectBindingContract(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64
    ) async throws -> BindingContractReportSnapshot
}

protocol CorePlatformCapabilitiesLoading: Sendable {
    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot
}

enum BindingTargetPlatformSnapshot: String, CaseIterable, Equatable, Hashable {
    case swift = "Swift"
    case kotlin = "Kotlin"
    case python = "Python"
}

enum BindingSupportStatusSnapshot: String, Equatable, Hashable {
    case supported = "Supported"
    case limited = "Limited"
    case missing = "Missing"
}

struct BindingApiContractSnapshot: Equatable, Identifiable {
    var name: String
    var capability: String
    var status: BindingSupportStatusSnapshot
    var reason: String?

    var id: String {
        "\(capability)-\(name)"
    }
}

struct BindingTypeMappingSnapshot: Equatable, Identifiable {
    var rustType: String
    var udlType: String
    var targetType: String
    var status: BindingSupportStatusSnapshot
    var reason: String?

    var id: String {
        "\(rustType)-\(udlType)-\(targetType)"
    }
}

struct BindingMissingCapabilitySnapshot: Equatable, Identifiable {
    var capability: String
    var label: String
    var status: BindingSupportStatusSnapshot
    var reason: String

    var id: String {
        "\(capability)-\(label)"
    }
}

struct BindingContractReportSnapshot: Equatable {
    var targetPlatform: BindingTargetPlatformSnapshot
    var bindingVersion: Int64
    var coreVersion: String
    var supportedApis: [BindingApiContractSnapshot]
    var typeMappings: [BindingTypeMappingSnapshot]
    var missingCapabilities: [BindingMissingCapabilitySnapshot]
}

enum PlatformIdSnapshot: String, Equatable, Hashable {
    case macos = "macOS"
    case ios = "iOS"
    case windows = "Windows"
    case linux = "Linux"
    case unknown = "Unknown"
}

enum PlatformCapabilityStatusSnapshot: String, Equatable, Hashable {
    case available = "Available"
    case limited = "Limited"
    case notAvailable = "Not available"
    case unknown = "Unknown"
}

struct PlatformCapabilitySupportSnapshot: Equatable {
    var status: PlatformCapabilityStatusSnapshot
    var uiEnabled: Bool
    var requiresPermission: Bool
    var reason: String?
}

struct PlatformCapabilitiesSnapshot: Equatable {
    var platform: PlatformIdSnapshot
    var appVersion: String
    var watcher: PlatformCapabilitySupportSnapshot
    var trash: PlatformCapabilitySupportSnapshot
    var shareExtension: PlatformCapabilitySupportSnapshot
    var cloudPlaceholder: PlatformCapabilitySupportSnapshot
    var securityBookmark: PlatformCapabilitySupportSnapshot

    static func unknown(
        platform: PlatformIdSnapshot,
        appVersion: String,
        reason: String
    ) -> PlatformCapabilitiesSnapshot {
        let support = PlatformCapabilitySupportSnapshot(
            status: .unknown,
            uiEnabled: false,
            requiresPermission: false,
            reason: reason
        )
        return PlatformCapabilitiesSnapshot(
            platform: platform,
            appVersion: appVersion,
            watcher: support,
            trash: support,
            shareExtension: support,
            cloudPlaceholder: support,
            securityBookmark: support
        )
    }
}

struct PlatformDifferencesCapabilityDisplayRow: Equatable, Identifiable {
    var name: String
    var support: PlatformCapabilitySupportSnapshot
    var detail: String
    var alternative: String?

    var id: String {
        name
    }
}

extension PlatformCapabilitiesSnapshot {
    var pageSpecRows: [PlatformDifferencesCapabilityDisplayRow] {
        [
            PlatformDifferencesCapabilityDisplayRow(
                name: "Repository access",
                support: securityBookmark,
                detail: "Uses platform repository permission or bookmark state from Core.",
                alternative: "Open repository settings if access needs to be renewed."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "File import",
                support: limitedFrom(
                    securityBookmark,
                    reason: "Import flows still rerun picker, permission, and duplicate preflight."
                ),
                detail: "Files and folders are imported only through their source flow.",
                alternative: "Return to the real import entry before choosing files."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "File watcher",
                support: watcher,
                detail: "Shows whether the platform can support repository change watching.",
                alternative: "Use manual rescan where watcher support is limited."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Cloud provider",
                support: cloudPlaceholder,
                detail: "Shows cloud placeholder or provider limitations without reporting sync progress.",
                alternative: "Use the platform cloud provider UI for exact sync state."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Trash / Recycle Bin",
                support: trash,
                detail: "Controls whether recoverable destructive actions may be enabled elsewhere.",
                alternative: "Keep dangerous actions disabled when this row is not available."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Share integration",
                support: shareExtension,
                detail: "Shows whether the platform exposes share or handoff entry points.",
                alternative: "Use file picker or drag and drop when share integration is unavailable."
            ),
            PlatformDifferencesCapabilityDisplayRow(
                name: "Camera import",
                support: limitedFrom(
                    shareExtension,
                    reason: "Camera capture is validated by the camera import flow, not this page."
                ),
                detail: "This page only explains camera entry availability; capture preflight stays in import.",
                alternative: "Open the camera import flow for the final permission check."
            )
        ]
    }

    private func limitedFrom(
        _ support: PlatformCapabilitySupportSnapshot,
        reason: String
    ) -> PlatformCapabilitySupportSnapshot {
        guard support.status == .available else {
            return support.withAdditionalReason(reason)
        }

        return PlatformCapabilitySupportSnapshot(
            status: .limited,
            uiEnabled: false,
            requiresPermission: true,
            reason: reason
        )
    }
}

private extension PlatformCapabilitySupportSnapshot {
    func withAdditionalReason(_ additionalReason: String) -> PlatformCapabilitySupportSnapshot {
        let combinedReason: String = if let reason, !reason.isEmpty {
            "\(reason) \(additionalReason)"
        } else {
            additionalReason
        }

        return PlatformCapabilitySupportSnapshot(
            status: status,
            uiEnabled: uiEnabled,
            requiresPermission: requiresPermission,
            reason: combinedReason
        )
    }
}

extension CoreBridge: CoreBindingContractInspecting {
    func inspectBindingContract(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64
    ) async throws -> BindingContractReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let request = BindingContractRequest(
                targetPlatform: targetPlatform.coreTargetPlatform,
                bindingVersion: bindingVersion
            )
            let report = try inspectCoreBindingContract(request: request)
            return BindingContractReportSnapshot(coreReport: report)
        }.value
    }
}

extension CoreBridge: CorePlatformCapabilitiesLoading {
    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let capabilities = try loadCorePlatformCapabilities(
                platform: platform.corePlatformId,
                appVersion: appVersion
            )
            return PlatformCapabilitiesSnapshot(coreCapabilities: capabilities)
        }.value
    }
}

extension BindingContractReportSnapshot {
    init(coreReport: BindingContractReport) {
        targetPlatform = BindingTargetPlatformSnapshot(coreTargetPlatform: coreReport.targetPlatform)
        bindingVersion = coreReport.bindingVersion
        coreVersion = coreReport.coreVersion
        supportedApis = coreReport.supportedApis.map(BindingApiContractSnapshot.init(coreContract:))
        typeMappings = coreReport.typeMappings.map(BindingTypeMappingSnapshot.init(coreMapping:))
        missingCapabilities = coreReport.missingCapabilities.map(
            BindingMissingCapabilitySnapshot.init(coreCapability:)
        )
    }
}

extension PlatformCapabilitiesSnapshot {
    init(coreCapabilities: PlatformCapabilities) {
        platform = PlatformIdSnapshot(corePlatformId: coreCapabilities.platform)
        appVersion = coreCapabilities.appVersion
        watcher = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.watcher)
        trash = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.trash)
        shareExtension = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.shareExtension)
        cloudPlaceholder = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.cloudPlaceholder)
        securityBookmark = PlatformCapabilitySupportSnapshot(coreSupport: coreCapabilities.securityBookmark)
    }
}

private extension PlatformCapabilitySupportSnapshot {
    init(coreSupport: PlatformCapabilitySupport) {
        status = PlatformCapabilityStatusSnapshot(coreStatus: coreSupport.status)
        uiEnabled = coreSupport.uiEnabled
        requiresPermission = coreSupport.requiresPermission
        reason = coreSupport.reason
    }
}

private extension BindingApiContractSnapshot {
    init(coreContract: BindingApiContract) {
        name = coreContract.name
        capability = coreContract.capability
        status = BindingSupportStatusSnapshot(coreStatus: coreContract.status)
        reason = coreContract.reason
    }
}

private extension BindingTypeMappingSnapshot {
    init(coreMapping: BindingTypeMapping) {
        rustType = coreMapping.rustType
        udlType = coreMapping.udlType
        targetType = coreMapping.targetType
        status = BindingSupportStatusSnapshot(coreStatus: coreMapping.status)
        reason = coreMapping.reason
    }
}

private extension BindingMissingCapabilitySnapshot {
    init(coreCapability: BindingMissingCapability) {
        capability = coreCapability.capability
        label = coreCapability.label
        status = BindingSupportStatusSnapshot(coreStatus: coreCapability.status)
        reason = coreCapability.reason
    }
}

private extension PlatformIdSnapshot {
    init(corePlatformId: PlatformId) {
        switch corePlatformId {
        case .macos:
            self = .macos
        case .ios:
            self = .ios
        case .windows:
            self = .windows
        case .linux:
            self = .linux
        case .unknown:
            self = .unknown
        }
    }

    var corePlatformId: PlatformId {
        switch self {
        case .macos:
            .macos
        case .ios:
            .ios
        case .windows:
            .windows
        case .linux:
            .linux
        case .unknown:
            .unknown
        }
    }
}

private extension BindingTargetPlatformSnapshot {
    init(coreTargetPlatform: BindingTargetPlatform) {
        switch coreTargetPlatform {
        case .swift:
            self = .swift
        case .kotlin:
            self = .kotlin
        case .python:
            self = .python
        }
    }

    var coreTargetPlatform: BindingTargetPlatform {
        switch self {
        case .swift:
            .swift
        case .kotlin:
            .kotlin
        case .python:
            .python
        }
    }
}

private extension PlatformCapabilityStatusSnapshot {
    init(coreStatus: PlatformCapabilityStatus) {
        switch coreStatus {
        case .available:
            self = .available
        case .limited:
            self = .limited
        case .notAvailable:
            self = .notAvailable
        case .unknown:
            self = .unknown
        }
    }
}

private extension BindingSupportStatusSnapshot {
    init(coreStatus: BindingSupportStatus) {
        switch coreStatus {
        case .supported:
            self = .supported
        case .limited:
            self = .limited
        case .missing:
            self = .missing
        }
    }
}

private func inspectCoreBindingContract(request: BindingContractRequest) throws -> BindingContractReport {
    try inspectBindingContract(request: request)
}

private func loadCorePlatformCapabilities(
    platform: PlatformId,
    appVersion: String
) throws -> PlatformCapabilities {
    try getPlatformCapabilities(platform: platform, appVersion: appVersion)
}
