import XCTest

class MacOSGovernanceTestCase: XCTestCase {}

final class MacOSArchitectureBoundaryGovernanceTests: MacOSGovernanceTestCase {
    private let featurePlatformCapabilityPatterns = [
        #"FileManager\.default"#,
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
        #"Process\("#
    ]

    private let nonBridgeCoreErrorInventory = [
        "Features/SyncConflicts/ICloudConflictMinimalResolution.swift:CoreError.Internal:1",
        "Features/SyncConflicts/ICloudConflictMinimalResolution.swift:CoreError:1",
        "Features/SyncConflicts/ICloudConflictMinimalValidation.swift:CoreError.Conflict:1",
        "Features/SyncConflicts/ICloudConflictMinimalValidation.swift:CoreError.Internal:2",
        "Features/SyncConflicts/MainICloudConflictRoutingActions.swift:CoreError.Internal:2"
    ]

    func testGeneratedCoreCallsStayInsideBridge() throws {
        let violations = try productionSwiftFiles()
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/") }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: #"\bAreaMatrix\.[A-Za-z_][A-Za-z0-9_]*\s*\("#
                )
            }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Swift production code must call Rust Core through Bridge/CoreBridge, not generated UniFFI bindings."
        )
    }

    func testSwiftUIViewFilesDoNotOwnPlatformIO() throws {
        let platformIOTerms = [
            "FileManager.default",
            "NSApplication.shared",
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

    func testFeaturePlatformCapabilityUseStaysInventoried() throws {
        let expected = [
            "Features/AI/RemoteProviderCredentialStore.swift:SecItemAdd:1",
            "Features/AI/RemoteProviderCredentialStore.swift:SecItemCopyMatching:1",
            "Features/AI/RemoteProviderCredentialStore.swift:SecItemDelete:1",
            "Features/AI/RemoteProviderCredentialStore.swift:SecItemUpdate:1",
            "Features/Import/ImportSingleFilePreflightSupport.swift:FileManager.default:1",
            "Features/Import/ImportSingleFilePreflightSupport.swift:startDownloadingUbiquitousItem:1"
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

    func testGeneratedBindingDirectoriesContainOnlyGeneratedArtifacts() throws {
        let expected = [
            "Bridge/Generated/area_matrix.swift",
            "Bridge/Generated/area_matrixFFI.h",
            "Bridge/Generated/area_matrixFFI.modulemap",
            "Bridge/Generated/libarea_matrix_core.a",
            "Bridge/Generated/module.modulemap",
            "Bridge/UniFFI/area_matrix.swift",
            "Bridge/UniFFI/area_matrixFFI.h",
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
}

final class MacOSPlatformAdapterGovernanceTests: MacOSGovernanceTestCase {
    private let nsWorkspaceOpenInventory = [
        "App/AppPlatformServiceAdapters.swift:NSWorkspace.shared.activateFileViewerSelecting:1",
        "App/AppPlatformServiceAdapters.swift:NSWorkspace.shared.open:1",
        "PlatformServices/ExternalURLPolicy.swift:NSWorkspace.shared.open:1"
    ]

    func testAppPlatformDefaultAdaptersStayCentralized() throws {
        let violations = try productionSwiftFiles()
            .filter { !appPlatformServiceFiles.contains(relativeProductionPath(for: $0)) }
            .flatMap {
                try sourceRegexViolations(
                    in: $0,
                    pattern: [
                        #"\bBundleAppVersionReader\s*\("#,
                        #"\bFileImportBatchSessionStore\s*\("#,
                        #"\bLocalWelcomeHelpOpener\s*\("#,
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
                        #"\bLocalAboutDiagnosticsExporter\s*\("#,
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
            in: productionSwiftFiles(),
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
            "PlatformServices/ExternalURLPolicy.swift:URL(string::1"
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles(),
            pattern: #"\bURL\s*\(\s*string\s*:"#
        )

        XCTAssertEqual(
            actual,
            expected,
            "External URL string parsing should stay behind ExternalURLPolicy so app and feature code " +
                "reuse the same HTTPS-only guard before opening remote links."
        )
    }

    func testExternalURLPolicyUseStaysBehindSharedOpener() throws {
        let expected = [
            "PlatformServices/ExternalURLPolicy.swift:ExternalURLPolicy.validatedHTTPSURL:1"
        ]
        let actual = try countedRegexMatches(
            in: productionSwiftFiles(),
            pattern: #"\bExternalURLPolicy\.validatedHTTPSURL\b"#
        )

        XCTAssertEqual(
            actual,
            expected,
            "Remote link validation should stay behind the shared ExternalURLStringOpening adapter " +
                "instead of being repeated in feature-specific platform services."
        )
    }

    func testRepositoryLogsPathConstructionStaysCentralized() throws {
        let expectedLogsComponentConstruction = [
            "PlatformServices/RepositoryMetadataPresencePlatformServices.swift:" +
                #".appendingPathComponent("logs", isDirectory: true):1"#
        ]
        let actualLogsComponentConstruction = try countedRegexMatches(
            in: productionSwiftFiles(),
            pattern: #"\.appendingPathComponent\(\s*"logs"\s*,\s*isDirectory:\s*true\s*\)"#
        )

        XCTAssertEqual(
            actualLogsComponentConstruction,
            expectedLogsComponentConstruction,
            ".areamatrix/logs URL construction should stay behind RepositoryMetadataPath.logsURL " +
                "instead of being repeated in settings platform adapters."
        )

        let expectedHelperUse = [
            "PlatformServices/AboutSettingsPlatformServices.swift:RepositoryMetadataPath.logsURL:2",
            "PlatformServices/AdvancedSettingsPlatformServices.swift:RepositoryMetadataPath.logsURL:1"
        ]
        let actualHelperUse = try countedRegexMatches(
            in: productionSwiftFiles(),
            pattern: #"\bRepositoryMetadataPath\.logsURL\b"#
        )

        XCTAssertEqual(
            actualHelperUse,
            expectedHelperUse,
            "Settings log folder openers should reuse the shared repository metadata logs URL helper."
        )
    }
}

extension MacOSGovernanceTestCase {
    var appPlatformServiceFiles: Set<String> {
        [
            "App/AppPlatformServices.swift",
            "App/AppPlatformServiceAdapters.swift"
        ]
    }

    func productionSwiftFiles() throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: productionDirectory(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/Generated/") }
            .filter { !relativeProductionPath(for: $0).hasPrefix("Bridge/UniFFI/") }
    }

    func productionDirectory() -> URL {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testsDirectory.deletingLastPathComponent()
            .appendingPathComponent("AreaMatrix", isDirectory: true)
    }

    func generatedBindingArtifacts() throws -> [String] {
        try ["Bridge/Generated", "Bridge/UniFFI"].flatMap { relativeDirectory in
            let directoryURL = productionDirectory().appendingPathComponent(relativeDirectory, isDirectory: true)
            let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return try (enumerator?.compactMap { $0 as? URL } ?? [])
                .filter { try isRegularFile($0) }
                .map { relativeProductionPath(for: $0) }
        }
        .sorted()
    }

    func isRegularFile(_ fileURL: URL) throws -> Bool {
        try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    }

    func isViewLikeProductionFile(_ fileURL: URL) -> Bool {
        let relativePath = relativeProductionPath(for: fileURL)
        if relativePath.hasPrefix("Views/") { return true }

        let fileName = fileURL.lastPathComponent
        let viewSuffixes = ["View.swift", "Pane.swift", "Sheet.swift", "Section.swift", "Row.swift", "Panel.swift"]
        return relativePath.hasPrefix("Features/") && viewSuffixes.contains { fileName.hasSuffix($0) }
    }

    func relativeProductionPath(for fileURL: URL) -> String {
        let marker = "/AreaMatrix/"
        guard let range = fileURL.path.range(of: marker, options: .backwards) else {
            return fileURL.lastPathComponent
        }
        return String(fileURL.path[range.upperBound...])
    }

    func sourceTermViolations(in fileURL: URL, terms: [String]) throws -> [String] {
        try sourceLineViolations(in: fileURL) { line in
            terms.filter { line.contains($0) }
        }
    }

    func sourceRegexViolations(in fileURL: URL, pattern: String) throws -> [String] {
        try sourceLineViolations(in: fileURL) { line in
            try regexMatches(in: line, pattern: pattern)
        }
    }

    func countedRegexMatches(in fileURLs: [URL], pattern: String) throws -> [String] {
        let matches = try fileURLs.flatMap { fileURL in
            try sourceRegexMatches(in: fileURL, pattern: pattern)
        }
        let counts = Dictionary(grouping: matches, by: { $0 }).mapValues(\.count)
        return counts.map { "\($0.key):\($0.value)" }.sorted()
    }

    func sourceRegexMatches(in fileURL: URL, pattern: String) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(separator: "\n", omittingEmptySubsequences: false).flatMap { line in
            try regexMatches(in: String(line), pattern: pattern).map {
                "\(relativeProductionPath(for: fileURL)):\($0)"
            }
        }
    }

    func regexMatches(in line: String, pattern: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let range = Range(match.range, in: line) else { return nil }
            return String(line[range])
        }
    }

    func sourceLineViolations(in fileURL: URL, matches: (String) throws -> [String]) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { offset, line in
                try matches(String(line)).map {
                    "\(relativeProductionPath(for: fileURL)):\(offset + 1): \($0)"
                }
            }
    }
}
