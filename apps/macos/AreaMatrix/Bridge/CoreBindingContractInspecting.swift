import AreaMatrixCoreBridgeContract
import AreaMatrixCoreContracts
import Foundation

extension BindingTargetPlatformSnapshot {
    var displayName: String {
        rawValue
    }
}

extension BindingSupportStatusSnapshot {
    var displayName: String {
        switch self {
        case .supported: L10n.string("Supported")
        case .limited: L10n.string("Limited")
        case .missing: L10n.string("Missing")
        }
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
            let report = try self.generatedAdapter.inspectBindingContract(request: request)
            return BindingContractReportSnapshot(coreReport: report)
        }.value
    }
}

extension BindingContractReportSnapshot {
    init(coreReport: BindingContractReport) {
        self.init(
            targetPlatform: BindingTargetPlatformSnapshot(coreTargetPlatform: coreReport.targetPlatform),
            bindingVersion: coreReport.bindingVersion,
            coreVersion: coreReport.coreVersion,
            supportedApis: coreReport.supportedApis.map(BindingApiContractSnapshot.init(coreContract:)),
            typeMappings: coreReport.typeMappings.map(BindingTypeMappingSnapshot.init(coreMapping:)),
            missingCapabilities: coreReport.missingCapabilities.map(
                BindingMissingCapabilitySnapshot.init(coreCapability:)
            )
        )
    }
}

private extension BindingApiContractSnapshot {
    init(coreContract: BindingApiContract) {
        self.init(
            name: coreContract.name,
            capability: coreContract.capability,
            status: BindingSupportStatusSnapshot(coreStatus: coreContract.status),
            reason: coreContract.reason
        )
    }
}

private extension BindingTypeMappingSnapshot {
    init(coreMapping: BindingTypeMapping) {
        self.init(
            rustType: coreMapping.rustType,
            udlType: coreMapping.udlType,
            targetType: coreMapping.targetType,
            status: BindingSupportStatusSnapshot(coreStatus: coreMapping.status),
            reason: coreMapping.reason
        )
    }
}

private extension BindingMissingCapabilitySnapshot {
    init(coreCapability: BindingMissingCapability) {
        self.init(
            capability: coreCapability.capability,
            label: coreCapability.label,
            status: BindingSupportStatusSnapshot(coreStatus: coreCapability.status),
            reason: coreCapability.reason
        )
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
