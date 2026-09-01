import AreaMatrixCoreSDK
import Foundation

protocol PlatformDifferencesBindingContractInspecting: Sendable {
    func inspectBindingContract(
        targetPlatform: PlatformDifferencesBindingTarget,
        bindingVersion: Int64
    ) async throws -> PlatformDifferencesBindingContractReport
}

enum PlatformDifferencesBindingTarget: String, CaseIterable, Equatable, Identifiable, Sendable {
    case swift = "Swift"
    case kotlin = "Kotlin"
    case python = "Python"

    var id: String { rawValue }
}

enum PlatformDifferencesBindingSupportStatus: String, Equatable, Sendable {
    case supported = "Supported"
    case limited = "Limited"
    case missing = "Missing"
}

struct PlatformDifferencesBindingApiContract: Equatable, Identifiable, Sendable {
    var name: String
    var capability: String
    var status: PlatformDifferencesBindingSupportStatus
    var reason: String?

    var id: String { "\(capability)-\(name)" }
}

struct PlatformDifferencesBindingTypeMapping: Equatable, Identifiable, Sendable {
    var rustType: String
    var udlType: String
    var targetType: String
    var status: PlatformDifferencesBindingSupportStatus
    var reason: String?

    var id: String { "\(rustType)-\(udlType)-\(targetType)" }
}

struct PlatformDifferencesMissingCapability: Equatable, Identifiable, Sendable {
    var capability: String
    var label: String
    var status: PlatformDifferencesBindingSupportStatus
    var reason: String

    var id: String { "\(capability)-\(label)" }
}

struct PlatformDifferencesBindingContractReport: Equatable, Sendable {
    var targetPlatform: PlatformDifferencesBindingTarget
    var bindingVersion: Int64
    var coreVersion: String
    var supportedApis: [PlatformDifferencesBindingApiContract]
    var typeMappings: [PlatformDifferencesBindingTypeMapping]
    var missingCapabilities: [PlatformDifferencesMissingCapability]
}

enum PlatformDifferencesBindingContractError: Error, Equatable, LocalizedError {
    case config(String)
    case internalFailure(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .config(reason), let .internalFailure(reason), let .unavailable(reason):
            reason
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .config:
            "Choose a supported binding contract version, then retry."
        case .internalFailure:
            "Retry after the Core bridge reports a complete contract."
        case .unavailable:
            "Check the Core bridge integration, then retry."
        }
    }
}

actor LivePlatformDifferencesCoreBridge: PlatformDifferencesBindingContractInspecting {
    private let client: PlatformDifferencesCoreFFIClient

    init(client: PlatformDifferencesCoreFFIClient = PlatformDifferencesCoreFFIClient()) {
        self.client = client
    }

    func inspectBindingContract(
        targetPlatform: PlatformDifferencesBindingTarget,
        bindingVersion: Int64
    ) async throws -> PlatformDifferencesBindingContractReport {
        try client.inspectBindingContract(targetPlatform: targetPlatform, bindingVersion: bindingVersion)
    }
}

struct PlatformDifferencesCoreFFIClient: Sendable {
    func inspectBindingContract(
        targetPlatform: PlatformDifferencesBindingTarget,
        bindingVersion: Int64
    ) throws -> PlatformDifferencesBindingContractReport {
        do {
            let request = AreaMatrixCoreSDK.BindingContractRequest(
                targetPlatform: PlatformDifferencesBindingSDKMapping.sdkTarget(targetPlatform),
                bindingVersion: bindingVersion
            )
            return PlatformDifferencesBindingSDKMapping.report(
                try AreaMatrixCoreSDK.inspectBindingContract(request: request)
            )
        } catch {
            throw PlatformDifferencesBindingSDKMapping.error(error)
        }
    }
}

enum PlatformDifferencesBindingSDKMapping {
    static func report(
        _ value: AreaMatrixCoreSDK.BindingContractReport
    ) -> PlatformDifferencesBindingContractReport {
        PlatformDifferencesBindingContractReport(
            targetPlatform: target(value.targetPlatform),
            bindingVersion: value.bindingVersion,
            coreVersion: value.coreVersion,
            supportedApis: value.supportedApis.map(api),
            typeMappings: value.typeMappings.map(typeMapping),
            missingCapabilities: value.missingCapabilities.map(missingCapability)
        )
    }

    private static func api(
        _ value: AreaMatrixCoreSDK.BindingApiContract
    ) -> PlatformDifferencesBindingApiContract {
        PlatformDifferencesBindingApiContract(
            name: value.name,
            capability: value.capability,
            status: status(value.status),
            reason: value.reason
        )
    }

    private static func typeMapping(
        _ value: AreaMatrixCoreSDK.BindingTypeMapping
    ) -> PlatformDifferencesBindingTypeMapping {
        PlatformDifferencesBindingTypeMapping(
            rustType: value.rustType,
            udlType: value.udlType,
            targetType: value.targetType,
            status: status(value.status),
            reason: value.reason
        )
    }

    private static func missingCapability(
        _ value: AreaMatrixCoreSDK.BindingMissingCapability
    ) -> PlatformDifferencesMissingCapability {
        PlatformDifferencesMissingCapability(
            capability: value.capability,
            label: value.label,
            status: status(value.status),
            reason: value.reason
        )
    }

    private static func target(
        _ value: AreaMatrixCoreSDK.BindingTargetPlatform
    ) -> PlatformDifferencesBindingTarget {
        switch value {
        case .swift:
            .swift
        case .kotlin:
            .kotlin
        case .python:
            .python
        }
    }

    private static func status(
        _ value: AreaMatrixCoreSDK.BindingSupportStatus
    ) -> PlatformDifferencesBindingSupportStatus {
        switch value {
        case .supported:
            .supported
        case .limited:
            .limited
        case .missing:
            .missing
        }
    }

    static func sdkTarget(
        _ value: PlatformDifferencesBindingTarget
    ) -> AreaMatrixCoreSDK.BindingTargetPlatform {
        switch value {
        case .swift:
            .swift
        case .kotlin:
            .kotlin
        case .python:
            .python
        }
    }

    static func error(_ error: Error) -> PlatformDifferencesBindingContractError {
        if let contractError = error as? PlatformDifferencesBindingContractError {
            return contractError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable("Platform capability details are unavailable.")
        }
        switch coreError {
        case let .Config(reason), let .Validation(reason):
            return .config(reason)
        case let .Internal(message):
            return .internalFailure(message)
        default:
            return .unavailable("Platform capability details are unavailable.")
        }
    }
}
