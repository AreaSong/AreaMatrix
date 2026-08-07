@testable import AreaMatrix
import AreaMatrixCoreContracts
import Combine
import XCTest

final class MacOSFeatureOwnershipGovernanceTests: MacOSGovernanceTestCase {
    private var featureOwnerInventory: [FeatureManifest] {
        FeatureManifestRegistry.all
    }

    func testFeatureDirectoriesStayOwnedAndInventoried() throws {
        let actual = try productionFeatureDirectories()
        let expected = featureOwnerInventory.map(\.id).sorted()

        XCTAssertEqual(
            actual,
            expected,
            "Every Features directory must have an explicit owner inventory entry before new feature code lands."
        )
    }

    func testFeatureOwnerInventoryDocumentsResponsibilityRiskAndValidation() {
        let incomplete = featureOwnerInventory.compactMap { item -> String? in
            guard !item.owner.isEmpty,
                  !item.responsibility.isEmpty,
                  !item.riskBoundary.isEmpty,
                  !item.validationProfile.rawValue.isEmpty,
                  !item.previewScenarios.isEmpty
            else {
                return item.id
            }
            return nil
        }

        XCTAssertEqual(
            incomplete,
            [],
            "Each feature manifest must document owner, responsibility, risk, preview, and validation profile."
        )
    }

    func testFeatureManifestIDsAndDependenciesAreStable() {
        let ids = featureOwnerInventory.map(\.id)
        let duplicateIDs = Dictionary(grouping: ids, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        let knownIDs = Set(ids).union(FeatureManifestRegistry.infrastructureIDs)
        let unknownDependencies = featureOwnerInventory.flatMap { manifest in
            manifest.dependencies
                .filter { !knownIDs.contains($0) }
                .map { "\(manifest.id)->\($0)" }
        }.sorted()

        XCTAssertEqual(duplicateIDs, [], "Feature IDs must be unique for routing and validation selection.")
        XCTAssertEqual(
            unknownDependencies,
            [],
            "Feature dependencies must point to an inventoried feature or a named infrastructure boundary."
        )
        XCTAssertEqual(
            FeatureManifestRegistry.validationIssues,
            [],
            "Feature manifest composition must reject empty metadata, duplicate dependencies, and dependency cycles."
        )
    }

    func testFeatureExtensionRegistriesAreTypedOwnedAndValidated() {
        XCTAssertEqual(
            FeatureManifestRegistry.extensionValidationIssues,
            [],
            "Command, import-source, and AI-provider registrations must have unique IDs and known owners/dependencies."
        )

        for kind in FeatureExtensionKind.allCases {
            XCTAssertFalse(
                FeatureManifestRegistry.extensions(of: kind).isEmpty,
                "The (kind.rawValue) extension registry must have at least one built-in contract."
            )
        }

        let owners = Set(FeatureManifestRegistry.all.map(\.id))
        XCTAssertTrue(
            FeatureManifestRegistry.extensions.allSatisfy { owners.contains($0.ownerFeatureID) },
            "Every extension must remain owned by an inventoried feature."
        )
    }

    @MainActor
    func testBuiltInRuntimeRegistryExecutesOnlyDeclaredExtensions() {
        let router = AppCommandRouter()
        let registry = FeatureManifestRegistry.makeRuntimeRegistry(commandRouter: router)
        XCTAssertEqual(registry.validationIssues, [])
        XCTAssertEqual(
            registry.registeredIDs,
            [
                "ai.remote-provider",
                "command.file-actions",
                "command.palette",
                "command.settings",
                "import.files",
                "import.folder"
            ]
        )
        XCTAssertFalse(registry.execute(id: "unknown.extension"))

        var received: [AppCommandRouter.Command] = []
        let cancellable = router.commands.sink { received.append($0) }
        defer { cancellable.cancel() }
        XCTAssertTrue(registry.execute(id: "command.palette"))
        XCTAssertTrue(registry.execute(id: "command.file-actions"))
        XCTAssertTrue(registry.execute(id: "ai.remote-provider"))
        XCTAssertEqual(
            received,
            [
                .commandPaletteRequested,
                .featureExtensionRequested(id: "command.file-actions"),
                .featureExtensionRequested(id: "ai.remote-provider")
            ]
        )
    }

    @MainActor
    func testRuntimeRegistryRejectsContractVersionDriftBeforeExecution() {
        let registrations = FeatureManifestRegistry.extensions.map { extensionManifest in
            FeatureExtensionRuntimeRegistration(
                id: extensionManifest.id,
                contractVersion: extensionManifest.id == "command.palette" ? "2.0.0" : extensionManifest
                    .contractVersion,
                execute: {}
            )
        }
        let registry = FeatureExtensionRuntimeRegistry(
            manifestRegistry: FeatureManifestRegistry.extensionRegistry,
            registrations: registrations
        )

        XCTAssertTrue(registry.validationIssues.contains(.contractVersionMismatch(
            id: "command.palette",
            expected: "1.0.0",
            actual: "2.0.0"
        )))
        XCTAssertFalse(registry.execute(id: "command.palette"))
    }
}
