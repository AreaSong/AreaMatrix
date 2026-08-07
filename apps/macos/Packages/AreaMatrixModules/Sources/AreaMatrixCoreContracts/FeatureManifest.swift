import Foundation

/// Compile-time feature ownership contract consumed by the application composition root.
public struct FeatureManifest: Equatable, Identifiable, Sendable {
    public enum RiskLevel: String, Sendable {
        case low
        case medium
        case high
        case missionCritical
    }

    public enum ValidationProfile: String, Sendable {
        case unit
        case feature
        case integration
        case safety
    }

    public let id: String
    public let owner: String
    public let responsibility: String
    public let riskBoundary: String
    public let routes: [String]
    public let commands: [String]
    public let settingsPanes: [String]
    public let capabilities: [String]
    public let dependencies: [String]
    public let previewScenarios: [String]
    public let riskLevel: RiskLevel
    public let validationProfile: ValidationProfile
    public let extensions: [FeatureExtensionManifest]

    public init(
        id: String,
        owner: String,
        responsibility: String,
        riskBoundary: String,
        routes: [String],
        commands: [String],
        settingsPanes: [String],
        capabilities: [String],
        dependencies: [String],
        previewScenarios: [String],
        riskLevel: RiskLevel,
        validationProfile: ValidationProfile,
        extensions: [FeatureExtensionManifest] = []
    ) {
        self.id = id
        self.owner = owner
        self.responsibility = responsibility
        self.riskBoundary = riskBoundary
        self.routes = routes
        self.commands = commands
        self.settingsPanes = settingsPanes
        self.capabilities = capabilities
        self.dependencies = dependencies
        self.previewScenarios = previewScenarios
        self.riskLevel = riskLevel
        self.validationProfile = validationProfile
        self.extensions = extensions
    }
}

/// Compile-time ownership contract supplied by each feature and composed by the App target.
public protocol FeatureManifestProvider {
    static var manifest: FeatureManifest { get }
}

/// Deterministic validation for the feature dependency graph.
///
/// The application owns composition, while this contract package owns the
/// graph invariants that every composition must satisfy. Keeping the checker
/// here lets package-level tests and the App governance suite use the same
/// rules without duplicating traversal logic.
public enum FeatureManifestGraph {
    public enum ValidationIssue: Equatable, Sendable {
        case duplicateID(String)
        case missingField(featureID: String, field: String)
        case duplicateDependency(featureID: String, dependency: String)
        case unknownDependency(featureID: String, dependency: String)
        case dependencyCycle([String])
    }

    public static func validate(
        _ manifests: [FeatureManifest],
        infrastructureIDs: Set<String> = []
    ) -> [ValidationIssue] {
        let groupedIDs = Dictionary(grouping: manifests, by: \.id)
        let manifestByID = manifestByID(from: groupedIDs)
        let knownIDs = Set(manifestByID.keys).union(infrastructureIDs)
        return duplicateIssues(from: groupedIDs) +
            manifestIssues(manifests, knownIDs: knownIDs) +
            dependencyCycleIssues(manifestByID: manifestByID)
    }

    private static func duplicateIssues(
        from groupedIDs: [String: [FeatureManifest]]
    ) -> [ValidationIssue] {
        groupedIDs.keys.sorted().compactMap { id in
            groupedIDs[id, default: []].count > 1 ? .duplicateID(id) : nil
        }
    }

    private static func manifestByID(
        from groupedIDs: [String: [FeatureManifest]]
    ) -> [String: FeatureManifest] {
        groupedIDs.reduce(into: [String: FeatureManifest]()) { result, entry in
            // Duplicate IDs are reported above; use the first declaration for
            // graph traversal so validation remains non-fatal and deterministic.
            result[entry.key] = entry.value[0]
        }
    }

    private static func manifestIssues(
        _ manifests: [FeatureManifest],
        knownIDs: Set<String>
    ) -> [ValidationIssue] {
        manifests.sorted(by: { $0.id < $1.id }).flatMap { manifest in
            let requiredFields: [(String, Bool)] = [
                ("id", !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("owner", !manifest.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("responsibility", !manifest.responsibility.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("riskBoundary", !manifest.riskBoundary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]
            let missingFields: [ValidationIssue] = requiredFields.compactMap { field, isPresent -> ValidationIssue? in
                isPresent ? nil : .missingField(featureID: manifest.id, field: field)
            }
            let duplicateDependencies = Dictionary(grouping: manifest.dependencies, by: { $0 })
                .filter { $0.value.count > 1 }
                .map(\.key)
                .sorted()
                .map { ValidationIssue.duplicateDependency(featureID: manifest.id, dependency: $0) }
            let sortedDependencies = manifest.dependencies.sorted()
            let unknownDependencies = sortedDependencies.compactMap { dependency -> ValidationIssue? in
                knownIDs.contains(dependency)
                    ? nil
                    : .unknownDependency(featureID: manifest.id, dependency: dependency)
            }
            return missingFields + duplicateDependencies + unknownDependencies
        }
    }

    private static func dependencyCycleIssues(
        manifestByID: [String: FeatureManifest]
    ) -> [ValidationIssue] {
        var visitState: [String: VisitState] = [:]
        var path: [String] = []
        var cycles = Set<[String]>()

        func visit(_ id: String) {
            guard let manifest = manifestByID[id] else { return }
            switch visitState[id] {
            case .visited:
                return
            case .visiting:
                guard let start = path.firstIndex(of: id) else { return }
                cycles.insert(Array(path[start...]) + [id])
                return
            case nil:
                break
            }

            visitState[id] = .visiting
            path.append(id)
            for dependency in manifest.dependencies.sorted() where manifestByID[dependency] != nil {
                visit(dependency)
            }
            _ = path.popLast()
            visitState[id] = .visited
        }

        for id in manifestByID.keys.sorted() {
            visit(id)
        }
        return cycles
            .sorted(by: { $0.lexicographicallyPrecedes($1) })
            .map(ValidationIssue.dependencyCycle)
    }

    private enum VisitState {
        case visiting
        case visited
    }
}
