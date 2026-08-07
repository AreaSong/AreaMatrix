import XCTest

final class MacOSArchitectureBoundaryGovernanceTests: MacOSGovernanceTestCase {
    private let featurePlatformCapabilityPatterns = [
        #"FileManager(?:\.default|\s*=\s*\.default)"#,
        "startDownloadingUbiquitousItem",
        #"Task\.detached"#,
        "SecItemCopyMatching",
        "SecItemUpdate",
        "SecItemAdd",
        "SecItemDelete",
        "NSWorkspace[A-Za-z0-9_]*",
        "NSPasteboard[A-Za-z0-9_]*",
        "NSOpenPanel[A-Za-z0-9_]*",
        "NSSavePanel[A-Za-z0-9_]*",
        "FSEventStream",
        "URLSession",
        "NSFileCoordinator",
        #"Process\("#,
        "FileHandle",
        "resourceValues",
        #"Data\(contentsOf:"#,
        #"write\(to:"#,
        #"setenv\("#,
        #"getenv\("#,
        #"unsetenv\("#,
        #"\blstat\("#,
        #"\bstat\("#,
        #"\bgeteuid\("#
    ]

    private let nonBridgeCoreErrorInventory: [String] = []

    func testSwiftUIViewFilesDoNotOwnPlatformIO() throws {
        let platformIOTerms = [
            "FileManager.default",
            "NSApplication.shared",
            "NSApp.appearance", "NSCursor.", "NSHapticFeedbackManager", "NotificationCenter.default.post",
            "startDownloadingUbiquitousItem",
            "NSFileCoordinator",
            "FSEventStream",
            "URLSession",
            "Task.detached"
        ]
        let violations = try productionSwiftFiles()
            .filter(isViewLikeProductionFile)
            .flatMap { try sourceTermViolations(in: $0, terms: platformIOTerms) }
            .sorted()
        XCTAssertEqual(
            violations,
            [],
            "SwiftUI view files should delegate platform IO to models, Bridge, or PlatformServices."
        )
    }

    func testFeatureAndViewInteractionFeedbackUsesEnvironmentDependency() throws {
        let environmentDeclarationPath =
            "Packages/AreaMatrixModules/Sources/AreaMatrixUIFoundation/InteractionFeedbackEnvironment.swift"
        let violations = try productionSwiftFiles()
            .filter { fileURL in
                let path = relativeProductionPath(for: fileURL)
                return (path.hasPrefix("Features/") || path.hasPrefix("Views/")) &&
                    path != environmentDeclarationPath
            }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\bAppPlatformServices\.interactionFeedback\b"#
                )
            }
            .sorted()
        XCTAssertEqual(
            violations,
            [],
            "Feature and view code should consume interaction feedback through SwiftUI Environment " +
                "so previews and tests can inject a controlled platform double."
        )

        let environmentSourceFiles = try productionSwiftFiles() + packageSwiftFiles("AreaMatrixUIFoundation")
        let environmentSource = try String(
            contentsOf: XCTUnwrap(environmentSourceFiles.first {
                relativeProductionPath(for: $0) == environmentDeclarationPath
            }),
            encoding: .utf8
        )
        XCTAssertTrue(
            environmentSource.contains(
                "static let defaultValue: any AreaMatrixInteractionFeedbackPerforming = " +
                    "AreaMatrixNoopInteractionFeedback()"
            ),
            "The Environment default must be side-effect free; production AppKit feedback " +
                "must be injected by App composition."
        )
    }

    func testFeaturePlatformCapabilityUseStaysInventoried() throws {
        let expected = [
            "Features/AI/RemoteProviderCredentialStore.swift:SecItemAdd:1",
            "Features/AI/RemoteProviderCredentialStore.swift:SecItemCopyMatching:1",
            "Features/AI/RemoteProviderCredentialStore.swift:SecItemDelete:1",
            "Features/AI/RemoteProviderCredentialStore.swift:SecItemUpdate:1"
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles().filter { relativeProductionPath(for: $0).hasPrefix("Features/") },
            pattern: featurePlatformCapabilityPatterns.joined(separator: "|")
        )
        XCTAssertEqual(
            actual,
            expected,
            "Feature-layer platform capability usage must stay explicitly inventoried until migrated " +
                "to PlatformServices."
        )
    }

    func testRemoteProviderProbeServiceImplementationStaysInPlatformServices() throws {
        let implementationFiles = try productionSwiftFiles().filter {
            relativeProductionPath(for: $0) == "PlatformServices/RemoteProviderProbeService.swift"
        }
        let actual = try countedRegexMatches(
            in: implementationFiles,
            pattern: #"\bactor RemoteProviderProbeService\b"#
        )

        XCTAssertEqual(
            actual,
            ["PlatformServices/RemoteProviderProbeService.swift:actor RemoteProviderProbeService:1"],
            "Remote provider Keychain and URLSession execution must stay outside the AI feature implementation."
        )
    }

    func testRemoteProviderProbeServiceKeepsCredentialAndNetworkLimitsExplicit() throws {
        let implementationFiles = try productionSwiftFiles().filter {
            relativeProductionPath(for: $0) == "PlatformServices/RemoteProviderProbeService.swift"
        }
        let source = try String(contentsOf: XCTUnwrap(implementationFiles.first), encoding: .utf8)
        let requiredTerms = [
            "static let shared = RemoteProviderProbeService()",
            "KeychainProbeCredentialReader",
            "URLSessionRemoteProviderProbeTransport",
            "URLSessionConfiguration.ephemeral",
            "maximumResponseBodyBytes == 0",
            "!plan.followRedirects",
            "completionHandler(nil)",
            "kSecReturnData"
        ]

        let missing = requiredTerms.filter { !source.contains($0) }
        XCTAssertEqual(
            missing,
            [],
            "Remote provider platform execution must keep Keychain isolation and headers-only network limits."
        )
    }

    func testImportSessionPersistenceImplementationStaysInPlatformServices() throws {
        let implementationFiles = try productionSwiftFiles().filter {
            relativeProductionPath(for: $0) == "PlatformServices/ImportBatchSessionPlatformServices.swift"
        }
        let actual = try countedRegexMatches(
            in: implementationFiles,
            pattern: #"\bFileImportBatchSessionStore\b"#
        )

        XCTAssertEqual(
            actual,
            ["PlatformServices/ImportBatchSessionPlatformServices.swift:FileImportBatchSessionStore:1"],
            "Import session file persistence should stay in PlatformServices; the Import feature owns only " +
                "session semantics and recovery state."
        )
    }

    func testGeneratedBindingDirectoriesContainOnlyGeneratedArtifacts() throws {
        let expected = [
            "Bridge/Generated/area_matrix.swift",
            "Bridge/Generated/area_matrixFFI.h",
            "Bridge/Generated/area_matrixFFI.modulemap",
            "Bridge/Generated/libarea_matrix_core.a",
            "Bridge/Generated/module.modulemap",
            "Bridge/UniFFI/area_matrix.swift",
            "Bridge/UniFFI/area_matrixFFI.h",
            "Bridge/UniFFI/area_matrixFFI.modulemap",
            "Bridge/UniFFI/libarea_matrix_core.a",
            "Bridge/UniFFI/module.modulemap"
        ]
        let actual = try generatedBindingArtifacts()

        XCTAssertEqual(
            actual,
            expected,
            "Bridge/Generated and Bridge/UniFFI should only contain generated UniFFI artifacts."
        )
    }

    func testSQLiteAccessStaysInBridgeOrPlatformServices() throws {
        let violations = try productionSwiftFiles()
            .filter { fileURL in
                let path = relativeProductionPath(for: fileURL)
                return !path.hasPrefix("Bridge/") && !path.hasPrefix("PlatformServices/")
            }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\bsqlite3_[A-Za-z0-9_]+\b|\bSQLITE_[A-Z0-9_]+\b"#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "SQLite direct access should stay behind Bridge or PlatformServices, not feature, view, or model code."
        )
    }

    func testNonBridgeCoreErrorUsageStaysInventoried() throws {
        let actual = try countedRegexMatches(
            in: productionSwiftFiles().filter { fileURL in
                let path = relativeProductionPath(for: fileURL)
                return !path.hasPrefix("Bridge/") && !path.hasPrefix("PlatformServices/")
            },
            pattern: #"\bCoreError(?:\.[A-Za-z]+)?\b"#
        )

        XCTAssertEqual(
            actual,
            nonBridgeCoreErrorInventory,
            "Non-Bridge CoreError usage must stay explicitly inventoried until migrated to app semantic errors."
        )
    }

    func testAppErrorMappingProviderStaysCentralizedInBridgeSnapshots() throws {
        let violations = try productionSwiftFiles()
            .filter { relativeProductionPath(for: $0) != "Bridge/CoreErrorMappingSnapshots.swift" }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\bAppErrorMappingProviding\b"#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "App semantic error mapping providers should stay centralized in Bridge snapshots; " +
                "feature code should use AppSemanticError."
        )
    }

    func testGeneratedErrorMappingTypesStayInsideBridge() throws {
        let violations = try productionSwiftFiles()
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/") }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: [
                        #"\bErrorMappingInput\b"#,
                        #"\bErrorMapping\b"#,
                        #"\bErrorSeverity\b"#,
                        #"\bErrorRecoverability\b"#,
                        #"\bmapCoreError\s*\(\s*input\s*:"#
                    ].joined(separator: "|")
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Generated Core error mapping DTOs and functions should stay behind Bridge; " +
                "feature code should consume CoreErrorMappingSnapshot or AppSemanticError."
        )
    }

    func testGeneratedReindexReportStaysInsideBridge() throws {
        let violations = try productionSwiftFiles()
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/") }
            .flatMap {
                try sourceRegexViolations(in: $0, pattern: #"\bReindexReport\b"#)
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Generated ReindexReport must be converted to ReindexReportSnapshot inside Bridge."
        )
    }
}

final class MacOSPlatformAdapterGovernanceTests: MacOSGovernanceTestCase {
    private let nsWorkspaceOpenInventory = [
        "Packages/AreaMatrixModules/Sources/AreaMatrixPlatformKit/ExternalURLPolicy.swift:NSWorkspace.shared.open:1",
        "Packages/AreaMatrixModules/Sources/AreaMatrixPlatformKit/LocalFileURLPolicy.swift:NSWorkspace.shared.activateFileViewerSelecting:1",
        "Packages/AreaMatrixModules/Sources/AreaMatrixPlatformKit/LocalFileURLPolicy.swift:NSWorkspace.shared.open:1"
    ]

    func testAppPlatformDefaultAdaptersStayCentralized() throws {
        let violations = try productionSwiftFiles()
            .filter { !appPlatformServiceFiles.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: [
                        #"\bAppKitInteractionFeedbackPerformer\s*\("#,
                        #"\bBundleAppVersionReader\s*\("#,
                        #"\bFileImportBatchSessionStore\s*\("#,
                        #"\bWelcomeHelpOpener\s*\("#,
                        #"\bLocalRootOverviewFileInspector\s*\("#,
                        #"\bLocalSystemCapabilities\s*\("#,
                        #"\bNSApplicationKeyWindowCloser\s*\("#,
                        #"\bNSOpenPanelRepositoryDirectoryPicker\s*\("#,
                        #"\bNSOpenPanelRepositoryImportPicker\s*\("#,
                        #"\bNSPasteboardRepositoryPathCopier\s*\("#,
                        #"\bNSPasteboardStringWriter\s*\("#,
                        #"\bNSSavePanelImportResultDetailsExporter\s*\("#,
                        #"\bSQLiteExistingRepositoryMetadataReader\s*\("#,
                        #"\bVoiceOverAccessibilityAnnouncer\s*\("#,
                        #"\bNSWorkspaceRepositoryFileOpener\s*\("#,
                        #"\bNSWorkspaceRepositoryFileRevealer\s*\("#,
                        #"\bNSWorkspaceRepositoryFinderOpener\s*\("#
                    ].joined(separator: "|")
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "App-wide platform default adapters should be constructed through AppPlatformServices."
        )
    }

    func testFeaturePlatformDefaultAdaptersStayInPlatformServices() throws {
        let violations = try productionSwiftFiles()
            .filter { fileURL in
                let path = relativeProductionPath(for: fileURL)
                return !path.hasPrefix("PlatformServices/")
            }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: [
                        #"\bLocalICloudStatusDetector\s*\("#,
                        #"\bLocalImportFolderScanner\s*\("#,
                        #"\bLocalModelStorageProvider\s*\("#,
                        #"\bLocalSourcePreflightInspector\s*\("#,
                        #"\bNSPasteboardLocalModelDiagnosticsCopier\s*\("#,
                        #"\bNSWorkspaceLocalModelFolderOpener\s*\("#,
                        #"\bNSWorkspaceLocalModelInstallHelpOpener\s*\("#,
                        #"\bNSWorkspaceRepositoryIgnoreRulesManager\s*\("#
                    ].joined(separator: "|")
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Feature platform default adapters should be constructed through PlatformServices."
        )
    }

    func testNSWorkspaceOpeningSideEffectsStayBehindPlatformAdapters() throws {
        let violations = try productionSwiftFiles()
            .filter { fileURL in
                let path = relativeProductionPath(for: fileURL)
                return !path.hasPrefix("App/") && !path.hasPrefix("PlatformServices/")
            }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\bNSWorkspace\.shared\.(?:open|activateFileViewerSelecting)\s*\("#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Opening URLs, files, folders, or Finder selections through NSWorkspace should stay " +
                "behind App or PlatformServices adapters."
        )
    }

    func testNSWorkspaceOpeningSideEffectsStayInventoried() throws {
        let actual = try countedRegexMatches(
            in: productionSwiftFiles() + packageSwiftFiles("AreaMatrixPlatformKit"),
            pattern: #"\bNSWorkspace\.shared\.(?:open|activateFileViewerSelecting)\b"#
        )

        XCTAssertEqual(
            actual,
            nsWorkspaceOpenInventory,
            "Direct NSWorkspace open/reveal calls should stay behind reviewed shared adapters; " +
                "new call sites must either reuse LocalFileURLOpening or be explicitly inventoried."
        )
    }

    func testExternalURLStringParsingStaysCentralizedInPolicy() throws {
        let expected = [
            "Packages/AreaMatrixModules/Sources/AreaMatrixPlatformKit/ExternalURLPolicy.swift:URL(string::1",
            "PlatformServices/RemoteProviderProbeService.swift:URL(string::1"
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles() + packageSwiftFiles("AreaMatrixPlatformKit"),
            pattern: #"\bURL\s*\(\s*string\s*:"#
        )

        XCTAssertEqual(
            actual,
            expected,
            "External links stay behind ExternalURLPolicy; remote provider probe URLs are a separately reviewed " +
                "network boundary in PlatformServices."
        )
    }

    func testExternalURLPolicyUseStaysBehindSharedOpener() throws {
        let expected = [
            "Packages/AreaMatrixModules/Sources/AreaMatrixPlatformKit/ExternalURLPolicy.swift:" +
                "ExternalURLPolicy.validatedHTTPSURL:1"
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles() + packageSwiftFiles("AreaMatrixPlatformKit"),
            pattern: #"\bExternalURLPolicy\.validatedHTTPSURL\b"#
        )

        XCTAssertEqual(
            actual,
            expected,
            "Remote link validation should stay behind the shared ExternalURLStringOpening adapter " +
                "instead of being repeated in feature-specific platform services."
        )
    }
}
