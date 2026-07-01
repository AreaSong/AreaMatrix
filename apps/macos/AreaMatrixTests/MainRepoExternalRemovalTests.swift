@testable import AreaMatrix
import SwiftUI
import XCTest

// swiftlint:disable:next type_body_length
final class MainRepoExternalRemovalTests: XCTestCase {
    func testSearchResultsPageIntegrationRendersSearchRouteViews() {
        let request = SearchQueryRequestSnapshot.mainRepoSearchResultsRouteFixture(query: "合同")
        let emptyView = SearchEmptyRouteView(
            request: request,
            onClearSearch: {},
            onClearFilters: {},
            onRemoveFilter: { _ in },
            onSearchAllFileTypes: {}
        )
        let errorBody = QueryErrorRouteView(
            request: request,
            diagnostic: SearchQueryDiagnosticSnapshot(
                severityDisplayName: "Error",
                message: "Unknown field: owner",
                suggestion: "Use category:"
            ),
            onClear: {}
        ).body
        let savedSearchStore = MainRepoSavedSearchRecordingStore(results: [.list([])])
        let saveBody = SavedSearchSheetRouteView(
            request: request,
            repoPath: "/tmp/repo",
            resultCountState: .loaded(3),
            savedSearchStore: savedSearchStore,
            errorMapper: StaticCoreErrorMapper(mapping: .mainRepoSearchFiltersDbFixture()),
            onCancel: {}
        ).body
        let indexingBody = SearchIndexingStatusRouteView(
            request: request,
            indexStatus: .unavailable,
            onRetry: {},
            onClose: {}
        ).body
        var commandQuery = "合同"
        let commandBody = SearchCommandPaletteRouteView(
            query: Binding(get: { commandQuery }, set: { commandQuery = $0 }),
            state: .idle,
            onLoad: {},
            onExecuteTarget: { _ in },
            onClose: {}
        ).body

        assertMainRepoSearchRouteBodies(MainRepoSearchRouteBodies(
            empty: emptyView.body,
            error: errorBody,
            save: saveBody,
            indexing: indexingBody,
            command: commandBody
        ))
    }

    @MainActor
    func testSavedSearchSavedSearchSheetCreatesSmartListThroughCoreBridge() async {
        let request = SearchQueryRequestSnapshot.mainRepoSearchResultsRouteFixture(query: "合同")
        let model = SavedSearchSheetModel(request: request, resultCount: 0)
        let saved = SavedSearchSnapshot.mainRepoSavedSearchFixture(id: 77, request: model.createRequest)
        let store = MainRepoSavedSearchRecordingStore(results: [.list([]), .create(.success(saved))])

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
    func testSavedSearchSavedSearchSheetBlocksDuplicateNameBeforeCreate() async {
        let request = SearchQueryRequestSnapshot.mainRepoSearchResultsRouteFixture(query: "Finance")
        var model = SavedSearchSheetModel(request: request, resultCount: 12)
        model.existingNames = ["finance"]
        let store = MainRepoSavedSearchRecordingStore(results: [.list([.mainRepoSavedSearchFixture(
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
    func testSavedSearchSavedSearchFailureKeepsDraftAndMapsError() async {
        let request = SearchQueryRequestSnapshot.mainRepoSearchResultsRouteFixture(query: "Finance")
        var model = SavedSearchSheetModel(request: request, resultCount: nil)
        let mapping = CoreErrorMappingSnapshot.mainRepoSearchFiltersDbFixture()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let store = MainRepoSavedSearchRecordingStore(results: [.create(.failure(CoreError.Db(message: "db locked")))])

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

    func testSearchFiltersTagFilterEditingSupportsMultipleTagsAndAllMatchMode() {
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

    func testSearchFiltersSearchFilterEditingKeepsInvalidCustomDateOutOfFilterState() {
        let filters = SearchFilterStateSnapshot.mainRepoSearchFiltersFixture()
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

    func testSearchFiltersFilterChipsRemoveSingleFiltersWithoutClearingQueryOwnedState() {
        let filters = SearchFilterStateSnapshot.mainRepoSearchFiltersFixture()

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
    func testSearchFiltersSmartListEditingUpdatesDraftFiltersWithoutSavingOrOpeningCreateSheet() {
        let model = MainFileListModel(
            opening: .mainRepoSearchFiltersFixture(repoPath: "/tmp/repo", tree: .mainRepoSearchFiltersFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            searchFiltering: MainListRecordingSearchFiltering(results: []),
            errorMapper: StaticCoreErrorMapper(mapping: .mainRepoSearchFiltersDbFixture())
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
    func testSearchFiltersSearchFilterRoutingWritesBannerChipRemovalIntoSmartListDraftOnly() {
        let model = MainFileListModel(
            opening: .mainRepoSearchFiltersFixture(repoPath: "/tmp/repo", tree: .mainRepoSearchFiltersFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            searchFiltering: MainListRecordingSearchFiltering(results: []),
            errorMapper: StaticCoreErrorMapper(mapping: .mainRepoSearchFiltersDbFixture())
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
        let draftFilters = SearchFilterStateSnapshot.mainRepoSearchFiltersFixture(tag: "draft")

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
            startupRecoverer: StaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/repo/docs/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let requests = await syncer.recordedRemovedRequests()
        let validatedPaths = await initializedValidator.requestedRepoPaths()
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        let request = try? XCTUnwrap(requests.first)
        XCTAssertEqual(request?.kind, .removed)
        XCTAssertEqual(request?.repoPath, "/tmp/repo")
        XCTAssertEqual(request?.relativePath, "docs/gone.pdf")
        XCTAssertGreaterThan(request?.fsEventID ?? 0, 0)
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
            startupRecoverer: StaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/other/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let requests = await syncer.recordedRemovedRequests()

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
            startupRecoverer: StaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: NoopWelcomeHelpOpener()
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

private struct MainRepoSearchRouteBodies {
    let empty: Any
    let error: Any
    let save: Any
    let indexing: Any
    let command: Any
}

private func assertMainRepoSearchRouteBodies(
    _ bodies: MainRepoSearchRouteBodies,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestMirrorDescription(of: bodies.empty, contains: [
        "search-empty-search-empty",
        "Clear filters",
        "Search all file types"
    ], file: file, line: line)
    assertTestMirrorDescription(of: bodies.error, contains: [
        "Unknown field: owner",
        "query-error-query-error"
    ], file: file, line: line)
    assertTestMirrorDescription(of: bodies.save, contains: "saved-search-search-route", file: file, line: line)
    assertTestMirrorDescription(of: bodies.indexing, contains: [
        "search-index-status-indexing-status-search-route"
    ], file: file, line: line)
    assertTestMirrorDescription(of: bodies.command, contains: "command-palette-search-route", file: file, line: line)
}
