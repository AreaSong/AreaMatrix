@testable import AreaMatrixCoreContracts
import XCTest

final class FeatureManifestCatalogTests: XCTestCase {
    func testCatalogContainsEveryBuiltInFeatureExactlyOnce() {
        let manifests = FeatureManifestCatalog.all

        XCTAssertEqual(manifests.count, 12)
        XCTAssertEqual(Set(manifests.map(\.id)).count, manifests.count)
        XCTAssertEqual(
            manifests.map(\.id),
            [
                "AI",
                "CommandPalette",
                "Detail",
                "Diagnostics",
                "FileActions",
                "Import",
                "MainList",
                "Onboarding",
                "RepositoryLifecycle",
                "Search",
                "Settings",
                "SyncConflicts"
            ]
        )
    }

    func testCatalogDependencyAndExtensionGraphsAreValid() {
        let manifests = FeatureManifestCatalog.all
        let infrastructure = ["CoreBridge", "PlatformServices", "DesignSystem"]

        XCTAssertEqual(
            FeatureManifestGraph.validate(manifests, infrastructureIDs: Set(infrastructure)),
            []
        )
        XCTAssertEqual(
            FeatureExtensionRegistry(featureManifests: manifests, infrastructureIDs: Set(infrastructure))
                .validationIssues,
            []
        )
    }

    func testCatalogLookupReturnsStableIdentity() {
        XCTAssertEqual(FeatureManifestCatalog.byID["Import"], FeatureManifestCatalog.import)
        XCTAssertEqual(FeatureManifestCatalog.byID["Settings"], FeatureManifestCatalog.settings)
        XCTAssertNil(FeatureManifestCatalog.byID["Unknown"])
    }
}
