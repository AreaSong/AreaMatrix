@testable import AreaMatrix
import XCTest

final class ImportResultCopyRetryTests: XCTestCase {
    @MainActor
    func testImportResultImportCopyFileCoreRetryFailedCopyItemUsesCoreBridgeImporterAndUpdatesResult() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let importer = ImportSingleFileRecordingImporter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        await model.retryImportResultFailedItems()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFileImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "failed.pdf",
                duplicateStrategy: .ask
            )
        ])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 2, failed 0, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .imported])
        XCTAssertFalse(result.canRetryFailedItems)
        XCTAssertFalse(result.isRetryingFailedItems)
    }

    @MainActor
    func testImportResultRetryFailedRoutesThroughImportProgressProgressBeforeReturningResults() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let gate = ImportSingleFileImportGate()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: ImportSingleFileSuspendingImporter(gate: gate),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        let retryTask = Task { await model.retryImportResultFailedItems() }
        await gate.waitUntilStarted()

        guard case let .importProgress(progress) = model.route else {
            await gate.finish()
            await retryTask.value
            return XCTFail("Expected import-progress import progress while retrying failed import-result items")
        }
        XCTAssertEqual(progress.resultSummaryText, "Imported 0, failed 0, stopped 0, pending 1.")
        XCTAssertEqual(progress.items.map(\.sourcePath), ["/tmp/failed.pdf"])
        XCTAssertEqual(progress.items.map(\.phase), [.copying])

        await gate.finish()
        await retryTask.value
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result after retry completes")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 2, failed 0, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .imported])
    }

    @MainActor
    func testImportResultImportCopyFileCoreRetryFailedCopyItemMapsErrorAndKeepsRetryableRow() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let importer = ImportSingleFileFailingImporter(error: CoreError.PermissionDenied(path: "/tmp/failed.pdf"))
        let errorMapper = ImportSingleFileRecordingErrorMapper()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            errorMapper: errorMapper,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        await model.retryImportResultFailedItems()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: "/tmp/failed.pdf")])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.last?.status, .failed)
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
        XCTAssertTrue(result.canRetryFailedItems)
        XCTAssertFalse(result.isRetryingFailedItems)
    }

    @MainActor
    func testImportResultListChangeLogCoreLoadsImportChangeLogThroughCoreBridge() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let lister = ImportResultRecordingChangeLogLister(results: [.success([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: "imported.pdf")
        ])])
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.importedProgress)
        await model.loadImportResultChangeLog()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [ImportResultChangeLogRequest(repoPath: "/tmp/repo", filter: .importResultRecent)])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.changeLog, .loaded([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: "imported.pdf")
        ]))
    }

    @MainActor
    func testImportResultListChangeLogCoreMapsListChangesFailureInline() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let lister =
            ImportResultRecordingChangeLogLister(results: [.failure(CoreError.Db(message: "change log locked"))])
        let errorMapper = ImportSingleFileRecordingErrorMapper()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            errorMapper: errorMapper,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.importedProgress)
        await model.loadImportResultChangeLog()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "change log locked")])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.changeLog, .failed(.importSingleFileError(kind: .db)))
    }

    func testImportResultChangeLogDetailSummaryRedactsImportedSourcePath() {
        let entry = ChangeLogEntrySnapshot.importResultFixture(
            detailJSON: #"{"source":"/Users/example/private/imported.pdf","mode":"copied","category":"docs"}"#
        )

        XCTAssertTrue(entry.detailSummary.contains("source: .../imported.pdf"))
        XCTAssertFalse(entry.detailSummary.contains("/Users/example/private"))
    }

    @MainActor
    func testImportResultSkippedDuplicateCanShowExistingFileFromResultSummary() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let revealer = RecordingRepositoryFileRevealer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            fileRevealer: revealer,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.skippedDuplicateProgress)
        guard case let .importResult(result) = model.route,
              let skippedItem = result.items.first(where: { $0.status == .skipped })
        else {
            return XCTFail("Expected skipped duplicate result item")
        }

        model.showImportResultExistingFile(itemID: skippedItem.id)

        XCTAssertEqual(revealer.requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(revealer.requests.map(\.relativePath), ["docs/existing.pdf"])
        XCTAssertNil(model.toastMessage)
    }

    @MainActor
    func testTagSuggestionsTagSuggestionsCoreImportResultQueuesTagSuggestionReviewForImportedFile() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.importedProgress)
        guard case let .importResult(result) = model.route,
              let importedItem = result.items.first(where: { $0.canReviewTagSuggestions })
        else {
            return XCTFail("Expected imported result item with tag-suggestions review action")
        }

        model.reviewImportResultTagSuggestions(itemID: importedItem.id)

        XCTAssertEqual(model.pendingTagSuggestionFocus?.fileID, 117)
        XCTAssertEqual(model.pendingTagSuggestionFocus?.source, .importResult)
        guard case let .mainList(mainOpening) = model.route else {
            return XCTFail("Expected main list route for tag-suggestions tag suggestions")
        }
        XCTAssertTrue(mainOpening.currentCategoryFiles.contains { $0.id == 117 && $0.path == "docs/imported.pdf" })
    }

    @MainActor
    func testTagSuggestionsTagSuggestionsCorePartialApplyFailureCanRetryFailedSuggestionOnly() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 231, currentName: "invoice_2026.pdf")
        let report = TagSuggestionReportSnapshot.tagSuggestionsFixture(fileID: detail.id)
        let partialFailure = TagSuggestionApplyReportSnapshot.tagSuggestionsPartialFailure(fileID: detail.id)
        let retrySuccess = TagSuggestionApplyReportSnapshot.tagSuggestionsApplied(
            fileID: detail.id,
            suggestionID: "tagSuggestions-tax",
            slug: "tax-review",
            displayName: "Tax Review"
        )
        let tagStore = DetailTagRecordingStore(
            suggestionResults: [.success(report)],
            applySuggestionResults: [.success(partialFailure), .success(retrySuccess)]
        )
        let model = MainFileListModel.tagSuggestionsFixture(detail: detail, tagStore: tagStore)

        await model.selectFiles([detail.id])
        await model.loadSelectedFileTagSuggestions()
        model.toggleSelectedFileTagSuggestion("tagSuggestions-tax")
        model.startEditingSelectedFileTagSuggestions()
        model.updateSelectedFileTagSuggestionSlug(suggestionID: "tagSuggestions-tax", slug: "tax-review")
        _ = await model.applyEditedSelectedFileTagSuggestions()

        XCTAssertEqual(model.detailTagSuggestionState.appliedReport?.failedCount, 1)
        XCTAssertEqual(model.detailTagSuggestionState.editSession?.drafts.map(\.status.label), ["Applied", "Failed"])
        XCTAssertEqual(DetailTagSuggestionAction.retryFailedItems(in: model.detailTagSuggestionState), [
            ApplyTagSuggestionItemSnapshot(
                suggestionID: "tagSuggestions-tax",
                slug: "tax-review",
                displayName: "Tax"
            )
        ])

        _ = await model.retryFailedSelectedFileTagSuggestions()
        let applyRequests = await tagStore.applySuggestionRequests()

        XCTAssertEqual(applyRequests.last?.request.suggestions, [
            ApplyTagSuggestionItemSnapshot(
                suggestionID: "tagSuggestions-tax",
                slug: "tax-review",
                displayName: "Tax"
            )
        ])
        XCTAssertEqual(model.detailTagSuggestionState.appliedReport?.failedCount, 0)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["tax-review"])
    }

    @MainActor
    func testImportResultExportDetailsUsesRedactedPathsAndPrivacyState() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let exporter = ImportResultExporter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importResultExporter: exporter,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        model.requestImportResultExportPrivacyConfirmation()
        guard case let .importResult(confirming) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(confirming.exportState, .confirmingPrivacy)

        model.exportImportResultDetails()

        XCTAssertEqual(exporter.requests.map(\.suggestedFilename), ["AreaMatrix-Import-Result.txt"])
        XCTAssertTrue(exporter.requests.first?.details.contains(".../failed.pdf") == true)
        XCTAssertFalse(exporter.requests.first?.details.contains("/tmp/failed.pdf") == true)
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.exportState, .exported("/tmp/AreaMatrix-Import-Result.txt"))
        XCTAssertEqual(model.toastMessage, "Import result details exported.")
    }
}

private extension ImportResultCopyRetryTests {
    static let importedProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 1,
        remaining: 0,
        currentPath: "docs/imported.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                fileID: 117,
                sourcePath: "/tmp/imported.pdf",
                targetPath: "docs/imported.pdf",
                phase: .done,
                errorMessage: nil
            )
        ]
    )

    static let failedCopyProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: "docs/failed.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/imported.pdf",
                targetPath: "docs/imported.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/failed.pdf",
                targetPath: "docs/failed.pdf",
                phase: .failed,
                errorMessage: "无访问权限"
            )
        ]
    )

    static let skippedDuplicateProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 2,
        remaining: 0,
        currentPath: "docs/imported.pdf",
        skipped: 1,
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/Users/example/private/imported.pdf",
                targetPath: "docs/imported.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/Users/example/private/existing.pdf",
                targetPath: "docs/existing.pdf",
                phase: .pending,
                errorMessage: "Duplicate skipped",
                existingRelativePath: "docs/existing.pdf"
            )
        ]
    )
}

private struct ImportResultChangeLogRequest: Equatable {
    var repoPath: String
    var filter: ChangeFilterSnapshot
}

private actor ImportResultRecordingChangeLogLister: CoreChangeLogListing {
    enum Result {
        case success([ChangeLogEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [ImportResultChangeLogRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        requests.append(ImportResultChangeLogRequest(repoPath: repoPath, filter: filter))
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case let .success(entries):
            return entries
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [ImportResultChangeLogRequest] {
        requests
    }
}

@MainActor
private final class ImportResultExporter: ImportResultDetailsExporting {
    private(set) var requests: [(details: String, suggestedFilename: String)] = []

    func exportDetails(_ details: String, suggestedFilename: String) throws -> String {
        requests.append((details: details, suggestedFilename: suggestedFilename))
        return "/tmp/\(suggestedFilename)"
    }
}

private extension ChangeLogEntrySnapshot {
    static func importResultFixture(
        id: Int64 = 1,
        filename: String = "imported.pdf",
        detailJSON: String = #"{"source":"/tmp/imported.pdf","mode":"copied","category":"docs"}"#
    ) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: id,
            fileID: 10,
            filename: filename,
            category: "docs",
            action: "imported",
            detailJSON: detailJSON,
            occurredAt: 1_700_000_000
        )
    }
}
