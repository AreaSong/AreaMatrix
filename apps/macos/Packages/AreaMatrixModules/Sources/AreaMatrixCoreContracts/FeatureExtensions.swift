import Foundation

/// Stable extension kinds that can be composed by the application.
///
/// These are compile-time registrations, not a runtime plug-in loader. Each
/// registration has an owning feature, an explicit contract version, and a
/// validation profile so the App can reject drift before routing user input.
public enum FeatureExtensionKind: String, CaseIterable, Equatable, Sendable {
    case command
    case importSource
    case aiProvider
}

public struct FeatureExtensionManifest: Equatable, Identifiable, Sendable {
    public let id: String
    public let ownerFeatureID: String
    public let kind: FeatureExtensionKind
    public let contractVersion: String
    public let capabilities: [String]
    public let dependencies: [String]
    public let riskLevel: FeatureManifest.RiskLevel
    public let validationProfile: FeatureManifest.ValidationProfile

    public init(
        id: String,
        ownerFeatureID: String,
        kind: FeatureExtensionKind,
        contractVersion: String,
        capabilities: [String],
        dependencies: [String],
        riskLevel: FeatureManifest.RiskLevel,
        validationProfile: FeatureManifest.ValidationProfile
    ) {
        self.id = id
        self.ownerFeatureID = ownerFeatureID
        self.kind = kind
        self.contractVersion = contractVersion
        self.capabilities = capabilities
        self.dependencies = dependencies
        self.riskLevel = riskLevel
        self.validationProfile = validationProfile
    }
}

/// Validation for command, import-source, and AI-provider registrations.
public enum FeatureExtensionGraph {
    public enum ValidationIssue: Equatable, Sendable {
        case duplicateID(String)
        case missingField(extensionID: String, field: String)
        case ownerMismatch(extensionID: String, declaredOwner: String, featureID: String)
        case duplicateDependency(extensionID: String, dependency: String)
        case unknownDependency(extensionID: String, dependency: String)
    }

    public static func validate(
        _ extensions: [FeatureExtensionManifest],
        featureIDs: Set<String>,
        infrastructureIDs: Set<String> = [],
        expectedOwnerByExtensionID: [String: String] = [:]
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let groupedIDs = Dictionary(grouping: extensions, by: \.id)

        for id in groupedIDs.keys.sorted() where groupedIDs[id, default: []].count > 1 {
            issues.append(.duplicateID(id))
        }

        let knownDependencies = featureIDs.union(infrastructureIDs)
        for item in extensions.sorted(by: { $0.id < $1.id }) {
            let requiredFields: [(String, Bool)] = [
                ("id", !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("ownerFeatureID", !item.ownerFeatureID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("contractVersion", !item.contractVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]
            for (field, isPresent) in requiredFields where !isPresent {
                issues.append(.missingField(extensionID: item.id, field: field))
            }

            if let expectedOwner = expectedOwnerByExtensionID[item.id] {
                if item.ownerFeatureID != expectedOwner {
                    issues.append(.ownerMismatch(
                        extensionID: item.id,
                        declaredOwner: item.ownerFeatureID,
                        featureID: expectedOwner
                    ))
                }
            } else if !item.ownerFeatureID.isEmpty, !featureIDs.contains(item.ownerFeatureID) {
                issues.append(.ownerMismatch(
                    extensionID: item.id,
                    declaredOwner: item.ownerFeatureID,
                    featureID: "<missing>"
                ))
            }

            let duplicateDependencies = Dictionary(grouping: item.dependencies, by: { $0 })
                .filter { $0.value.count > 1 }
                .map(\.key)
                .sorted()
            issues.append(contentsOf: duplicateDependencies.map {
                .duplicateDependency(extensionID: item.id, dependency: $0)
            })

            for dependency in item.dependencies.sorted() where !knownDependencies.contains(dependency) {
                issues.append(.unknownDependency(extensionID: item.id, dependency: dependency))
            }
        }

        return issues
    }
}

/// Application-owned registry for compile-time feature extensions.
///
/// The registry deliberately stores manifests rather than executable plug-in
/// instances. Runtime plug-ins are outside the current security and API
/// compatibility boundary; this type provides the stable lookup and
/// validation contract that command, import-source, and AI-provider adapters
/// can consume.
public struct FeatureExtensionRegistry: Equatable, Sendable {
    public let all: [FeatureExtensionManifest]
    public let featureIDs: Set<String>
    public let infrastructureIDs: Set<String>
    private let expectedOwnerByExtensionID: [String: String]

    public init(
        featureManifests: [FeatureManifest],
        infrastructureIDs: Set<String> = []
    ) {
        self.featureIDs = Set(featureManifests.map(\.id))
        self.infrastructureIDs = infrastructureIDs
        self.all = featureManifests
            .flatMap(\.extensions)
            .sorted { $0.id < $1.id }

        self.expectedOwnerByExtensionID = featureManifests.reduce(into: [String: String]()) { result, feature in
            for extensionManifest in feature.extensions where result[extensionManifest.id] == nil {
                result[extensionManifest.id] = feature.id
            }
        }
    }

    public var validationIssues: [FeatureExtensionGraph.ValidationIssue] {
        FeatureExtensionGraph.validate(
            all,
            featureIDs: featureIDs,
            infrastructureIDs: infrastructureIDs,
            expectedOwnerByExtensionID: expectedOwnerByExtensionID
        )
    }

    public func manifest(id: String) -> FeatureExtensionManifest? {
        all.first { $0.id == id }
    }

    public func extensions(of kind: FeatureExtensionKind) -> [FeatureExtensionManifest] {
        all.filter { $0.kind == kind }
    }
}
