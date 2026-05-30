@testable import AreaMatrix
import XCTest

final class GeneralSettingsImportDefaultModeTests: XCTestCase {
    @MainActor
    func testS305CallLogLoadsThroughC305BridgeFilterAndPagination() async {
        let page = s305Page(records: [s305Record(id: 601), s305Record(id: 602, feature: .providerTest)])
        let lister = S305CallLogLister(pages: [page])
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: S305CallLogClearer(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )

        model.routeFilter = .remote
        model.statusFilter = .success
        model.searchQuery = "OpenAI"
        await model.load()
        let requests = await lister.requests()

        XCTAssertEqual(model.records, page.records)
        XCTAssertEqual(model.page?.retentionDays, 90)
        XCTAssertEqual(requests.first?.filter.route, .remote)
        XCTAssertEqual(requests.first?.filter.status, .success)
        XCTAssertEqual(requests.first?.filter.searchQuery, "OpenAI")
        XCTAssertEqual(requests.first?.pagination.limit, 100)
    }

    @MainActor
    func testS305DateRangeFeedsC305OccurredBoundsAndClearsFilters() async {
        let lister = S305CallLogLister(pages: [
            s305Page(records: []),
            s305Page(records: [])
        ])
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: S305CallLogClearer(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedAfter = Int64(Calendar.current.date(byAdding: .day, value: -7, to: now)?.timeIntervalSince1970 ?? 0)

        await model.applyDatePreset(.last7Days, now: now)
        let filteredRequest = await lister.requests().first
        await model.clearFilters()
        let clearRequest = await lister.requests().last

        XCTAssertEqual(filteredRequest?.filter.occurredAfter, expectedAfter)
        XCTAssertNil(filteredRequest?.filter.occurredBefore)
        XCTAssertFalse(model.hasActiveFilters)
        XCTAssertNil(clearRequest?.filter.occurredAfter)
        XCTAssertNil(clearRequest?.filter.occurredBefore)
    }

    @MainActor
    func testS305FilterEmptyStateIsDistinctFromNoLogState() async {
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: S305CallLogLister(pages: [s305Page(records: [])]),
            clearer: S305CallLogClearer(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )

        model.searchQuery = "missing-provider"
        await model.load()

        XCTAssertEqual(model.records, [])
        XCTAssertTrue(model.hasActiveFilters)
        XCTAssertEqual(model.emptyStateTitle, "No AI calls match these filters.")
        XCTAssertEqual(model.emptyStateActionTitle, "Clear filters")
    }

    @MainActor
    func testS305ClearLogCallsC305ClearAllAndRefreshesEmptyState() async {
        let lister = S305CallLogLister(pages: [
            s305Page(records: [s305Record(id: 603)]),
            s305Page(records: [])
        ])
        let clearer = S305CallLogClearer()
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: clearer,
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )

        await model.load()
        await model.clearAll()
        let clearRequests = await clearer.requests()

        XCTAssertEqual(clearRequests.first?.scope, .all)
        XCTAssertEqual(clearRequests.first?.entryIds, [])
        XCTAssertEqual(model.records, [])
        XCTAssertEqual(model.toastMessage, "AI call log cleared.")
    }

    @MainActor
    func testS305DeleteSelectedOnlySendsSelectedLogIds() async {
        let lister = S305CallLogLister(pages: [
            s305Page(records: [s305Record(id: 604), s305Record(id: 605)]),
            s305Page(records: [s305Record(id: 604)])
        ])
        let clearer = S305CallLogClearer()
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: clearer,
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )

        await model.load()
        model.selectedRecordIDs = [605]
        await model.deleteSelected()
        let clearRequests = await clearer.requests()

        XCTAssertEqual(clearRequests.first?.scope, .selectedEntries)
        XCTAssertEqual(clearRequests.first?.entryIds, [605])
        XCTAssertEqual(model.records.map(\.id), [604])
        XCTAssertEqual(model.toastMessage, "AI log entries deleted.")
    }

    @MainActor
    func testS305SingleDeleteConfirmationTitleMatchesSpec() async {
        let lister = S305CallLogLister(pages: [s305Page(records: [s305Record(id: 606)])])
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: lister,
            clearer: S305CallLogClearer(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )

        await model.load()
        model.selectedRecordIDs = [606]

        XCTAssertEqual(model.deleteConfirmationTitle, "Delete this AI call log entry?")
        model.selectedRecordIDs = [606, 607]
        XCTAssertEqual(model.deleteConfirmationTitle, "Delete selected AI call log entries?")
    }

    func testS305VisibleRowIncludesRemoteScopeAndResultColumns() {
        let record = s305Record(id: 607, feature: .providerTest)
        let row = AICallLogRowPresentation(record: record)

        XCTAssertEqual(row.remote, "-")
        XCTAssertEqual(row.scope, "Provider verification")
        XCTAssertEqual(row.result, "Connection verified")
    }

    @MainActor
    func testS305FailureMapsCoreErrorAndDoesNotFakeLoadedState() async {
        let model = AICallLogModel(
            repoPath: "/tmp/repo",
            lister: S305CallLogLister(error: CoreError.Db(message: "locked")),
            clearer: S305CallLogClearer(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )

        await model.load()

        guard case let .failed(error) = model.state else {
            return XCTFail("Expected failed C3-05 state.")
        }
        XCTAssertEqual(error.message, "AI call log could not be loaded.")
        XCTAssertEqual(model.records, [])
        XCTAssertEqual(model.exportDisabledReason, "AI call log could not be loaded")
    }

    @MainActor
    func testS126MoveDefaultFeedsLaterImportSheetDefaults() async throws {
        let opening = RepositoryOpeningResult.generalSettingsImportFixture(defaultMode: "Moved")
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: GeneralSettingsImportDefaultAnnouncer(),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

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
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )

        await singleModel.load(request: request)

        XCTAssertEqual(singleModel.selectedStorageMode, .move)
    }

    @MainActor
    private func assertBatchSheetUsesMove(opening: RepositoryOpeningResult, sourceURL: URL) {
        let batchModel = ImportBatchCopyImportModel(
            importer: S118RecordingBatchImporter(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper()
        )
        batchModel.applyPreviewRows(
            [
                ImportBatchPreviewRow.ready(url: sourceURL, prediction: .s117Fixture())
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
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S118RecordingBatchImporter(),
            errorMapper: GeneralSettingsImportDefaultErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: S119StaticFolderScanner(result: ImportFolderScanResult(
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

private actor S305CallLogLister: CoreAICallLogListing {
    typealias Request = (filter: AiCallLogFilter, pagination: AiCallLogPagination)

    private var pages: [AiCallLogPage]
    private let error: Error?
    private var recordedRequests: [Request] = []

    init(pages: [AiCallLogPage] = [], error: Error? = nil) {
        self.pages = pages
        self.error = error
    }

    func listAICalls(
        repoPath _: String,
        filter: AiCallLogFilter,
        pagination: AiCallLogPagination
    ) async throws -> AiCallLogPage {
        recordedRequests.append((filter, pagination))
        if let error { throw error }
        return pages.isEmpty ? s305Page(records: []) : pages.removeFirst()
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private actor S305CallLogClearer: CoreAICallLogClearing {
    private var recordedRequests: [AiCallLogClearRequest] = []

    func clearAICallLog(repoPath _: String, request: AiCallLogClearRequest) async throws -> AiCallLogClearReport {
        recordedRequests.append(request)
        return AiCallLogClearReport(deletedCount: Int64(request.entryIds.count), remainingCount: 0, clearedAt: 1_700_000_100)
    }

    func requests() -> [AiCallLogClearRequest] {
        recordedRequests
    }
}

@MainActor
private final class GeneralSettingsImportDefaultAnnouncer: AccessibilityAnnouncing {
    func announce(_: String) {}
}

private actor GeneralSettingsImportDefaultErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "保存失败",
            severity: .medium,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "S1-26 import default"
        )
    }
}

private func s305Page(records: [AiCallLogRecord]) -> AiCallLogPage {
    AiCallLogPage(
        totalCount: Int64(records.count),
        records: records,
        limit: 100,
        offset: 0,
        hasMore: false,
        retentionDays: 90,
        redactionPolicy: "API keys, full prompts, outputs, notes, and file contents are redacted."
    )
}

private func s305Record(
    id: Int64,
    feature: AiCallLogFeature = .classification,
    status: AiCallLogStatus = .success
) -> AiCallLogRecord {
    AiCallLogRecord(
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
            config: RepoConfigSnapshot(
                repoPath: "/tmp/repo",
                defaultMode: defaultMode,
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "system",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: 0,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}
