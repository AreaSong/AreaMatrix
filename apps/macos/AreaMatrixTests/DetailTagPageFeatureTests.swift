@testable import AreaMatrix
import XCTest

final class DetailTagPageFeatureTests: XCTestCase {
    @MainActor
    func testTagAddAddTagFailurePreservesPreviousStateAndDoesNotOfferUndo() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 207, currentName: "tag-fail.pdf")
        let initialTags = TagSetSnapshot.tagAddFixture(fileID: detail.id, values: ["urgent"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            addResults: [.failure(CoreError.InvalidPath(path: "bad/tag"))]
        )
        let mapping = CoreErrorMappingSnapshot.tagAddTagDb()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: mapper
        )

        await model.selectFiles([detail.id])
        await model.detailTagModel.loadSelectedFileTags()
        await model.detailTagModel.addSelectedFileTag("bad/tag")

        await tagStore.assertDetailTagAddRequests([
            DetailTagMutationRequest(repoPath: "/tmp/repo", fileID: detail.id, tag: "bad/tag")
        ])
        XCTAssertEqual(model.detailTagModel.editorState, .failed(
            fileID: detail.id,
            operation: .add("bad/tag"),
            mapping,
            previous: initialTags
        ))
        XCTAssertEqual(model.detailTagModel.editorState.tagSet, initialTags)
        XCTAssertNil(model.detailTagModel.undoToast)
        await mapper.assertMappedCoreErrors([CoreError.InvalidPath(path: "bad/tag")])
        XCTAssertFalse(DetailTagInputCommitPolicy.shouldClearSubmittedQuery(
            submittedTag: "bad/tag",
            state: model.detailTagModel.editorState
        ))
    }

    @MainActor
    func testTagAddRemoveTagFailureKeepsChipAndDoesNotOfferUndo() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 208, currentName: "remove-fail.pdf")
        let initialTags = TagSetSnapshot.tagAddFixture(fileID: detail.id, values: ["clienta"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            removeResults: [.failure(CoreError.Db(message: "tag relation locked"))]
        )
        let mapping = CoreErrorMappingSnapshot.tagAddTagDb()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        await model.selectFiles([detail.id])
        await model.detailTagModel.loadSelectedFileTags()
        await model.detailTagModel.removeSelectedFileTag("clienta")

        await tagStore.assertDetailTagRemoveRequests([
            DetailTagMutationRequest(repoPath: "/tmp/repo", fileID: detail.id, tag: "clienta")
        ])
        XCTAssertEqual(model.detailTagModel.editorState, .failed(
            fileID: detail.id,
            operation: .remove("clienta"),
            mapping,
            previous: initialTags
        ))
        XCTAssertEqual(model.detailTagModel.editorState.tagSet?.fileTags.map(\.value), ["clienta"])
        XCTAssertNil(model.detailTagModel.undoToast)
    }

    @MainActor
    func testTagAddSwitchingFilesClearsUndoToastAndBlocksStaleUndo() async {
        let first = FileEntrySnapshot.detailMetaFixture(id: 210, currentName: "first.pdf")
        let second = FileEntrySnapshot.detailMetaFixture(id: 211, currentName: "second.pdf")
        let initialTags = TagSetSnapshot.tagAddFixture(fileID: first.id, values: [])
        let addedTags = TagSetSnapshot.tagAddFixture(fileID: first.id, values: ["clienta"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            addResults: [.success(addedTags)]
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailTagFileDetailer(files: [first, second]),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([first.id])
        await model.detailTagModel.loadSelectedFileTags()
        await model.detailTagModel.addSelectedFileTag("clienta")
        XCTAssertEqual(model.detailTagModel.undoToast?.fileID, first.id)

        await model.selectFiles([second.id])
        XCTAssertNil(model.detailTagModel.undoToast)

        await model.detailTagModel.undoLastDetailTagChange()
        await tagStore.assertDetailTagRemoveRequests([])
    }

    @MainActor
    func testTagAddWriteLockedSelectionDoesNotCallTagStoreMutations() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 212, currentName: "locked-tag.pdf")
        let tagStore = DetailTagRecordingStore()
        var opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [detail])
        opening.writeLockedFileIDs = [detail.id]
        let model = MainFileListModel(
            opening: opening,
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([detail.id])
        await model.detailTagModel.addSelectedFileTag("clienta")
        await model.detailTagModel.removeSelectedFileTag("clienta")

        await tagStore.assertDetailTagAddRequests([])
        await tagStore.assertDetailTagRemoveRequests([])
        XCTAssertEqual(model.writeActionDisabledReason(fileID: detail.id), .importLocked)
    }

    @MainActor
    func testTagAddInputCommitPolicyClearsOnlyAfterSuccessfulAdd() {
        let fileID: Int64 = 209
        let failedState = DetailTagEditorState.failed(
            fileID: fileID,
            operation: .add("ClientA"),
            .tagAddTagDb(),
            previous: TagSetSnapshot.tagAddFixture(fileID: fileID, values: [])
        )
        let loadedState = DetailTagEditorState.loaded(
            fileID: fileID,
            TagSetSnapshot.tagAddFixture(fileID: fileID, values: ["clienta"])
        )

        XCTAssertFalse(DetailTagInputCommitPolicy.shouldClearSubmittedQuery(
            submittedTag: " ClientA ",
            state: failedState
        ))
        XCTAssertTrue(DetailTagInputCommitPolicy.shouldClearSubmittedQuery(
            submittedTag: " ClientA ",
            state: loadedState
        ))
    }

    @MainActor
    func testTagFilterTagsFilterUsesSearchFiltersCoreFacetsAndSearchFiltersOnly() async {
        let filters = SearchFilterEditing.settingTagMatchMode(
            .all,
            in: SearchFilterEditing.togglingTag(
                "Tax",
                in: SearchFilterEditing.togglingTag("finance", in: .empty)
            )
        )
        let tagStore = TagFilterForbiddenTagStore()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .failure(CoreError.FileNotFound(path: "unused"))),
            searchQuerying: MainListRecordingSearchQuerying(
                results: [.success(.tagFilterSearchPage(filters: filters))]
            ),
            searchFiltering: MainListRecordingSearchFiltering(results: [.success(.tagFilterFacets())]),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.searchModel.runSearch(
            query: "",
            scope: .all,
            sort: .newestImported,
            sidebarRow: .tagFilterRoot,
            filters: filters
        )
        await model.searchModel.loadSearchFacets(
            query: "",
            scope: .all,
            sidebarRow: .tagFilterRoot,
            filters: filters
        )

        XCTAssertEqual(model.searchModel.searchState.request?.filters.tags, ["finance", "Tax"])
        XCTAssertEqual(model.searchModel.searchFacetsState.facets?.tags.map(\.label), ["Finance", "Tax", "Archive"])
        await tagStore.assertNoCalls()
    }

    @MainActor
    func testTagFilterTagsFilterLoadsTagCrudCoreRegistryWithoutMutatingTags() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 208, currentName: "registry.pdf")
        let registry = TagSetSnapshot.tagFilterRegistryFixture(fileID: detail.id)
        let tagStore = DetailTagRecordingStore(listResults: [.success(registry)])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            searchQuerying: MainListRecordingSearchQuerying(results: [.success(.tagFilterSearchPage(filters: .empty))]),
            searchFiltering: MainListRecordingSearchFiltering(results: [.success(.tagFilterFacets())]),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([detail.id])
        await model.searchModel.loadSearchFacets(query: "tag", scope: .all, sidebarRow: .tagFilterRoot, filters: .empty)
        await model.detailTagModel.loadTagFilterRegistry(activeFileID: detail.id)
        let options = TagFilterRegistryPresentation.options(
            registryState: model.detailTagModel.filterRegistryState,
            facetsState: model.searchModel.searchFacetsState
        )

        await tagStore.assertDetailTagListRequests([DetailTagListRequest(repoPath: "/tmp/repo", fileID: detail.id)])
        XCTAssertEqual(options.map(\.value), ["finance", "tax", "archive", "legal"])
        XCTAssertEqual(options.first { $0.value == "legal" }?.countDisplayText, "--")
        XCTAssertEqual(options.first { $0.value == "legal" }?.disabled, false)
        await tagStore.assertDetailTagAddRequests([])
        await tagStore.assertDetailTagRemoveRequests([])
    }

    @MainActor
    func testTagFilterTagRegistryFailureMapsErrorAndPreservesPreviousOptions() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 209, currentName: "registry-fail.pdf")
        let registry = TagSetSnapshot.tagFilterRegistryFixture(fileID: detail.id)
        let mapping = CoreErrorMappingSnapshot.tagAddTagDb()
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(registry), .failure(CoreError.Db(message: "tag registry locked"))]
        )
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: mapper
        )

        await model.detailTagModel.loadTagFilterRegistry(activeFileID: detail.id)
        await model.detailTagModel.loadTagFilterRegistry(activeFileID: detail.id)

        XCTAssertEqual(
            model.detailTagModel.filterRegistryState,
            .failed(fileID: detail.id, mapping, previous: registry)
        )
        XCTAssertEqual(model.detailTagModel.filterRegistryState.tagSet, registry)
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "tag registry locked")])
    }

    @MainActor
    func testTagFilterClearingDetailClearsTagRegistryAnchorState() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 210, currentName: "clear-registry.pdf")
        let registry = TagSetSnapshot.tagFilterRegistryFixture(fileID: detail.id)
        let tagStore = DetailTagRecordingStore(listResults: [.success(registry)])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.detailTagModel.loadTagFilterRegistry(activeFileID: detail.id)
        model.clearDetail()

        XCTAssertEqual(model.detailTagModel.filterRegistryState, .idle)
    }

    func testTagFilterTagsFilterEditingIsCaseInsensitiveAndDoesNotCreateTags() {
        var filters = SearchFilterEditing.togglingTag("Finance", in: .empty)
        filters = SearchFilterEditing.togglingTag("finance", in: filters)
        XCTAssertEqual(filters.tags, [])
        filters = SearchFilterEditing.removingTag(
            "FINANCE",
            from: SearchFilterEditing.togglingTag("Finance", in: .empty)
        )
        XCTAssertEqual(filters.tags, [])
        XCTAssertEqual(
            TagFacetFiltering.visibleTags(query: "TAX", facets: SearchFacetsSnapshot.tagFilterFacets().tags)
                .map(\.value),
            ["tax"]
        )
    }
}
