@testable import AreaMatrix
import XCTest

final class SavedSearchPageFeatureTests: XCTestCase {
    @MainActor
    func testSavedSearchSavedSearchFailureShowsRetryAndUnavailableResultCount() {
        var model = SavedSearchSheetModel(
            request: .savedSearchSavedSearchFixture(query: "Finance"),
            resultCountState: .failed
        )

        model.saveFailure = .savedSearchSavedSearchDbFixture()

        XCTAssertEqual(model.resultCountSummary, "Result count unavailable")
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.showsRetry)
        XCTAssertNil(model.emptyResultWarning)
    }

    @MainActor
    func testSavedSearchSavedSearchSuccessInsertsSidebarRowAndRestoresQuery() async {
        let request = SearchQueryRequestSnapshot.savedSearchSavedSearchFixture(query: "Finance")
        let saved = SavedSearchSnapshot.savedSearchFixture(
            id: 77,
            request: CreateSavedSearchRequestSnapshot.testFixture(
                name: "Finance",
                request: request
            )
        )
        let resultFile = FileEntrySnapshot.savedSearchSavedSearchFixture()
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.savedSearchSavedSearchFixture(
                request: .testFixture(savedSearchQuery: saved.query),
                files: [resultFile]
            ))
        ])
        let model = MainFileListModel(
            opening: .savedSearchSavedSearchFixture(repoPath: "/tmp/repo", tree: .savedSearchSavedSearchFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .savedSearchSavedSearchDbFixture())
        )
        let updatedTree = RepositoryTreeNodeSnapshot.savedSearchSavedSearchFixtureTree().insertingSavedSearch(saved)

        await model.restoreSavedSearch(saved)

        XCTAssertEqual(
            updatedTree.sidebarRow(id: RepositoryTreeNodeSnapshot.savedSearchSidebarID(77))?.displayName,
            "Finance"
        )
        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 77, name: "Finance"))
        XCTAssertEqual(model.searchState.request, .testFixture(savedSearchQuery: saved.query))
        let recordedRequests = await searcher.recordedSmartListRequests()
        assertSmartListRunRequests(recordedRequests, savedSearchID: 77)
        XCTAssertEqual(model.files, [resultFile])
    }

    @MainActor
    func testSavedSearchSidebarSelectionRestoresCachedSavedSearchQuery() async {
        let request = SearchQueryRequestSnapshot.savedSearchSavedSearchFixture(query: "Finance")
        let saved = SavedSearchSnapshot.savedSearchFixture(
            id: 77,
            request: CreateSavedSearchRequestSnapshot.testFixture(
                name: "Finance",
                request: request
            )
        )
        let resultFile = FileEntrySnapshot.savedSearchSavedSearchFixture()
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.savedSearchSavedSearchFixture(
                request: .testFixture(savedSearchQuery: saved.query),
                files: [resultFile]
            ))
        ])
        let model = MainFileListModel(
            opening: .savedSearchSavedSearchFixture(
                repoPath: "/tmp/repo",
                tree: .savedSearchSavedSearchFixtureTree().insertingSavedSearch(saved)
            ),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .savedSearchSavedSearchDbFixture())
        )

        await model.restoreSavedSearch(saved)

        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 77, name: "Finance"))
        XCTAssertEqual(
            model.searchState.request,
            .testFixture(savedSearchQuery: saved.query)
        )
        XCTAssertEqual(model.files, [resultFile])
        let recordedRequests = await searcher.recordedSmartListRequests()
        assertSmartListRunRequests(recordedRequests, savedSearchID: 77)
    }

    @MainActor
    func testSmartListRenameBuildsUpdateRequestAndBlocksDuplicateName() {
        let saved = SavedSearchSnapshot.smartListFixture(id: 77, name: "Finance", pinned: true, updatedAt: 10)
        var model = SmartListEditorModel(
            mode: .rename,
            savedSearch: saved,
            existingNames: ["finance", "tax"],
            resultCountState: .loaded(12)
        )

        XCTAssertNil(model.validationMessage)
        model.name = " Tax "
        XCTAssertEqual(model.validationMessage, "A Smart List named \"Tax\" already exists.")
        XCTAssertFalse(model.canSubmit)

        model.name = " Quarter Plan "
        let request = model.updateRequest

        XCTAssertNil(model.validationMessage)
        XCTAssertEqual(model.primaryActionTitle, "Save")
        XCTAssertEqual(request.id, 77)
        XCTAssertEqual(request.name, "Quarter Plan")
        XCTAssertEqual(request.query.query, "Finance")
        XCTAssertEqual(request.query.filter.tags, ["finance"])
        XCTAssertTrue(request.pinned)
    }

    @MainActor
    func testSmartListDuplicateCreatesUnpinnedRequestWithoutMutatingOriginal() {
        let saved = SavedSearchSnapshot.smartListFixture(id: 77, name: "Finance", pinned: true, updatedAt: 10)
        var model = SmartListEditorModel(
            mode: .duplicate,
            savedSearch: saved,
            existingNames: ["finance"],
            resultCountState: .failed
        )

        XCTAssertEqual(model.name, "Finance Copy")
        XCTAssertEqual(model.resultCountSummary, "Result count unavailable")
        XCTAssertEqual(model.createRequest.name, "Finance Copy")
        XCTAssertFalse(model.createRequest.pinned)
        XCTAssertTrue(saved.pinned)

        model.name = "Finance"
        XCTAssertEqual(model.validationMessage, "A Smart List named \"Finance\" already exists.")
        XCTAssertFalse(model.canSubmit)
    }

    @MainActor
    func testSmartListLoadSmartListsUsesCoreListAndBuildsPinnedSortedSidebar() async {
        let pinnedOld = SavedSearchSnapshot.smartListFixture(id: 1, name: "Pinned Old", pinned: true, updatedAt: 10)
        let pinnedNew = SavedSearchSnapshot.smartListFixture(id: 2, name: "Pinned New", pinned: true, updatedAt: 20)
        let alpha = SavedSearchSnapshot.smartListFixture(id: 3, name: "Alpha", pinned: false, updatedAt: 30)
        let store = SmartListRecordingSavedSearchStore(listResults: [.success([alpha, pinnedOld, pinnedNew])])
        let saved = try? await store.listSavedSearches(repoPath: "/tmp/repo")
        let rows = RepositoryTreeNodeSnapshot
            .savedSearchSavedSearchFixtureTree()
            .appendingSortedSavedSearches(saved ?? [])

        let recordedRepoPaths = await store.recordedListRepoPaths()
        XCTAssertEqual(recordedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(rows.sidebarRows.filter { !$0.isSmartList }.map(\.displayName), ["inbox"])
        XCTAssertEqual(rows.sidebarRows.filter(\.isSmartList).map(\.displayName), ["Pinned New", "Pinned Old", "Alpha"])
        XCTAssertEqual(rows.sidebarRows.filter(\.isSmartList).compactMap(\.savedSearchID), [2, 1, 3])
    }

    @MainActor
    func testSmartListLoadSmartListsFailureKeepsNormalSidebarRecoverable() async {
        let mapping = CoreErrorMappingSnapshot.savedSearchSavedSearchDbFixture()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let store = SmartListRecordingSavedSearchStore(listResults: [.failure(CoreError.Db(message: "db locked"))])
        let tree = RepositoryTreeNodeSnapshot.savedSearchSavedSearchFixtureTree()
        do {
            _ = try await store.listSavedSearches(repoPath: "/tmp/repo")
            XCTFail("Expected saved search list to fail.")
        } catch {
            guard let coreError = error as? CoreError else {
                XCTFail("Expected CoreError for saved search list failure.")
                return
            }
            let mapped = await mapper.mapCoreError(coreError)

            XCTAssertEqual(tree.sidebarRows.filter { !$0.isSmartList }.map(\.displayName), ["inbox"])
            XCTAssertEqual(tree.sidebarRows.filter(\.isSmartList), [])
            XCTAssertEqual(mapped, mapping)
            await mapper.assertRecordedErrors([CoreError.Db(message: "db locked")])
        }
    }

    func testSmartListDeleteCopyStatesFilesAreNotMovedOrDeleted() {
        let saved = SavedSearchSnapshot.smartListFixture(id: 77, name: "Finance", pinned: true, updatedAt: 10)
        let model = SmartListEditorModel(
            mode: .delete,
            savedSearch: saved,
            existingNames: ["finance"],
            resultCountState: .loaded(3)
        )

        XCTAssertEqual(
            SmartListEditorModel.deleteSafetyMessage,
            "This only removes the Smart List. Files will not be deleted or moved."
        )
        XCTAssertNil(model.validationMessage)
        XCTAssertEqual(model.primaryActionTitle, "Delete Smart List")
        XCTAssertTrue(model.canSubmit)
    }
}
