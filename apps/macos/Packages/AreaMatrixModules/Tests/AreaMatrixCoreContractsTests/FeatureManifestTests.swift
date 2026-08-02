@testable import AreaMatrixCoreContracts
import XCTest

final class FeatureManifestTests: XCTestCase {
    func testManifestPreservesOwnershipAndValidationContract() {
        let manifest = FeatureManifest(
            id: "Library",
            owner: "Library",
            responsibility: "List and detail composition",
            riskBoundary: "Read-only projection",
            routes: ["library"],
            commands: ["openLibrary"],
            settingsPanes: [],
            capabilities: ["CoreBridge"],
            dependencies: ["CoreBridge"],
            previewScenarios: ["Empty"],
            riskLevel: .medium,
            validationProfile: .feature
        )

        XCTAssertEqual(manifest.id, "Library")
        XCTAssertEqual(manifest.riskLevel, .medium)
        XCTAssertEqual(manifest.validationProfile, .feature)
        XCTAssertEqual(manifest.dependencies, ["CoreBridge"])
    }

    func testManifestProviderExposesTheFeatureContract() {
        enum TestFeatureProvider: FeatureManifestProvider {
            static let manifest = FeatureManifest(
                id: "TestFeature",
                owner: "TestFeature",
                responsibility: "Contract test",
                riskBoundary: "None",
                routes: ["test"],
                commands: [],
                settingsPanes: [],
                capabilities: [],
                dependencies: [],
                previewScenarios: ["Empty"],
                riskLevel: .low,
                validationProfile: .unit
            )
        }

        XCTAssertEqual(TestFeatureProvider.manifest.id, "TestFeature")
        XCTAssertEqual(TestFeatureProvider.manifest.validationProfile, .unit)
    }

    func testDependencyGraphReportsUnknownDependenciesAndCycles() {
        let manifests = [
            FeatureManifest(
                id: "A",
                owner: "A",
                responsibility: "A",
                riskBoundary: "A",
                routes: [],
                commands: [],
                settingsPanes: [],
                capabilities: [],
                dependencies: ["B", "Missing"],
                previewScenarios: ["default"],
                riskLevel: .low,
                validationProfile: .unit
            ),
            FeatureManifest(
                id: "B",
                owner: "B",
                responsibility: "B",
                riskBoundary: "B",
                routes: [],
                commands: [],
                settingsPanes: [],
                capabilities: [],
                dependencies: ["A"],
                previewScenarios: ["default"],
                riskLevel: .low,
                validationProfile: .unit
            )
        ]

        let issues = FeatureManifestGraph.validate(manifests)

        XCTAssertTrue(issues.contains(.unknownDependency(featureID: "A", dependency: "Missing")))
        XCTAssertTrue(issues.contains(.dependencyCycle(["A", "B", "A"])))
    }

    func testDependencyGraphReportsDuplicateIDsAndDependencies() {
        let manifest = FeatureManifest(
            id: "A",
            owner: "A",
            responsibility: "A",
            riskBoundary: "A",
            routes: [],
            commands: [],
            settingsPanes: [],
            capabilities: [],
            dependencies: ["Core", "Core"],
            previewScenarios: ["default"],
            riskLevel: .low,
            validationProfile: .unit
        )

        let issues = FeatureManifestGraph.validate([manifest, manifest], infrastructureIDs: ["Core"])

        XCTAssertTrue(issues.contains(.duplicateID("A")))
        XCTAssertTrue(issues.contains(.duplicateDependency(featureID: "A", dependency: "Core")))
    }

    func testExtensionGraphValidatesOwnerContractAndDependencies() {
        let extensions = [
            FeatureExtensionManifest(
                id: "command.library",
                ownerFeatureID: "Library",
                kind: .command,
                contractVersion: "1.0.0",
                capabilities: ["KeyboardRouting"],
                dependencies: ["CoreBridge"],
                riskLevel: .low,
                validationProfile: .feature
            ),
            FeatureExtensionManifest(
                id: "command.library",
                ownerFeatureID: "MissingFeature",
                kind: .command,
                contractVersion: "",
                capabilities: [],
                dependencies: ["Unknown", "Unknown"],
                riskLevel: .low,
                validationProfile: .unit
            )
        ]

        let issues = FeatureExtensionGraph.validate(
            extensions,
            featureIDs: ["Library"],
            infrastructureIDs: ["CoreBridge"]
        )

        XCTAssertTrue(issues.contains(.duplicateID("command.library")))
        XCTAssertTrue(issues.contains(.missingField(extensionID: "command.library", field: "contractVersion")))
        XCTAssertTrue(issues.contains(.ownerMismatch(
            extensionID: "command.library",
            declaredOwner: "MissingFeature",
            featureID: "<missing>"
        )))
        XCTAssertTrue(issues.contains(.duplicateDependency(extensionID: "command.library", dependency: "Unknown")))
        XCTAssertTrue(issues.contains(.unknownDependency(extensionID: "command.library", dependency: "Unknown")))
    }

    func testFeatureManifestCarriesFeatureOwnedExtensions() {
        let extensionManifest = FeatureExtensionManifest(
            id: "import.files",
            ownerFeatureID: "Import",
            kind: .importSource,
            contractVersion: "1.0.0",
            capabilities: ["UserFileRead"],
            dependencies: ["CoreBridge"],
            riskLevel: .missionCritical,
            validationProfile: .safety
        )
        let manifest = FeatureManifest(
            id: "Import",
            owner: "Import",
            responsibility: "Import",
            riskBoundary: "User files",
            routes: [],
            commands: [],
            settingsPanes: [],
            capabilities: [],
            dependencies: ["CoreBridge"],
            previewScenarios: ["default"],
            riskLevel: .missionCritical,
            validationProfile: .safety,
            extensions: [extensionManifest]
        )

        XCTAssertEqual(manifest.extensions, [extensionManifest])
        XCTAssertEqual(manifest.extensions.first?.kind, .importSource)
    }

    func testExtensionRegistryValidatesNestedOwnershipAndSupportsTypedLookup() {
        let importExtension = FeatureExtensionManifest(
            id: "import.files",
            ownerFeatureID: "OtherFeature",
            kind: .importSource,
            contractVersion: "1.0.0",
            capabilities: ["UserFileRead"],
            dependencies: ["CoreBridge"],
            riskLevel: .missionCritical,
            validationProfile: .safety
        )
        let feature = FeatureManifest(
            id: "Import",
            owner: "Import",
            responsibility: "Import",
            riskBoundary: "User files",
            routes: [],
            commands: [],
            settingsPanes: [],
            capabilities: [],
            dependencies: ["CoreBridge"],
            previewScenarios: ["default"],
            riskLevel: .missionCritical,
            validationProfile: .safety,
            extensions: [importExtension]
        )

        let registry = FeatureExtensionRegistry(
            featureManifests: [feature],
            infrastructureIDs: ["CoreBridge"]
        )

        XCTAssertEqual(registry.manifest(id: "import.files"), importExtension)
        XCTAssertEqual(registry.extensions(of: .importSource), [importExtension])
        XCTAssertTrue(registry.validationIssues.contains(.ownerMismatch(
            extensionID: "import.files",
            declaredOwner: "OtherFeature",
            featureID: "Import"
        )))
    }
}
