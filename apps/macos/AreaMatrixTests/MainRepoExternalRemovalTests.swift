@testable import AreaMatrix
import SwiftUI
import XCTest

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
final class MainRepoExternalRemovalTests: XCTestCase {
    func testS201PageIntegrationRendersSearchRouteViews() {
        let request = SearchQueryRequestSnapshot.s201RouteFixture(query: "合同")
        let emptyView = SearchEmptyRouteView(
            request: request,
            onClearSearch: {},
            onClearFilters: {},
            onRemoveFilter: { _ in },
            onSearchAllFileTypes: {}
        )
        let emptyBody = s201RouteMirrorDescription(of: emptyView.body)
        let errorBody = s201RouteMirrorDescription(of: QueryErrorRouteView(
            request: request,
            diagnostic: SearchQueryDiagnosticSnapshot(
                severityDisplayName: "Error",
                message: "Unknown field: owner",
                suggestion: "Use category:"
            ),
            onClear: {}
        ).body)
        let savedSearchStore = S203RecordingSavedSearchStore(results: [.listSuccess([])])
        let saveBody = s201RouteMirrorDescription(of: SavedSearchSheetRouteView(
            request: request,
            repoPath: "/tmp/repo",
            resultCountState: .loaded(3),
            savedSearchStore: savedSearchStore,
            errorMapper: MainListRecordingErrorMapper(mapping: .searchFiltersDbFixture()),
            onCancel: {}
        ).body)
        let indexingBody = s201RouteMirrorDescription(of: SearchIndexingStatusRouteView(
            request: request,
            indexStatus: .unavailable,
            onRetry: {},
            onClose: {}
        ).body)
        var commandQuery = "合同"
        let commandBody = s201RouteMirrorDescription(of: SearchCommandPaletteRouteView(
            query: Binding(get: { commandQuery }, set: { commandQuery = $0 }),
            state: .idle,
            onLoad: {},
            onExecuteTarget: { _ in },
            onClose: {}
        ).body)

        XCTAssertTrue(emptyBody.contains("S2-04-search-empty"))
        XCTAssertTrue(emptyBody.contains("Clear filters") && emptyBody.contains("Search all file types"))
        XCTAssertTrue(errorBody.contains("Unknown field: owner"))
        XCTAssertTrue(errorBody.contains("S2-05-query-error"))
        XCTAssertTrue(saveBody.contains("S2-03-search-route"))
        XCTAssertTrue(indexingBody.contains("S2-01-indexing-status-search-route"))
        XCTAssertTrue(commandBody.contains("S2-15-search-route"))
    }

    @MainActor
    func testS203SavedSearchSheetCreatesSmartListThroughCoreBridge() async {
        let request = SearchQueryRequestSnapshot.s201RouteFixture(query: "合同")
        let model = SavedSearchSheetModel(request: request, resultCount: 0)
        let saved = SavedSearchSnapshot.s203Fixture(id: 77, request: model.createRequest)
        let store = S203RecordingSavedSearchStore(results: [.listSuccess([]), .createSuccess(saved)])

        _ = try? await store.listSavedSearches(repoPath: "/tmp/repo")
        let created = try? await store.createSavedSearch(repoPath: "/tmp/repo", request: model.createRequest)

        XCTAssertEqual(created, saved)
        XCTAssertEqual(model.createRequest.name, "合同")
        XCTAssertEqual(model.createRequest.query.filter.tags, ["contract"])
        XCTAssertEqual(model.createRequest.query.sort, .relevance)
        XCTAssertEqual(model.createRequest.pinned, true)
        XCTAssertEqual(model.emptyResultWarning, "This Smart List is currently empty.")
        let createdRequests = await store.createdRequests().map(\.request)
        XCTAssertEqual(createdRequests, [model.createRequest])
    }

    @MainActor
    func testS203SavedSearchSheetBlocksDuplicateNameBeforeCreate() async {
        let request = SearchQueryRequestSnapshot.s201RouteFixture(query: "Finance")
        var model = SavedSearchSheetModel(request: request, resultCount: 12)
        model.existingNames = ["finance"]
        let store = S203RecordingSavedSearchStore(results: [.listSuccess([.s203Fixture(
            id: 1,
            request: model.createRequest
        )])])

        XCTAssertEqual(model.validationMessage, "A Smart List named \"Finance\" already exists.")
        XCTAssertFalse(model.canSave)
        XCTAssertEqual(model.resultCountSummary, "12 files")
        let createdRequests = await store.createdRequests()
        XCTAssertEqual(createdRequests, [])
    }

    @MainActor
    func testS203SavedSearchFailureKeepsDraftAndMapsError() async {
        let request = SearchQueryRequestSnapshot.s201RouteFixture(query: "Finance")
        var model = SavedSearchSheetModel(request: request, resultCount: nil)
        let mapping = CoreErrorMappingSnapshot.searchFiltersDbFixture()
        let mapper = MainListRecordingErrorMapper(mapping: mapping)
        let store = S203RecordingSavedSearchStore(results: [.createFailure(CoreError.Db(message: "db locked"))])

        do {
            _ = try await store.createSavedSearch(repoPath: "/tmp/repo", request: model.createRequest)
            XCTFail("expected saved search create failure")
        } catch let error as CoreError {
            model.saveFailure = await mapper.mapCoreError(error)
        } catch {
            XCTFail("expected CoreError, got \(error)")
        }

        XCTAssertEqual(model.name, "Finance")
        XCTAssertEqual(model.resultCountSummary, "Counting results...")
        XCTAssertEqual(model.saveFailure, mapping)
        let recordedErrors = await mapper.recordedErrors()
        XCTAssertEqual(recordedErrors, [CoreError.Db(message: "db locked")])
    }

    func testS202TagFilterEditingSupportsMultipleTagsAndAllMatchMode() {
        let filters = SearchFilterStateSnapshot.empty
        let withFinance = SearchFilterEditing.togglingTag("finance", in: filters)
        let withTax = SearchFilterEditing.togglingTag("tax", in: withFinance)
        let allSelected = SearchFilterEditing.settingTagMatchMode(.all, in: withTax)
        let withoutFinance = SearchFilterEditing.togglingTag("finance", in: allSelected)
        let withoutTags = SearchFilterEditing.togglingTag("tax", in: withoutFinance)

        XCTAssertEqual(allSelected.tags, ["finance", "tax"])
        XCTAssertEqual(allSelected.tagMatchMode, .all)
        XCTAssertEqual(withoutFinance.tags, ["tax"])
        XCTAssertEqual(withoutFinance.tagMatchMode, .all)
        XCTAssertEqual(withoutTags.tags, [])
        XCTAssertEqual(withoutTags.tagMatchMode, .any)
    }

    func testS202SearchFilterEditingKeepsInvalidCustomDateOutOfFilterState() {
        let filters = SearchFilterStateSnapshot.searchFiltersFixture()
        let invalid = SearchFilterEditing.settingCustomDateRange(
            from: Date(timeIntervalSince1970: 1_800_086_400),
            until: Date(timeIntervalSince1970: 1_800_000_000),
            field: .modified,
            in: filters
        )

        XCTAssertNil(invalid.updatedFilters)
        XCTAssertEqual(invalid.errorMessage, "End date must be after start date.")
        XCTAssertEqual(filters.modifiedAfter, 1_700_000_000)
        XCTAssertNil(filters.modifiedBefore)

        let validFrom = Date(timeIntervalSince1970: 1_800_000_000)
        let validTo = Date(timeIntervalSince1970: 1_800_086_400)
        let valid = SearchFilterEditing.settingCustomDateRange(
            from: validFrom,
            until: validTo,
            field: .modified,
            in: filters
        )
        let expectedStart = Int64(Calendar.current.startOfDay(for: validFrom).timeIntervalSince1970)
        let expectedEnd = Int64(Calendar.current.startOfDay(for: validTo).timeIntervalSince1970)

        XCTAssertEqual(valid.updatedFilters?.modifiedAfter, expectedStart)
        XCTAssertEqual(valid.updatedFilters?.modifiedBefore, expectedEnd)
        XCTAssertNil(valid.errorMessage)
    }

    func testS202FilterChipsRemoveSingleFiltersWithoutClearingQueryOwnedState() {
        let filters = SearchFilterStateSnapshot.searchFiltersFixture()

        XCTAssertEqual(
            SearchFilterChips.items(for: filters).map(\.kind),
            [.category, .fileKind, .tags, .modifiedDate, .storage, .includeDeleted]
        )

        let withoutTags = SearchFilterEditing.removing(.tags, from: filters)
        XCTAssertEqual(withoutTags.category, "docs")
        XCTAssertEqual(withoutTags.fileKind, "pdf")
        XCTAssertEqual(withoutTags.tags, [])
        XCTAssertEqual(withoutTags.tagMatchMode, .any)
        XCTAssertEqual(withoutTags.modifiedAfter, 1_700_000_000)
        XCTAssertEqual(withoutTags.storageMode, .copied)
        XCTAssertTrue(withoutTags.includeDeleted)

        let withoutDate = SearchFilterEditing.removing(.modifiedDate, from: filters)
        XCTAssertNil(withoutDate.modifiedAfter)
        XCTAssertNil(withoutDate.modifiedBefore)
        XCTAssertEqual(withoutDate.tags, ["finance"])
    }

    @MainActor
    func testS202SmartListEditingUpdatesDraftFiltersWithoutSavingOrOpeningCreateSheet() {
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: .searchFiltersFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            searchFiltering: MainListRecordingSearchFiltering(results: []),
            errorMapper: MainListRecordingErrorMapper(mapping: .searchFiltersDbFixture())
        )
        let baseFilters = SearchFilterStateSnapshot.empty
        let draftFilters = SearchFilterEditing.settingTagMatchMode(
            .all,
            in: SearchFilterEditing.togglingTag(
                "tax",
                in: SearchFilterEditing.togglingTag("finance", in: baseFilters)
            )
        )

        model.beginSmartListFilterDraft(id: 42, name: "最近合同", filters: baseFilters)
        model.updateSmartListFilterDraft(draftFilters)
        model.openSavedSearchSheet()

        XCTAssertEqual(model.smartListFilterDraft?.id, 42)
        XCTAssertEqual(model.smartListFilterDraft?.filters.tags, ["finance", "tax"])
        XCTAssertEqual(model.smartListFilterDraft?.filters.tagMatchMode, .all)
        XCTAssertEqual(model.lastSearchExitContext, MainSearchExitContext.smartList(id: 42, name: "最近合同"))
        XCTAssertNil(model.pendingSearchDestination)
    }

    @MainActor
    func testS202SearchFilterRoutingWritesBannerChipRemovalIntoSmartListDraftOnly() {
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: .searchFiltersFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            searchFiltering: MainListRecordingSearchFiltering(results: []),
            errorMapper: MainListRecordingErrorMapper(mapping: .searchFiltersDbFixture())
        )
        var searchFilters = SearchFilterStateSnapshot(
            category: "docs",
            fileKind: "pdf",
            tags: ["ordinary"],
            tagMatchMode: .any,
            importedAfter: nil,
            importedBefore: nil,
            modifiedAfter: nil,
            modifiedBefore: nil,
            storageMode: .copied,
            includeDeleted: false
        )
        let draftFilters = SearchFilterStateSnapshot.searchFiltersFixture(tag: "draft")

        model.beginSmartListFilterDraft(id: 42, name: "最近合同", filters: draftFilters)
        let updated = SearchFilterEditing.removing(
            .tags,
            from: SearchFilterStateRouting.effective(searchFilters: searchFilters, draft: model.smartListFilterDraft)
        )
        SearchFilterStateRouting.assign(updated, searchFilters: &searchFilters, fileListModel: model)

        XCTAssertEqual(searchFilters.tags, ["ordinary"])
        XCTAssertEqual(model.smartListFilterDraft?.filters.tags, [])
        XCTAssertEqual(model.smartListFilterDraft?.filters.tagMatchMode, .any)
        XCTAssertEqual(model.smartListFilterDraft?.filters.modifiedAfter, 1_700_000_000)
    }

    @MainActor
    func testMainRepoErrorExternalRemovalSyncsMissingFileThroughCoreBridge() async {
        let result = SyncResultSnapshot.shellDeletedFixture()
        let syncer = ShellRecordingExternalChangesSyncer(result: .success(result))
        let opener = ShellRecordingRepositoryOpener(result: .success(
            .shellFixture(repoPath: "/tmp/repo", fileCount: 0)
        ))
        let initializedValidator = ShellRecordingInitializedPathValidator(
            result: .success(.shellFixture(
                repoPath: "/tmp/repo",
                isInitialized: true,
                recommendedMode: nil
            ))
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/repo/docs/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let requests = await syncer.recordedRequests()
        let validatedPaths = await initializedValidator.requestedRepoPaths()
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(requests.map(\.relativePath), ["docs/gone.pdf"])
        XCTAssertEqual(validatedPaths, ["/tmp/repo"])
        XCTAssertEqual(openedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.mainRepoExternalRemoval, .synced(result))
        XCTAssertEqual(model.route, .mainEmpty(.shellFixture(repoPath: "/tmp/repo", fileCount: 0)))
        XCTAssertFalse(model.isRetryingMainRepository)
    }

    @MainActor
    func testMainRepoErrorExternalRemovalIgnoresPathOutsideRepository() async {
        let syncer = ShellRecordingExternalChangesSyncer(result: .success(.shellDeletedFixture()))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/other/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let requests = await syncer.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.mainRepoExternalRemoval, .unavailable)
        XCTAssertFalse(model.isRetryingMainRepository)
    }

    @MainActor
    func testMainRepoErrorExternalRemovalKeepsErrorStateWhenCoreSyncFails() async {
        let syncer = ShellRecordingExternalChangesSyncer(result: .failure(CoreError.Db(message: "db locked")))
        let opener = ShellRecordingRepositoryOpener(result: .success(
            .shellFixture(repoPath: "/tmp/repo", fileCount: 0)
        ))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/repo/docs/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .failed(failureMapping) = model.mainRepoExternalRemoval else {
            return XCTFail("expected failed external removal state")
        }
        guard case let .mainRepoError(repoPath, routeMapping) = model.route else {
            return XCTFail("expected main repo error, got \(model.route)")
        }

        XCTAssertEqual(openedPaths, [])
        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(failureMapping.kind, .db)
        XCTAssertEqual(routeMapping?.kind, .db)
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping?.kind, .db)
        XCTAssertFalse(model.isRetryingMainRepository)
    }
}

private extension SearchQueryRequestSnapshot {
    static func s201RouteFixture(query: String) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .current,
            currentPath: "docs/contracts",
            category: "docs",
            filters: .s201RouteFilters,
            sort: .relevance,
            limit: 50,
            offset: 0
        )
    }
}

private extension RepositoryOpeningResult {
    static func searchFiltersFixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func searchFiltersFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: []
        )
    }
}

private extension SearchFilterStateSnapshot {
    static func searchFiltersFixture(tag: String = "finance") -> SearchFilterStateSnapshot {
        SearchFilterStateSnapshot(
            category: "docs",
            fileKind: "pdf",
            tags: [tag],
            tagMatchMode: .all,
            importedAfter: nil,
            importedBefore: nil,
            modifiedAfter: 1_700_000_000,
            modifiedBefore: nil,
            storageMode: .copied,
            includeDeleted: true
        )
    }

    static let s201RouteFilters = SearchFilterStateSnapshot(
        category: "docs",
        fileKind: "pdf",
        tags: ["contract"],
        tagMatchMode: .any,
        importedAfter: nil,
        importedBefore: nil,
        modifiedAfter: nil,
        modifiedBefore: nil,
        storageMode: .copied,
        includeDeleted: false
    )
}

private extension CoreErrorMappingSnapshot {
    static func searchFiltersDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "过滤器不可用",
            severity: .high,
            suggestedAction: "请重试过滤器。",
            recoverability: .retryable,
            rawContext: "facet db locked"
        )
    }
}

private struct S203SavedSearchRequestRecord: Equatable {
    var repoPath: String
    var request: CreateSavedSearchRequestSnapshot
}

private actor S203RecordingSavedSearchStore: CoreSavedSearchCRUD {
    enum Result {
        case listSuccess([SavedSearchSnapshot])
        case createSuccess(SavedSearchSnapshot)
        case createFailure(Error)
    }

    private var results: [Result]
    private var createRecords: [S203SavedSearchRequestRecord] = []

    init(results: [Result]) {
        self.results = results
    }

    func createSavedSearch(
        repoPath: String,
        request: CreateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        createRecords.append(S203SavedSearchRequestRecord(repoPath: repoPath, request: request))
        guard !results.isEmpty else { throw CoreError.Db(message: "missing saved search result") }
        switch results.removeFirst() {
        case let .createSuccess(saved):
            return saved
        case let .createFailure(error):
            throw error
        case .listSuccess:
            throw CoreError.Internal(message: "expected saved search create result")
        }
    }

    func listSavedSearches(repoPath _: String) async throws -> [SavedSearchSnapshot] {
        guard !results.isEmpty else { return [] }
        switch results.removeFirst() {
        case let .listSuccess(saved):
            return saved
        case .createSuccess, .createFailure:
            throw CoreError.Internal(message: "expected saved search list result")
        }
    }

    func createdRequests() -> [S203SavedSearchRequestRecord] {
        createRecords
    }
}

private extension SavedSearchSnapshot {
    static func s203Fixture(id: Int64, request: CreateSavedSearchRequestSnapshot) -> SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: id,
            name: request.name,
            query: request.query,
            icon: request.icon,
            color: request.color,
            pinned: request.pinned,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}

private func s201RouteMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    s201RouteAppendMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func s201RouteAppendMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label { lines.append(label) }
        s201RouteAppendMirrorDescription(of: child.value, to: &lines)
    }
}
