/// Stable binding-contract values shared by the Bridge, features, and tests.
///
/// These values intentionally do not expose UniFFI-generated types or
/// application-localized display text. The Bridge owns conversion from Core;
/// the App owns localized presentation.
public enum BindingTargetPlatformSnapshot: String, CaseIterable, Equatable, Hashable, Sendable {
    case swift = "Swift"
    case kotlin = "Kotlin"
    case python = "Python"
}

public enum BindingSupportStatusSnapshot: String, Equatable, Hashable, Sendable {
    case supported = "Supported"
    case limited = "Limited"
    case missing = "Missing"
}

public struct BindingApiContractSnapshot: Equatable, Identifiable, Sendable {
    public let name: String
    public let capability: String
    public let status: BindingSupportStatusSnapshot
    public let reason: String?

    public init(
        name: String,
        capability: String,
        status: BindingSupportStatusSnapshot,
        reason: String?
    ) {
        self.name = name
        self.capability = capability
        self.status = status
        self.reason = reason
    }

    public var id: String {
        "\(capability)-\(name)"
    }
}

public struct BindingTypeMappingSnapshot: Equatable, Identifiable, Sendable {
    public let rustType: String
    public let udlType: String
    public let targetType: String
    public let status: BindingSupportStatusSnapshot
    public let reason: String?

    public init(
        rustType: String,
        udlType: String,
        targetType: String,
        status: BindingSupportStatusSnapshot,
        reason: String?
    ) {
        self.rustType = rustType
        self.udlType = udlType
        self.targetType = targetType
        self.status = status
        self.reason = reason
    }

    public var id: String {
        "\(rustType)-\(udlType)-\(targetType)"
    }
}

public struct BindingMissingCapabilitySnapshot: Equatable, Identifiable, Sendable {
    public let capability: String
    public let label: String
    public let status: BindingSupportStatusSnapshot
    public let reason: String

    public init(
        capability: String,
        label: String,
        status: BindingSupportStatusSnapshot,
        reason: String
    ) {
        self.capability = capability
        self.label = label
        self.status = status
        self.reason = reason
    }

    public var id: String {
        "\(capability)-\(label)"
    }
}

public struct BindingContractReportSnapshot: Equatable, Sendable {
    public let targetPlatform: BindingTargetPlatformSnapshot
    public let bindingVersion: Int64
    public let coreVersion: String
    public let supportedApis: [BindingApiContractSnapshot]
    public let typeMappings: [BindingTypeMappingSnapshot]
    public let missingCapabilities: [BindingMissingCapabilitySnapshot]

    public init(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64,
        coreVersion: String,
        supportedApis: [BindingApiContractSnapshot],
        typeMappings: [BindingTypeMappingSnapshot],
        missingCapabilities: [BindingMissingCapabilitySnapshot]
    ) {
        self.targetPlatform = targetPlatform
        self.bindingVersion = bindingVersion
        self.coreVersion = coreVersion
        self.supportedApis = supportedApis
        self.typeMappings = typeMappings
        self.missingCapabilities = missingCapabilities
    }
}
