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
        var issues: [ValidationIssue] = []
        let groupedIDs = Dictionary(grouping: manifests, by: \.id)

        for id in groupedIDs.keys.sorted() where groupedIDs[id, default: []].count > 1 {
            issues.append(.duplicateID(id))
        }

        let manifestByID = groupedIDs.reduce(into: [String: FeatureManifest]()) { result, entry in
            // Duplicate IDs are reported above; use the first declaration for
            // graph traversal so validation remains non-fatal and deterministic.
            result[entry.key] = entry.value[0]
        }
        let knownIDs = Set(manifestByID.keys).union(infrastructureIDs)

        for manifest in manifests.sorted(by: { $0.id < $1.id }) {
            let requiredFields: [(String, Bool)] = [
                ("id", !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("owner", !manifest.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("responsibility", !manifest.responsibility.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                ("riskBoundary", !manifest.riskBoundary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]
            for (field, isPresent) in requiredFields where !isPresent {
                issues.append(.missingField(featureID: manifest.id, field: field))
            }

            let duplicateDependencies = Dictionary(grouping: manifest.dependencies, by: { $0 })
                .filter { $0.value.count > 1 }
                .map(\.key)
                .sorted()
            issues.append(contentsOf: duplicateDependencies.map {
                .duplicateDependency(featureID: manifest.id, dependency: $0)
            })

            for dependency in manifest.dependencies.sorted() where !knownIDs.contains(dependency) {
                issues.append(.unknownDependency(featureID: manifest.id, dependency: dependency))
            }
        }

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
        for cycle in cycles.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            issues.append(.dependencyCycle(cycle))
        }

        return issues
    }

    private enum VisitState {
        case visiting
        case visited
    }
}
