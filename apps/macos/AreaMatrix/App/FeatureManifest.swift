import AreaMatrixCoreContracts
import AreaMatrixFeatureAI
import AreaMatrixFeatureIngestion
import AreaMatrixFeatureLibrary
import AreaMatrixFeatureOperation
import AreaMatrixFeatureSettings

/// Composition-only registry. Ownership and metadata live beside each feature;
/// this type only defines application order and infrastructure entries.
enum FeatureManifestRegistry {
    static let infrastructureIDs: Set<String> = [
        "AreaMatrixApp",
        "CoreBridge",
        "DesignSystem",
        "PlatformServices"
    ]

    static let all: [FeatureManifest] =
        AIFeatureManifests.all +
        LibraryFeatureManifests.all +
        IngestionFeatureManifests.all +
        OperationFeatureManifests.all +
        SettingsFeatureManifests.all + [
            DiagnosticsFeatureManifestProvider.manifest
        ]

    static var byID: [String: FeatureManifest] {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    static var validationIssues: [FeatureManifestGraph.ValidationIssue] {
        FeatureManifestGraph.validate(all, infrastructureIDs: infrastructureIDs)
    }

    static let extensionRegistry = FeatureExtensionRegistry(
        featureManifests: all,
        infrastructureIDs: infrastructureIDs
    )

    static var extensions: [FeatureExtensionManifest] {
        extensionRegistry.all
    }

    static var extensionValidationIssues: [FeatureExtensionGraph.ValidationIssue] {
        extensionRegistry.validationIssues
    }

    static func extensions(of kind: FeatureExtensionKind) -> [FeatureExtensionManifest] {
        extensionRegistry.extensions(of: kind)
    }

    @MainActor
    static func makeRuntimeRegistry(commandRouter: AppCommandRouter) -> FeatureExtensionRuntimeRegistry {
        FeatureExtensionRuntimeRegistry(
            manifestRegistry: extensionRegistry,
            registrations: [
                FeatureExtensionRuntimeRegistration(id: "command.palette", contractVersion: "1.0.0") {
                    commandRouter.publish(.commandPaletteRequested)
                },
                FeatureExtensionRuntimeRegistration(id: "command.settings", contractVersion: "1.0.0") {
                    commandRouter.publish(.settingsRequested)
                },
                FeatureExtensionRuntimeRegistration(id: "command.file-actions", contractVersion: "1.0.0") {
                    commandRouter.publish(.featureExtensionRequested(id: "command.file-actions"))
                },
                FeatureExtensionRuntimeRegistration(id: "import.files", contractVersion: "1.0.0") {
                    commandRouter.publish(.importRequested)
                },
                FeatureExtensionRuntimeRegistration(id: "import.folder", contractVersion: "1.0.0") {
                    commandRouter.publish(.importRequested)
                },
                FeatureExtensionRuntimeRegistration(id: "ai.remote-provider", contractVersion: "1.0.0") {
                    commandRouter.publish(.featureExtensionRequested(id: "ai.remote-provider"))
                }
            ]
        )
    }
}

/// A concrete executable registration for a built-in feature extension.
///
/// The closure is supplied by the App composition root and may capture the
/// typed dependencies required by the owning feature. No dynamic loading or
/// third-party code execution is implied by this registry.
@MainActor
struct FeatureExtensionRuntimeRegistration {
    let id: String
    let contractVersion: String
    let execute: () -> Void
}

@MainActor
struct FeatureExtensionRuntimeRegistry {
    enum ValidationIssue: Equatable {
        case duplicateRegistration(String)
        case unknownExtension(String)
        case missingRegistration(String)
        case missingContractVersion(String)
        case contractVersionMismatch(id: String, expected: String, actual: String)
    }

    private let registrationsByID: [String: FeatureExtensionRuntimeRegistration]
    private let manifestRegistry: FeatureExtensionRegistry

    init(
        manifestRegistry: FeatureExtensionRegistry,
        registrations: [FeatureExtensionRuntimeRegistration]
    ) {
        self.manifestRegistry = manifestRegistry
        registrationsByID = Dictionary(
            grouping: registrations,
            by: \.id
        ).reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.first
        }
        duplicateRegistrationIDs = Dictionary(grouping: registrations, by: \.id)
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }

    private let duplicateRegistrationIDs: [String]

    var validationIssues: [ValidationIssue] {
        let duplicateIssues = duplicateRegistrationIDs.map(ValidationIssue.duplicateRegistration)
        let unknownIssues = registrationsByID.keys
            .filter { manifestRegistry.manifest(id: $0) == nil }
            .sorted()
            .map(ValidationIssue.unknownExtension)
        let missingIssues = Set(manifestRegistry.all.map(\.id))
            .subtracting(registrationsByID.keys)
            .sorted()
            .map(ValidationIssue.missingRegistration)
        let contractIssues = registrationsByID.keys.sorted().flatMap { id -> [ValidationIssue] in
            guard let registration = registrationsByID[id],
                  let manifest = manifestRegistry.manifest(id: id)
            else { return [] }
            let version = registration.contractVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty else {
                return [.missingContractVersion(id)]
            }
            guard version != manifest.contractVersion else { return [] }
            return [.contractVersionMismatch(
                id: id,
                expected: manifest.contractVersion,
                actual: registration.contractVersion
            )]
        }
        return duplicateIssues + unknownIssues + missingIssues + contractIssues
    }

    var registeredIDs: [String] {
        registrationsByID.keys.sorted()
    }

    @discardableResult
    func execute(id: String) -> Bool {
        guard validationIssues.isEmpty else { return false }
        guard let registration = registrationsByID[id], manifestRegistry.manifest(id: id) != nil else {
            return false
        }
        registration.execute()
        return true
    }
}
