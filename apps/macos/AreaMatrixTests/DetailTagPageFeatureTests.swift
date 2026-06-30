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
        await model.loadSelectedFileTags()
        await model.addSelectedFileTag("bad/tag")
        let addRequests = await tagStore.addRequests()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(addRequests, [
            DetailTagMutationRequest(repoPath: "/tmp/repo", fileID: detail.id, tag: "bad/tag")
        ])
        XCTAssertEqual(model.detailTagEditorState, .failed(
            fileID: detail.id,
            operation: .add("bad/tag"),
            mapping,
            previous: initialTags
        ))
        XCTAssertEqual(model.detailTagEditorState.tagSet, initialTags)
        XCTAssertNil(model.detailTagUndoToast)
        XCTAssertEqual(mappedErrors, [CoreError.InvalidPath(path: "bad/tag")])
        XCTAssertFalse(DetailTagInputCommitPolicy.shouldClearSubmittedQuery(
            submittedTag: "bad/tag",
            state: model.detailTagEditorState
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
        await model.loadSelectedFileTags()
        await model.removeSelectedFileTag("clienta")
        let removeRequests = await tagStore.removeRequests()

        XCTAssertEqual(removeRequests, [
            DetailTagMutationRequest(repoPath: "/tmp/repo", fileID: detail.id, tag: "clienta")
        ])
        XCTAssertEqual(model.detailTagEditorState, .failed(
            fileID: detail.id,
            operation: .remove("clienta"),
            mapping,
            previous: initialTags
        ))
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["clienta"])
        XCTAssertNil(model.detailTagUndoToast)
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
        await model.loadSelectedFileTags()
        await model.addSelectedFileTag("clienta")
        XCTAssertEqual(model.detailTagUndoToast?.fileID, first.id)

        await model.selectFiles([second.id])
        XCTAssertNil(model.detailTagUndoToast)

        await model.undoLastDetailTagChange()
        let removeRequests = await tagStore.removeRequests()
        XCTAssertEqual(removeRequests, [])
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
        await model.addSelectedFileTag("clienta")
        await model.removeSelectedFileTag("clienta")
        let addRequests = await tagStore.addRequests()
        let removeRequests = await tagStore.removeRequests()

        XCTAssertEqual(addRequests, [])
        XCTAssertEqual(removeRequests, [])
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

        await model.runSearch(
            query: "",
            scope: .all,
            sort: .newestImported,
            sidebarRow: .tagFilterRoot,
            filters: filters
        )
        await model.loadSearchFacets(
            query: "",
            scope: .all,
            sidebarRow: .tagFilterRoot,
            filters: filters
        )

        XCTAssertEqual(model.searchState.request?.filters.tags, ["finance", "Tax"])
        XCTAssertEqual(model.searchFacetsState.facets?.tags.map(\.label), ["Finance", "Tax", "Archive"])
        let tagStoreCalls = await tagStore.recordedCalls()
        XCTAssertEqual(tagStoreCalls, [])
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
        await model.loadSearchFacets(query: "tag", scope: .all, sidebarRow: .tagFilterRoot, filters: .empty)
        await model.loadTagFilterRegistry(activeFileID: detail.id)
        let options = TagFilterRegistryPresentation.options(
            registryState: model.tagFilterRegistryState,
            facetsState: model.searchFacetsState
        )
        let listRequests = await tagStore.listRequests()

        XCTAssertEqual(listRequests, [DetailTagListRequest(repoPath: "/tmp/repo", fileID: detail.id)])
        XCTAssertEqual(options.map(\.value), ["finance", "tax", "archive", "legal"])
        XCTAssertEqual(options.first { $0.value == "legal" }?.countDisplayText, "--")
        XCTAssertEqual(options.first { $0.value == "legal" }?.disabled, false)
        let addRequests = await tagStore.addRequests()
        let removeRequests = await tagStore.removeRequests()
        XCTAssertEqual(addRequests, [])
        XCTAssertEqual(removeRequests, [])
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

        await model.loadTagFilterRegistry(activeFileID: detail.id)
        await model.loadTagFilterRegistry(activeFileID: detail.id)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.tagFilterRegistryState, .failed(fileID: detail.id, mapping, previous: registry))
        XCTAssertEqual(model.tagFilterRegistryState.tagSet, registry)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "tag registry locked")])
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

        await model.loadTagFilterRegistry(activeFileID: detail.id)
        model.clearDetail()

        XCTAssertEqual(model.tagFilterRegistryState, .idle)
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
