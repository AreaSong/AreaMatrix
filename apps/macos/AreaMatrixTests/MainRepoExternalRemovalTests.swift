@testable import AreaMatrix
import XCTest

final class MainRepoExternalRemovalTests: XCTestCase {
    func testS201PageIntegrationRendersSearchRouteViews() {
        let request = SearchQueryRequestSnapshot.s201RouteFixture(query: "合同")
        let diagnostic = SearchQueryDiagnosticSnapshot(
            severityDisplayName: "Error",
            message: "Unknown field: owner",
            suggestion: "Use category:"
        )

        let emptyBody = s201RouteMirrorDescription(of: SearchEmptyRouteView(request: request, onClear: {}).body)
        let errorBody = s201RouteMirrorDescription(of: QueryErrorRouteView(
            request: request,
            diagnostic: diagnostic,
            onClear: {}
        ).body)
        let saveBody = s201RouteMirrorDescription(of: SavedSearchSheetRouteView(request: request, onCancel: {}).body)
        let indexingBody = s201RouteMirrorDescription(of: SearchIndexingStatusRouteView(
            request: request,
            indexStatus: .unavailable,
            onRetry: {},
            onClose: {}
        ).body)
        let commandBody = s201RouteMirrorDescription(of: SearchCommandPaletteRouteView(query: "合同", onClose: {}).body)

        XCTAssertTrue(emptyBody.contains("S2-04-search-empty"))
        XCTAssertTrue(errorBody.contains("Unknown field: owner"))
        XCTAssertTrue(errorBody.contains("S2-05-query-error"))
        XCTAssertTrue(saveBody.contains("S2-03-search-route"))
        XCTAssertTrue(indexingBody.contains("S2-01-indexing-status-search-route"))
        XCTAssertTrue(commandBody.contains("S2-15-search-route"))
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
            to: Date(timeIntervalSince1970: 1_800_000_000),
            field: .modified,
            in: filters
        )

        XCTAssertNil(invalid.updatedFilters)
        XCTAssertEqual(invalid.errorMessage, "End date must be after start date.")
        XCTAssertEqual(filters.modifiedAfter, 1_700_000_000)
        XCTAssertNil(filters.modifiedBefore)

        let valid = SearchFilterEditing.settingCustomDateRange(
            from: Date(timeIntervalSince1970: 1_800_000_000),
            to: Date(timeIntervalSince1970: 1_800_086_400),
            field: .modified,
            in: filters
        )

        XCTAssertEqual(valid.updatedFilters?.modifiedAfter, 1_799_971_200)
        XCTAssertEqual(valid.updatedFilters?.modifiedBefore, 1_800_057_600)
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

private func s201RouteMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    s201RouteAppendMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func s201RouteAppendMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        s201RouteAppendMirrorDescription(of: child.value, to: &lines)
    }
}
