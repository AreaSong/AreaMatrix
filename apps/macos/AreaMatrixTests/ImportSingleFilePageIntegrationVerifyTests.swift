import XCTest
@testable import AreaMatrix

final class ImportSingleFilePageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS117EntryCancelAndImportRoutesThroughS120Progress() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let announcer = S117RecordingAccessibilityAnnouncer()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: S117StaticRepositoryOpener(opening: opening),
            accessibilityAnnouncer: announcer,
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainEmpty(opening)
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

        let imported = FileEntrySnapshot.s117Fixture(currentName: "source.pdf", category: "docs")
        await model.finishImportEntry(repoPath: opening.config.repoPath, entry: imported)

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：source.pdf")
        XCTAssertEqual(announcer.announcements, ["已导入：source.pdf"])
    }

    @MainActor
    func testS117FailedImportRoutesThroughS121ResultSummary() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(currentPath: "docs/source.pdf")
        model.failImportEntry(currentPath: "docs/source.pdf", mapping: .s117Error(kind: .duplicateFile))

        guard case .importResult(let result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 0, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.failed])
    }

    @MainActor
    func testS117DockOpenFileQueuesSingleFileImportWhenRepositoryIsOpen() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.handleDockOpenFiles([sourceURL])

        XCTAssertEqual(model.pendingImportEntry?.source, .dockOpenFile)
        XCTAssertEqual(model.pendingImportEntry?.urls, [sourceURL])
        XCTAssertEqual(model.pendingImportEntry?.availableCategories, ["inbox", "docs", "finance"])
    }

    @MainActor
    func testS117SwitchLocalRepoClosesSheetAndEntersChoosePathFlow() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.startImportEntry(opening: opening, source: .filePicker, urls: [sourceURL])
        model.switchImportEntryToLocalRepository()

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .choosePath)
    }

    @MainActor
    func testS117ImportEntryCarriesRealRepositoryCategoriesForEditableSelection() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.startImportEntry(
            opening: opening,
            source: .filePicker,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")]
        )

        XCTAssertEqual(model.pendingImportEntry?.availableCategories, ["inbox", "docs", "finance"])
    }

    @MainActor
    func testS117PredictionThenCopyMoveAndIndexOnlyUseTheExpectedCoreCapabilities() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
        )
        let predictor = S117RecordingPredictor(result: ClassifyResultSnapshot(
            category: "docs",
            suggestedName: "2026Q1_合同.pdf",
            reason: .keyword,
            confidence: 0.93
        ))
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: request)
        let predictRequests = await predictor.recordedRequests()
        XCTAssertEqual(predictRequests, [
            S117PredictRequest(repoPath: "/tmp/repo", filename: "合同.pdf"),
        ])
        XCTAssertEqual(model.selectedCategory, "docs")
        XCTAssertEqual(model.suggestedName, "2026Q1_合同.pdf")
        XCTAssertEqual(model.selectedStorageMode, .copy)

        model.selectedCategory = " finance "
        model.suggestedName = " copy.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        let copied = await model.importSelectedFile()
        XCTAssertEqual(copied?.storageMode, "Copied")

        await model.load(request: request)
        model.selectedCategory = " finance "
        model.selectedStorageMode = .move
        model.suggestedName = " move.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        let moved = await model.importSelectedFile()
        XCTAssertEqual(moved?.storageMode, "Moved")

        await model.load(request: request)
        model.selectedCategory = " finance "
        model.selectedStorageMode = .indexOnly
        model.suggestedName = " indexed.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        let indexed = await model.importSelectedFile()
        XCTAssertEqual(indexed?.storageMode, "Indexed")

        let importRequests = await importer.recordedRequests()
        XCTAssertEqual(importRequests, [
            S117ImportRequest(mode: .copy, overrideCategory: "finance", overrideFilename: "copy.pdf", duplicateStrategy: .ask),
            S117ImportRequest(mode: .move, overrideCategory: "finance", overrideFilename: "move.pdf", duplicateStrategy: .ask),
            S117ImportRequest(mode: .indexOnly, overrideCategory: "finance", overrideFilename: "indexed.pdf", duplicateStrategy: .ask),
        ])
    }

    @MainActor
    func testS117ImportStaysDisabledWhileImportingAndAfterSuccess() async {
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile
        )
        let gate = S117ImportGate()
        let importer = S117SuspendingImporter(gate: gate)
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: S117RecordingErrorMapper()
        )

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
    func testS122ImportFileDuplicateErrorOpensDuplicateConflictPage() async {
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile
        )
        let errorMapper = S117RecordingErrorMapper()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117FailingImporter(error: CoreError.DuplicateFile(existingPath: "docs/source.pdf")),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: errorMapper
        )

        await model.load(request: request)
        let imported = await model.importSelectedFile()

        XCTAssertNil(imported)
        let mappedErrors = await errorMapper.recordedErrors()
        XCTAssertEqual(mappedErrors, [])
        XCTAssertEqual(model.activeConflictPage, .duplicate)
        XCTAssertEqual(model.importStatus, .idle)
        XCTAssertEqual(model.currentPreflightResult?.conflict, .duplicate(existingPath: "docs/source.pdf"))
        XCTAssertNil(model.currentPreflightResult?.keepBothTargetRelativePath)
        XCTAssertEqual(model.duplicateResolution, .skip)
        XCTAssertNil(model.importDisabledReason)
    }

    @MainActor
    func testS122DuplicateDefaultsToSkipWithoutEnteringAdjacentPages() async {
        let hidden = ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .duplicate(existingPath: "docs/source.pdf")
        )
        let importer = S117RecordingImporter()

        let hiddenModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: hidden),
            errorMapper: S117RecordingErrorMapper()
        )

        await hiddenModel.load(request: .s117ImportRequest())
        let skipped = await hiddenModel.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(hiddenModel.activeConflictPage, .duplicate)
        XCTAssertEqual(hiddenModel.duplicateResolution, .skip)
        XCTAssertNil(skipped)
        XCTAssertEqual(hiddenModel.importStatus, .skippedDuplicate("docs/source.pdf"))
        XCTAssertEqual(hiddenModel.importDisabledReason, "重复文件已跳过")
        XCTAssertEqual(requests, [])
    }

    @MainActor
    func testS117ICloudPlaceholderKeepsSheetBlockedWithDownloadActions() async {
        let result = ImportSingleFilePreflightResult(
            sourceSizeBytes: nil,
            hashSha256: nil,
            targetRelativePath: "docs/source.pdf",
            conflict: .iCloudPlaceholder(path: "/tmp/source.pdf")
        )
        let importer = S117RecordingImporter()
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: result),
            placeholderDownloader: ImportSingleFileStaticICloudDownloader(),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .s117ImportRequest())
        let imported = await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertNil(imported)
        XCTAssertTrue(model.showsICloudActions)
        XCTAssertNil(model.activeConflictPage)
        XCTAssertEqual(model.importDisabledReason, "iCloud placeholder 需要下载后才能导入")
        XCTAssertEqual(requests, [])
    }

    @MainActor
    func testS117ICloudDownloadFailureKeepsDownloadAndSwitchActionsVisible() async {
        let result = ImportSingleFilePreflightResult(
            sourceSizeBytes: nil,
            hashSha256: nil,
            targetRelativePath: "docs/source.pdf",
            conflict: .iCloudPlaceholder(path: "/tmp/source.pdf")
        )
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: result),
            placeholderDownloader: ImportSingleFileStaticICloudDownloader(
                error: ImportSingleFileStaticLocalizedError(message: "download timed out")
            ),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: .s117ImportRequest())
        await model.downloadICloudPlaceholderAndRetry()

        XCTAssertTrue(model.showsICloudActions)
        XCTAssertFalse(model.showsRetryPreviewAction)
        XCTAssertNil(model.activeConflictPage)
        XCTAssertEqual(model.importDisabledReason, "iCloud 下载失败后请重试下载或切换本地资料库")
        guard case .iCloudDownloadFailed(let path, let reason) = model.currentPreflightResult?.conflict else {
            return XCTFail("Expected iCloud download failure to stay on S1-17 recovery state")
        }
        XCTAssertEqual(path, "/tmp/source.pdf")
        XCTAssertEqual(reason, "download timed out")
    }

    @MainActor
    func testS122RealCorePreImportDuplicateRendersPageAndSkipDoesNotWrite() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s122-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s122-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
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
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: bridge,
            preflight: CoreImportSingleFilePreflight(),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: ImportEntryRequest(
            repoPath: repoURL.path,
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
        ))

        XCTAssertEqual(model.currentPreflightResult?.hashSha256, "41cf6794ba4200b839c53531555f0f3998df4cbb01a4d5cb0b94e3ca5e23947d")
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
    func testS122RealCoreKeepBothPreviewMatchesFinalNumberedImport() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s122-keepboth-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s122-keepboth-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
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

        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: bridge,
            preflight: CoreImportSingleFilePreflight(),
            errorMapper: S117RecordingErrorMapper()
        )
        await model.load(request: ImportEntryRequest(
            repoPath: repoURL.path,
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
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
    func testS117FileMetadataAndFilenameValidationMatchPageSpec() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s117-metadata")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("合同.pdf")
        try Data("abc".utf8).write(to: sourceURL)
        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight.ready(targetRelativePath: "docs/合同.pdf"),
            errorMapper: S117RecordingErrorMapper()
        )

        await model.load(request: ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
        ))

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
