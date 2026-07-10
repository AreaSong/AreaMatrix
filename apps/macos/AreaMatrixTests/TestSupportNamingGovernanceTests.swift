import XCTest

private let featureLocalDoubleDeclarations = [
    "enum ChangeCategoryRequest",
    "actor ChangeCategoryRecordingMover",
    "typealias ChangeCategoryRecordingPredictor",
    "typealias ChangeCategoryRecordingLister",
    "typealias DetailLogRecordingLister",
    "struct RenameRequest",
    "actor RenameRecordingRenamer",
    "struct BatchRenamePreviewRequest",
    "struct BatchRenameApplyRequest",
    "actor BatchRenameRecordingRenamer",
    "struct ImportBatchBatchImportRequest",
    "actor ImportBatchRecordingBatchImporter",
    "actor ImportBatchSequenceBatchImporter",
    "actor ImportBatchStaticBatchFileLoader",
    "struct ImportBatchNameConflictPrecheckRequest",
    "actor ImportBatchStaticNameConflictPrechecker",
    "struct ImportSingleFileStaticLocalizedError",
    "struct ImportSingleFileImportRequest",
    "struct ImportSingleFileCoreImportRequest",
    "typealias ImportSingleFileStaticICloudDownloader",
    "typealias ImportSingleFilePredictRequest",
    "typealias ImportSingleFileRecordingPredictor",
    "typealias ImportSingleFileStaticRepositoryOpener",
    "struct ImportSingleFileStaticPreflight",
    "struct ImportSingleFileFileLoadRequest",
    "actor ImportSingleFileStaticFileLoader",
    "actor ImportSingleFileRecordingImporter",
    "actor ImportSingleFileSuspendingImporter",
    "actor ImportSingleFileImportGate",
    "actor ImportSingleFileFailingImporter",
    "typealias ImportFolderPredictRequest",
    "typealias ImportFolderRecordingPredictor",
    "typealias ImportFolderMappedPredictor",
    "typealias ImportFolderRecordingICloudDownloader",
    "struct ImportFolderStaticFolderScanner",
    "actor ImportFolderSequenceFolderScanner",
    "struct ImportFolderConflictPrecheckRequest",
    "actor ImportFolderStaticConflictPrechecker",
    "actor ImportFolderNoopConflictPrechecker",
    "typealias ShellStaticSettingsReader",
    "typealias ShellRecordingSettingsWriter",
    "typealias ShellRecordingConfigLoader",
    "typealias ShellRecordingRepositoryOpener",
    "typealias ShellRecordingPathValidator",
    "typealias ShellRecordingInitializedPathValidator",
    "typealias ShellRecordingExternalChangesSyncer",
    "typealias ShellRecordingDiagnosticsCollector",
    "typealias ShellRecordingRepositoryInitializer",
    "typealias ShellStaticScanSessionReader",
    "typealias ShellStaticImportBatchSessionStore",
    "struct ShellFailingWelcomeHelpOpener",
    "final class ShellRecordingPathCopier",
    "typealias ShellExistingRepoMetadataReader",
    "final class ShellRecordingDirectoryPicker",
    "struct ShellStaticImportPicker",
    "typealias ImportConflictChangeLogRequest",
    "typealias ImportConflictChangeLogLister",
    "struct ImportConflictPreviewRequest",
    "struct ImportConflictApplyRequest",
    "typealias ImportResultChangeLogRequest",
    "typealias ImportResultRecordingChangeLogLister",
    "final class ImportResultExporter",
    "actor DetailMetaImmediateDetailer",
    "struct FileDetailRequest",
    "actor RecordingFileDetailer",
    "actor RepoSettingsMetadataReader",
    "typealias RepoSettingsRepositoryOpener",
    "typealias RepoSettingsScanSessionReader",
    "final class RecordingRepoMetadataPresenceChecker",
    "typealias RepoSettingsCapabilityLoader",
    "typealias AITagSuggestionAISettingsLoader",
    "typealias SmartListRecordingSmartListRunner",
    "typealias SmokeStaticSettingsReader",
    "typealias SmokeRecordingSettingsWriter",
    "typealias SmokeRecordingConfigLoader",
    "typealias SmokeRecordingPathValidator",
    "typealias SmokeRecordingRepositoryOpener",
    "typealias SmokeRecordingScanSessionReader",
    "typealias SmokeNoopWelcomeHelpOpener",
    "typealias SmokeExistingRepoMetadataReader",
    "typealias ImportDropPredictRequest",
    "typealias ImportDropRecordingPredictor",
    "struct MainEmptyImportStaticImportPicker",
    "actor MainLoadingPausingStartupRecoverer",
    "actor MainLoadingRecordingTreeLister",
    "actor MainLoadingInitializedPathValidator",
    "actor MainLoadingPausingRepositoryOpener",
    "typealias MainLoadingFailingRepositoryOpener",
    "typealias MainLoadingRecordingSettingsWriter",
    "typealias MainListIntegrationDetailer",
    "typealias MainListIntegrationDiagnosticsCollector",
    "typealias MainListIntegrationNoopDetailer",
    "typealias MainListRecordingFileLister",
    "typealias MainListRecordingSearchQuerying",
    "typealias MainListSearchRequestRecord",
    "typealias MainListSmartListRequestRecord",
    "struct MainListFallbackRequestRecord",
    "actor MainListRecordingSemanticSearcher",
    "actor MainListRecordingSemanticFallbackReader",
    "actor MainListIntegrationSuspendedLister",
    "typealias SemanticSearchDetailer",
    "typealias SemanticSearchLister",
    "typealias SemanticSearchNormalSearcher",
    "typealias SemanticSearchPageDetailer",
    "typealias SemanticSearchPageLister",
    "typealias SemanticSearchPageNormalSearcher",
    "actor SemanticSearchSemanticSearcher",
    "actor SemanticSearchPagedSemanticSearcher",
    "actor SemanticSearchDelayedSemanticSearcher",
    "typealias SmartListSmartListRunRequest",
    "typealias SyncConflictReviewRecordingFileDetailer",
    "struct SyncConflictPreviewRequest",
    "struct SyncConflictResolveRequest",
    "typealias ICloudPathValidator"
]

private let bridgeBoundaryDeclarations = [
    "actor AIPrivacyRulesFailingBridge",
    "actor FileActionsRecordingCore",
    "actor ICloudConflictMinimalRecordingMainCore",
    "actor ICloudConflictResolver",
    "actor ICloudConflictReviewer",
    "actor RemotePrivacyRulesBridge"
]

final class TestSupportNamingGovernanceTests: XCTestCase {
    func testFixtureDataUsesFixturesFileSuffix() throws {
        let fixtureSupportSuffix = "Fixture" + "Support.swift"
        let testFixturesSuffix = "Test" + "Fixtures.swift"

        let violations = try testSupportSwiftFiles()
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(fixtureSupportSuffix) || $0.hasSuffix(testFixturesSuffix) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Pure fixture data belongs in *Fixtures.swift; behavior helpers belong in *TestSupport.swift."
        )
    }

    func testFixturesFilesDoNotContainBehaviorSupport() throws {
        let prohibitedTerms = [
            "Recording",
            "Recorder",
            "Recorded",
            "Spy",
            "Mock",
            "Stub",
            "Fake",
            "Noop",
            "Immediate",
            "CoreBridge",
            "Store",
            "Manager",
            "Service",
            "Actor",
            "@MainActor",
            "async",
            "throws",
            "FileManager",
            "temporaryDirectory",
            "createDirectory",
            "write("
        ]
        let violations = try testSupportSwiftFiles()
            .filter { $0.lastPathComponent.hasSuffix("Fixtures.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: prohibitedTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Fixture files should only define reusable sample data; behavior belongs in *TestSupport.swift."
        )
    }

    func testCoreBridgeUsageStaysInNamedBoundarySupportFiles() throws {
        let violations = try supportSwiftFiles()
            .filter { !isNamedCoreBridgeBoundarySupport($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: ["CoreBridge"]) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Support files that touch CoreBridge must expose that bridge boundary in their file name."
        )
    }

    func testFileSystemIOStaysInNamedBoundarySupportFiles() throws {
        let fileSystemTerms = [
            "makeTestTemporaryDirectory",
            "FileManager",
            "temporaryDirectory",
            "createDirectory",
            "write(",
            "setAttributes",
            "removeItem",
            "copyItem",
            "moveItem"
        ]
        let violations = try supportSwiftFiles()
            .filter { !isNamedFileSystemBoundarySupport($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: fileSystemTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Support files that perform filesystem IO must expose that boundary in their file name."
        )
    }

    func testBridgeBoundarySupportDoesNotHideFileSystemHelpers() throws {
        let fileSystemHelperTerms = [
            "makeTestTemporaryDirectory",
            "FileManager",
            "String(contentsOf:",
            "Data(contentsOf:",
            "createDirectory",
            "write(",
            "removeItem",
            "copyItem",
            "moveItem"
        ]
        let violations = try supportSwiftFiles()
            .filter { isNamedBridgeBoundarySupport($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: fileSystemHelperTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Bridge support files should not hide filesystem helpers; use *FileSystemTestSupport.swift."
        )
    }

    func testTestDoubleSupportDoesNotHideBridgeOrFileSystemBoundaries() throws {
        let boundaryTerms = [
            "CoreBridge",
            "makeTestTemporaryDirectory",
            "FileManager",
            "temporaryDirectory",
            "String(contentsOf:",
            "Data(contentsOf:",
            "createDirectory",
            "write(",
            "setAttributes",
            "removeItem",
            "copyItem",
            "moveItem"
        ]
        let violations = try supportSwiftFiles()
            .filter { $0.lastPathComponent.hasSuffix("TestDoubleSupport.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: boundaryTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Test-double support files should stay pure doubles; use named bridge or filesystem boundary support files."
        )
    }

    func testRawTemporaryFilesystemOperationsStayInSharedSupport() throws {
        let temporaryDirectoryTerm = "FileManager.default." + "temporaryDirectory"
        let instanceTemporaryDirectoryTerm = ".temporary" + "Directory"
        let nsTemporaryDirectoryTerm = "NSTemporary" + "Directory("
        let removeItemTerm = "remove" + "Item(at:"
        let guardedTerms = [
            temporaryDirectoryTerm,
            instanceTemporaryDirectoryTerm,
            nsTemporaryDirectoryTerm,
            removeItemTerm
        ]
        let violations = try testSupportSwiftFiles()
            .filter { $0.lastPathComponent != "TestTemporaryDirectoryFileSystemTestSupport.swift" }
            .flatMap { try sourceTermViolations(in: $0, terms: guardedTerms) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Raw temporary-directory creation and cleanup should stay behind " +
                "TestTemporaryDirectoryFileSystemTestSupport so tests share one filesystem safety boundary."
        )
    }

    func testActionRecordingSupportUsesTestDoubleSuffix() throws {
        let violations = try supportSwiftFiles()
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix("ActionRecordingTestSupport.swift") }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Action recording helpers are pure test doubles; use *ActionTestDoubleSupport.swift."
        )
    }

    func testStoreDoubleDeclarationsUseTestDoubleSuffix() throws {
        let storeDoubleDeclarations = [
            "actor StaticImportBatchSessionStore",
            "actor RecordingImportBatchSessionStore",
            "actor NoopUndoActionStore",
            "actor UndoActionRecordingTestStore",
            "actor LenientUndoActionRecordingTestStore",
            "actor RedoActionLogRecordingRedoStore",
            "actor DetailTagRecordingStore",
            "actor TagFilterForbiddenTagStore",
            "final class RemoteProviderTestCredentialStore"
        ]
        let violations = try supportSwiftFiles()
            .filter { !$0.lastPathComponent.hasSuffix("TestDoubleSupport.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: storeDoubleDeclarations) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Store double declarations should live in *TestDoubleSupport.swift."
        )
    }

    func testStoreDoubleAliasesUseTestDoubleSuffix() throws {
        let storeDoubleAliases = [
            "= LenientUndoActionRecordingTestStore",
            "= NoopUndoActionStore",
            "= RecordingSavedSearchStore"
        ]
        let violations = try supportSwiftFiles()
            .filter { !$0.lastPathComponent.hasSuffix("TestDoubleSupport.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: storeDoubleAliases) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Pure store double aliases should live in *TestDoubleSupport.swift."
        )
    }

    func testFeatureLocalDoublesUseTestDoubleSuffix() throws {
        let violations = try supportSwiftFiles()
            .filter { !$0.lastPathComponent.hasSuffix("TestDoubleSupport.swift") }
            .flatMap { try sourceTermViolations(in: $0, terms: featureLocalDoubleDeclarations) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Feature-local doubles should live in *TestDoubleSupport.swift."
        )
    }

    func testBridgeBoundaryDeclarationsUseBridgeSupportSuffix() throws {
        let violations = try supportSwiftFiles()
            .filter { !isNamedBridgeBoundarySupport($0.lastPathComponent) }
            .flatMap { try sourceTermViolations(in: $0, terms: bridgeBoundaryDeclarations) }
            .sorted()

        XCTAssertEqual(
            violations,
            [],
            "Bridge protocol doubles should live in *BridgeTestSupport.swift."
        )
    }

    func testSnapshotDirectConstructorsStayInventoried() throws {
        for (term, inventory) in snapshotConstructorInventories {
            let actual = try countedTermMatches(in: testSupportSwiftFiles(), term: term)
            XCTAssertEqual(
                actual,
                inventory,
                "Snapshot test data should use shared testFixture helpers, except for inventoried roots."
            )
        }
    }

    private func testSupportSwiftFiles() throws -> [URL] {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        return try FileManager.default.contentsOfDirectory(
            at: testsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    private func supportSwiftFiles() throws -> [URL] {
        try testSupportSwiftFiles()
            .filter { $0.lastPathComponent.hasSuffix("Support.swift") }
    }

    private func sourceTermViolations(in fileURL: URL, terms: [String]) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)

        return lines.enumerated().flatMap { lineOffset, line in
            terms.compactMap { term in
                guard line.contains(term) else {
                    return nil
                }

                return "\(fileURL.lastPathComponent):\(lineOffset + 1): \(term)"
            }
        }
    }

    private func countedTermMatches(in files: [URL], term: String) throws -> [String] {
        try files.compactMap { fileURL in
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let count = exactTermCount(in: contents, term: term)

            guard count > 0 else {
                return nil
            }

            return "\(fileURL.lastPathComponent):\(term):\(count)"
        }
        .sorted()
    }

    private func isNamedCoreBridgeBoundarySupport(_ fileName: String) -> Bool {
        fileName.hasSuffix("BridgeTestSupport.swift") ||
            fileName.hasSuffix("CoreBridgeTestSupport.swift") ||
            fileName.hasSuffix("RealCoreTestSupport.swift")
    }

    private func isNamedBridgeBoundarySupport(_ fileName: String) -> Bool {
        fileName.hasSuffix("BridgeTestSupport.swift") ||
            fileName.hasSuffix("CoreBridgeTestSupport.swift")
    }

    private func isNamedFileSystemBoundarySupport(_ fileName: String) -> Bool {
        fileName.hasSuffix("FileSystemTestSupport.swift") ||
            fileName.hasSuffix("RealCoreTestSupport.swift") ||
            fileName.hasSuffix("RuntimeTestSupport.swift")
    }
}
