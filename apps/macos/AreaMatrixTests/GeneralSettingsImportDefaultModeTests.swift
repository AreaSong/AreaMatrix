@testable import AreaMatrix
import XCTest

final class GeneralSettingsImportDefaultModeTests: XCTestCase {
    @MainActor
    func testAICallLogCallLogLoadsThroughAICallLogCoreBridgeFilterAndPagination() async {
        let page = aiCallLogPage(records: [aiCallLogRecord(id: 601), aiCallLogRecord(id: 602, feature: .providerTest)])
        let lister = AICallLogCallLogLister(pages: [page])
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: AICallLogCallLogClearer(),
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )

        model.routeFilter = .remote
        model.statusFilter = .success
        model.searchQuery = "OpenAI"
        await model.load()

        XCTAssertEqual(model.records, page.records)
        XCTAssertEqual(model.page?.retentionDays, 90)
        await lister.assertFirstAICallLogListRequest(
            route: .remote,
            status: .success,
            searchQuery: "OpenAI"
        )
    }

    @MainActor
    func testAICallLogDateRangeFeedsAICallLogCoreOccurredBoundsAndClearsFilters() async {
        let lister = AICallLogCallLogLister(pages: [
            aiCallLogPage(records: []),
            aiCallLogPage(records: [])
        ])
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: AICallLogCallLogClearer(),
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedAfter = Int64(Calendar.current.date(byAdding: .day, value: -7, to: now)?.timeIntervalSince1970 ?? 0)

        await model.applyDatePreset(.last7Days, now: now)
        await model.clearFilters()

        await lister.assertFirstAICallLogListRequest(occurredAfter: expectedAfter)
        XCTAssertFalse(model.hasActiveFilters)
        await lister.assertLastAICallLogListRequest()
    }

    @MainActor
    func testAICallLogFilterEmptyStateIsDistinctFromNoLogState() async {
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: AICallLogCallLogLister(pages: [aiCallLogPage(records: [])]),
            clearer: AICallLogCallLogClearer(),
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )

        model.searchQuery = "missing-provider"
        await model.load()

        XCTAssertEqual(model.records, [])
        XCTAssertTrue(model.hasActiveFilters)
        XCTAssertEqual(model.emptyStateTitle, "No AI calls match these filters.")
        XCTAssertEqual(model.emptyStateActionTitle, "Clear filters")
    }

    @MainActor
    func testAICallLogClearLogCallsAICallLogCoreClearAllAndRefreshesEmptyState() async {
        let lister = AICallLogCallLogLister(pages: [
            aiCallLogPage(records: [aiCallLogRecord(id: 603)]),
            aiCallLogPage(records: [])
        ])
        let clearer = AICallLogCallLogClearer()
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: clearer,
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )

        await model.load()
        await model.clearAll()

        await clearer.assertFirstAICallLogClearRequest(scope: .all, entryIDs: [])
        XCTAssertEqual(model.records, [])
        XCTAssertEqual(model.toastMessage, L10n.message("AI call log cleared."))
    }

    @MainActor
    func testAICallLogDeleteSelectedOnlySendsSelectedLogIds() async {
        let lister = AICallLogCallLogLister(pages: [
            aiCallLogPage(records: [aiCallLogRecord(id: 604), aiCallLogRecord(id: 605)]),
            aiCallLogPage(records: [aiCallLogRecord(id: 604)])
        ])
        let clearer = AICallLogCallLogClearer()
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: clearer,
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )

        await model.load()
        model.selectedRecordIDs = [605]
        await model.deleteSelected()

        await clearer.assertFirstAICallLogClearRequest(scope: .selectedEntries, entryIDs: [605])
        XCTAssertEqual(model.records.map(\.id), [604])
        XCTAssertEqual(model.toastMessage, L10n.message("AI log entries deleted."))
    }

    @MainActor
    func testAICallLogSingleDeleteConfirmationTitleMatchesSpec() async {
        let lister = AICallLogCallLogLister(pages: [aiCallLogPage(records: [aiCallLogRecord(id: 606)])])
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: AICallLogCallLogClearer(),
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )

        await model.load()
        model.selectedRecordIDs = [606]

        XCTAssertEqual(model.deleteConfirmationTitle, "Delete this AI call log entry?")
        model.selectedRecordIDs = [606, 607]
        XCTAssertEqual(model.deleteConfirmationTitle, "Delete selected AI call log entries?")
    }

    func testAICallLogVisibleRowIncludesRemoteScopeAndResultColumns() {
        let record = aiCallLogRecord(id: 607, feature: .providerTest)
        let row = AICallLogRowPresentation(record: record)

        XCTAssertEqual(row.remote, "-")
        XCTAssertEqual(row.scope, "Provider verification")
        XCTAssertEqual(row.result, "Connection verified")
    }

    @MainActor
    func testAICallLogFailureMapsCoreErrorAndDoesNotFakeLoadedState() async {
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: AICallLogCallLogLister(error: CoreError.Db(message: "locked")),
            clearer: AICallLogCallLogClearer(),
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )

        await model.load()

        guard case let .failed(error) = model.state else {
            return XCTFail("Expected failed AI call log state.")
        }
        XCTAssertEqual(error.message, L10n.message("AI call log could not be loaded."))
        XCTAssertEqual(model.records, [])
        XCTAssertEqual(model.exportDisabledReason, "AI call log could not be loaded")
    }

    @MainActor
    func testGeneralSettingsMoveDefaultFeedsLaterImportSheetDefaults() async throws {
        let opening = RepositoryOpeningResult.generalSettingsImportFixture(defaultMode: "Moved")
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let model = makeShellOnboardingModel(settingsReader: ShellStaticSettingsReader(repoPath: nil))

        model.startImportEntry(opening: opening, source: .filePicker, urls: [sourceURL])
        let request = try XCTUnwrap(model.pendingImportEntry)

        XCTAssertEqual(request.defaultStorageMode, .move)
        try await assertSingleFileSheetUsesMove(request: request)
        assertBatchSheetUsesMove(opening: opening, sourceURL: sourceURL)
        await assertFolderSheetUsesMove(opening: opening)
    }

    @MainActor
    private func assertSingleFileSheetUsesMove(request: ImportEntryRequest) async throws {
        let singleModel = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: ImportSingleFileRecordingImporter(),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )

        await singleModel.load(request: request)

        XCTAssertEqual(singleModel.selectedStorageMode, .move)
    }

    @MainActor
    private func assertBatchSheetUsesMove(opening: RepositoryOpeningResult, sourceURL: URL) {
        let batchModel = ImportBatchCopyImportModel(
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: generalSettingsImportDefaultErrorMapper()
        )
        batchModel.applyPreviewRows(
            [
                ImportBatchPreviewRow.ready(url: sourceURL, prediction: .importSingleFileFixture())
            ],
            request: ImportEntryRequest(
                repoPath: opening.config.repoPath,
                source: .dropZone,
                destination: .autoClassify,
                urls: [sourceURL, URL(fileURLWithPath: "/tmp/other.pdf")],
                kind: .multipleItems(2),
                defaultStorageMode: .move
            ),
            selectedDestination: .autoClassify
        )

        XCTAssertEqual(batchModel.selectedStorageMode, .move)
    }

    @MainActor
    private func assertFolderSheetUsesMove(opening: RepositoryOpeningResult) async {
        let folderModel = ImportFolderPreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: generalSettingsImportDefaultErrorMapper(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
                rows: [],
                folderCount: 0,
                skippedRules: [],
                errors: []
            ))
        )

        await folderModel.load(request: ImportEntryRequest(
            repoPath: opening.config.repoPath,
            source: .dropZone,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/import-folder", isDirectory: true)],
            kind: .folder,
            defaultStorageMode: .move
        ))

        XCTAssertEqual(folderModel.selectedStorageMode, .move)
    }
}

private typealias AICallLogCallLogLister = RecordingAICallLogLister
private typealias AICallLogCallLogClearer = RecordingAICallLogClearer

private func generalSettingsImportDefaultErrorMapper() -> StaticCoreErrorMapper {
    StaticCoreErrorMapper(mapping: CoreErrorMappingSnapshot.testFixture(
        kind: .internal,
        userMessage: "保存失败",
        severity: .medium,
        suggestedAction: "Retry",
        recoverability: .retryable,
        rawContext: "general-settings import default"
    ))
}

private func aiCallLogPage(records: [AICallLogRecordSnapshot]) -> AICallLogPageSnapshot {
    AICallLogPageSnapshot(
        totalCount: Int64(records.count),
        records: records,
        limit: 100,
        offset: 0,
        hasMore: false,
        retentionDays: 90,
        redactionPolicy: "API keys, full prompts, outputs, notes, and file contents are redacted."
    )
}

private func aiCallLogRecord(
    id: Int64,
    feature: AICallLogFeatureSnapshot = .classification,
    status: AICallLogStatusSnapshot = .success
) -> AICallLogRecordSnapshot {
    AICallLogRecordSnapshot(
        id: id,
        occurredAt: 1_700_000_000 + id,
        feature: feature,
        fileId: feature == .providerTest ? nil : 42,
        fileDisplayName: feature == .providerTest ? nil : "invoice.pdf",
        batchId: nil,
        scope: feature == .providerTest ? "Provider verification" : "single file",
        route: feature == .providerTest ? nil : .remote,
        providerName: feature == .providerTest ? "OpenAI" : "OpenAI",
        modelName: feature == .providerTest ? "gpt-4.1-mini" : "gpt-4.1-mini",
        status: status,
        durationMs: 125,
        sentFields: feature == .providerTest ? [] : [.fileName, .extension],
        privacyRulesChecked: feature != .providerTest,
        privacyRuleId: status == .skipped ? "rule-finance" : nil,
        privacyRuleName: status == .skipped ? "Finance" : nil,
        matchedFieldType: status == .skipped ? .fileName : nil,
        resultSummary: status == .skipped ? "No AI call was made" : "Connection verified",
        errorCode: status == .failed ? "network failed" : nil
    )
}

private extension RepositoryOpeningResult {
    static func generalSettingsImportFixture(defaultMode: String) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .testFixture(repoPath: "/tmp/repo") {
                $0.defaultMode = defaultMode
                $0.locale = "system"
            },
            tree: .testRoot(
                displayName: "资料库",
                fileCount: 0
            ),
            currentCategoryFiles: []
        )
    }
}
