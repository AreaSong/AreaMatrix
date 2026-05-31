@testable import AreaMatrix
import XCTest

// swiftlint:disable:next type_body_length
final class DetailTagPageFeatureTests: XCTestCase {
    @MainActor
    func testS207AddTagFailurePreservesPreviousStateAndDoesNotOfferUndo() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 207, currentName: "tag-fail.pdf")
        let initialTags = TagSetSnapshot.s207Fixture(fileID: detail.id, values: ["urgent"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            addResults: [.failure(CoreError.InvalidPath(path: "bad/tag"))]
        )
        let mapping = CoreErrorMappingSnapshot.s207TagDb()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
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
    func testS207RemoveTagFailureKeepsChipAndDoesNotOfferUndo() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 208, currentName: "remove-fail.pdf")
        let initialTags = TagSetSnapshot.s207Fixture(fileID: detail.id, values: ["clienta"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            removeResults: [.failure(CoreError.Db(message: "tag relation locked"))]
        )
        let mapping = CoreErrorMappingSnapshot.s207TagDb()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: mapping)
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
    func testS207SwitchingFilesClearsUndoToastAndBlocksStaleUndo() async {
        let first = FileEntrySnapshot.detailMetaFixture(id: 210, currentName: "first.pdf")
        let second = FileEntrySnapshot.detailMetaFixture(id: 211, currentName: "second.pdf")
        let initialTags = TagSetSnapshot.s207Fixture(fileID: first.id, values: [])
        let addedTags = TagSetSnapshot.s207Fixture(fileID: first.id, values: ["clienta"])
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(initialTags)],
            addResults: [.success(addedTags)]
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailTagFileDetailer(files: [first, second]),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
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
    func testS207InputCommitPolicyClearsOnlyAfterSuccessfulAdd() {
        let fileID: Int64 = 209
        let failedState = DetailTagEditorState.failed(
            fileID: fileID,
            operation: .add("ClientA"),
            .s207TagDb(),
            previous: TagSetSnapshot.s207Fixture(fileID: fileID, values: [])
        )
        let loadedState = DetailTagEditorState.loaded(
            fileID: fileID,
            TagSetSnapshot.s207Fixture(fileID: fileID, values: ["clienta"])
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
    func testS208TagsFilterUsesC202FacetsAndSearchFiltersOnly() async {
        let filters = SearchFilterEditing.settingTagMatchMode(
            .all,
            in: SearchFilterEditing.togglingTag(
                "Tax",
                in: SearchFilterEditing.togglingTag("finance", in: .empty)
            )
        )
        let tagStore = S208ForbiddenTagStore()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .failure(CoreError.FileNotFound(path: "unused"))),
            searchQuerying: MainListRecordingSearchQuerying(results: [.success(.s208SearchPage(filters: filters))]),
            searchFiltering: MainListRecordingSearchFiltering(results: [.success(.s208Facets())]),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.runSearch(
            query: "",
            scope: .all,
            sort: .newestImported,
            sidebarRow: .s208Root,
            filters: filters
        )
        await model.loadSearchFacets(
            query: "",
            scope: .all,
            sidebarRow: .s208Root,
            filters: filters
        )

        XCTAssertEqual(model.searchState.request?.filters.tags, ["finance", "Tax"])
        XCTAssertEqual(model.searchFacetsState.facets?.tags.map(\.label), ["Finance", "Tax", "Archive"])
        let tagStoreCalls = await tagStore.recordedCalls()
        XCTAssertEqual(tagStoreCalls, [])
    }

    @MainActor
    func testS208TagsFilterLoadsC205RegistryWithoutMutatingTags() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 208, currentName: "registry.pdf")
        let registry = TagSetSnapshot.s208RegistryFixture(fileID: detail.id)
        let tagStore = DetailTagRecordingStore(listResults: [.success(registry)])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            searchQuerying: MainListRecordingSearchQuerying(results: [.success(.s208SearchPage(filters: .empty))]),
            searchFiltering: MainListRecordingSearchFiltering(results: [.success(.s208Facets())]),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([detail.id])
        await model.loadSearchFacets(query: "tag", scope: .all, sidebarRow: .s208Root, filters: .empty)
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
    func testS208TagRegistryFailureMapsErrorAndPreservesPreviousOptions() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 209, currentName: "registry-fail.pdf")
        let registry = TagSetSnapshot.s208RegistryFixture(fileID: detail.id)
        let mapping = CoreErrorMappingSnapshot.s207TagDb()
        let tagStore = DetailTagRecordingStore(
            listResults: [.success(registry), .failure(CoreError.Db(message: "tag registry locked"))]
        )
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
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
    func testS208ClearingDetailClearsTagRegistryAnchorState() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 210, currentName: "clear-registry.pdf")
        let registry = TagSetSnapshot.s208RegistryFixture(fileID: detail.id)
        let tagStore = DetailTagRecordingStore(listResults: [.success(registry)])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.loadTagFilterRegistry(activeFileID: detail.id)
        model.clearDetail()

        XCTAssertEqual(model.tagFilterRegistryState, .idle)
    }

    func testS208TagsFilterEditingIsCaseInsensitiveAndDoesNotCreateTags() {
        var filters = SearchFilterEditing.togglingTag("Finance", in: .empty)
        filters = SearchFilterEditing.togglingTag("finance", in: filters)
        XCTAssertEqual(filters.tags, [])
        filters = SearchFilterEditing.removingTag(
            "FINANCE",
            from: SearchFilterEditing.togglingTag("Finance", in: .empty)
        )
        XCTAssertEqual(filters.tags, [])
        XCTAssertEqual(
            TagFacetFiltering.visibleTags(query: "TAX", facets: SearchFacetsSnapshot.s208Facets().tags).map(\.value),
            ["tax"]
        )
    }

    @MainActor
    func testS223C219LoadsDeterministicSuggestionsThroughTagStore() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 223, currentName: "invoice_2026.pdf")
        let report = TagSuggestionReportSnapshot.s223Fixture(fileID: detail.id)
        let tagStore = DetailTagRecordingStore(suggestionResults: [.success(report)])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileTagSuggestions()
        let requests = await tagStore.suggestionRequests()

        XCTAssertEqual(requests, [
            TagSuggestionRequestRecord(repoPath: "/tmp/repo", request: .s223(fileID: detail.id))
        ])
        XCTAssertEqual(model.detailTagSuggestionState.report?.suggestions.map(\.slug), ["finance", "tax"])
        XCTAssertEqual(model.detailTagSuggestionState.selectedIDs, ["s223-finance"])
        XCTAssertFalse(model.detailTagSuggestionState.report?.contentsRead ?? true)
        XCTAssertFalse(model.detailTagSuggestionState.report?.aiUsed ?? true)
        XCTAssertFalse(model.detailTagSuggestionState.report?.networkUsed ?? true)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileID, detail.id)
    }

    @MainActor
    func testS223C219CommandPalettePresentationTargetsSelectedFile() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 228, currentName: "command.pdf")
        let model = MainFileListModel.s223Fixture(detail: detail)

        await model.selectFiles([detail.id])
        model.presentSelectedFileTagSuggestions(source: .commandPalette)
        let request = model.tagSuggestionPresentationRequest

        XCTAssertEqual(request?.fileID, detail.id)
        XCTAssertEqual(request?.source, .commandPalette)
        XCTAssertEqual(model.detailTabRequest, .automatic(.meta))
        if let request {
            model.consumeTagSuggestionPresentationRequest(request)
        }
        XCTAssertNil(model.tagSuggestionPresentationRequest)
    }

    @MainActor
    func testS223C205ManualFallbackUsesTagCrudWithoutApplyingSuggestions() async {
        // swiftlint:disable:next large_tuple
        let scenarios: [(Int64, String, String, DetailTagRecordingStore.SuggestionResult)] = [
            (229, "manual-tag.pdf", "manual", .success(.s223EmptyFixture(fileID: 229))),
            (230, "suggestion-fail.pdf", "fallback", .failure(CoreError.Db(message: "suggestion locked")))
        ]
        for scenario in scenarios {
            let detail = FileEntrySnapshot.detailMetaFixture(id: scenario.0, currentName: scenario.1)
            let tagStore = DetailTagRecordingStore(
                listResults: [.success(.s207Fixture(fileID: detail.id, values: [scenario.2]))],
                suggestionResults: [scenario.3]
            )
            let model = MainFileListModel.s223Fixture(detail: detail, tagStore: tagStore)

            await model.selectFiles([detail.id])
            await model.loadSelectedFileTagSuggestions()
            await model.loadSelectedFileTags()

            let listRequests = await tagStore.listRequests()
            let applyRequests = await tagStore.applySuggestionRequests()
            XCTAssertEqual(listRequests, [
                DetailTagListRequest(repoPath: "/tmp/repo", fileID: detail.id)
            ])
            XCTAssertEqual(applyRequests, [])
            XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), [scenario.2])
        }
    }

    @MainActor
    func testS223C219ApplySelectedUsesCoreApplyAndRefreshesUndoAction() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 224, currentName: "invoice_2026.pdf")
        let report = TagSuggestionReportSnapshot.s223Fixture(fileID: detail.id)
        let applyReport = TagSuggestionApplyReportSnapshot.s223Applied(fileID: detail.id)
        let tagStore = DetailTagRecordingStore(
            suggestionResults: [.success(report)],
            applySuggestionResults: [.success(applyReport)]
        )
        let undoStore = S223UndoActionStore(actions: [.s223ApplySuggestion(token: "undo-s223")])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            undoActionStore: undoStore,
            changeLogLister: DetailLogRecordingChangeLister(entries: [.s223Applied()]),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileTagSuggestions()
        let undoState = await model.applySelectedFileTagSuggestions()
        let applyRequests = await tagStore.applySuggestionRequests()
        let undoRequests = await undoStore.listRequests()

        XCTAssertEqual(applyRequests, [
            ApplyTagSuggestionsRequestRecord(
                repoPath: "/tmp/repo",
                request: ApplyTagSuggestionsRequestSnapshot(
                    fileID: detail.id,
                    suggestions: [
                        ApplyTagSuggestionItemSnapshot(
                            suggestionID: "s223-finance",
                            slug: "finance",
                            displayName: "Finance"
                        )
                    ]
                )
            )
        ])
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["finance"])
        XCTAssertEqual(model.detailTagSuggestionState.appliedReport?.undoToken, "undo-s223")
        XCTAssertEqual(undoRequests, ["/tmp/repo"])
        XCTAssertEqual(undoState?.action?.actionID, "undo-s223")
        XCTAssertNotNil(model.detailLogState.entries)
    }

    @MainActor
    func testS223C219SelectAllPreservesExplicitWeakMatchesOnly() {
        let report = TagSuggestionReportSnapshot.s223Fixture(fileID: 225)
        let loaded = DetailTagSuggestionState.loaded(fileID: 225, report, [])
        let strongOnly = DetailTagSuggestionAction.selectingAll(in: loaded)

        XCTAssertEqual(strongOnly.selectedIDs, ["s223-finance"])

        let withExplicitWeak = DetailTagSuggestionAction.togglingSelection(
            suggestionID: "s223-tax",
            in: strongOnly
        )
        let selectedAll = DetailTagSuggestionAction.selectingAll(in: withExplicitWeak)

        XCTAssertEqual(selectedAll.selectedIDs, ["s223-finance", "s223-tax"])
    }

    @MainActor
    func testS223C219EditModeValidatesInvalidDuplicateAlreadyAddedAndReadOnly() {
        let report = TagSuggestionReportSnapshot.s223Fixture(fileID: 226, existingValues: ["finance"])
        let loaded = DetailTagSuggestionState.loaded(
            fileID: 226,
            report,
            ["s223-finance", "s223-tax"]
        )
        let editing = DetailTagSuggestionAction.startingEdit(in: loaded, disabledReason: nil)
        let invalid = DetailTagSuggestionAction.updatingSlug(
            suggestionID: "s223-tax",
            slug: "bad/tag",
            in: editing,
            disabledReason: nil
        )
        let duplicate = DetailTagSuggestionAction.updatingSlug(
            suggestionID: "s223-tax",
            slug: "finance",
            in: editing,
            disabledReason: nil
        )
        let readOnly = DetailTagSuggestionAction.startingEdit(
            in: loaded,
            disabledReason: "Tag store is read-only."
        )

        XCTAssertEqual(editing.editSession?.drafts.first?.status.label, "Already added")
        XCTAssertEqual(invalid.editSession?.drafts.last?.status.label, "Invalid")
        XCTAssertEqual(duplicate.editSession?.drafts.last?.status.label, "Duplicate")
        XCTAssertEqual(readOnly.editSession?.drafts.map(\.status.label), ["Blocked", "Blocked"])
        XCTAssertEqual(DetailTagSuggestionAction.editedItems(in: invalid), [])
        XCTAssertEqual(DetailTagSuggestionAction.cancelingEdit(in: invalid).selectedIDs, ["s223-finance", "s223-tax"])
    }

    @MainActor
    func testS223C219ApplyEditedUsesEditedValuesAndRestoresEditModeOnFailure() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 227, currentName: "invoice_2026.pdf")
        let report = TagSuggestionReportSnapshot.s223Fixture(fileID: detail.id)
        let applyReport = TagSuggestionApplyReportSnapshot.s223Applied(
            fileID: detail.id,
            suggestionID: "s223-tax",
            slug: "tax-review",
            displayName: "Tax Review"
        )
        let tagStore = DetailTagRecordingStore(
            suggestionResults: [.success(report)],
            applySuggestionResults: [.success(applyReport), .failure(CoreError.Db(message: "tag write failed"))]
        )
        let model = MainFileListModel.s223Fixture(detail: detail, tagStore: tagStore)

        await model.selectFiles([detail.id])
        await model.loadSelectedFileTagSuggestions()
        model.clearSelectedFileTagSuggestions()
        model.toggleSelectedFileTagSuggestion("s223-tax")
        model.startEditingSelectedFileTagSuggestions()
        model.updateSelectedFileTagSuggestionDisplayName(suggestionID: "s223-tax", displayName: "  ")
        model.updateSelectedFileTagSuggestionSlug(suggestionID: "s223-tax", slug: "tax-review")

        _ = await model.applyEditedSelectedFileTagSuggestions()
        let firstApply = await tagStore.applySuggestionRequests()
        model.startEditingSelectedFileTagSuggestions()
        _ = await model.applyEditedSelectedFileTagSuggestions()

        XCTAssertEqual(firstApply.last?.request.suggestions, [
            ApplyTagSuggestionItemSnapshot(
                suggestionID: "s223-tax",
                slug: "tax-review",
                displayName: "tax-review"
            )
        ])
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["tax-review"])
        XCTAssertNotNil(model.detailTagSuggestionState.editSession)
        XCTAssertNotNil(model.detailTagEditorState.failure)
    }

}
