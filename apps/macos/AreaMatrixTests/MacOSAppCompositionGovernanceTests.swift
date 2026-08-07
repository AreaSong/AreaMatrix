import XCTest

final class MacOSAppCompositionGovernanceTests: MacOSGovernanceTestCase {
    func testInFlightFileChangeTrackingIsComposedAtTheAppBoundary() throws {
        let watcherFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "PlatformServices/MainExternalCreatedFileWatcher.swift"
        })
        let noteFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Detail/MainDetailNoteState.swift"
        })
        let windowFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindow.swift"
        })
        let assemblyFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/MainRepositoryContentAssembly.swift"
        })

        let hiddenDefaultsPatterns = [
            #"cursorStore:\s*any\s+CoreExternalChangesSyncing\s*=\s*AppCoreServices\.externalChangesSyncer"#,
            #"inFlightTracker:\s*any\s+InFlightFileChangeTracking\s*=\s*InFlightFileChangeTracker\.shared"#
        ]
        let hiddenDefaults = try [watcherFile, noteFile].flatMap { file in
            try hiddenDefaultsPatterns.flatMap { pattern in
                try sourceRegexMatches(in: file, pattern: pattern)
            }
        }
        XCTAssertEqual(
            hiddenDefaults,
            [],
            "Watcher and detail-note models must not hide the process-wide in-flight tracker "
                + "behind initializer defaults."
        )

        let windowSource = try String(contentsOf: windowFile, encoding: .utf8)
        XCTAssertTrue(
            windowSource.contains("inFlightTracker: resolvedDependencies.platform.inFlightFileChangeTracker"),
            "MainWindow must pass the tracker from AppDependencyContainer into the watcher."
        )

        let assemblySource = try String(contentsOf: assemblyFile, encoding: .utf8)
        XCTAssertTrue(
            assemblySource.contains("inFlightFileChangeTracker: dependencies.platform.inFlightFileChangeTracker") &&
                assemblySource.contains("inFlightTracker: supporting.inFlightFileChangeTracker"),
            "MainRepositoryContentAssembly must pass the tracker into DetailNoteModel explicitly."
        )
    }

    func testDiagnosticsRuntimeDependenciesAreComposedAtTheAppBoundary() throws {
        let modelFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Diagnostics/DiagnosticsSettingsModel.swift"
        })
        let paneFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Diagnostics/DiagnosticsSettingsPane.swift"
        })
        let dependencyFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/FeatureDependencyDefaults.swift"
        })
        let appContainerFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppFeatureDependencyContainer.swift"
        })

        let modelSource = try String(contentsOf: modelFile, encoding: .utf8)
        XCTAssertFalse(
            modelSource.contains("runtime: ObservabilityRuntimeAssembly? = nil") ||
                modelSource.contains("runtime ?? .shared") ||
                modelSource.contains("AdvancedSettingsPlatformServices.diagnosticsPackagePreviewer") ||
                modelSource.contains("AdvancedSettingsPlatformServices.diagnosticsPackageHandler"),
            "DiagnosticsSettingsModel must not resolve runtime or package collaborators "
                + "through hidden production defaults."
        )
        XCTAssertTrue(modelSource.contains("runtime: ObservabilityRuntimeAssembly"))
        XCTAssertTrue(modelSource.contains("incidentManager: any DiagnosticsIncidentManaging"))

        let dependencySource = try String(contentsOf: dependencyFile, encoding: .utf8)
        XCTAssertTrue(dependencySource.contains("let runtime: @MainActor () -> ObservabilityRuntimeAssembly"))

        let appContainerSource = try String(contentsOf: appContainerFile, encoding: .utf8)
        XCTAssertTrue(
            appContainerSource.contains("runtime: { ObservabilityRuntimeAssembly.shared }"),
            "Diagnostics runtime must be supplied by an AppFeatureDependencyContainer-owned main-actor provider."
        )

        let paneSource = try String(contentsOf: paneFile, encoding: .utf8)
        XCTAssertTrue(
            paneSource.contains("let runtime = dependencies.runtime()") &&
                paneSource.contains("ObservabilityRuntimeIncidentAdapter(runtime: runtime)"),
            "Diagnostics pane must resolve the runtime provider at its main-actor composition boundary."
        )
        XCTAssertFalse(
            paneSource.contains("init(repositoryURL: URL)"),
            "Production diagnostics panes must require an explicit feature dependency scope."
        )
    }

    func testMainWindowSharedRuntimeDependenciesAreExplicitAtTheAppBoundary() throws {
        let appFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AreaMatrixApp.swift"
        })
        let windowFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindow.swift"
        })
        let routeContentFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindowRouteContent.swift"
        })
        let repositoryContentFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/Main/MainRepositoryContentView.swift"
        })

        let appSource = try String(contentsOf: appFile, encoding: .utf8)
        let windowSource = try String(contentsOf: windowFile, encoding: .utf8)
        let routeContentSource = try String(contentsOf: routeContentFile, encoding: .utf8)
        let repositoryContentSource = try String(contentsOf: repositoryContentFile, encoding: .utf8)

        XCTAssertFalse(
            windowSource.contains("observabilityRuntime: ObservabilityRuntimeAssembly? = nil") ||
                windowSource.contains("commandRouter: AppCommandRouter? = nil") ||
                windowSource.contains("observabilityRuntime ?? .shared") ||
                windowSource.contains("commandRouter ?? .shared"),
            "MainWindow must not hide process-wide runtime dependencies behind initializer defaults."
        )
        XCTAssertTrue(
            windowSource.contains("_observabilityRuntime = ObservedObject(wrappedValue: observabilityRuntime)") &&
                windowSource.contains("_commandRouter = ObservedObject(wrappedValue: commandRouter)"),
            "MainWindow must store the explicitly composed runtime dependencies."
        )
        XCTAssertTrue(
            appSource.contains("observabilityRuntime: observabilityRuntime") &&
                appSource.contains("commandRouter: commandRouter"),
            "AreaMatrixApp must compose and pass the shared runtime dependencies to MainWindow."
        )
        XCTAssertFalse(
            routeContentSource.contains("commandRouter: AppCommandRouter? = nil") ||
                routeContentSource.contains("commandRouter ?? .shared") ||
                repositoryContentSource.contains("commandRouter: AppCommandRouter? = nil") ||
                repositoryContentSource.contains("commandRouter ?? .shared"),
            "MainWindowRouteContent and MainRepositoryContentView must not resolve AppCommandRouter "
                + "through hidden defaults."
        )
        XCTAssertTrue(
            routeContentSource.contains("commandRouter: AppCommandRouter,") &&
                repositoryContentSource.contains("commandRouter: AppCommandRouter,") &&
                repositoryContentSource.contains("_commandRouter = ObservedObject(wrappedValue: commandRouter)"),
            "Main route and content views must require and store the explicitly composed command router."
        )
    }

    func testCoreBridgeLocaleAndImportObservabilityAreComposedAtTheAppBoundary() throws {
        let bridgePaths = [
            "Bridge/CoreBridge.swift",
            "Bridge/CoreBridgeRuntime.swift",
            "Bridge/CoreRepositoryOpening.swift",
            "Bridge/CoreImportObservability.swift"
        ]
        let bridgeFiles = try bridgePaths.map { path in
            try XCTUnwrap(productionSwiftFiles().first { relativeProductionPath(for: $0) == path })
        }
        let runtimeFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/CoreBridgeRuntimeAssembly.swift"
        })
        let runtimeAdapterFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Bridge/CoreBridgeRuntime.swift"
        })

        let hiddenRuntimeReferences = try bridgeFiles.flatMap {
            try sourceRegexMatches(
                in: $0,
                pattern: #"CoreBridge\s*\(|CoreBridgeRuntime\.shared|AppLanguageRuntime\.shared|ObservabilityRuntimeAssembly\.shared|AppLogger\.shared|CoreImportObservabilityRecorder\.live"#
            )
        }
        XCTAssertEqual(
            hiddenRuntimeReferences,
            [],
            "CoreBridge implementation files must not resolve process-wide locale or observability singletons."
        )

        let runtimeAdapterSource = try String(contentsOf: runtimeAdapterFile, encoding: .utf8)
        XCTAssertTrue(
            runtimeAdapterSource.contains("extension CoreBridge: CoreBridgeRuntimeProviding") &&
                runtimeAdapterSource.contains("extension CoreBridge: CoreVersionLoading"),
            "Bridge/CoreBridgeRuntime.swift must remain a protocol-conformance adapter only."
        )
        XCTAssertFalse(
            runtimeAdapterSource.contains("CoreBridge(") || runtimeAdapterSource.contains("CoreBridgeRuntime.shared"),
            "Bridge/CoreBridgeRuntime.swift must not own process-level CoreBridge construction."
        )

        let runtimeSource = try String(contentsOf: runtimeFile, encoding: .utf8)
        XCTAssertTrue(
            runtimeSource.contains("interfaceLocaleIdentifier: { AppLanguageRuntime.shared.resolvedIdentifier() }") &&
                runtimeSource.contains("CoreImportObservabilityRecorder.live(") &&
                runtimeSource.contains("logger: AppLogger.shared"),
            "The process-scoped bridge runtime must compose locale and import observability explicitly."
        )
    }

    func testClassifierSettingsInterfaceLocaleIsComposedAtTheAppBoundary() throws {
        let appFeatureDependencyFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppFeatureDependencyContainer.swift"
        })
        let dependencyDefaultsFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/FeatureDependencyDefaults.swift"
        })
        let classifierFiles = try productionSwiftFiles().filter {
            relativeProductionPath(for: $0).hasPrefix("Features/Settings/Classifier")
        }

        let appFeatureDependencySource = try String(contentsOf: appFeatureDependencyFile, encoding: .utf8)
        let dependencyDefaultsSource = try String(contentsOf: dependencyDefaultsFile, encoding: .utf8)
        let hiddenRuntimeReferences = try classifierFiles.flatMap {
            try sourceRegexMatches(in: $0, pattern: #"AppLanguageRuntime\.shared"#)
        }

        XCTAssertTrue(
            dependencyDefaultsSource.contains("let interfaceLocaleIdentifier: @MainActor () -> String") &&
                appFeatureDependencySource
                .contains("interfaceLocaleIdentifier: { AppLanguageRuntime.shared.resolvedIdentifier() }"),
            "Classifier settings interface locale must be supplied by the App feature dependency scope."
        )
        XCTAssertEqual(
            hiddenRuntimeReferences,
            [],
            "Classifier settings must not resolve AppLanguageRuntime.shared inside the Settings feature."
        )
    }

    func testAdvancedSettingsActionLoggerIsComposedAtTheAppBoundary() throws {
        let paneFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Settings/AdvancedSettingsPane.swift"
        })
        let dependencyFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/FeatureDependencyDefaults.swift"
        })
        let appContainerFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppFeatureDependencyContainer.swift"
        })

        let paneSource = try String(contentsOf: paneFile, encoding: .utf8)
        let dependencySource = try String(contentsOf: dependencyFile, encoding: .utf8)
        let appContainerSource = try String(contentsOf: appContainerFile, encoding: .utf8)

        XCTAssertFalse(
            paneSource.contains("AppLogger.shared"),
            "Advanced Settings must not resolve the process-wide logger inside the feature view."
        )
        XCTAssertTrue(
            paneSource.contains("actionLogger: any AppUIActionLogging") &&
                dependencySource.contains("let actionLogger: any AppUIActionLogging") &&
                appContainerSource.contains("actionLogger: AppLogger.shared"),
            "Advanced Settings action logging must be supplied by the App feature dependency scope."
        )
    }

    func testDiagnosticPackageLocaleIsComposedAtTheAppBoundary() throws {
        let exporterFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "PlatformServices/Observability/DiagnosticPackageExporter.swift"
        })
        let platformFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "PlatformServices/AdvancedSettingsPlatformServices.swift"
        })
        let appContainerFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppFeatureDependencyContainer.swift"
        })

        let exporterSource = try String(contentsOf: exporterFile, encoding: .utf8)
        let platformSource = try String(contentsOf: platformFile, encoding: .utf8)
        let appContainerSource = try String(contentsOf: appContainerFile, encoding: .utf8)

        XCTAssertFalse(
            exporterSource.contains("AppLanguageRuntime.shared"),
            "Diagnostic package export must not read the process-wide language runtime from PlatformServices."
        )
        XCTAssertTrue(
            exporterSource.contains("interfaceLocaleIdentifier: @escaping @Sendable () -> String") &&
                platformSource.contains("diagnosticsPackagePreviewer(") &&
                appContainerSource.contains(
                    "interfaceLocaleIdentifier: { AppLanguageRuntime.shared.resolvedIdentifier() }"
                ),
            "Diagnostic package locale must be supplied through the App composition boundary."
        )
    }
}

extension MacOSAppCompositionGovernanceTests {
    func testImportActionLoggingIsComposedAtTheAppBoundary() throws {
        let importFiles = try productionSwiftFiles().filter {
            relativeProductionPath(for: $0).hasPrefix("Features/Import/")
        }
        let dependencyFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/FeatureDependencyDefaults.swift"
        })
        let featureContainerFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppFeatureDependencyContainer.swift"
        })
        let appContainerFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppDependencyContainer.swift"
        })
        let windowFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Views/MainWindow.swift"
        })
        let entryFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Features/Import/ImportEntrySheetView.swift"
        })

        let hiddenLoggerReferences = try importFiles.flatMap {
            try sourceRegexMatches(in: $0, pattern: #"\bAppLogger\.shared\b"#)
        }
        XCTAssertEqual(
            hiddenLoggerReferences,
            [],
            "Import must not resolve the process-wide logger inside feature code."
        )

        let dependencySource = try String(contentsOf: dependencyFile, encoding: .utf8)
        let featureContainerSource = try String(contentsOf: featureContainerFile, encoding: .utf8)
        let appContainerSource = try String(contentsOf: appContainerFile, encoding: .utf8)
        let windowSource = try String(contentsOf: windowFile, encoding: .utf8)
        let entrySource = try String(contentsOf: entryFile, encoding: .utf8)

        XCTAssertTrue(
            dependencySource.contains("struct ImportFeatureDependencies") &&
                dependencySource.contains("let actionLogger: any AppUIActionLogging") &&
                featureContainerSource.contains("actionLogger: AppLogger.shared"),
            "Import action logging must be supplied by the App-owned feature dependency scope."
        )
        XCTAssertTrue(
            windowSource.contains("actionLogger: dependencies.feature.import.actionLogger") &&
                entrySource.contains("let actionLogger: any AppUIActionLogging") &&
                entrySource.contains("actionLogger: dependencies.actionLogger"),
            "Import entry models must receive the composed logger rather than resolving a global."
        )
    }

    func testOnboardingActionLoggingIsComposedAtTheAppBoundary() throws {
        let onboardingFiles = try productionSwiftFiles().filter {
            let path = relativeProductionPath(for: $0)
            return path == "Features/Onboarding/ImportProgressActions.swift"
                || path == "Features/Onboarding/ImportResultActions.swift"
        }
        let onboardingModelFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppShellModel.swift"
        })
        let appContainerFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "App/AppDependencyContainer.swift"
        })

        let hiddenLoggerReferences = try onboardingFiles.flatMap {
            try sourceRegexMatches(in: $0, pattern: #"\bAppLogger\.shared\b"#)
        }
        XCTAssertEqual(
            hiddenLoggerReferences,
            [],
            "Onboarding must not resolve the process-wide logger inside feature code."
        )

        let appContainerSource = try String(contentsOf: appContainerFile, encoding: .utf8)
        let onboardingModelSource = try String(contentsOf: onboardingModelFile, encoding: .utf8)
        XCTAssertTrue(
            appContainerSource.contains("let actionLogger: any AppUIActionLogging") &&
                appContainerSource.contains("actionLogger: AppLogger.shared") &&
                onboardingModelSource.contains("let actionLogger: any AppUIActionLogging") &&
                onboardingModelSource.contains("actionLogger: dependencies.onboarding.actionLogger"),
            "Onboarding action logging must be composed explicitly from AppDependencyContainer."
        )
    }
}
