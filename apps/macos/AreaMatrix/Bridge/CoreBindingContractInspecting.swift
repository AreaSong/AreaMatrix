import Foundation

protocol CoreBindingContractInspecting: Sendable {
    func inspectBindingContract(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64
    ) async throws -> BindingContractReportSnapshot
}

enum BindingTargetPlatformSnapshot: String, CaseIterable, Equatable, Hashable, Sendable {
    case swift = "Swift"
    case kotlin = "Kotlin"
    case python = "Python"
}

enum BindingSupportStatusSnapshot: String, Equatable, Hashable, Sendable {
    case supported = "Supported"
    case limited = "Limited"
    case missing = "Missing"
}

struct BindingApiContractSnapshot: Equatable, Sendable, Identifiable {
    var name: String
    var capability: String
    var status: BindingSupportStatusSnapshot
    var reason: String?

    var id: String {
        "\(capability)-\(name)"
    }
}

struct BindingTypeMappingSnapshot: Equatable, Sendable, Identifiable {
    var rustType: String
    var udlType: String
    var targetType: String
    var status: BindingSupportStatusSnapshot
    var reason: String?

    var id: String {
        "\(rustType)-\(udlType)-\(targetType)"
    }
}

struct BindingMissingCapabilitySnapshot: Equatable, Sendable, Identifiable {
    var capability: String
    var label: String
    var status: BindingSupportStatusSnapshot
    var reason: String

    var id: String {
        "\(capability)-\(label)"
    }
}

struct BindingContractReportSnapshot: Equatable, Sendable {
    var targetPlatform: BindingTargetPlatformSnapshot
    var bindingVersion: Int64
    var coreVersion: String
    var supportedApis: [BindingApiContractSnapshot]
    var typeMappings: [BindingTypeMappingSnapshot]
    var missingCapabilities: [BindingMissingCapabilitySnapshot]
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
