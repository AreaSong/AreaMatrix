import XCTest

final class AppCoreServicesGovernanceTests: MacOSGovernanceTestCase {
    func testAppCoreServicesHasNoStaticServiceSurface() throws {
        let appCoreServicesFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppCoreServices.swift"
        })
        let actual = try sourceRegexMatches(
            in: appCoreServicesFile,
            pattern: #"\bstatic\s+(?:let|var)\s+[A-Za-z][A-Za-z0-9_]*"#
        )
        .sorted()

        XCTAssertEqual(
            actual,
            [],
            "Core capabilities must be owned by an AppCoreServices instance, never exposed as static services."
        )
    }

    func testProductionCodeHasNoStaticCoreServiceLocator() throws {
        let violations = try productionSwiftFiles()
            .flatMap { file in
                try sourceRegexViolations(
                    in: file,
                    pattern: #"\bstatic\s+(?:let|var)\s+[A-Za-z][A-Za-z0-9_]*\s*:\s*any\s+Core[A-Za-z0-9_]+"#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "New process-global Core services are forbidden; compose protocol values through an instance container."
        )
    }

    func testRepositoryWriteCoordinatorIsOwnedByTheCoreServiceGraph() throws {
        let coordinatorFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "PlatformServices/RepositoryWriteCoordinator.swift"
        })
        let servicesFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppCoreServices.swift"
        })
        let coordinatorSource = try String(contentsOf: coordinatorFile, encoding: .utf8)
        let servicesSource = try String(contentsOf: servicesFile, encoding: .utf8)

        XCTAssertFalse(coordinatorSource.contains("static let shared"))
        XCTAssertTrue(
            servicesSource.contains(
                "repositoryWriteCoordinator: RepositoryWriteCoordinator = RepositoryWriteCoordinator()"
            )
        )
    }

    func testAppCoreServicesUsesItsInjectedBridgeInstance() throws {
        let appCoreServicesFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppCoreServices.swift"
        })
        let constructionMatches = try sourceRegexMatches(
            in: appCoreServicesFile,
            pattern: #"\bCoreBridge\s*\("#
        )
        let factoryMatches = try sourceRegexMatches(
            in: appCoreServicesFile,
            pattern: #"\bprivate func coreBridge\(\) -> CoreBridge\b"#
        )

        XCTAssertEqual(
            constructionMatches,
            [],
            "AppCoreServices defaults should use the process-scoped CoreBridge runtime instead of constructing " +
                "a bridge for every protocol lookup."
        )
        XCTAssertEqual(
            factoryMatches,
            ["App/AppCoreServices.swift:private func coreBridge() -> CoreBridge"],
            "The injected CoreBridge accessor should stay private to AppCoreServices."
        )
    }

    func testAppLoggerBindsObservabilityHubAtItsCompositionPoint() throws {
        let appFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AreaMatrixApp.swift"
        })
        let source = try String(contentsOf: appFile, encoding: .utf8)

        XCTAssertTrue(
            source.contains("static let shared = AppLogger(hub: .shared)"),
            "The process logger may be shared, but its hub binding must remain explicit."
        )
        XCTAssertTrue(
            source.contains("init(hub: ObservabilityHub)"),
            "AppLogger initializers must require an explicit observability hub."
        )
        XCTAssertFalse(
            source.contains("init(hub: ObservabilityHub = .shared)"),
            "AppLogger must not hide the global observability hub behind a default argument."
        )
    }

    func testCoreBridgeImplementsTheSharedRuntimeContract() throws {
        let bridgeFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Bridge/CoreBridge.swift"
        })
        let source = try String(contentsOf: bridgeFile, encoding: .utf8)
        let runtimeAdapterFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Bridge/CoreBridgeRuntime.swift"
        })
        let runtimeAdapterSource = try String(contentsOf: runtimeAdapterFile, encoding: .utf8)
        let runtimeFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/CoreBridgeRuntimeAssembly.swift"
        })
        let runtimeSource = try String(contentsOf: runtimeFile, encoding: .utf8)

        XCTAssertTrue(
            runtimeAdapterSource.contains("extension CoreBridge: CoreBridgeRuntimeProviding"),
            "The App-owned CoreBridge runtime adapter must implement the package runtime contract."
        )
        XCTAssertTrue(
            source.contains("private let runtimeCoordinator: CoreBridgeRuntimeCoordinator") &&
                source.contains("await runtimeCoordinator.declaredBoundaries()"),
            "CoreBridge must delegate runtime metadata to the physical package coordinator."
        )
        XCTAssertTrue(
            source.contains("typealias BridgeState = CoreBridgeRuntimeState"),
            "Legacy state references must remain aliases to the package contract, not a second enum."
        )
    }

    func testCoreBridgeRuntimeComposesRemoteProbeAtTheAppBoundary() throws {
        let runtimeFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/CoreBridgeRuntimeAssembly.swift"
        })
        let source = try String(contentsOf: runtimeFile, encoding: .utf8)

        XCTAssertTrue(
            source.contains("static let shared = CoreBridge("),
            "The process-scoped CoreBridge must be composed at the App boundary."
        )
        XCTAssertTrue(
            source.contains("remoteProviderProbePerformer: RemoteProviderProbeService.shared"),
            "The process-scoped CoreBridge must compose the high-risk remote probe performer explicitly."
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
        let makeDeclaration = try XCTUnwrap(
            appServicesSource.range(of: "static func make(")
        )
        let makeBody = String(appServicesSource[makeDeclaration.lowerBound...])

        XCTAssertTrue(appServicesSource.contains("struct MainRepositoryContentAssembly"))
        XCTAssertTrue(appServicesSource.contains("static func makeForProduction("))
        XCTAssertFalse(appServicesSource.contains("static func live("))
        XCTAssertTrue(appServicesSource.contains("dependencies: AppDependencyContainer"))
        XCTAssertFalse(
            makeBody.contains("= AppCoreServices.") || makeBody.contains("= AppPlatformServices."),
            "The test/fixture assembly factory must not expose hidden production service defaults."
        )
        XCTAssertFalse(
            appServicesSource.contains("dependencies ?? .live"),
            "Production repository assembly must not silently fall back to the global live container."
        )
        XCTAssertTrue(routeContentSource.contains(
            "assembly: .makeForProduction(session: session, opening: displayOpening, dependencies: dependencies)"
        ))
        XCTAssertTrue(contentViewSource.contains("assembly: MainRepositoryContentAssembly"))
        for dependency in [
            "semanticFallbackReader: core.semanticFallbackReader",
            "fileRenamer: core.fileRenamer",
            "fileDeleter: core.fileDeleter",
            "categoryPredictor: core.categoryPredictor",
            "aiSettingsLoader: core.aiSettingsLoader",
            "aiTagSuggestionStore: core.aiTagSuggestionStore"
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

        XCTAssertTrue(appSource.contains("private let coreServices: AppCoreServices"))
        XCTAssertTrue(appSource.contains("let coreServices = AppCoreServices()"))
        XCTAssertTrue(appSource.contains("dependencies = AppDependencyContainer.live(coreServices: coreServices)"))
        XCTAssertTrue(
            appSource.contains("MainWindow(") &&
                appSource.contains("dependencies: dependencies")
        )
        XCTAssertTrue(windowSource.contains("OnboardingModel(dependencies: resolvedDependencies)"))
        XCTAssertTrue(windowSource.contains("dependencies: dependencies"))
        XCTAssertTrue(routeSource.contains("let dependencies: AppDependencyContainer"))

        let containerFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppDependencyContainer.swift"
        })
        let containerSource = try String(contentsOf: containerFile, encoding: .utf8)
        XCTAssertTrue(containerSource.contains("static func live(coreServices: AppCoreServices)"))
        XCTAssertFalse(containerSource.contains("coreServices: AppCoreServices ="))
        XCTAssertTrue(containerSource.contains("feature: .live(coreServices: coreServices)"))
        XCTAssertFalse(containerSource.contains("static let live"))
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
        XCTAssertTrue(routeSource.contains("aiDependencies: dependencies.feature.aiFeature"))
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
        XCTAssertTrue(settingsViewSource.contains("dependencies: diagnosticsDependencies"))
    }

    func testProductionSettingsDiagnosticsRouteUsesExplicitFeatureDependencies() throws {
        let settingsFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Settings/GeneralSettingsView.swift"
        })
        let source = try String(contentsOf: settingsFile, encoding: .utf8)

        XCTAssertTrue(
            source.contains("DiagnosticsSettingsPane(") &&
                source.contains("dependencies: diagnosticsDependencies"),
            "Production diagnostics settings must receive package IO collaborators from App composition."
        )
        XCTAssertFalse(
            source.contains("DiagnosticsSettingsPane(repositoryURL:"),
            "Production settings must not construct diagnostics platform defaults implicitly."
        )
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
            "categoryPredictor: dependencies.feature.import.categoryPredictor",
            "batchFileLoader: dependencies.feature.import.batchFileLoader",
            "fileImporter: dependencies.feature.import.fileImporter",
            "batchFileImporter: dependencies.feature.import.batchFileImporter",
            "batchConflictBatcher: dependencies.feature.import.conflictBatcher",
            "undoActionStore: dependencies.feature.import.undoActionStore",
            "folderScanner: dependencies.feature.import.folderScanner",
            "sourcePreflightInspector: dependencies.feature.import.sourcePreflightInspector",
            "placeholderDownloader: dependencies.feature.import.placeholderDownloader",
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
}

extension AppCoreServicesGovernanceTests {
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
        XCTAssertTrue(syncRoutingSource.contains("dependencies.syncConflictDetector"))
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
            "let fileListModel = assembly.makeFileListModel()",
            "_fileListModel = StateObject(wrappedValue: fileListModel)",
            "_commandPaletteModel = StateObject(wrappedValue: assembly.makeCommandPaletteModel())",
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
