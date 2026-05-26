@testable import AreaMatrix
import XCTest

final class ImportFolderPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS119EntryCancelAndImportRoutesThroughS120ProgressAndResult() async throws {
        let folderURL = try makeImportFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let announcer = S117RecordingAccessibilityAnnouncer()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: S117StaticRepositoryOpener(opening: opening),
            accessibilityAnnouncer: announcer,
            helpOpener: S117NoopWelcomeHelpOpener()
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
            entry: .s117Fixture(currentName: "invoice.pdf", category: "finance")
        )

        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：invoice.pdf")
        XCTAssertEqual(announcer.announcements, ["已导入：invoice.pdf"])
    }

    @MainActor
    func testS119PageIntegrationUsesC105C106AndC108WithoutControlMapOutOfScopeCalls() async {
        let copyURL = URL(fileURLWithPath: "/tmp/client-a/invoice.pdf")
        let indexURL = URL(fileURLWithPath: "/tmp/client-a/reference.pdf")
        let scanner = s119StaticScanner(urls: [copyURL, indexURL])
        let predictor = S119MappedPredictor(resultsByFilename: [
            "invoice.pdf": .success(.s119Prediction(category: "finance", suggestedName: "invoice-2026.pdf")),
            "reference.pdf": .success(.s119Prediction(category: "docs", suggestedName: "reference-index.pdf"))
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )
        let request = s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a"), destination: .category("docs"))

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
        XCTAssertEqual(importRequests, s119ExpectedCopyAndIndexRequests())
    }

    @MainActor
    func testS119ScanErrorsAndICloudPlaceholdersBlockOrSummarizeWithoutSilentImport() async {
        let readyURL = URL(fileURLWithPath: "/tmp/client-a/ready.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/client-a/cloud.pdf.icloud")
        let scanner = s119ScanErrorScanner(readyURL: readyURL, cloudURL: cloudURL)
        let predictor = S119RecordingPredictor(results: [.success(.s119Prediction())])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        XCTAssertEqual(model.importDisabledReason, "预扫描存在错误，请先 Retry scan 或 Cancel")
        let blockedOutcome = await model.importReadyFiles()
        let blockedRequests = await importer.recordedRequests()
        XCTAssertNil(blockedOutcome)
        XCTAssertEqual(blockedRequests, [])

        let cleanScanner = s119CleanPlaceholderScanner(readyURL: readyURL, cloudURL: cloudURL)
        let cleanModel = ImportFolderPreviewModel(
            predictor: S119RecordingPredictor(results: [.success(.s119Prediction())]),
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: cleanScanner
        )

        await cleanModel.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
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
                    fileID: 117,
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
    func testS119PageIntegrationConflictReviewCoversDupNameBlockedAndReplaceConfirmation() async throws {
        let fixture = makeS119ConflictReviewFixture()
        let model = fixture.model

        await model.load(request: fixture.request)

        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "NAME", "BLOCKED"])
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        let initialRequests = await fixture.importer.recordedRequests()
        XCTAssertEqual(initialRequests, [])

        applyS119InitialConflictResolutions(model: model, fixture: fixture)
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        try confirmS119Replace(model: model, rowID: fixture.nameURL.path)
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")

        try confirmS119Replace(model: model, rowID: fixture.blockedURL.path)
        let outcome = await model.importReadyFiles()
        let recordedRequests = await fixture.importer.recordedRequests()

        assertS119ConflictImportResult(outcome: outcome, recordedRequests: recordedRequests, model: model)
    }

    @MainActor
    func testS119ICloudDownloadRetryPreservesStorageModeAndDestination() async {
        let cloudURL = URL(fileURLWithPath: "/tmp/client-a/cloud.pdf.icloud")
        let scanner = S119SequenceFolderScanner(results: [
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
        let downloader = S119RecordingICloudDownloader()
        let model = ImportFolderPreviewModel(
            predictor: S119RecordingPredictor(results: [.success(.s119Prediction())]),
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner,
            placeholderDownloader: downloader
        )

        await model.load(request: s119FolderRequest(
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
    func testS119FolderFatalImportRoutesToS120PauseWithRetryContextAndPendingRows() async {
        let scenario = makeS119FatalFolderImportScenario()

        await scenario.importModel.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        scenario.model.route = .mainList(scenario.opening)
        let outcome = await scenario.importModel.importReadyFiles(controlState: scenario.controlState) { progress in
            scenario.model.updateImportEntryProgress(progress)
        }

        guard case let .importProgress(progress) = scenario.model.route else {
            return XCTFail("Expected S1-20 progress route")
        }
        scenario.model.failImportEntry(
            progress: progress.progressSnapshot,
            mapping: S120FatalFolderErrorMapper.mapping,
            retryContext: outcome?.fatalRetryContext,
            recoveryCheck: .checking
        )
        scenario.controlState.registerQueueContinuation(scenario.importModel)
        let requests = await scenario.importer.recordedRequests()

        XCTAssertEqual(requests.map(\.overrideFilename), ["first.pdf", "second.pdf"])
        XCTAssertEqual(outcome?.fatalRetryContext, s119FatalRetryContext(sourcePath: scenario.secondURL.path))
        guard case let .importProgress(pausedState) = scenario.model.route else {
            return XCTFail("Expected S1-20 fatal pause route")
        }
        assertS119FatalPause(pausedState)
    }

    @MainActor
    func testS119FailedImportRoutesToS121ResultInsteadOfFatalPause() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let progress = ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "docs/private.pdf"
        )
        let mapping = CoreErrorMappingSnapshot.s117Error(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(progress)
        model.failImportEntry(progress: progress, mapping: mapping)

        if case let .importResult(result) = model.route {
            XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
            XCTAssertEqual(result.items.map(\.status), [.failed])
        } else {
            XCTFail("Expected S1-21 import result route")
        }
    }
}

@MainActor
private struct S119ConflictReviewFixture {
    let duplicateURL: URL
    let nameURL: URL
    let blockedURL: URL
    let importer: S118RecordingBatchImporter
    let model: ImportFolderPreviewModel
    let request: ImportEntryRequest
}

@MainActor
private func makeS119ConflictReviewFixture() -> S119ConflictReviewFixture {
    let duplicateURL = URL(fileURLWithPath: "/tmp/client-a/dup.pdf")
    let nameURL = URL(fileURLWithPath: "/tmp/client-a/name.pdf")
    let blockedURL = URL(fileURLWithPath: "/tmp/client-a/private.pdf")
    let scanner = s119StaticScanner(urls: [duplicateURL, nameURL, blockedURL])
    let prechecker = S119StaticConflictPrechecker(results: [
        duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf"),
        nameURL.path: .nameConflict(existingPath: "docs/name.pdf"),
        blockedURL.path: .blocked("Conflict precheck failed: permission denied")
    ])
    let importer = S118RecordingBatchImporter()
    let model = ImportFolderPreviewModel(
        predictor: s119ConflictReviewPredictor(),
        importer: importer,
        errorMapper: S117RecordingErrorMapper(),
        conflictPrechecker: prechecker,
        scanner: scanner
    )
    let request = s119FolderRequest(
        rootURL: URL(fileURLWithPath: "/tmp/client-a"),
        allowReplaceDuringImport: true
    )
    return S119ConflictReviewFixture(
        duplicateURL: duplicateURL,
        nameURL: nameURL,
        blockedURL: blockedURL,
        importer: importer,
        model: model,
        request: request
    )
}

private func s119ConflictReviewPredictor() -> S119MappedPredictor {
    S119MappedPredictor(resultsByFilename: [
        "dup.pdf": .success(.s119Prediction(category: "docs", suggestedName: "dup.pdf")),
        "name.pdf": .success(.s119Prediction(category: "docs", suggestedName: "name.pdf")),
        "private.pdf": .success(.s119Prediction(category: "docs", suggestedName: "private.pdf"))
    ])
}

@MainActor
private func applyS119InitialConflictResolutions(
    model: ImportFolderPreviewModel,
    fixture: S119ConflictReviewFixture
) {
    model.setRowStatus(.skippedDuplicate(existingPath: "docs/existing-dup.pdf"), for: fixture.duplicateURL.path)
    model.updateNameConflictResolution(for: fixture.nameURL.path, resolution: .replace(isConfirmed: false))
    model.setRowStatus(.nameConflict(
        existingPath: "docs/name.pdf",
        resolution: .replace(isConfirmed: false)
    ), for: fixture.blockedURL.path)
}

@MainActor
private func confirmS119Replace(model: ImportFolderPreviewModel, rowID: String) throws {
    let context: SingleFileReplaceConfirmationContext = try XCTUnwrap(
        model.beginReplaceConfirmation(for: rowID)
    )
    model.applyReplaceConfirmation(for: rowID, decision: context.decision(understandsReplace: true))
}

@MainActor
private func assertS119ConflictImportResult(
    outcome: ImportBatchImportResult?,
    recordedRequests: [S118BatchImportRequest],
    model: ImportFolderPreviewModel
) {
    XCTAssertEqual(recordedRequests, [
        S118BatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "name.pdf",
            duplicateStrategy: .overwrite
        ),
        S118BatchImportRequest(
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
private struct S119FatalFolderImportScenario {
    let secondURL: URL
    let importer: S118SequenceBatchImporter
    let importModel: ImportFolderPreviewModel
    let opening: RepositoryOpeningResult
    let controlState: ImportProgressControlState
    let model: OnboardingModel
}

@MainActor
private func makeS119FatalFolderImportScenario() -> S119FatalFolderImportScenario {
    let urls = [
        URL(fileURLWithPath: "/tmp/client-a/first.pdf"),
        URL(fileURLWithPath: "/tmp/client-a/second.pdf"),
        URL(fileURLWithPath: "/tmp/client-a/third.pdf")
    ]
    let importer = S118SequenceBatchImporter(results: [
        .success(.s117Fixture(currentName: "first.pdf", category: "docs")),
        .failure(CoreError.Io(message: "staging write failed")),
        .success(.s117Fixture(currentName: "third.pdf", category: "docs"))
    ])
    let importModel = ImportFolderPreviewModel(
        predictor: s119FatalFolderPredictor(),
        importer: importer,
        errorMapper: S120FatalFolderErrorMapper(),
        conflictPrechecker: S119NoopConflictPrechecker(),
        scanner: s119StaticScanner(urls: urls)
    )
    let controlState = ImportProgressControlState()
    let model = OnboardingModel(
        settingsReader: S117StaticSettingsReader(repoPath: nil),
        importProgressControlState: controlState,
        accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
        helpOpener: S117NoopWelcomeHelpOpener()
    )
    return S119FatalFolderImportScenario(
        secondURL: urls[1],
        importer: importer,
        importModel: importModel,
        opening: .s117Fixture(repoPath: "/tmp/repo"),
        controlState: controlState,
        model: model
    )
}

private func s119FatalFolderPredictor() -> S119MappedPredictor {
    S119MappedPredictor(resultsByFilename: [
        "first.pdf": .success(.s119Prediction(category: "docs", suggestedName: "first.pdf")),
        "second.pdf": .success(.s119Prediction(category: "docs", suggestedName: "second.pdf")),
        "third.pdf": .success(.s119Prediction(category: "docs", suggestedName: "third.pdf"))
    ])
}

private func s119ExpectedCopyAndIndexRequests() -> [S118BatchImportRequest] {
    [
        s119ExpectedImportRequest(storageMode: .copy, overrideFilename: "invoice-2026.pdf"),
        s119ExpectedImportRequest(storageMode: .copy, overrideFilename: "reference-index.pdf"),
        s119ExpectedImportRequest(storageMode: .indexOnly, overrideFilename: "invoice-2026.pdf"),
        s119ExpectedImportRequest(storageMode: .indexOnly, overrideFilename: "reference-index.pdf")
    ]
}

private func s119ExpectedImportRequest(
    storageMode: ImportSingleFileStorageMode,
    overrideFilename: String
) -> S118BatchImportRequest {
    S118BatchImportRequest(
        storageMode: storageMode,
        destination: .category("docs"),
        suggestedCategory: "docs",
        overrideFilename: overrideFilename,
        duplicateStrategy: .ask
    )
}

private func s119FatalRetryContext(sourcePath: String) -> ImportProgressRetryContext {
    ImportProgressRetryContext(
        repoPath: "/tmp/repo",
        sourcePath: sourcePath,
        storageMode: .copy,
        overrideCategory: "docs",
        overrideFilename: "second.pdf",
        duplicateStrategy: .ask
    )
}

private func assertS119FatalPause(_ pausedState: ImportProgressRouteState) {
    XCTAssertEqual(pausedState.titleText, "导入已暂停")
    XCTAssertEqual(pausedState.items.map(\.phase), [.done, .failed, .pending])
    XCTAssertFalse(pausedState.canRetryCurrentItem)
    XCTAssertEqual(pausedState.retryStatusText, "Checking recovery state...")
}

private struct S120FatalFolderErrorMapper: CoreErrorMapping {
    static let mapping = CoreErrorMappingSnapshot(
        kind: .io,
        userMessage: "文件读写失败",
        severity: .critical,
        suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
        recoverability: .fatal,
        rawContext: "S1-20 folder fatal import progress"
    )

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        Self.mapping
    }
}
