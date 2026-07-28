@testable import AreaMatrix
import XCTest

final class ImportFolderConflictIntegrationTests: XCTestCase {
    @MainActor
    func testImportFolderPageIntegrationConflictReviewCoversDupNameBlockedAndReplaceConfirmation() async throws {
        let fixture = makeImportFolderConflictReviewFixture()
        let model = fixture.model

        await model.load(request: fixture.request)

        assertImportRowStatusTags(model.rows, ["DUP", "NAME", "BLOCKED"])
        assertImportBlockedByUnresolvedConflicts(model.importDisabledReason)
        await fixture.importer.assertImportedBatchFiles([])

        applyImportFolderInitialConflictResolutions(model: model, fixture: fixture)
        assertImportBlockedByUnresolvedConflicts(model.importDisabledReason)
        try confirmImportFolderReplace(model: model, rowID: fixture.nameURL.path)
        assertImportBlockedByUnresolvedConflicts(model.importDisabledReason)

        try confirmImportFolderReplace(model: model, rowID: fixture.blockedURL.path)
        let outcome = await model.importReadyFiles()

        await assertImportFolderConflictImportResult(outcome: outcome, importer: fixture.importer, model: model)
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
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
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

        XCTAssertTrue(didRetry)
        await downloader.assertDownloadedURLs([cloudURL])
        XCTAssertEqual(model.selectedStorageMode, .indexOnly)
        XCTAssertEqual(model.selectedDestination, .category("docs"))
        assertImportRowStatusTags(model.rows, ["OK"])
    }

    @MainActor
    func testImportFolderFolderFatalImportRoutesToImportProgressPauseWithRetryContextAndPendingRows() async {
        let scenario = makeImportFolderFatalFolderImportScenario()

        await scenario.importModel
            .load(request: importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        let outcome = await scenario.importModel.importReadyFiles(controlState: scenario.controlState) { progress in
            scenario.model.updateImportEntryProgress(progress)
        }

        guard let progress = requireImportProgressRoute(
            scenario.model,
            message: "Expected import-progress progress route"
        ) else { return }
        scenario.model.failImportEntry(
            progress: progress.progressSnapshot,
            mapping: .importProgressFatalFolderError,
            retryContext: outcome?.fatalRetryContext,
            recoveryCheck: .checking
        )
        scenario.controlState.registerQueueContinuation(scenario.importModel)
        await scenario.importer.assertImportedOverrideFilenames(["first.pdf", "second.pdf"])
        assertImportProgressRetryContext(
            outcome?.fatalRetryContext,
            equals: importFolderFatalRetryContext(sourcePath: scenario.secondURL.path)
        )
        XCTAssertNotNil(outcome?.fatalRetryContext?.traceID)
        XCTAssertNotNil(outcome?.fatalRetryContext?.operationID)
        guard let pausedState = requireImportProgressRoute(
            scenario.model,
            message: "Expected import-progress fatal pause route"
        ) else { return }
        assertImportFolderFatalPause(pausedState)
    }

    @MainActor
    func testFolderRetrySourceRetainedContinuesQueueAndShowsDegradedResult() async {
        var sourceRetainedEntry = FileEntrySnapshot.importSingleFileFixture(
            currentName: "second.pdf",
            category: "docs"
        )
        sourceRetainedEntry.importCommitState = .sourceRetained
        let scenario = makeImportFolderFatalFolderImportScenario(
            retryResults: [.success(sourceRetainedEntry)]
        )

        await scenario.importModel.load(
            request: importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a"))
        )
        let outcome = await scenario.importModel.importReadyFiles(controlState: scenario.controlState) { progress in
            scenario.model.updateImportEntryProgress(progress)
        }
        guard let progress = requireImportProgressRoute(scenario.model) else { return }
        scenario.model.failImportEntry(
            progress: progress.progressSnapshot,
            mapping: .importProgressFatalFolderError,
            retryContext: outcome?.fatalRetryContext,
            recoveryCheck: .retryAllowed(nil)
        )
        scenario.controlState.registerQueueContinuation(scenario.importModel)

        await scenario.model.retryCurrentImportProgressItem()

        guard let result = requireImportResultRoute(scenario.model) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 3, failed 0, stopped 0, pending 0.",
            statuses: [.imported, .sourceRetained, .imported]
        )
        XCTAssertEqual(scenario.importModel.rows[1].importCommitState, .sourceRetained)
    }

    @MainActor
    func testImportFolderFailedImportRoutesToImportResultResultInsteadOfFatalPause() {
        let model = makeImportResultMainListFixture().model
        let progress = importBatchProgress(
            completed: 1,
            failed: 1,
            total: 2,
            currentPath: "docs/private.pdf"
        )
        let mapping = CoreErrorMappingSnapshot.importSingleFileError(kind: .permissionDenied)

        model.updateImportEntryProgress(progress)
        model.failImportEntry(progress: progress, mapping: mapping)

        guard let result = requireImportResultRoute(
            model,
            message: "Expected import-result import result route"
        ) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 1, stopped 0, pending 0.",
            statuses: [.failed]
        )
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
        blockedURL.path: .blocked(L10n.verbatim(
            "Conflict precheck failed: permission denied",
            reason: .technicalDetail
        ))
    ])
    let importer = ImportBatchRecordingBatchImporter()
    let model = ImportFolderPreviewModel(
        predictor: importFolderConflictReviewPredictor(),
        importer: importer,
        errorMapper: RecordingCoreErrorMapper.importSingleFile(),
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
    importer: ImportBatchRecordingBatchImporter,
    model: ImportFolderPreviewModel
) async {
    await importer.assertImportedBatchFiles([
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
    assertImportRowStatusTags(model.rows, ["SKIPPED", "IMPORTED", "IMPORTED"])
}

@MainActor
private struct ImportFolderFatalFolderImportScenario {
    let secondURL: URL
    let importer: ImportBatchSequenceBatchImporter
    let retryImporter: ImportSingleFileRecordingImporter
    let importModel: ImportFolderPreviewModel
    let controlState: ImportProgressControlState
    let model: OnboardingModel
}

@MainActor
private func makeImportFolderFatalFolderImportScenario(
    retryResults: [Result<FileEntrySnapshot, Error>]? = nil
) -> ImportFolderFatalFolderImportScenario {
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
        errorMapper: StaticCoreErrorMapper(mapping: .importProgressFatalFolderError),
        conflictPrechecker: ImportFolderNoopConflictPrechecker(),
        scanner: importFolderStaticScanner(urls: urls)
    )
    let controlState = ImportProgressControlState()
    let retryImporter = ImportSingleFileRecordingImporter(results: retryResults)
    let fixture = makeImportProgressMainListFixture(
        importProgressImporter: retryImporter,
        importProgressControlState: controlState
    )
    return ImportFolderFatalFolderImportScenario(
        secondURL: urls[1],
        importer: importer,
        retryImporter: retryImporter,
        importModel: importModel,
        controlState: controlState,
        model: fixture.model
    )
}

private func importFolderFatalFolderPredictor() -> ImportFolderMappedPredictor {
    ImportFolderMappedPredictor(resultsByFilename: [
        "first.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "first.pdf")),
        "second.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "second.pdf")),
        "third.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "third.pdf"))
    ])
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
    XCTAssertEqual(pausedState.titleText, "Import Paused")
    XCTAssertEqual(pausedState.items.map(\.phase), [.done, .failed, .pending])
    assertImportProgressRecoveryCheckPending(pausedState)
}

private extension CoreErrorMappingSnapshot {
    static var importProgressFatalFolderError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "import-progress folder fatal import progress"
        )
    }
}
