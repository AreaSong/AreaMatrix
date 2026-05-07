import XCTest
@testable import AreaMatrix

final class ImportProgressCopyQueueRecoveryTests: XCTestCase {
    @MainActor
    func testS120C107DiagnosticsAndStopActionsStayOnSafeUiPaths() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: ".areamatrix/diagnostics/import-fatal.zip",
            createdAt: 1_700_000_100,
            warnings: ["paths redacted"]
        )
        let diagnostics = ShellRecordingDiagnosticsCollector(result: .success(snapshot))
        let finder = ShellRecordingFinderOpener()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            diagnosticsCollector: diagnostics,
            finderOpener: finder,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.beginImportEntryProgress(
            currentPath: "docs/moved.pdf",
            sourcePath: "/tmp/source.pdf",
            storageMode: .move,
            overrideCategory: "docs",
            overrideFilename: "moved.pdf",
            duplicateStrategy: .ask
        )
        model.failImportEntry(
            progress: Self.moveFailedProgress,
            mapping: CoreErrorMappingSnapshot.s120FatalCopyError,
            retryContext: Self.moveRetryContext(sourcePath: "/tmp/source.pdf"),
            recoveryCheck: .retryAllowed(nil)
        )
        model.requestImportProgressDiagnosticsPrivacyConfirmation()
        await model.collectImportProgressDiagnostics()
        model.openImportProgressRepositoryInFinder()
        model.stopImportProgressAndViewResults()
        let diagnosticPaths = await diagnostics.requestedRepoPaths()

        XCTAssertEqual(diagnosticPaths, ["/tmp/repo"])
        XCTAssertEqual(finder.openedRepoPaths, ["/tmp/repo"])
        XCTAssertNil(model.toastMessage)
        guard case .importResult(let result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 0, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.failed])
        model.finishImportResult()
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }

    @MainActor
    func testS120StopAfterCurrentFileStopsBatchAtSafePointAndReturnsResults() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let controlState = ImportProgressControlState()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressControlState: controlState,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let importer = S118RecordingBatchImporter()
        let importModel = ImportBatchCopyImportModel(importer: importer, errorMapper: S117RecordingErrorMapper())
        let firstURL = URL(fileURLWithPath: "/tmp/first.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/second.pdf")

        importModel.applyPreviewRows(
            [Self.readyRow(firstURL, "first.pdf"), Self.readyRow(secondURL, "second.pdf")],
            request: Self.batchRequest(urls: [firstURL, secondURL]),
            selectedDestination: .autoClassify
        )
        model.route = .mainList(opening)
        model.updateImportEntryProgress(ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: 2,
            remaining: 2,
            currentPath: "docs/first.pdf",
            items: importModel.progressItems()
        ))
        model.stopImportProgressAfterCurrentFile()

        let outcome = await importModel.importReadyFiles(
            selectedDestination: .autoClassify,
            controlState: controlState
        ) { progress in
            model.updateImportEntryProgress(progress.withItems(importModel.progressItems()))
        }
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [S118BatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "first.pdf",
            duplicateStrategy: .ask
        )])
        XCTAssertTrue(outcome?.didStopAfterCurrentFile == true)
        XCTAssertNil(model.toastMessage)
        guard case .importResult(let result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 0, stopped 1, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .skipped])
        model.finishImportResult()
        XCTAssertEqual(model.route, .mainEmpty(opening))
    }

    @MainActor
    func testS120ResultSummaryRoutesToS121ImportResult() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.partialResultProgress)
        model.showImportEntryResults(Self.partialResultProgress)

        guard case .importResult(let result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed])
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
    }

    @MainActor
    func testS120FatalCopyRetryContinuesRemainingQueue() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let controlState = ImportProgressControlState()
        let importer = S118SequenceBatchImporter(results: [
            .success(.s117Fixture(currentName: "first.pdf", category: "docs")),
            .failure(CoreError.Io(message: "staging write failed")),
            .success(.s117Fixture(currentName: "third.pdf", category: "docs")),
        ])
        let retryImporter = S117RecordingImporter()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressImporter: retryImporter,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            importProgressControlState: controlState,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let importModel = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S120FatalCopyErrorMapper()
        )
        let urls = [
            URL(fileURLWithPath: "/tmp/first.pdf"),
            URL(fileURLWithPath: "/tmp/second.pdf"),
            URL(fileURLWithPath: "/tmp/third.pdf"),
        ]

        importModel.applyPreviewRows(
            [
                Self.readyRow(urls[0], "first.pdf"),
                Self.readyRow(urls[1], "second.pdf"),
                Self.readyRow(urls[2], "third.pdf"),
            ],
            request: Self.batchRequest(urls: urls),
            selectedDestination: .autoClassify
        )
        model.route = .mainList(opening)
        let outcome = await importModel.importReadyFiles(
            selectedDestination: .autoClassify,
            controlState: controlState
        ) { progress in
            model.updateImportEntryProgress(progress.withItems(importModel.progressItems()))
        }

        guard let progress = model.currentImportProgressState else {
            return XCTFail("Expected failed S1-20 progress route")
        }
        XCTAssertEqual(
            outcome?.fatalRetryContext,
            Self.copyRetryContext(sourcePath: "/tmp/second.pdf", overrideFilename: "second.pdf")
        )
        XCTAssertFalse(progress.canRetryCurrentItem)

        model.failImportEntry(
            progress: progress.progressSnapshot,
            mapping: CoreErrorMappingSnapshot.s120FatalCopyError,
            retryContext: outcome?.fatalRetryContext,
            recoveryCheck: .retryAllowed(nil)
        )
        controlState.registerQueueContinuation(importModel)

        await model.retryCurrentImportProgressItem()
        let retryRequests = await retryImporter.recordedRequests()
        let batchRequests = await importer.recordedRequests()

        XCTAssertEqual(retryRequests, [
            S117ImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "second.pdf",
                duplicateStrategy: .ask
            ),
        ])
        XCTAssertEqual(batchRequests.map(\.overrideFilename), ["first.pdf", "second.pdf", "third.pdf"])
        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：third.pdf")
    }
}

private extension ImportProgressCopyQueueRecoveryTests {
    static let moveFailedProgress = ImportBatchProgressSnapshot(
        completed: 0,
        failed: 1,
        total: 1,
        remaining: 0,
        currentPath: "docs/moved.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/source.pdf",
                targetPath: "docs/moved.pdf",
                phase: .failed,
                errorMessage: "文件读写失败"
            ),
        ]
    )

    static func moveRetryContext(sourcePath: String) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: "/tmp/repo",
            sourcePath: sourcePath,
            storageMode: .move,
            overrideCategory: "docs",
            overrideFilename: "moved.pdf",
            duplicateStrategy: .ask
        )
    }

    static func copyRetryContext(
        sourcePath: String,
        overrideFilename: String = "copied.pdf"
    ) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: "/tmp/repo",
            sourcePath: sourcePath,
            storageMode: .copy,
            overrideCategory: "docs",
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }

    static func readyRow(_ url: URL, _ suggestedName: String) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow.ready(url: url, prediction: ClassifyResultSnapshot(
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
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/合同.pdf",
                targetPath: "finance/合同.pdf",
                phase: .failed,
                errorMessage: "无访问权限"
            ),
        ]
    )
}

private extension OnboardingModel {
    var currentImportProgressState: ImportProgressRouteState? {
        guard case .importProgress(let state) = route else { return nil }
        return state
    }
}

private actor S120FatalCopyErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case .Io:
            return .s120FatalCopyError
        default:
            return .s117Error(kind: .internal)
        }
    }
}

private extension CoreErrorMappingSnapshot {
    static var s120FatalCopyError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "S1-20 fatal copy retry"
        )
    }
}
