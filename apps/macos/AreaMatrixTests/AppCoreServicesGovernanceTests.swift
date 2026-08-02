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
    "App/AppCoreServices.swift:static var importProgressImporter",
    "App/AppCoreServices.swift:static var localModelStatusReader",
    "App/AppCoreServices.swift:static var missingFileRecoverer",
    "App/AppCoreServices.swift:static var noteStore",
    "App/AppCoreServices.swift:static var observabilityController",
    "App/AppCoreServices.swift:static var overviewRegenerationCoordinator",
    "App/AppCoreServices.swift:static var overviewRegenerator",
    "App/AppCoreServices.swift:static var platformCapabilityLoader",
    "App/AppCoreServices.swift:static var redoActionStore",
    "App/AppCoreServices.swift:static var remoteProviderConfigurer",
    "App/AppCoreServices.swift:static var repositoryContentLocaleSnapshotter",
    "App/AppCoreServices.swift:static var repositoryPathValidator",
    "App/AppCoreServices.swift:static var repositoryInitializer",
    "App/AppCoreServices.swift:static var savedSearchStore",
    "App/AppCoreServices.swift:static var scanSessionReader",
    "App/AppCoreServices.swift:static var searchFiltering",
    "App/AppCoreServices.swift:static var searchQuerying",
    "App/AppCoreServices.swift:static var semanticFallbackReader",
    "App/AppCoreServices.swift:static var semanticSearching",
    "App/AppCoreServices.swift:static var syncConflictDetector",
    "App/AppCoreServices.swift:static var startupRecoverer",
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
            expectedAppCoreServiceSurface.sorted(),
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
        let runtimeMatches = try sourceRegexMatches(
            in: appCoreServicesFile,
            pattern: #"\bCoreBridgeRuntime\.shared\b"#
        )
        let factoryMatches = try sourceRegexMatches(
            in: appCoreServicesFile,
            pattern: #"\bprivate static func coreBridge\(\) -> CoreBridge\b"#
        )

        XCTAssertEqual(
            constructionMatches,
            [],
            "AppCoreServices defaults should use the process-scoped CoreBridge runtime instead of constructing " +
                "a bridge for every protocol lookup."
        )
        XCTAssertEqual(runtimeMatches, ["App/AppCoreServices.swift:CoreBridgeRuntime.shared"])
        XCTAssertEqual(
            factoryMatches,
            ["App/AppCoreServices.swift:private static func coreBridge() -> CoreBridge"],
            "The CoreBridge factory should stay private to AppCoreServices."
        )
    }

    func testMainRepositoryContentDefaultsAreAssembledInAppLayer() throws {
        let appServicesFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/MainRepositoryContentAssembly.swift"
        })
        let contentViewFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/Main/MainRepositoryContentView.swift"
        })
        let routeContentFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindowRouteContent.swift"
        })
        let appServicesSource = try String(contentsOf: appServicesFile, encoding: .utf8)
        let contentViewSource = try String(contentsOf: contentViewFile, encoding: .utf8)
        let routeContentSource = try String(contentsOf: routeContentFile, encoding: .utf8)

        XCTAssertTrue(appServicesSource.contains("struct MainRepositoryContentAssembly"))
        XCTAssertTrue(appServicesSource.contains("static func live("))
        XCTAssertTrue(appServicesSource.contains("dependencies: AppDependencyContainer"))
        XCTAssertFalse(
            appServicesSource.contains("dependencies ?? .live"),
            "Production repository assembly must not silently fall back to the global live container."
        )
        XCTAssertTrue(routeContentSource.contains(
            "assembly: .live(opening: displayOpening, dependencies: dependencies)"
        ))
        XCTAssertTrue(contentViewSource.contains("assembly: MainRepositoryContentAssembly"))
        for dependency in [
            "semanticFallbackReader: semanticFallbackReader",
            "fileRenamer: fileRenamer",
            "fileDeleter: fileDeleter",
            "categoryPredictor: fileListCategoryPredictor",
            "aiSettingsLoader: aiSettingsLoader",
            "aiTagSuggestionStore: aiTagSuggestionStore"
        ] {
            XCTAssertTrue(
                appServicesSource.contains(dependency),
                "MainRepositoryContentAssembly must resolve the nested MainFileListModel default: \(dependency)."
            )
        }
        XCTAssertFalse(contentViewSource.contains("AppCoreServices."))
        XCTAssertFalse(contentViewSource.contains("AppPlatformServices."))
    }

    func testProductionCompositionPassesTheDependencyContainerFromTheAppRoot() throws {
        let appFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AreaMatrixApp.swift"
        })
        let windowFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindow.swift"
        })
        let routeFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindowRouteContent.swift"
        })
        let appSource = try String(contentsOf: appFile, encoding: .utf8)
        let windowSource = try String(contentsOf: windowFile, encoding: .utf8)
        let routeSource = try String(contentsOf: routeFile, encoding: .utf8)

        XCTAssertTrue(appSource.contains("private let dependencies = AppDependencyContainer.live"))
        XCTAssertTrue(appSource.contains("MainWindow(dependencies: dependencies"))
        XCTAssertTrue(windowSource.contains("OnboardingModel(dependencies: resolvedDependencies)"))
        XCTAssertTrue(windowSource.contains("dependencies: dependencies"))
        XCTAssertTrue(routeSource.contains("let dependencies: AppDependencyContainer"))
    }

    func testSettingsRoutePassesFeatureDependenciesExplicitly() throws {
        let routeFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindowRouteContent.swift"
        })
        let settingsViewFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Settings/GeneralSettingsView.swift"
        })
        let routeSource = try String(contentsOf: routeFile, encoding: .utf8)
        let settingsViewSource = try String(contentsOf: settingsViewFile, encoding: .utf8)

        XCTAssertTrue(routeSource.contains("featureDependencies: dependencies.feature.settings"))
        XCTAssertTrue(routeSource.contains("aiDependencies: dependencies.feature.ai"))
        XCTAssertTrue(routeSource.contains("sharedDependencies: dependencies.feature.shared"))
        for child in [
            "LanguageSettingsPane(",
            "RepositorySettingsPane(",
            "ClassifierSettingsPane(",
            "AISettingsPane(",
            "IntegrationsSettingsPane(",
            "AdvancedSettingsPane(",
            "AboutSettingsPane("
        ] {
            XCTAssertTrue(
                settingsViewSource.contains(child),
                "Settings root must keep the (child) composition point visible."
            )
        }
        XCTAssertTrue(settingsViewSource.contains("featureDependencies: featureDependencies"))
        XCTAssertTrue(settingsViewSource.contains("featureDependencies: aiDependencies"))
        XCTAssertTrue(settingsViewSource.contains("sharedDependencies: sharedDependencies"))
    }

    func testImportEntryRoutePassesFileReadAndWriteDependenciesExplicitly() throws {
        let windowFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindow.swift"
        })
        let entryFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Import/ImportEntrySheetView.swift"
        })
        let windowSource = try String(contentsOf: windowFile, encoding: .utf8)
        let entrySource = try String(contentsOf: entryFile, encoding: .utf8)

        for dependency in [
            "categoryPredictor: dependencies.feature.`import`.categoryPredictor",
            "batchFileLoader: dependencies.feature.`import`.batchFileLoader",
            "fileImporter: dependencies.feature.`import`.fileImporter",
            "batchFileImporter: dependencies.feature.`import`.batchFileImporter",
            "batchConflictBatcher: dependencies.feature.`import`.conflictBatcher",
            "undoActionStore: dependencies.feature.`import`.undoActionStore",
            "errorMapper: dependencies.feature.shared.errorMapper",
            "batchSessionStore: model.importBatchSessionStore"
        ] {
            XCTAssertTrue(
                windowSource.contains(dependency),
                "Import entry must receive the explicit dependency: \(dependency)."
            )
        }

        XCTAssertFalse(entrySource.contains("CoreBridgeBatchFileLoader()"))
        XCTAssertFalse(entrySource.contains("AppCoreServices."))
    }

    func testMainRepositoryActionRoutesReceiveFeatureDependenciesFromAssembly() throws {
        let assemblyFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/MainRepositoryContentAssembly.swift"
        })
        let contentViewFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/Main/MainRepositoryContentView.swift"
        })
        let actionRoutingFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/FileActions/MainFileActionRoutingSupport.swift"
        })
        let syncRoutingFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/SyncConflicts/SyncConflictReviewSupportViews.swift"
        })
        let assemblySource = try String(contentsOf: assemblyFile, encoding: .utf8)
        let contentViewSource = try String(contentsOf: contentViewFile, encoding: .utf8)
        let actionRoutingSource = try String(contentsOf: actionRoutingFile, encoding: .utf8)
        let syncRoutingSource = try String(contentsOf: syncRoutingFile, encoding: .utf8)

        XCTAssertTrue(assemblySource.contains("let fileActionsDependencies: FileActionsFeatureDependencies"))
        XCTAssertTrue(assemblySource.contains("let syncConflictsDependencies: SyncConflictsFeatureDependencies"))
        XCTAssertTrue(contentViewSource.contains("fileActionsDependencies = assembly.fileActionsDependencies"))
        XCTAssertTrue(contentViewSource.contains("syncConflictsDependencies = assembly.syncConflictsDependencies"))
        XCTAssertTrue(actionRoutingSource.contains("fileActionsDependencies.repositoryPathValidator"))
        XCTAssertTrue(actionRoutingSource.contains("fileActionsDependencies.classifierRuleSaver"))
        XCTAssertTrue(syncRoutingSource.contains("syncConflictsDependencies.syncConflictDetector"))
    }

    func testFeatureAndViewLayersDoNotReadAppCoreServicesDirectly() throws {
        let violations = try productionSwiftFiles()
            .filter {
                let path = relativeProductionPath(for: $0)
                return path.hasPrefix("Features/") || path.hasPrefix("Views/")
            }
            .flatMap { try sourceTermViolations(in: $0, terms: ["AppCoreServices."]) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Feature and View layers must receive dependencies from the App composition root rather than " +
                "reading AppCoreServices directly."
        )
    }

    func testFeatureLayersDoNotReadTheAppDependencyContainerDirectly() throws {
        let violations = try productionSwiftFiles()
            .filter { relativeProductionPath(for: $0).hasPrefix("Features/") }
            .flatMap { try sourceTermViolations(in: $0, terms: ["AppDependencyContainer"]) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Feature defaults must resolve through their feature dependency namespace; the App container belongs " +
                "to the composition root and must not leak into feature code."
        )
    }

    func testFeatureDefaultsStayOwnedByFeatureNamespaces() throws {
        let allowedNamespacesByFeature: [String: Set<String>] = [
            "AI": ["AIFeatureDependencies", "SharedFeatureDependencies"],
            "FileActions": ["FileActionsFeatureDependencies", "SharedFeatureDependencies"],
            "Import": ["ImportFeatureDependencies", "SharedFeatureDependencies"],
            "MainList": ["MainListFeatureDependencies", "SharedFeatureDependencies"],
            "Onboarding": ["OnboardingFeatureDependencies", "SharedFeatureDependencies"],
            "Search": ["SearchFeatureDependencies", "SharedFeatureDependencies"],
            "Settings": [
                "AIFeatureDependencies",
                "SettingsFeatureDependencies",
                "SharedFeatureDependencies",
                "SyncConflictsFeatureDependencies"
            ],
            "SyncConflicts": ["SharedFeatureDependencies", "SyncConflictsFeatureDependencies"]
        ]
        let dependencyPattern = #"\b[A-Za-z]+FeatureDependencies\.[A-Za-z0-9_]+"#
        var violations: [String] = []

        for (feature, allowedNamespaces) in allowedNamespacesByFeature {
            let featureFiles = try productionSwiftFiles().filter {
                relativeProductionPath(for: $0).hasPrefix("Features/\(feature)/")
            }
            let matches = try featureFiles.flatMap {
                try sourceRegexMatches(in: $0, pattern: dependencyPattern)
            }
        violations.append(contentsOf: matches.filter { match in
            !allowedNamespaces.contains { namespace in
                match.contains(":\(namespace).")
            }
        })
        }

        XCTAssertEqual(
            violations.sorted(),
            [],
            "Feature defaults must remain owned by their feature namespace or the explicitly shared namespace."
        )
    }

    func testFeatureManifestOwnershipIsDistributedAndComposedByApp() throws {
        let providerByFeature = [
            "AI": "AIFeatureManifestProvider",
            "CommandPalette": "CommandPaletteFeatureManifestProvider",
            "Detail": "DetailFeatureManifestProvider",
            "Diagnostics": "DiagnosticsFeatureManifestProvider",
            "FileActions": "FileActionsFeatureManifestProvider",
            "Import": "ImportFeatureManifestProvider",
            "MainList": "MainListFeatureManifestProvider",
            "Onboarding": "OnboardingFeatureManifestProvider",
            "RepositoryLifecycle": "RepositoryLifecycleFeatureManifestProvider",
            "Search": "SearchFeatureManifestProvider",
            "Settings": "SettingsFeatureManifestProvider",
            "SyncConflicts": "SyncConflictsFeatureManifestProvider"
        ]
        let registryFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/FeatureManifest.swift"
        })
        let registrySource = try String(contentsOf: registryFile, encoding: .utf8)

        XCTAssertFalse(
            registrySource.contains("FeatureManifest("),
            "The App registry should compose feature-owned manifests instead of owning their metadata."
        )

        for (feature, provider) in providerByFeature {
            let providerPath = "Features/\(feature)/\(provider).swift"
            let providerFile = try XCTUnwrap(productionSwiftFiles().first {
                relativeProductionPath(for: $0) == providerPath
            })
            let providerSource = try String(contentsOf: providerFile, encoding: .utf8)
            XCTAssertTrue(providerSource.contains("enum \(provider): FeatureManifestProvider"))
            XCTAssertTrue(registrySource.contains("\(provider).manifest"))
        }
    }

    func testMainRepositoryContentStateObjectsKeepViewOwnedIdentity() throws {
        let contentViewFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/Main/MainRepositoryContentView.swift"
        })
        let source = try String(contentsOf: contentViewFile, encoding: .utf8)
        let expectedStateObjectInitializers = [
            "_dropPreviewModel = StateObject(wrappedValue: assembly.makeDropPreviewModel())",
            "_detailNoteModel = StateObject(wrappedValue: assembly.makeDetailNoteModel())",
            "_summaryExitController = StateObject(wrappedValue: assembly.makeSummaryExitController())",
            "_fileListModel = StateObject(wrappedValue: assembly.makeFileListModel())",
            "_syncConflictEntryModel = StateObject(wrappedValue: assembly.makeSyncConflictEntryModel())"
        ]

        for initializer in expectedStateObjectInitializers {
            XCTAssertTrue(
                source.contains(initializer),
                "MainRepositoryContentView must continue to own StateObject identity: \(initializer)."
            )
        }
    }
}
