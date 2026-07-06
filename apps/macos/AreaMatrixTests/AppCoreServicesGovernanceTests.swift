import XCTest

private let expectedAppCoreServiceSurface = [
    "App/AppCoreServices.swift:static var aiCallLogClearer",
    "App/AppCoreServices.swift:static var aiCallLogLister",
    "App/AppCoreServices.swift:static var aiClassificationFallbackReader",
    "App/AppCoreServices.swift:static var aiClassificationSuggester",
    "App/AppCoreServices.swift:static var aiPrivacyRules",
    "App/AppCoreServices.swift:static var aiPrivacyRulesManager",
    "App/AppCoreServices.swift:static var aiSettingsLoader",
    "App/AppCoreServices.swift:static var aiSettingsUpdater",
    "App/AppCoreServices.swift:static var aiSummaryStore",
    "App/AppCoreServices.swift:static var aiTagSuggestionStore",
    "App/AppCoreServices.swift:static var batchCategoryChanger",
    "App/AppCoreServices.swift:static var batchDeleter",
    "App/AppCoreServices.swift:static var batchRenamer",
    "App/AppCoreServices.swift:static var bindingContractInspector",
    "App/AppCoreServices.swift:static var categoryPredictor",
    "App/AppCoreServices.swift:static var changeLogLister",
    "App/AppCoreServices.swift:static var classifierImpactPreviewer",
    "App/AppCoreServices.swift:static var classifierRuleEditor",
    "App/AppCoreServices.swift:static var classifierRuleSaver",
    "App/AppCoreServices.swift:static var commandIndexer",
    "App/AppCoreServices.swift:static var configurationLoader",
    "App/AppCoreServices.swift:static var configurationUpdater",
    "App/AppCoreServices.swift:static var coreVersionLoader",
    "App/AppCoreServices.swift:static var coreVersionReader",
    "App/AppCoreServices.swift:static var diagnosticsCollector",
    "App/AppCoreServices.swift:static var emptyRepositoryOpener",
    "App/AppCoreServices.swift:static var errorMapper",
    "App/AppCoreServices.swift:static var externalChangesSyncer",
    "App/AppCoreServices.swift:static var fileCategoryMover",
    "App/AppCoreServices.swift:static var fileDeleter",
    "App/AppCoreServices.swift:static var fileDetailer",
    "App/AppCoreServices.swift:static var fileLister",
    "App/AppCoreServices.swift:static var fileRenamer",
    "App/AppCoreServices.swift:static var iCloudConflictLister",
    "App/AppCoreServices.swift:static var iCloudConflictResolver",
    "App/AppCoreServices.swift:static var iCloudConflictReviewer",
    "App/AppCoreServices.swift:static var initializedRepositoryPathValidator",
    "App/AppCoreServices.swift:static var localModelStatusReader",
    "App/AppCoreServices.swift:static var noteStore",
    "App/AppCoreServices.swift:static var platformCapabilityLoader",
    "App/AppCoreServices.swift:static var redoActionStore",
    "App/AppCoreServices.swift:static var remoteProviderConfigurer",
    "App/AppCoreServices.swift:static var repositoryPathValidator",
    "App/AppCoreServices.swift:static var savedSearchStore",
    "App/AppCoreServices.swift:static var scanSessionReader",
    "App/AppCoreServices.swift:static var searchFiltering",
    "App/AppCoreServices.swift:static var searchQuerying",
    "App/AppCoreServices.swift:static var semanticFallbackReader",
    "App/AppCoreServices.swift:static var semanticSearching",
    "App/AppCoreServices.swift:static var syncConflictDetector",
    "App/AppCoreServices.swift:static var tagStore",
    "App/AppCoreServices.swift:static var treeLister",
    "App/AppCoreServices.swift:static var undoActionStore"
]

final class AppCoreServicesGovernanceTests: MacOSGovernanceTestCase {
    func testAppCoreServicesDefaultSurfaceStaysInventoried() throws {
        let appCoreServicesFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppCoreServices.swift"
        })
        let actual = try sourceRegexMatches(
            in: appCoreServicesFile,
            pattern: #"\bstatic var [A-Za-z][A-Za-z0-9_]*"#
        )
        .sorted()

        XCTAssertEqual(
            actual,
            expectedAppCoreServiceSurface,
            "The default Core service surface should stay explicit so new shared defaults are reviewed, " +
                "documented, and kept separate from high-risk direct CoreBridge defaults."
        )
    }

    func testAppCoreServicesConstructsCoreBridgeOnlyThroughPrivateFactory() throws {
        let appCoreServicesFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppCoreServices.swift"
        })
        let constructionMatches = try sourceRegexMatches(
            in: appCoreServicesFile,
            pattern: #"\bCoreBridge\s*\("#
        )
        let factoryMatches = try sourceRegexMatches(
            in: appCoreServicesFile,
            pattern: #"\bprivate static func coreBridge\(\) -> CoreBridge\b"#
        )

        XCTAssertEqual(
            constructionMatches,
            ["App/AppCoreServices.swift:CoreBridge("],
            "AppCoreServices defaults should call the private coreBridge() factory instead of scattering " +
                "direct CoreBridge construction through the service list."
        )
        XCTAssertEqual(
            factoryMatches,
            ["App/AppCoreServices.swift:private static func coreBridge() -> CoreBridge"],
            "The CoreBridge factory should stay private to AppCoreServices."
        )
    }
}
