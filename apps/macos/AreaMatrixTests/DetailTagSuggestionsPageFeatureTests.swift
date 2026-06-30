@testable import AreaMatrix
import XCTest

final class DetailTagSuggestionsPageFeatureTests: XCTestCase {
    @MainActor
    func testTagSuggestionsTagSuggestionsCoreLoadsDeterministicSuggestionsThroughTagStore() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 223, currentName: "invoice_2026.pdf")
        let report = TagSuggestionReportSnapshot.tagSuggestionsFixture(fileID: detail.id)
        let tagStore = DetailTagRecordingStore(suggestionResults: [.success(report)])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileTagSuggestions()
        let requests = await tagStore.suggestionRequests()

        XCTAssertEqual(requests, [
            TagSuggestionRequestRecord(repoPath: "/tmp/repo", request: .tagSuggestions(fileID: detail.id))
        ])
        XCTAssertEqual(model.detailTagSuggestionState.report?.suggestions.map(\.slug), ["finance", "tax"])
        XCTAssertEqual(model.detailTagSuggestionState.selectedIDs, ["tagSuggestions-finance"])
        XCTAssertFalse(model.detailTagSuggestionState.report?.contentsRead ?? true)
        XCTAssertFalse(model.detailTagSuggestionState.report?.aiUsed ?? true)
        XCTAssertFalse(model.detailTagSuggestionState.report?.networkUsed ?? true)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileID, detail.id)
    }

    @MainActor
    func testTagSuggestionsTagSuggestionsCoreCommandPalettePresentationTargetsSelectedFile() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 228, currentName: "command.pdf")
        let model = MainFileListModel.tagSuggestionsFixture(detail: detail)

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
    func testTagSuggestionsTagCrudCoreManualFallbackUsesTagCrudWithoutApplyingSuggestions() async {
        // swiftlint:disable:next large_tuple
        let scenarios: [(Int64, String, String, DetailTagRecordingStore.SuggestionResult)] = [
            (229, "manual-tag.pdf", "manual", .success(.tagSuggestionsEmptyFixture(fileID: 229))),
            (230, "suggestion-fail.pdf", "fallback", .failure(CoreError.Db(message: "suggestion locked")))
        ]
        for scenario in scenarios {
            let detail = FileEntrySnapshot.detailMetaFixture(id: scenario.0, currentName: scenario.1)
            let tagStore = DetailTagRecordingStore(
                listResults: [.success(.tagAddFixture(fileID: detail.id, values: [scenario.2]))],
                suggestionResults: [scenario.3]
            )
            let model = MainFileListModel.tagSuggestionsFixture(detail: detail, tagStore: tagStore)

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
    func testTagSuggestionsTagSuggestionsCoreApplySelectedUsesCoreApplyAndRefreshesUndoAction() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 224, currentName: "invoice_2026.pdf")
        let report = TagSuggestionReportSnapshot.tagSuggestionsFixture(fileID: detail.id)
        let applyReport = TagSuggestionApplyReportSnapshot.tagSuggestionsApplied(fileID: detail.id)
        let tagStore = DetailTagRecordingStore(
            suggestionResults: [.success(report)],
            applySuggestionResults: [.success(applyReport)]
        )
        let undoStore =
            TagSuggestionsUndoActionStore(actions: [.tagSuggestionsApplySuggestion(token: "undo-tagSuggestions")])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            undoActionStore: undoStore,
            changeLogLister: DetailLogRecordingChangeLister(entries: [.tagSuggestionsApplied()]),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
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
                            suggestionID: "tagSuggestions-finance",
                            slug: "finance",
                            displayName: "Finance"
                        )
                    ]
                )
            )
        ])
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["finance"])
        XCTAssertEqual(model.detailTagSuggestionState.appliedReport?.undoToken, "undo-tagSuggestions")
        XCTAssertEqual(undoRequests, ["/tmp/repo"])
        XCTAssertEqual(undoState?.action?.actionID, "undo-tagSuggestions")
        XCTAssertNotNil(model.detailLogState.entries)
    }

    @MainActor
    func testTagSuggestionsTagSuggestionsCoreSelectAllPreservesExplicitWeakMatchesOnly() {
        let report = TagSuggestionReportSnapshot.tagSuggestionsFixture(fileID: 225)
        let loaded = DetailTagSuggestionState.loaded(fileID: 225, report, [])
        let strongOnly = DetailTagSuggestionAction.selectingAll(in: loaded)

        XCTAssertEqual(strongOnly.selectedIDs, ["tagSuggestions-finance"])

        let withExplicitWeak = DetailTagSuggestionAction.togglingSelection(
            suggestionID: "tagSuggestions-tax",
            in: strongOnly
        )
        let selectedAll = DetailTagSuggestionAction.selectingAll(in: withExplicitWeak)

        XCTAssertEqual(selectedAll.selectedIDs, ["tagSuggestions-finance", "tagSuggestions-tax"])
    }

    @MainActor
    func testTagSuggestionsTagSuggestionsCoreEditModeValidatesInvalidDuplicateAlreadyAddedAndReadOnly() {
        let report = TagSuggestionReportSnapshot.tagSuggestionsFixture(fileID: 226, existingValues: ["finance"])
        let loaded = DetailTagSuggestionState.loaded(
            fileID: 226,
            report,
            ["tagSuggestions-finance", "tagSuggestions-tax"]
        )
        let editing = DetailTagSuggestionAction.startingEdit(in: loaded, disabledReason: nil)
        let invalid = DetailTagSuggestionAction.updatingSlug(
            suggestionID: "tagSuggestions-tax",
            slug: "bad/tag",
            in: editing,
            disabledReason: nil
        )
        let duplicate = DetailTagSuggestionAction.updatingSlug(
            suggestionID: "tagSuggestions-tax",
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
        XCTAssertEqual(
            DetailTagSuggestionAction.cancelingEdit(in: invalid).selectedIDs,
            ["tagSuggestions-finance", "tagSuggestions-tax"]
        )
    }

    @MainActor
    func testTagSuggestionsTagSuggestionsCoreApplyEditedUsesEditedValuesAndRestoresEditModeOnFailure() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 227, currentName: "invoice_2026.pdf")
        let report = TagSuggestionReportSnapshot.tagSuggestionsFixture(fileID: detail.id)
        let applyReport = TagSuggestionApplyReportSnapshot.tagSuggestionsApplied(
            fileID: detail.id,
            suggestionID: "tagSuggestions-tax",
            slug: "tax-review",
            displayName: "Tax Review"
        )
        let tagStore = DetailTagRecordingStore(
            suggestionResults: [.success(report)],
            applySuggestionResults: [.success(applyReport), .failure(CoreError.Db(message: "tag write failed"))]
        )
        let model = MainFileListModel.tagSuggestionsFixture(detail: detail, tagStore: tagStore)

        await model.selectFiles([detail.id])
        await model.loadSelectedFileTagSuggestions()
        model.clearSelectedFileTagSuggestions()
        model.toggleSelectedFileTagSuggestion("tagSuggestions-tax")
        model.startEditingSelectedFileTagSuggestions()
        model.updateSelectedFileTagSuggestionDisplayName(suggestionID: "tagSuggestions-tax", displayName: "  ")
        model.updateSelectedFileTagSuggestionSlug(suggestionID: "tagSuggestions-tax", slug: "tax-review")

        _ = await model.applyEditedSelectedFileTagSuggestions()
        let firstApply = await tagStore.applySuggestionRequests()
        model.startEditingSelectedFileTagSuggestions()
        _ = await model.applyEditedSelectedFileTagSuggestions()

        XCTAssertEqual(firstApply.last?.request.suggestions, [
            ApplyTagSuggestionItemSnapshot(
                suggestionID: "tagSuggestions-tax",
                slug: "tax-review",
                displayName: "tax-review"
            )
        ])
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["tax-review"])
        XCTAssertNotNil(model.detailTagSuggestionState.editSession)
        XCTAssertNotNil(model.detailTagEditorState.failure)
    }
}
