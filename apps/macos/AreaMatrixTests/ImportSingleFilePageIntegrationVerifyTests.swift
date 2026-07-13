@testable import AreaMatrix
import XCTest

final class SingleFileImportIntegrationTests: XCTestCase {
    @MainActor
    func testImportSingleFileEntryCancelAndImportRoutesThroughImportProgressProgress() async {
        let sourceURL = importSingleFileSourceURL()
        let fixture = makeImportSingleFileMainEmptyFixture()
        let opening = fixture.opening
        let model = fixture.model
        let announcer = fixture.accessibilityAnnouncer

        model.startImportEntry(opening: opening, source: .dropZone, urls: [sourceURL])
        XCTAssertEqual(model.pendingImportEntry?.kind, .singleFile)

        model.dismissImportEntry()
        XCTAssertNil(model.pendingImportEntry)

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [sourceURL],
            destination: .category("docs")
        )
        model.beginImportEntryProgress(currentPath: "docs/source.pdf")

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: "docs/source.pdf"
        )))
        XCTAssertNil(model.toastMessage)

        let imported = FileEntrySnapshot.importSingleFileFixture(currentName: "source.pdf", category: "docs")
        await model.finishImportEntry(repoPath: opening.config.repoPath, entry: imported)

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：source.pdf")
        announcer.assertAnnouncements(["已导入：source.pdf"])
    }

    @MainActor
    func testImportSingleFileFailedImportRoutesThroughImportResultResultSummary() {
        let fixture = makeImportSingleFileMainListFixture()
        let model = fixture.model

        model.beginImportEntryProgress(currentPath: "docs/source.pdf")
        model.failImportEntry(currentPath: "docs/source.pdf", mapping: .importSingleFileError(kind: .duplicateFile))

        guard let result = requireImportResultRoute(
            model,
            message: "Expected import-result import result route"
        ) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 0, failed 1, stopped 0, pending 0.",
            statuses: [.failed]
        )
    }

    @MainActor
    func testImportSingleFileRetryProgressUsesInjectedRepositoryFinderAvailability() {
        let fixture = makeImportSingleFileMainListFixture(
            systemCapabilityChecker: StaticOnboardingSystemCapabilityChecker(
                repositoryFinderAvailabilityByPath: [importSingleFileRepoPath(): false]
            )
        )
        let model = fixture.model

        model.beginImportEntryProgress(
            currentPath: "docs/source.pdf",
            retryContext: ImportProgressRetryContext(
                repoPath: importSingleFileRepoPath(),
                sourcePath: importSingleFileSourcePath(),
                storageMode: .copy,
                overrideCategory: "docs",
                overrideFilename: "source.pdf",
                duplicateStrategy: .ask
            )
        )

        XCTAssertEqual(model.currentImportProgressState?.isRepositoryFinderAvailable, false)
    }

    @MainActor
    func testImportSingleFileDockOpenFileQueuesSingleFileImportWhenRepositoryIsOpen() {
        let fixture = makeImportSingleFileMainListFixture()
        let model = fixture.model
        let sourceURL = importSingleFileSourceURL()

        model.handleDockOpenFiles([sourceURL])

        XCTAssertEqual(model.pendingImportEntry?.source, .dockOpenFile)
        XCTAssertEqual(model.pendingImportEntry?.urls, [sourceURL])
        XCTAssertEqual(model.pendingImportEntry?.availableCategories, ["inbox", "docs", "finance"])
    }

    @MainActor
    func testImportSingleFileSwitchLocalRepoClosesSheetAndEntersChoosePathFlow() {
        let sourceURL = importSingleFileSourceURL()
        let fixture = makeImportSingleFileMainEmptyFixture()
        let opening = fixture.opening
        let model = fixture.model

        model.startImportEntry(opening: opening, source: .filePicker, urls: [sourceURL])
        model.switchImportEntryToLocalRepository()

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .choosePath)
    }

    @MainActor
    func testImportSingleFileImportEntryCarriesRealRepositoryCategoriesForEditableSelection() {
        let fixture = makeImportSingleFileMainListFixture()
        let opening = fixture.opening
        let model = fixture.model

        model.startImportEntry(
            opening: opening,
            source: .filePicker,
            urls: [importSingleFileSourceURL()]
        )

        XCTAssertEqual(model.pendingImportEntry?.availableCategories, ["inbox", "docs", "finance"])
    }

    @MainActor
    func testImportSingleFilePredictionThenCopyMoveAndIndexOnlyUseTheExpectedCoreCapabilities() async {
        let request = importSingleFileCoreCapabilityRequest()
        let predictor = ImportSingleFileRecordingPredictor(result: importSingleFileCoreCapabilityPrediction())
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer
        )

        await model.load(request: request)
        await predictor.assertCategoryPredictionRequests([
            ImportSingleFilePredictRequest(repoPath: importSingleFileRepoPath(), filename: "合同.pdf")
        ])
        XCTAssertEqual(model.selectedCategory, "docs")
        XCTAssertEqual(model.suggestedName, "2026Q1_合同.pdf")
        XCTAssertEqual(model.selectedStorageMode, .copy)

        await importImportSingleFileMode(
            model: model,
            request: request,
            mode: .copy,
            name: "copy.pdf",
            storageMode: "Copied"
        )
        await importImportSingleFileMode(
            model: model,
            request: request,
            mode: .move,
            name: "move.pdf",
            storageMode: "Moved"
        )
        await importImportSingleFileMode(
            model: model,
            request: request,
            mode: .indexOnly,
            name: "indexed.pdf",
            storageMode: "Indexed"
        )

        await importer.assertImportedFiles(importSingleFileCoreCapabilityImportRequests())
    }

    @MainActor
    func testImportSingleFileImportStaysDisabledWhileImportingAndAfterSuccess() async {
        let request = ImportEntryRequest.importSingleFileImportRequest()
        let gate = ImportSingleFileImportGate()
        let importer = ImportSingleFileSuspendingImporter(gate: gate)
        let model = makeImportSingleFilePreviewModel(importer: importer)

        await model.load(request: request)
        let importTask = Task { @MainActor in
            await model.importSelectedFile()
        }
        await gate.waitUntilStarted()

        XCTAssertEqual(model.importDisabledReason, "正在复制导入")

        await gate.finish()
        let imported = await importTask.value

        XCTAssertEqual(imported?.currentName, "source.pdf")
        XCTAssertEqual(model.importDisabledReason, "文件已导入")
    }

    @MainActor
    func testDuplicateConflictImportFileDuplicateErrorOpensDuplicateConflictPage() async {
        let request = ImportEntryRequest.importSingleFileImportRequest()
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = makeImportSingleFilePreviewModel(
            importer: ImportSingleFileFailingImporter(error: CoreError.DuplicateFile(existingPath: "docs/source.pdf")),
            errorMapper: errorMapper
        )

        await model.load(request: request)
        let imported = await model.importSelectedFile()

        XCTAssertNil(imported)
        await errorMapper.assertMappedCoreErrors([])
        XCTAssertEqual(model.activeConflictPage, .duplicate)
        XCTAssertEqual(model.importStatus, .idle)
        XCTAssertEqual(model.currentPreflightResult?.conflict, .duplicate(existingPath: "docs/source.pdf"))
        XCTAssertNil(model.currentPreflightResult?.keepBothTargetRelativePath)
        XCTAssertEqual(model.duplicateResolution, .skip)
        assertImportEnabled(model.importDisabledReason)
    }

    @MainActor
    func testDuplicateConflictDuplicateDefaultsToSkipWithoutEnteringAdjacentPages() async {
        let hidden = ImportSingleFilePreflightResult.importHiddenDuplicateFixture()
        let importer = ImportSingleFileRecordingImporter()
        let hiddenModel = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: hidden)
        )

        await hiddenModel.load(request: .importSingleFileImportRequest())
        let skipped = await hiddenModel.importSelectedFile()

        XCTAssertEqual(hiddenModel.activeConflictPage, .duplicate)
        XCTAssertEqual(hiddenModel.duplicateResolution, .skip)
        XCTAssertNil(skipped)
        XCTAssertEqual(hiddenModel.importStatus, .skippedDuplicate("docs/source.pdf"))
        XCTAssertEqual(hiddenModel.importDisabledReason, "重复文件已跳过")
        await importer.assertNoImportedFiles()
    }
}

final class SingleFileImportRecoveryIntegrationTests: XCTestCase {
    @MainActor
    func testImportSingleFileICloudPlaceholderKeepsSheetBlockedWithDownloadActions() async {
        let result = ImportSingleFilePreflightResult.importICloudPlaceholderFixture()
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportSingleFilePreviewModel(
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: result)
        )

        await model.load(request: .importSingleFileImportRequest())
        let imported = await model.importSelectedFile()

        XCTAssertNil(imported)
        assertImportSingleFileICloudPlaceholderBlocked(model)
        await importer.assertNoImportedFiles()
    }

    @MainActor
    func testImportSingleFileICloudDownloadFailureKeepsDownloadAndSwitchActionsVisible() async {
        let result = ImportSingleFilePreflightResult.importICloudPlaceholderFixture()
        let model = makeImportSingleFilePreviewModel(
            preflight: ImportSingleFileStaticPreflight(result: result),
            placeholderDownloader: ImportSingleFileStaticICloudDownloader(
                error: ImportSingleFileStaticLocalizedError(message: "download timed out")
            )
        )

        await model.load(request: .importSingleFileImportRequest())
        await model.downloadICloudPlaceholderAndRetry()

        assertImportSingleFileICloudDownloadFailure(model, reason: "download timed out")
    }

    @MainActor
    func testDuplicateConflictRealCorePreImportDuplicateRendersPageAndSkipDoesNotWrite() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "duplicateConflict-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "duplicateConflict-source")
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        try Data("source".utf8).write(to: existingURL)
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("source".utf8).write(to: sourceURL)
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let existing = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: existingURL,
            overrideCategory: "docs",
            overrideFilename: "existing.pdf"
        )
        let model = makeImportSingleFilePreviewModel(
            importer: bridge,
            preflight: CoreImportSingleFilePreflight()
        )

        await model.load(request: .importSingleFileImportRequest(
            repoPath: repoURL.path,
            sourcePath: sourceURL.path
        ))

        XCTAssertEqual(
            model.currentPreflightResult?.hashSha256,
            "41cf6794ba4200b839c53531555f0f3998df4cbb01a4d5cb0b94e3ca5e23947d"
        )
        XCTAssertEqual(model.currentPreflightResult?.conflict, .duplicate(existingPath: existing.path))
        XCTAssertEqual(model.currentPreflightResult?.keepBothTargetRelativePath, "docs/source.pdf")
        XCTAssertEqual(model.activeConflictPage, .duplicate)
        XCTAssertEqual(model.importStatus, .idle)

        let skipped = await model.importSelectedFile()
        XCTAssertNil(skipped)
        XCTAssertEqual(model.importStatus, .skippedDuplicate(existing.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        let docsURL = repoURL.appendingPathComponent("docs")
        let repoFiles = try FileManager.default.contentsOfDirectory(atPath: docsURL.path)
        XCTAssertEqual(repoFiles.sorted(), ["existing.pdf"])
    }

    @MainActor
    func testDuplicateConflictRealCoreKeepBothPreviewMatchesFinalNumberedImport() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "duplicateConflict-keepboth-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "duplicateConflict-keepboth-source")
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("same".utf8).write(to: existingURL)
        try Data("same".utf8).write(to: sourceURL)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        _ = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: existingURL,
            overrideCategory: "docs",
            overrideFilename: "source.pdf"
        )

        let model = makeImportSingleFilePreviewModel(
            importer: bridge,
            preflight: CoreImportSingleFilePreflight()
        )
        await model.load(request: .importSingleFileImportRequest(
            repoPath: repoURL.path,
            sourcePath: sourceURL.path
        ))

        XCTAssertEqual(model.currentPreflightResult?.conflict, .duplicate(existingPath: "docs/source.pdf"))
        XCTAssertEqual(model.currentPreflightResult?.keepBothTargetRelativePath, "docs/source_1.pdf")

        model.updateDuplicateResolution(.keepBoth)
        let imported = await model.importSelectedFile()

        XCTAssertEqual(model.progressCurrentPath, "docs/source_1.pdf")
        XCTAssertEqual(imported?.path, "docs/source_1.pdf")
        XCTAssertEqual(imported?.hashSha256, model.currentPreflightResult?.hashSha256)
    }

    @MainActor
    func testImportSingleFileFileMetadataAndFilenameValidationMatchPageSpec() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "importSingleFile-metadata")
        defer { removeTestTemporaryItems(sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("合同.pdf")
        try Data("abc".utf8).write(to: sourceURL)
        let model = makeImportSingleFilePreviewModel(
            preflight: ImportSingleFileStaticPreflight.ready(targetRelativePath: "docs/合同.pdf")
        )

        await model.load(request: .importSingleFileImportRequest(sourcePath: sourceURL.path))

        XCTAssertEqual(
            model.sourceSizeDescription,
            ByteCountFormatter.string(fromByteCount: 3, countStyle: .file)
        )

        model.suggestedName = "bad/name.pdf"

        XCTAssertEqual(model.filenameValidationMessage, "文件名不能包含 / \\ : * ? \" < > |")
        XCTAssertEqual(model.importDisabledReason, "文件名不能包含 / \\ : * ? \" < > |")
        XCTAssertEqual(
            model.currentPreflightResult?.conflict,
            .invalidFilename("文件名不能包含 / \\ : * ? \" < > |")
        )
        XCTAssertFalse(model.showsConflictSection)
        XCTAssertFalse(model.showsRetryPreviewAction)
    }
}
