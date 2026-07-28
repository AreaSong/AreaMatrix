import XCTest

private let expectedAppPlatformServiceSurface = [
    "App/AppPlatformServices.swift:static var accessibilityAnnouncer",
    "App/AppPlatformServices.swift:static var appVersionReader",
    "App/AppPlatformServices.swift:static var directoryPicker",
    "App/AppPlatformServices.swift:static var existingRepositoryMetadataReader",
    "App/AppPlatformServices.swift:static var externalURLStringOpener",
    "App/AppPlatformServices.swift:static var fileOpener",
    "App/AppPlatformServices.swift:static var fileRevealer",
    "App/AppPlatformServices.swift:static var finderOpener",
    "App/AppPlatformServices.swift:static var helpOpener",
    "App/AppPlatformServices.swift:static var importBatchSessionStore",
    "App/AppPlatformServices.swift:static var importPicker",
    "App/AppPlatformServices.swift:static var importResultExporter",
    "App/AppPlatformServices.swift:static var interactionFeedback",
    "App/AppPlatformServices.swift:static var localFileURLOpener",
    "App/AppPlatformServices.swift:static var missingFilePicker",
    "App/AppPlatformServices.swift:static var pasteboardStringWriter",
    "App/AppPlatformServices.swift:static var pathCopier",
    "App/AppPlatformServices.swift:static var rootOverviewInspector",
    "App/AppPlatformServices.swift:static var settingsReader",
    "App/AppPlatformServices.swift:static var settingsWriter",
    "App/AppPlatformServices.swift:static var systemCapabilityChecker",
    "App/AppPlatformServices.swift:static var windowCloser",
]

private let expectedFeaturePlatformServiceFacades = [
    "PlatformServices/AboutSettingsPlatformServices.swift:enum AboutSettingsPlatformServices",
    "PlatformServices/AboutSettingsPlatformServices.swift:enum PlatformDifferencesPlatformServices",
    "PlatformServices/AdvancedSettingsPlatformServices.swift:enum AdvancedSettingsPlatformServices",
    "PlatformServices/ClassifierRulesPlatformServices.swift:enum ClassifierSettingsPlatformServices",
    "PlatformServices/GeneralSettingsPlatformServices.swift:enum GeneralSettingsPlatformServices",
    "PlatformServices/ImportPlatformServices.swift:enum ImportPlatformServices",
    "PlatformServices/IntegrationsSettingsPlatformServices.swift:enum IntegrationsSettingsPlatformServices",
    "PlatformServices/LocalModelPlatformServices.swift:enum LocalModelStatusPlatformServices",
    "PlatformServices/MainExternalSyncEvents.swift:enum ICloudConflictListPlatformServices",
    "PlatformServices/OnboardingPlatformServices.swift:enum OnboardingPlatformServices",
    "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:enum RepositorySettingsPlatformServices",
]

private let expectedFeaturePlatformServiceSurface = [
    "PlatformServices/AboutSettingsPlatformServices.swift:static var accessibilityAnnouncer",
    "PlatformServices/AboutSettingsPlatformServices.swift:static var appVersionReader",
    "PlatformServices/AboutSettingsPlatformServices.swift:static var appVersionReader",
    "PlatformServices/AboutSettingsPlatformServices.swift:static var externalLinkOpener",
    "PlatformServices/AboutSettingsPlatformServices.swift:static var metadataReader",
    "PlatformServices/AboutSettingsPlatformServices.swift:static var stringCopier",
    "PlatformServices/AdvancedSettingsPlatformServices.swift:static var appVersionReader",
    "PlatformServices/AdvancedSettingsPlatformServices.swift:static var diagnosticSummaryCopier",
    "PlatformServices/AdvancedSettingsPlatformServices.swift:static var diagnosticsPackageHandler",
    "PlatformServices/AdvancedSettingsPlatformServices.swift:static var metadataReader",
    "PlatformServices/AdvancedSettingsPlatformServices.swift:static var rootOverviewInspector",
    "PlatformServices/ClassifierRulesPlatformServices.swift:static var accessibilityAnnouncer",
    "PlatformServices/ClassifierRulesPlatformServices.swift:static var fileOpener",
    "PlatformServices/ClassifierRulesPlatformServices.swift:static var fileRevealer",
    "PlatformServices/ClassifierRulesPlatformServices.swift:static var finderOpener",
    "PlatformServices/GeneralSettingsPlatformServices.swift:static var ignoreRulesManager",
    "PlatformServices/GeneralSettingsPlatformServices.swift:static var rootOverviewInspector",
    "PlatformServices/GeneralSettingsPlatformServices.swift:static var rootOverviewRevealer",
    "PlatformServices/ImportPlatformServices.swift:static var folderScanner",
    "PlatformServices/ImportPlatformServices.swift:static var sourcePreflightInspector",
    "PlatformServices/IntegrationsSettingsPlatformServices.swift:static var finderOpener",
    "PlatformServices/IntegrationsSettingsPlatformServices.swift:static var helpOpener",
    "PlatformServices/IntegrationsSettingsPlatformServices.swift:static var statusDetector",
    "PlatformServices/LocalModelPlatformServices.swift:static var diagnosticsCopier",
    "PlatformServices/LocalModelPlatformServices.swift:static var folderOpener",
    "PlatformServices/LocalModelPlatformServices.swift:static var installHelpOpener",
    "PlatformServices/LocalModelPlatformServices.swift:static var storageLocationProvider",
    "PlatformServices/MainExternalSyncEvents.swift:static var fileRevealer",
    "PlatformServices/MainExternalSyncEvents.swift:static var repositoryFinderOpener",
    "PlatformServices/OnboardingPlatformServices.swift:static var accessibilityAnnouncer",
    "PlatformServices/OnboardingPlatformServices.swift:static var metadataReader",
    "PlatformServices/OnboardingPlatformServices.swift:static var systemCapabilityChecker",
    "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:static var accessibilityAnnouncer",
    "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:static var appVersionReader",
    "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:static var finderOpener",
    "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:static var generatedOverviewRevealer",
    "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:static var metadataPresenceChecker",
    "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:static var metadataReader",
    "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:static var pathCopier",
]

final class AppPlatformServicesGovernanceTests: MacOSGovernanceTestCase {
    func testRepositoryWriteCoordinatorStaysInPlatformServices() throws {
        let implementationFiles = try productionSwiftFiles().filter {
            relativeProductionPath(for: $0) == "PlatformServices/RepositoryWriteCoordinator.swift"
        }
        let actual = try countedRegexMatches(
            in: implementationFiles,
            pattern: #"\bactor RepositoryWriteCoordinator\b"#
        )

        XCTAssertEqual(
            actual,
            ["PlatformServices/RepositoryWriteCoordinator.swift:actor RepositoryWriteCoordinator:1"],
            "Repository write serialization must stay in PlatformServices instead of App assembly."
        )
    }

    func testAppPlatformServicesDefaultSurfaceStaysInventoried() throws {
        let appPlatformServicesFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppPlatformServices.swift"
        })
        let actual = try sourceRegexMatches(
            in: appPlatformServicesFile,
            pattern: #"\bstatic var [A-Za-z][A-Za-z0-9_]*"#
        )
        .sorted()

        XCTAssertEqual(
            actual,
            expectedAppPlatformServiceSurface,
            "App-wide platform default services should stay explicit so new AppKit, FileManager, " +
                "pasteboard, panel, and metadata defaults are reviewed before becoming shared app services."
        )
    }

    func testDefaultLocalFileURLOpenerConstructionStaysCentralized() throws {
        let expected = [
            "App/AppPlatformServices.swift:NSWorkspaceLocalFileURLOpener():1",
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles(),
            pattern: #"\bNSWorkspaceLocalFileURLOpener\s*\(\s*\)"#
        )

        XCTAssertEqual(
            actual,
            expected,
            "Default local file URL opening should be constructed once through " +
                "AppPlatformServices.localFileURLOpener; feature and adapter defaults should reuse that shared root."
        )
    }

    func testDefaultExternalURLStringOpenerConstructionStaysCentralized() throws {
        let expected = [
            "App/AppPlatformServices.swift:NSWorkspaceExternalURLStringOpener():1",
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles(),
            pattern: #"\bNSWorkspaceExternalURLStringOpener\s*\(\s*\)"#
        )

        XCTAssertEqual(
            actual,
            expected,
            "Default external URL string opening should be constructed once through " +
                "AppPlatformServices.externalURLStringOpener; feature adapter defaults should reuse that shared root."
        )
    }

    func testDefaultAccessibilityAnnouncerConstructionStaysCentralized() throws {
        let expected = [
            "App/AppPlatformServices.swift:VoiceOverAccessibilityAnnouncer():1",
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles(),
            pattern: #"\bVoiceOverAccessibilityAnnouncer\s*\(\s*\)"#
        )

        XCTAssertEqual(
            actual,
            expected,
            "Default accessibility announcements should be constructed once through " +
                "AppPlatformServices.accessibilityAnnouncer; feature platform facades should reuse that shared root."
        )
    }

    func testFeaturePlatformServiceFacadesStayInventoried() throws {
        let actual = try platformServiceSwiftFiles()
            .flatMap {
                try sourceRegexMatches(
                    in: $0,
                    pattern: #"\benum [A-Za-z][A-Za-z0-9_]*PlatformServices\b"#
                )
            }
            .sorted()

        XCTAssertEqual(
            actual,
            expectedFeaturePlatformServiceFacades,
            "Feature-local platform service facades should stay explicit so new platform owners are reviewed."
        )
    }

    func testFeaturePlatformServiceSurfaceStaysInventoried() throws {
        let actual = try platformServiceSwiftFiles()
            .flatMap {
                try sourceRegexMatches(
                    in: $0,
                    pattern: #"\bstatic var [A-Za-z][A-Za-z0-9_]*"#
                )
            }
            .sorted()

        XCTAssertEqual(
            actual,
            expectedFeaturePlatformServiceSurface,
            "Feature-local platform default services should stay explicit; platform IO must be routed through " +
                "the owning facade instead of drifting back into feature models or SwiftUI views."
        )
    }

    private func platformServiceSwiftFiles() throws -> [URL] {
        try productionSwiftFiles().filter {
            relativeProductionPath(for: $0).hasPrefix("PlatformServices/")
        }
    }
}
