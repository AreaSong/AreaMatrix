@testable import AreaMatrix
import XCTest

final class ImportFolderPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testImportFolderEntryCancelAndImportRoutesThroughImportProgressProgressAndResult() async throws {
        let folderURL = try makeImportFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let announcer = ImportSingleFileRecordingAccessibilityAnnouncer()
        let model = OnboardingModel(
            settingsReader: ImportSingleFileStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: ImportSingleFileStaticRepositoryOpener(opening: opening),
            accessibilityAnnouncer: announcer,
            helpOpener: ImportSingleFileNoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [folderURL],
            destination: .category("finance")
        )
        XCTAssertEqual(model.pendingImportEntry?.kind, .folder)
        XCTAssertEqual(model.pendingImportEntry?.destination, .category("finance"))

        model.dismissImportEntry()
        XCTAssertNil(model.pendingImportEntry)

        model.startImportEntry(opening: opening, source: .dropZone, urls: [folderURL])
        model.updateImportEntryProgress(ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: 2,
            remaining: 2,
            currentPath: "finance/invoice.pdf"
        ))

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: "finance/invoice.pdf",
            status: .running,
            completed: 0,
            failed: 0,
            remaining: 2
        )))

        await model.finishImportEntry(
            repoPath: opening.config.repoPath,
            entry: .importSingleFileFixture(currentName: "invoice.pdf", category: "finance")
        )

        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：invoice.pdf")
        XCTAssertEqual(announcer.announcements, ["已导入：invoice.pdf"])
    }

    @MainActor
    func testImportFolderPageIntegrationUsesClassifyPreviewCoreImportCopyFileCoreAndImportIndexFileCoreWithoutControlMapOutOfScopeCalls() async {
        let copyURL = URL(fileURLWithPath: "/tmp/client-a/invoice.pdf")
        let indexURL = URL(fileURLWithPath: "/tmp/client-a/reference.pdf")
        let scanner = importFolderStaticScanner(urls: [copyURL, indexURL])
        let predictor = ImportFolderMappedPredictor(resultsByFilename: [
            "invoice.pdf": .success(.importFolderPrediction(category: "finance", suggestedName: "invoice-2026.pdf")),
            "reference.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "reference-index.pdf"))
        ])
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: ImportSingleFileRecordingErrorMapper(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: scanner
        )
        let request = importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a"), destination: .category("docs"))

        await model.load(request: request)
        XCTAssertEqual(model.selectedDestination, .category("docs"))
        XCTAssertEqual(model.targetRelativePath(for: model.rows[0]), "docs/invoice-2026.pdf")

        _ = await model.importReadyFiles()
        await model.load(request: request)
        model.selectedStorageMode = .indexOnly
        _ = await model.importReadyFiles()

        let predictRequests = await predictor.recordedRequests()
        let importRequests = await importer.recordedRequests()

        XCTAssertEqual(Set(predictRequests.map(\.filename)), ["invoice.pdf", "reference.pdf"])
        XCTAssertEqual(importRequests, importFolderExpectedCopyAndIndexRequests())
    }

    @MainActor
    func testImportFolderScanErrorsAndICloudPlaceholdersBlockOrSummarizeWithoutSilentImport() async {
        let readyURL = URL(fileURLWithPath: "/tmp/client-a/ready.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/client-a/cloud.pdf.icloud")
        let scanner = importFolderScanErrorScanner(readyURL: readyURL, cloudURL: cloudURL)
        let predictor = ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction())])
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: ImportSingleFileRecordingErrorMapper(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        XCTAssertEqual(model.importDisabledReason, "预扫描存在错误，请先 Retry scan 或 Cancel")
        let blockedOutcome = await model.importReadyFiles()
        let blockedRequests = await importer.recordedRequests()
        XCTAssertNil(blockedOutcome)
        XCTAssertEqual(blockedRequests, [])

        let cleanScanner = importFolderCleanPlaceholderScanner(readyURL: readyURL, cloudURL: cloudURL)
        let cleanModel = ImportFolderPreviewModel(
            predictor: ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction())]),
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: ImportSingleFileRecordingErrorMapper(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: cleanScanner
        )

        await cleanModel.load(request: importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        let outcome = await cleanModel.importReadyFiles()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "folder summary"), ImportBatchProgressSnapshot(
            completed: 1,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "docs/ready.pdf",
            skipped: 0,
            pending: 1,
            items: [
                ImportBatchProgressSnapshot.Item(
                    fileID: 42,
                    sourcePath: "/tmp/source.pdf",
                    targetPath: "docs/ready.pdf",
                    phase: .done,
                    errorMessage: nil
                )
            ]
        ))
    }
}

final class ImportFolderConflictIntegrationTests: XCTestCase {
    @MainActor
    func testImportFolderPageIntegrationConflictReviewCoversDupNameBlockedAndReplaceConfirmation() async throws {
        let fixture = makeImportFolderConflictReviewFixture()
        let model = fixture.model

        await model.load(request: fixture.request)

        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "NAME", "BLOCKED"])
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        let initialRequests = await fixture.importer.recordedRequests()
        XCTAssertEqual(initialRequests, [])

        applyImportFolderInitialConflictResolutions(model: model, fixture: fixture)
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        try confirmImportFolderReplace(model: model, rowID: fixture.nameURL.path)
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")

        try confirmImportFolderReplace(model: model, rowID: fixture.blockedURL.path)
        let outcome = await model.importReadyFiles()
        let recordedRequests = await fixture.importer.recordedRequests()

        assertImportFolderConflictImportResult(outcome: outcome, recordedRequests: recordedRequests, model: model)
    }

    @MainActor
    func testImportFolderICloudDownloadRetryPreservesStorageModeAndDestination() async {
        let cloudURL = URL(fileURLWithPath: "/tmp/client-a/cloud.pdf.icloud")
        let scanner = ImportFolderSequenceFolderScanner(results: [
            ImportFolderScanResult(
                rows: [
                    ImportFolderPreviewRow.loading(fileURL: cloudURL, rootURL: URL(fileURLWithPath: "/tmp/client-a"))
                        .withStatus(.iCloudPlaceholder(path: cloudURL.path))
                ],
                folderCount: 0,
                skippedRules: [],
                errors: []
            ),
            ImportFolderScanResult(
                rows: [
                    ImportFolderPreviewRow.loading(
                        fileURL: URL(fileURLWithPath: "/tmp/client-a/cloud.pdf"),
                        rootURL: URL(fileURLWithPath: "/tmp/client-a")
                    )
                ],
                folderCount: 0,
                skippedRules: [],
                errors: []
            )
        ])
        let downloader = ImportFolderRecordingICloudDownloader()
        let model = ImportFolderPreviewModel(
            predictor: ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction())]),
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: ImportSingleFileRecordingErrorMapper(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: scanner,
            placeholderDownloader: downloader
        )

        await model.load(request: importFolderFolderRequest(
            rootURL: URL(fileURLWithPath: "/tmp/client-a"),
            destination: .category("finance")
        ))
        model.selectedStorageMode = .indexOnly
        model.selectedDestination = .category("docs")

        let didRetry = await model.downloadICloudPlaceholdersAndRetry()
        let downloadedURLs = await downloader.recordedURLs()

        XCTAssertTrue(didRetry)
        XCTAssertEqual(downloadedURLs, [cloudURL])
        XCTAssertEqual(model.selectedStorageMode, .indexOnly)
        XCTAssertEqual(model.selectedDestination, .category("docs"))
        XCTAssertEqual(model.rows.map(\.status.tag), ["OK"])
    }

    @MainActor
    func testImportFolderFolderFatalImportRoutesToImportProgressPauseWithRetryContextAndPendingRows() async {
        let scenario = makeImportFolderFatalFolderImportScenario()

        await scenario.importModel.load(request: importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        scenario.model.route = .mainList(scenario.opening)
        let outcome = await scenario.importModel.importReadyFiles(controlState: scenario.controlState) { progress in
            scenario.model.updateImportEntryProgress(progress)
        }

        guard case let .importProgress(progress) = scenario.model.route else {
            return XCTFail("Expected import-progress progress route")
        }
        scenario.model.failImportEntry(
            progress: progress.progressSnapshot,
            mapping: ImportProgressFatalFolderErrorMapper.mapping,
            retryContext: outcome?.fatalRetryContext,
            recoveryCheck: .checking
        )
        scenario.controlState.registerQueueContinuation(scenario.importModel)
        let requests = await scenario.importer.recordedRequests()

        XCTAssertEqual(requests.map(\.overrideFilename), ["first.pdf", "second.pdf"])
        XCTAssertEqual(outcome?.fatalRetryContext, importFolderFatalRetryContext(sourcePath: scenario.secondURL.path))
        guard case let .importProgress(pausedState) = scenario.model.route else {
            return XCTFail("Expected import-progress fatal pause route")
        }
        assertImportFolderFatalPause(pausedState)
    }

    @MainActor
    func testImportFolderFailedImportRoutesToImportResultResultInsteadOfFatalPause() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: ImportSingleFileStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: ImportSingleFileRecordingAccessibilityAnnouncer(),
            helpOpener: ImportSingleFileNoopWelcomeHelpOpener()
        )
        let progress = ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "docs/private.pdf"
        )
        let mapping = CoreErrorMappingSnapshot.importSingleFileError(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(progress)
        model.failImportEntry(progress: progress, mapping: mapping)

        if case let .importResult(result) = model.route {
            XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
            XCTAssertEqual(result.items.map(\.status), [.failed])
        } else {
            XCTFail("Expected import-result import result route")
        }
    }
}

@MainActor
private struct ImportFolderConflictReviewFixture {
    let duplicateURL: URL
    let nameURL: URL
    let blockedURL: URL
    let importer: ImportBatchRecordingBatchImporter
    let model: ImportFolderPreviewModel
    let request: ImportEntryRequest
}

@MainActor
private func makeImportFolderConflictReviewFixture() -> ImportFolderConflictReviewFixture {
    let duplicateURL = URL(fileURLWithPath: "/tmp/client-a/dup.pdf")
    let nameURL = URL(fileURLWithPath: "/tmp/client-a/name.pdf")
    let blockedURL = URL(fileURLWithPath: "/tmp/client-a/private.pdf")
    let scanner = importFolderStaticScanner(urls: [duplicateURL, nameURL, blockedURL])
    let prechecker = ImportFolderStaticConflictPrechecker(results: [
        duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf"),
        nameURL.path: .nameConflict(existingPath: "docs/name.pdf"),
        blockedURL.path: .blocked("Conflict precheck failed: permission denied")
    ])
    let importer = ImportBatchRecordingBatchImporter()
    let model = ImportFolderPreviewModel(
        predictor: importFolderConflictReviewPredictor(),
        importer: importer,
        errorMapper: ImportSingleFileRecordingErrorMapper(),
        conflictPrechecker: prechecker,
        scanner: scanner
    )
    let request = importFolderFolderRequest(
        rootURL: URL(fileURLWithPath: "/tmp/client-a"),
        allowReplaceDuringImport: true
    )
    return ImportFolderConflictReviewFixture(
        duplicateURL: duplicateURL,
        nameURL: nameURL,
        blockedURL: blockedURL,
        importer: importer,
        model: model,
        request: request
    )
}

private func importFolderConflictReviewPredictor() -> ImportFolderMappedPredictor {
    ImportFolderMappedPredictor(resultsByFilename: [
        "dup.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "dup.pdf")),
        "name.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "name.pdf")),
        "private.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "private.pdf"))
    ])
}

@MainActor
private func applyImportFolderInitialConflictResolutions(
    model: ImportFolderPreviewModel,
    fixture: ImportFolderConflictReviewFixture
) {
    model.setRowStatus(.skippedDuplicate(existingPath: "docs/existing-dup.pdf"), for: fixture.duplicateURL.path)
    model.updateNameConflictResolution(for: fixture.nameURL.path, resolution: .replace(isConfirmed: false))
    model.setRowStatus(.nameConflict(
        existingPath: "docs/name.pdf",
        resolution: .replace(isConfirmed: false)
    ), for: fixture.blockedURL.path)
}

@MainActor
private func confirmImportFolderReplace(model: ImportFolderPreviewModel, rowID: String) throws {
    let context: SingleFileReplaceConfirmationContext = try XCTUnwrap(
        model.beginReplaceConfirmation(for: rowID)
    )
    model.applyReplaceConfirmation(for: rowID, decision: context.decision(understandsReplace: true))
}

@MainActor
private func assertImportFolderConflictImportResult(
    outcome: ImportBatchImportResult?,
    recordedRequests: [ImportBatchBatchImportRequest],
    model: ImportFolderPreviewModel
) {
    XCTAssertEqual(recordedRequests, [
        ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "name.pdf",
            duplicateStrategy: .overwrite
        ),
        ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "private.pdf",
            duplicateStrategy: .overwrite
        )
    ])
    XCTAssertEqual(outcome?.succeededEntries.count, 2)
    XCTAssertEqual(outcome?.skippedDuplicateCount, 1)
    XCTAssertEqual(model.rows.map(\.status.tag), ["SKIPPED", "IMPORTED", "IMPORTED"])
}

@MainActor
private struct ImportFolderFatalFolderImportScenario {
    let secondURL: URL
    let importer: ImportBatchSequenceBatchImporter
    let importModel: ImportFolderPreviewModel
    let opening: RepositoryOpeningResult
    let controlState: ImportProgressControlState
    let model: OnboardingModel
}

@MainActor
private func makeImportFolderFatalFolderImportScenario() -> ImportFolderFatalFolderImportScenario {
    let urls = [
        URL(fileURLWithPath: "/tmp/client-a/first.pdf"),
        URL(fileURLWithPath: "/tmp/client-a/second.pdf"),
        URL(fileURLWithPath: "/tmp/client-a/third.pdf")
    ]
    let importer = ImportBatchSequenceBatchImporter(results: [
        .success(.importSingleFileFixture(currentName: "first.pdf", category: "docs")),
        .failure(CoreError.Io(message: "staging write failed")),
        .success(.importSingleFileFixture(currentName: "third.pdf", category: "docs"))
    ])
    let importModel = ImportFolderPreviewModel(
        predictor: importFolderFatalFolderPredictor(),
        importer: importer,
        errorMapper: ImportProgressFatalFolderErrorMapper(),
        conflictPrechecker: ImportFolderNoopConflictPrechecker(),
        scanner: importFolderStaticScanner(urls: urls)
    )
    let controlState = ImportProgressControlState()
    let model = OnboardingModel(
        settingsReader: ImportSingleFileStaticSettingsReader(repoPath: nil),
        importProgressControlState: controlState,
        accessibilityAnnouncer: ImportSingleFileRecordingAccessibilityAnnouncer(),
        helpOpener: ImportSingleFileNoopWelcomeHelpOpener()
    )
    return ImportFolderFatalFolderImportScenario(
        secondURL: urls[1],
        importer: importer,
        importModel: importModel,
        opening: .importSingleFileFixture(repoPath: "/tmp/repo"),
        controlState: controlState,
        model: model
    )
}

private func importFolderFatalFolderPredictor() -> ImportFolderMappedPredictor {
    ImportFolderMappedPredictor(resultsByFilename: [
        "first.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "first.pdf")),
        "second.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "second.pdf")),
        "third.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "third.pdf"))
    ])
}

private func importFolderExpectedCopyAndIndexRequests() -> [ImportBatchBatchImportRequest] {
    [
        importFolderExpectedImportRequest(storageMode: .copy, overrideFilename: "invoice-2026.pdf"),
        importFolderExpectedImportRequest(storageMode: .copy, overrideFilename: "reference-index.pdf"),
        importFolderExpectedImportRequest(storageMode: .indexOnly, overrideFilename: "invoice-2026.pdf"),
        importFolderExpectedImportRequest(storageMode: .indexOnly, overrideFilename: "reference-index.pdf")
    ]
}

private func importFolderExpectedImportRequest(
    storageMode: ImportSingleFileStorageMode,
    overrideFilename: String
) -> ImportBatchBatchImportRequest {
    ImportBatchBatchImportRequest(
        storageMode: storageMode,
        destination: .category("docs"),
        suggestedCategory: "docs",
        overrideFilename: overrideFilename,
        duplicateStrategy: .ask
    )
}

private func importFolderFatalRetryContext(sourcePath: String) -> ImportProgressRetryContext {
    ImportProgressRetryContext(
        repoPath: "/tmp/repo",
        sourcePath: sourcePath,
        storageMode: .copy,
        overrideCategory: "docs",
        overrideFilename: "second.pdf",
        duplicateStrategy: .ask
    )
}

private func assertImportFolderFatalPause(_ pausedState: ImportProgressRouteState) {
    XCTAssertEqual(pausedState.titleText, "导入已暂停")
    XCTAssertEqual(pausedState.items.map(\.phase), [.done, .failed, .pending])
    XCTAssertFalse(pausedState.canRetryCurrentItem)
    XCTAssertEqual(pausedState.retryStatusText, "Checking recovery state...")
}

private struct ImportProgressFatalFolderErrorMapper: CoreErrorMapping {
    static let mapping = CoreErrorMappingSnapshot(
        kind: .io,
        userMessage: "文件读写失败",
        severity: .critical,
        suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
        recoverability: .fatal,
        rawContext: "import-progress folder fatal import progress"
    )

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        Self.mapping
    }
}
