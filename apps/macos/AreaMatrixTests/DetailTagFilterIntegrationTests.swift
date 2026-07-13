@testable import AreaMatrix
import XCTest

final class DetailTagFilterIntegrationTests: XCTestCase {
    func testSearchRoutingStateKeepsToolbarSidebarAndSmartListRoutesIndependent() {
        var routingState = MainRepositorySearchRoutingState()

        routingState.isSidebarTagsFilterPresented = true
        XCTAssertTrue(routingState.isSidebarTagsFilterPresented)
        XCTAssertFalse(routingState.isToolbarFiltersPresented)
        XCTAssertNil(routingState.smartListManagementRoute)

        routingState.isToolbarFiltersPresented = true
        routingState.isSidebarTagsFilterPresented = false
        XCTAssertTrue(routingState.isToolbarFiltersPresented)
        XCTAssertFalse(routingState.isSidebarTagsFilterPresented)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testTagFilterPageIntegrationVerifyConnectsEntryExitErrorsAndDeclaredCoreOnly() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 219, currentName: "integration.pdf")
        let filters = SearchFilterEditing.settingTagMatchMode(
            .all,
            in: SearchFilterEditing.togglingTag(
                "tax",
                in: SearchFilterEditing.togglingTag("finance", in: .empty)
            )
        )
        let tagStore = DetailTagRecordingStore(
            listResults: [
                .success(.tagFilterRegistryFixture(fileID: detail.id)),
                .failure(CoreError.Db(message: "tags")),
                .success(.tagFilterRegistryFixture(fileID: detail.id))
            ]
        )
        let facets = MainListRecordingSearchFiltering(results: [
            .success(.tagFilterIntegrationFacets()),
            .failure(CoreError.Db(message: "counts")),
            .success(.tagFilterIntegrationFacets())
        ])
        let searcher = MainListRecordingSearchQuerying(results: [.success(.tagFilterIntegrationSearchPage(filters))])
        let mapper = StaticCoreErrorMapper(mapping: .tagFilterFilterFailure())
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            searchQuerying: searcher,
            searchFiltering: facets,
            tagStore: tagStore,
            errorMapper: mapper
        )

        await model.selectFiles([detail.id])
        await model.runSearch(
            query: "",
            scope: .all,
            sort: .newestImported,
            sidebarRow: .tagFilterIntegrationRoot,
            filters: filters
        )
        await model.loadSearchFacets(query: "", scope: .all, sidebarRow: .tagFilterIntegrationRoot, filters: filters)
        await model.loadTagFilterRegistry(activeFileID: detail.id)
        model.beginSmartListFilterDraft(id: 42, name: "Tagged", filters: .empty)
        model.updateSmartListFilterDraft(filters)
        await model.loadSearchFacets(query: "", scope: .all, sidebarRow: .tagFilterIntegrationRoot, filters: filters)
        await model.retrySearchFacets()
        await model.retryTagFilterRegistry()

        await searcher.assertRequestFilters([filters])
        await facets.assertRequestFilters([filters, filters, filters])
        XCTAssertEqual(model.tagFilterRegistryState.errorMapping, .tagFilterFilterFailure())
        XCTAssertEqual(model.tagFilterRegistryState.tagSet?.availableTags.map(\.value), ["finance", "legal"])
        XCTAssertEqual(model.searchFacetsState.facets?.tags.map(\.value), ["finance", "tax", "archive"])
        await model.retryTagFilterRegistry()
        XCTAssertNil(model.tagFilterRegistryState.errorMapping)
        XCTAssertEqual(model.smartListFilterDraft?.filters, filters)
        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 42, name: "Tagged"))
        await tagStore.assertDetailTagListRequestFileIDs([detail.id, detail.id, detail.id])
        await tagStore.assertDetailTagAddRequests([])
        await tagStore.assertDetailTagRemoveRequests([])
    }

    @MainActor
    func testTagFilterSidebarTagsEntryOpensSameTagFilterRouteWithoutMutatingTags() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 220, currentName: "sidebar-tags.pdf")
        let tagStore = DetailTagRecordingStore(listResults: [.success(.tagFilterRegistryFixture(fileID: detail.id))])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            searchQuerying: MainListRecordingSearchQuerying(
                results: [.success(.tagFilterIntegrationSearchPage(.empty))]
            ),
            searchFiltering: MainListRecordingSearchFiltering(results: [.success(.tagFilterIntegrationFacets())]),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagFilterFilterFailure())
        )

        model.enterSearch(context: .sidebar("tag-filters-sidebar-tags-filter"))
        await model.loadTagFilterRegistry(activeFileID: detail.id)

        XCTAssertEqual(
            model.lastSearchExitContext,
            .sidebar("tag-filters-sidebar-tags-filter")
        )

        await tagStore.assertDetailTagListRequests([
            DetailTagListRequest(repoPath: "/tmp/repo", fileID: detail.id)
        ])
        await tagStore.assertDetailTagAddRequests([])
        await tagStore.assertDetailTagRemoveRequests([])
    }
}

private extension RepositorySidebarRowSnapshot {
    static let tagFilterIntegrationRoot = RepositorySidebarRowSnapshot.testFixture()
}

private extension SearchResultPageSnapshot {
    static func tagFilterIntegrationSearchPage(_ filters: SearchFilterStateSnapshot) -> SearchResultPageSnapshot {
        .testFixture(
            query: "",
            totalCount: filters.tags.isEmpty ? 0 : 1
        )
    }
}

private extension SearchFacetsSnapshot {
    static func tagFilterIntegrationFacets() -> SearchFacetsSnapshot {
        SearchFacetsSnapshot.testFixture(totalCount: 42) {
            $0.tags = [
                .testFixture(
                    value: "finance",
                    label: "Finance",
                    count: 24,
                    selected: true
                ),
                .testFixture(value: "tax", label: "Tax", count: 8, selected: true),
                .testFixture(value: "archive", label: "Archive", disabled: true)
            ]
            $0.activeFilterCount = 1
        }
    }
}

private extension CoreErrorMappingSnapshot {
    static func tagFilterFilterFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "Could not load tags",
            severity: .medium,
            suggestedAction: "Retry tag filter loading.",
            recoverability: .retryable,
            rawContext: "tag-filters tags-filter"
        )
    }
}
