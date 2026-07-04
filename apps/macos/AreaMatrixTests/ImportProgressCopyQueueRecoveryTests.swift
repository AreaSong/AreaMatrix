@testable import AreaMatrix
import XCTest

final class ImportProgressCopyQueueRecoveryTests: XCTestCase {
    @MainActor
    func testImportProgressImportMoveFileCoreDiagnosticsAndStopActionsStayOnSafeUiPaths() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
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
        let diagnosticPaths = await diagnostics.requestedRepoPaths()

        XCTAssertEqual(diagnosticPaths, [importProgressRepoPath()])
        XCTAssertEqual(finder.repoPaths, [importProgressRepoPath()])
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
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
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
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let firstURL = importProgressBatchSourceURL("first.pdf")
        let secondURL = importProgressBatchSourceURL("second.pdf")

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
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(ImportProgressFixtures.partialResultProgress)
        model.showImportEntryResults(ImportProgressFixtures.partialResultProgress)

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
            ImportProgressFixtures.copyRetryContext(
                sourcePath: importProgressBatchSourcePath("second.pdf"),
                overrideFilename: "second.pdf"
            )
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
    static let fatalCopyRetryFilenames = ["first.pdf", "second.pdf", "third.pdf"]

    @MainActor
    static func fatalCopyRetryScenario() -> ImportProgressFatalCopyRetryScenario {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
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
        fatalCopyRetryFilenames.map(importProgressBatchSourceURL)
    }

    static func fatalCopyRetryRows() -> [ImportBatchPreviewRow] {
        zip(fatalCopyRetryURLs, fatalCopyRetryFilenames).map(readyRow)
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
        XCTAssertEqual(batchRequests.map(\.overrideFilename), fatalCopyRetryFilenames)
        XCTAssertEqual(scenario.model.route, .mainEmpty(scenario.opening))
        XCTAssertEqual(scenario.model.toastMessage, "已导入：third.pdf")
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
