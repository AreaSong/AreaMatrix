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
    "App/AppPlatformServices.swift:static var windowCloser"
]

private let expectedFeaturePlatformServiceFacades = [
    "PlatformServices/AboutSettingsPlatformServices.swift:enum AboutSettingsPlatformServices",
    "PlatformServices/AdvancedSettingsPlatformServices.swift:enum AdvancedSettingsPlatformServices",
    "PlatformServices/GeneralSettingsPlatformServices.swift:enum GeneralSettingsPlatformServices",
    "PlatformServices/ImportPlatformServices.swift:enum ImportPlatformServices",
    "PlatformServices/IntegrationsSettingsPlatformServices.swift:enum IntegrationsSettingsPlatformServices",
    "PlatformServices/LocalModelPlatformServices.swift:enum LocalModelStatusPlatformServices"
]

private let expectedFeaturePlatformServiceSurface = [
    "PlatformServices/ImportPlatformServices.swift:static var fileResourceAccess",
    "PlatformServices/ImportPlatformServices.swift:static var folderScanner",
    "PlatformServices/ImportPlatformServices.swift:static var sourcePreflightInspector",
    "PlatformServices/Observability/DiagnosticPackageModels.swift:static var wireNames",
    "PlatformServices/Observability/DiagnosticPackageWriter.swift:static var defaultStagingRootURL",
    "PlatformServices/Observability/ObservabilityCatalog.swift:static var all",
    "PlatformServices/Observability/ObservabilityEventWireCoding.swift:static var wireNames"
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
            "App/AppPlatformServices.swift:NSWorkspaceLocalFileURLOpener():1"
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
            "App/AppPlatformServices.swift:NSWorkspaceExternalURLStringOpener():1"
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
            "App/AppPlatformServices.swift:VoiceOverAccessibilityAnnouncer():1"
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

    func testPlatformAdaptersRequireExplicitSharedDependencies() throws {
        let adapterPaths = Set([
            "App/AppPlatformServiceAdapters.swift",
            "App/RepositoryIgnoreRulesManager.swift",
            "PlatformServices/AboutSettingsPlatformServices.swift",
            "PlatformServices/AdvancedSettingsPlatformServices.swift",
            "PlatformServices/IntegrationsSettingsPlatformServices.swift",
            "PlatformServices/LocalModelPlatformServices.swift"
        ])
        let violations = try productionSwiftFiles()
            .filter { adapterPaths.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\b(?:AppPlatformServices|OnboardingPlatformServices)\."#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Low-risk platform adapters must receive shared platform capabilities explicitly; " +
                "initializer defaults must not reach back into AppPlatformServices."
        )
    }

    func testPlatformServicesDoNotReachBackIntoAppComposition() throws {
        let violations = try productionSwiftFiles()
            .filter { relativeProductionPath(for: $0).hasPrefix("PlatformServices/") }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\b(?:AppPlatformServices|OnboardingPlatformServices)\."#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "PlatformServices must expose implementations/factories and receive shared capabilities "
                + "from App composition; it must not reach back into AppPlatformServices or another global facade."
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
