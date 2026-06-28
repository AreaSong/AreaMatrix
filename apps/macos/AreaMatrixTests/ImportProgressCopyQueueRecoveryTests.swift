@testable import AreaMatrix
import XCTest

final class ImportProgressCopyQueueRecoveryTests: XCTestCase {
    @MainActor
    func testInterruptedCopySessionRoutesToImportResultAfterRepositoryOpen() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        let store = StaticImportBatchSessionStore(session: ImportBatchSessionSnapshot(
            repoPath: "/tmp/repo",
            storageMode: .copy,
            completed: 1,
            failed: 0,
            total: 3,
            currentPath: "finance/first.pdf",
            items: [
                ImportBatchProgressSnapshot.Item(
                    sourcePath: "/tmp/source/first.pdf",
                    targetPath: "finance/first.pdf",
                    phase: .done,
                    errorMessage: nil
                ),
                ImportBatchProgressSnapshot.Item(
                    sourcePath: "/tmp/source/second.pdf",
                    targetPath: "docs/second.pdf",
                    phase: .copying,
                    errorMessage: nil
                ),
                ImportBatchProgressSnapshot.Item(
                    sourcePath: "/tmp/source/third.pdf",
                    targetPath: "docs/third.pdf",
                    phase: .pending,
                    errorMessage: nil
                )
            ]
        ))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: store,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        guard let result = await waitForImportResultRoute(model) else { return }

        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 0, stopped 0, pending 2.")
        XCTAssertEqual(result.items.map(\.status), [
            ImportResultRouteState.ItemStatus.imported,
            .pending,
            .pending
        ])
        XCTAssertEqual(result.items.dropFirst().map(\.reason), [
            "Import not completed before AreaMatrix quit",
            "Import not completed before AreaMatrix quit"
        ])
        XCTAssertEqual(model.toastMessage, "检测到上次未完成的批量导入。")
    }

    @MainActor
    func testInterruptedCopySessionIsClearedWhenUserAcknowledgesResults() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        let store = StaticImportBatchSessionStore(session: ImportBatchSessionSnapshot(
            repoPath: "/tmp/repo",
            storageMode: .copy,
            completed: 1,
            failed: 0,
            total: 2,
            currentPath: "finance/first.pdf",
            items: [
                ImportBatchProgressSnapshot.Item(
                    sourcePath: "/tmp/source/first.pdf",
                    targetPath: "finance/first.pdf",
                    phase: .done,
                    errorMessage: nil
                ),
                ImportBatchProgressSnapshot.Item(
                    sourcePath: "/tmp/source/second.pdf",
                    targetPath: "docs/second.pdf",
                    phase: .pending,
                    errorMessage: nil
                )
            ]
        ))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: store,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        guard await waitForImportResultRoute(model) != nil else { return }
        model.finishImportResult()
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        let clearedRepoPaths = await store.clearedRepoPaths()
        XCTAssertEqual(clearedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, OnboardingModel.Route.mainList(opening))
    }

    @MainActor
    func testCorruptedOrMissingInterruptedCopySessionDoesNotBlockMainRoute() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: StaticImportBatchSessionStore(session: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        XCTAssertEqual(model.route, OnboardingModel.Route.mainList(opening))
        XCTAssertNil(model.toastMessage)
    }

    @MainActor
    func testImportProgressImportMoveFileCoreDiagnosticsAndStopActionsStayOnSafeUiPaths() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: ".areamatrix/diagnostics/import-fatal.zip",
            createdAt: 1_700_000_100,
            warnings: ["paths redacted"]
        )
        let diagnostics = ShellRecordingDiagnosticsCollector(result: .success(snapshot))
        let finder = RecordingRepositoryFinderOpener()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            diagnosticsCollector: diagnostics,
            finderOpener: finder,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            retryContext: Self.moveRetryContext(sourcePath: "/tmp/source.pdf")
        )
        model.failImportEntry(
            progress: Self.moveFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalCopyError,
            retryContext: Self.moveRetryContext(sourcePath: "/tmp/source.pdf"),
            recoveryCheck: .retryAllowed(nil)
        )
        model.requestImportProgressDiagnosticsPrivacyConfirmation()
        await model.collectImportProgressDiagnostics()
        model.openImportProgressRepositoryInFinder()
        model.stopImportProgressAndViewResults()
        let diagnosticPaths = await diagnostics.requestedRepoPaths()

        XCTAssertEqual(diagnosticPaths, ["/tmp/repo"])
        XCTAssertEqual(finder.repoPaths, ["/tmp/repo"])
        XCTAssertNil(model.toastMessage)
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 0, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.failed])
        model.finishImportResult()
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }

    @MainActor
    func testImportProgressStopAfterCurrentFileStopsBatchAtSafePointAndReturnsResults() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let controlState = ImportProgressControlState()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressControlState: controlState,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let importer = ImportBatchRecordingBatchImporter()
        let importModel = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )
        let firstURL = URL(fileURLWithPath: "/tmp/first.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/second.pdf")

        importModel.applyPreviewRows(
            [Self.readyRow(firstURL, "first.pdf"), Self.readyRow(secondURL, "second.pdf")],
            request: Self.batchRequest(urls: [firstURL, secondURL]),
            selectedDestination: .autoClassify
        )
        model.route = .mainList(opening)
        model.showInitialStopAfterCurrentProgress(importModel: importModel)
        model.stopImportProgressAfterCurrentFile()

        let outcome = await importModel.importReadyFiles(
            selectedDestination: .autoClassify,
            controlState: controlState
        ) { progress in
            model.updateImportEntryProgress(progress.withItems(importModel.progressItems()))
        }
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "first.pdf",
            duplicateStrategy: .ask
        )])
        assertStopAfterCurrentFileResult(outcome: outcome, model: model, opening: opening)
    }

    @MainActor
    func testImportProgressResultSummaryRoutesToImportResultImportResult() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.partialResultProgress)
        model.showImportEntryResults(Self.partialResultProgress)

        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed])
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
    }

    @MainActor
    func testImportProgressFatalCopyRetryContinuesRemainingQueue() async {
        let scenario = Self.fatalCopyRetryScenario()

        let outcome = await scenario.importModel.importReadyFiles(
            selectedDestination: .autoClassify,
            controlState: scenario.controlState
        ) { progress in
            scenario.model.updateImportEntryProgress(progress.withItems(scenario.importModel.progressItems()))
        }

        guard let progress = scenario.model.currentImportProgressState else {
            return XCTFail("Expected failed import-progress progress route")
        }
        XCTAssertEqual(
            outcome?.fatalRetryContext,
            Self.copyRetryContext(sourcePath: "/tmp/second.pdf", overrideFilename: "second.pdf")
        )
        XCTAssertFalse(progress.canRetryCurrentItem)

        scenario.model.failImportEntry(
            progress: progress.progressSnapshot,
            mapping: CoreErrorMappingSnapshot.importProgressFatalCopyError,
            retryContext: outcome?.fatalRetryContext,
            recoveryCheck: .retryAllowed(nil)
        )
        scenario.controlState.registerQueueContinuation(scenario.importModel)

        await scenario.model.retryCurrentImportProgressItem()
        await Self.assertFatalCopyRetryCompleted(scenario)
    }
}

@MainActor
private func assertStopAfterCurrentFileResult(
    outcome: ImportBatchImportResult?,
    model: OnboardingModel,
    opening: RepositoryOpeningResult,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(outcome?.didStopAfterCurrentFile == true, file: file, line: line)
    XCTAssertNil(model.toastMessage, file: file, line: line)
    guard case let .importResult(result) = model.route else {
        return XCTFail("Expected import-result import result route", file: file, line: line)
    }
    XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 0, stopped 1, pending 0.", file: file, line: line)
    XCTAssertEqual(result.items.map(\.status), [.imported, .skipped], file: file, line: line)
    model.finishImportResult()
    XCTAssertEqual(model.route, .mainEmpty(opening), file: file, line: line)
}

@MainActor
struct ImportProgressFatalCopyRetryScenario {
    let opening: RepositoryOpeningResult
    let controlState: ImportProgressControlState
    let importer: ImportBatchSequenceBatchImporter
    let retryImporter: ImportSingleFileRecordingImporter
    let model: OnboardingModel
    let importModel: ImportBatchCopyImportModel
}

private extension OnboardingModel {
    @MainActor
    func showInitialStopAfterCurrentProgress(importModel: ImportBatchCopyImportModel) {
        updateImportEntryProgress(ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: 2,
            remaining: 2,
            currentPath: "docs/first.pdf",
            items: importModel.progressItems()
        ))
    }
}

extension ImportProgressCopyQueueRecoveryTests {
    @MainActor
    static func fatalCopyRetryScenario() -> ImportProgressFatalCopyRetryScenario {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let controlState = ImportProgressControlState()
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "first.pdf", category: "docs")),
            .failure(CoreError.Io(message: "staging write failed")),
            .success(.importSingleFileFixture(currentName: "third.pdf", category: "docs"))
        ])
        let retryImporter = ImportSingleFileRecordingImporter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: retryImporter,
            startupRecoverer: StaticStartupRecoverer(),
            importProgressControlState: controlState,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let importModel = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: ImportProgressFatalCopyErrorMapper()
        )

        importModel.applyPreviewRows(
            fatalCopyRetryRows(),
            request: Self.batchRequest(urls: fatalCopyRetryURLs),
            selectedDestination: .autoClassify
        )
        model.route = .mainList(opening)
        return ImportProgressFatalCopyRetryScenario(
            opening: opening,
            controlState: controlState,
            importer: importer,
            retryImporter: retryImporter,
            model: model,
            importModel: importModel
        )
    }

    static var fatalCopyRetryURLs: [URL] {
        [
            URL(fileURLWithPath: "/tmp/first.pdf"),
            URL(fileURLWithPath: "/tmp/second.pdf"),
            URL(fileURLWithPath: "/tmp/third.pdf")
        ]
    }

    static func fatalCopyRetryRows() -> [ImportBatchPreviewRow] {
        zip(fatalCopyRetryURLs, ["first.pdf", "second.pdf", "third.pdf"]).map(readyRow)
    }

    @MainActor
    static func assertFatalCopyRetryCompleted(_ scenario: ImportProgressFatalCopyRetryScenario) async {
        let retryRequests = await scenario.retryImporter.recordedRequests()
        let batchRequests = await scenario.importer.recordedRequests()

        XCTAssertEqual(retryRequests, [
            ImportSingleFileImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "second.pdf",
                duplicateStrategy: .ask
            )
        ])
        XCTAssertEqual(batchRequests.map(\.overrideFilename), ["first.pdf", "second.pdf", "third.pdf"])
        XCTAssertEqual(scenario.model.route, .mainEmpty(scenario.opening))
        XCTAssertEqual(scenario.model.toastMessage, "已导入：third.pdf")
    }

    static let moveFailedProgress = ImportBatchProgressSnapshot(
        completed: 0,
        failed: 1,
        total: 1,
        remaining: 0,
        currentPath: "docs/moved.pdf",
        items: [.init(
            sourcePath: "/tmp/source.pdf",
            targetPath: "docs/moved.pdf",
            phase: .failed,
            errorMessage: "文件读写失败"
        )]
    )

    static func moveRetryContext(sourcePath: String) -> ImportProgressRetryContext {
        retryContext(sourcePath: sourcePath, storageMode: .move, overrideFilename: "moved.pdf")
    }

    static func copyRetryContext(sourcePath: String,
                                 overrideFilename: String = "copied.pdf") -> ImportProgressRetryContext {
        retryContext(sourcePath: sourcePath, storageMode: .copy, overrideFilename: overrideFilename)
    }

    private static func retryContext(
        sourcePath: String,
        storageMode: ImportSingleFileStorageMode,
        overrideFilename: String
    ) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: "/tmp/repo",
            sourcePath: sourcePath,
            storageMode: storageMode,
            overrideCategory: "docs",
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }

    static func readyRow(_ url: URL, _ suggestedName: String) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow.ready(url: url, prediction: .init(
            category: "docs",
            suggestedName: suggestedName,
            reason: .keyword,
            confidence: 0.9
        ))
    }

    static func batchRequest(urls: [URL]) -> ImportEntryRequest {
        ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: urls,
            kind: .multipleItems(urls.count),
            availableCategories: ["inbox", "docs"]
        )
    }

    static let partialResultProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: "finance/合同.pdf",
        items: [
            .init(sourcePath: "/tmp/invoice.pdf", targetPath: "finance/invoice.pdf", phase: .done, errorMessage: nil),
            .init(sourcePath: "/tmp/合同.pdf", targetPath: "finance/合同.pdf", phase: .failed, errorMessage: "无访问权限")
        ]
    )
}
