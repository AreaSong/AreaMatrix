@testable import AreaMatrix
import AreaMatrixCoreBridgeContract
import XCTest

final class ImportProgressCopyQueueRecoveryTests: XCTestCase {
    @MainActor
    func testImportProgressImportMoveFileCoreDiagnosticsAndStopActionsStayOnSafeUiPaths() async {
        let snapshot = DiagnosticsSnapshotSnapshot.testFixture(
            snapshotPath: ".areamatrix/diagnostics/import-fatal.zip",
            createdAt: 1_700_000_100,
            warnings: ["paths redacted"]
        )
        let diagnostics = ShellRecordingDiagnosticsCollector(result: .success(snapshot))
        let finder = RecordingRepositoryFinderOpener()
        let fixture = makeImportProgressMainListFixture(
            diagnosticsCollector: diagnostics,
            finderOpener: finder
        )
        let opening = fixture.opening
        let model = fixture.model

        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            retryContext: ImportProgressFixtures.moveRetryContext(sourcePath: importProgressSourcePath())
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.moveFailedProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalCopyError,
            retryContext: ImportProgressFixtures.moveRetryContext(sourcePath: importProgressSourcePath()),
            recoveryCheck: .retryAllowed(nil)
        )
        model.requestImportProgressDiagnosticsPrivacyConfirmation()
        await model.collectImportProgressDiagnostics()
        model.openImportProgressRepositoryInFinder()
        model.stopImportProgressAndViewResults()

        await diagnostics.assertRequestedRepoPaths([importProgressRepoPath()])
        finder.assertRepoPaths([importProgressRepoPath()])
        XCTAssertNil(model.toastMessage)
        guard let result = requireImportResultRoute(model) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 0, failed 1, stopped 0, pending 0.",
            statuses: [.failed]
        )
        model.finishImportResult()
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }

    @MainActor
    func testCancelledImportProgressDiagnosticsIgnoresLateCollectorResult() async {
        let collector = SuspendedDiagnosticsCollector(result: .success(.testFixture()))
        let model = makeImportProgressMainListFixture(diagnosticsCollector: collector).model
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            retryContext: ImportProgressFixtures.moveRetryContext(sourcePath: importProgressSourcePath())
        )
        model.failImportEntry(
            progress: ImportProgressFixtures.moveFailedProgress,
            mapping: .importProgressFatalCopyError,
            retryContext: ImportProgressFixtures.moveRetryContext(sourcePath: importProgressSourcePath()),
            recoveryCheck: .retryAllowed(nil)
        )
        model.requestImportProgressDiagnosticsPrivacyConfirmation()

        let collection = Task { await model.collectImportProgressDiagnostics() }
        await collector.waitUntilStarted()
        model.cancelImportProgressDiagnosticsPrivacyConfirmation()
        await collector.finish()
        await collection.value

        XCTAssertEqual(model.currentImportProgressState?.diagnostics, .idle)
    }

    @MainActor
    func testImportProgressStopAfterCurrentFileStopsBatchAtSafePointAndReturnsResults() async {
        let controlState = ImportProgressControlState()
        let fixture = makeImportProgressMainListFixture(importProgressControlState: controlState)
        let opening = fixture.opening
        let model = fixture.model
        let importer = ImportBatchRecordingBatchImporter()
        let importModel = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let firstURL = importProgressBatchSourceURL("first.pdf")
        let secondURL = importProgressBatchSourceURL("second.pdf")

        importModel.applyPreviewRows(
            [Self.readyRow(firstURL, "first.pdf"), Self.readyRow(secondURL, "second.pdf")],
            request: Self.batchRequest(urls: [firstURL, secondURL]),
            selectedDestination: .autoClassify
        )
        model.showInitialStopAfterCurrentProgress(importModel: importModel)
        model.stopImportProgressAfterCurrentFile()

        let outcome = await importModel.importReadyFiles(
            selectedDestination: .autoClassify,
            controlState: controlState
        ) { progress in
            model.updateImportEntryProgress(progress.withItems(importModel.progressItems()))
        }

        await importer.assertImportedBatchFiles([ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "first.pdf",
            duplicateStrategy: .ask
        )])
        assertStopAfterCurrentFileResult(outcome: outcome, model: model, opening: opening)
    }

    @MainActor
    func testImportProgressResultSummaryRoutesToImportResultImportResult() {
        let model = makeImportProgressMainListFixture().model

        model.updateImportEntryProgress(ImportProgressFixtures.partialResultProgress)
        model.showImportEntryResults(ImportProgressFixtures.partialResultProgress)

        guard let result = requireImportResultRoute(model) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 1, stopped 0, pending 0.",
            statuses: [.imported, .failed]
        )
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
        assertImportProgressRetryContext(
            outcome?.fatalRetryContext,
            equals: ImportProgressFixtures.copyRetryContext(
                sourcePath: importProgressBatchSourcePath("second.pdf"),
                overrideFilename: "second.pdf"
            )
        )
        XCTAssertNotNil(outcome?.fatalRetryContext?.traceID)
        XCTAssertNotNil(outcome?.fatalRetryContext?.operationID)
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

    @MainActor
    func testFatalCopyRetrySourceRetainedContinuesQueueAndShowsDegradedResult() async {
        var sourceRetainedEntry = FileEntrySnapshot.importSingleFileFixture(
            currentName: "second.pdf",
            category: "docs"
        )
        sourceRetainedEntry.importCommitState = .sourceRetained
        let scenario = Self.fatalCopyRetryScenario(retryResults: [.success(sourceRetainedEntry)])

        let outcome = await scenario.importModel.importReadyFiles(
            selectedDestination: .autoClassify,
            controlState: scenario.controlState
        ) { progress in
            scenario.model.updateImportEntryProgress(progress.withItems(scenario.importModel.progressItems()))
        }
        guard let progress = scenario.model.currentImportProgressState else {
            return XCTFail("Expected failed import-progress route")
        }
        scenario.model.failImportEntry(
            progress: progress.progressSnapshot,
            mapping: .importProgressFatalCopyError,
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
    guard let result = requireImportResultRoute(model, file: file, line: line) else { return }
    assertImportResultSummary(
        result,
        summaryText: "Imported 1, failed 0, stopped 1, pending 0.",
        statuses: [.imported, .skipped],
        file: file,
        line: line
    )
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
        updateImportEntryProgress(importBatchProgress(
            completed: 0,
            total: 2,
            currentPath: "docs/first.pdf",
            items: importModel.progressItems()
        ))
    }
}

extension ImportProgressCopyQueueRecoveryTests {
    static let fatalCopyRetryFilenames = ["first.pdf", "second.pdf", "third.pdf"]

    @MainActor
    static func fatalCopyRetryScenario(
        retryResults: [Result<FileEntrySnapshot, Error>]? = nil
    ) -> ImportProgressFatalCopyRetryScenario {
        let controlState = ImportProgressControlState()
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "first.pdf", category: "docs")),
            .failure(CoreError.Io(message: "staging write failed")),
            .success(.importSingleFileFixture(currentName: "third.pdf", category: "docs"))
        ])
        let retryImporter = ImportSingleFileRecordingImporter(results: retryResults)
        let fixture = makeImportProgressMainListFixture(
            importProgressImporter: retryImporter,
            startupRecoverer: StaticStartupRecoverer(),
            importProgressControlState: controlState
        )
        let opening = fixture.opening
        let model = fixture.model
        let importModel = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: ImportProgressFatalCopyErrorMapper()
        )

        importModel.applyPreviewRows(
            fatalCopyRetryRows(),
            request: Self.batchRequest(urls: fatalCopyRetryURLs),
            selectedDestination: .autoClassify
        )
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
        fatalCopyRetryFilenames.map(importProgressBatchSourceURL)
    }

    static func fatalCopyRetryRows() -> [ImportBatchPreviewRow] {
        zip(fatalCopyRetryURLs, fatalCopyRetryFilenames).map(readyRow)
    }

    @MainActor
    static func assertFatalCopyRetryCompleted(_ scenario: ImportProgressFatalCopyRetryScenario) async {
        await scenario.retryImporter.assertImportedFiles([
            ImportSingleFileImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "second.pdf",
                duplicateStrategy: .ask
            )
        ])
        await scenario.importer.assertImportedOverrideFilenames(fatalCopyRetryFilenames)
        XCTAssertEqual(scenario.model.route, .mainEmpty(scenario.opening))
        XCTAssertEqual(
            scenario.model.toastMessage,
            L10n.message("import.single.imported-file", arguments: [.string("third.pdf")])
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
            repoPath: importProgressRepoPath(),
            source: .dropZone,
            destination: .autoClassify,
            urls: urls,
            kind: .multipleItems(urls.count),
            availableCategories: ["inbox", "docs"]
        )
    }
}
