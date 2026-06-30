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
            request: CreateSavedSearchRequestSnapshot(
                name: "Finance",
                query: SavedSearchQuerySnapshot(request: request),
                icon: "magnifyingglass",
                color: nil,
                pinned: true
            )
        )
        let resultFile = FileEntrySnapshot.savedSearchSavedSearchFixture()
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.savedSearchSavedSearchFixture(
                request: SearchQueryRequestSnapshot(savedSearchQuery: saved.query),
                files: [resultFile]
            ))
        ])
        let model = MainFileListModel(
            opening: .savedSearchSavedSearchFixture(repoPath: "/tmp/repo", tree: .savedSearchSavedSearchFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
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
        XCTAssertEqual(model.searchState.request, SearchQueryRequestSnapshot(savedSearchQuery: saved.query))
        let recordedRequests = await searcher.recordedSmartListRequests()
        XCTAssertEqual(recordedRequests, [
            MainListSmartListRequestRecord(repoPath: "/tmp/repo", savedSearchID: 77, limit: 50, offset: 0)
        ])
        XCTAssertEqual(model.files, [resultFile])
    }

    @MainActor
    func testSavedSearchSidebarSelectionRestoresCachedSavedSearchQuery() async {
        let request = SearchQueryRequestSnapshot.savedSearchSavedSearchFixture(query: "Finance")
        let saved = SavedSearchSnapshot.savedSearchFixture(
            id: 77,
            request: CreateSavedSearchRequestSnapshot(
                name: "Finance",
                query: SavedSearchQuerySnapshot(request: request),
                icon: "magnifyingglass",
                color: nil,
                pinned: true
            )
        )
        let resultFile = FileEntrySnapshot.savedSearchSavedSearchFixture()
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.savedSearchSavedSearchFixture(
                request: SearchQueryRequestSnapshot(savedSearchQuery: saved.query),
                files: [resultFile]
            ))
        ])
        let model = MainFileListModel(
            opening: .savedSearchSavedSearchFixture(
                repoPath: "/tmp/repo",
                tree: .savedSearchSavedSearchFixtureTree().insertingSavedSearch(saved)
            ),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: StaticCoreErrorMapper(mapping: .savedSearchSavedSearchDbFixture())
        )

        await model.restoreSavedSearch(saved)

        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 77, name: "Finance"))
        XCTAssertEqual(
            model.searchState.request,
            SearchQueryRequestSnapshot(savedSearchQuery: saved.query)
        )
        XCTAssertEqual(model.files, [resultFile])
        let recordedRequests = await searcher.recordedSmartListRequests()
        XCTAssertEqual(recordedRequests, [
            MainListSmartListRequestRecord(repoPath: "/tmp/repo", savedSearchID: 77, limit: 50, offset: 0)
        ])
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
        let store = SmartListRecordingSavedSearchStore(results: [.listSuccess([alpha, pinnedOld, pinnedNew])])
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
        let store = SmartListRecordingSavedSearchStore(results: [.listFailure(CoreError.Db(message: "db locked"))])
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

            let recordedErrors = await mapper.recordedErrors()
            XCTAssertEqual(tree.sidebarRows.filter { !$0.isSmartList }.map(\.displayName), ["inbox"])
            XCTAssertEqual(tree.sidebarRows.filter(\.isSmartList), [])
            XCTAssertEqual(mapped, mapping)
            XCTAssertEqual(recordedErrors, [CoreError.Db(message: "db locked")])
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

private extension SearchQueryRequestSnapshot {
    static func savedSearchSavedSearchFixture(query: String) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .all,
            currentPath: nil,
            category: nil,
            filters: SearchFilterStateSnapshot(
                category: "docs",
                fileKind: "pdf",
                tags: ["finance"],
                tagMatchMode: .all,
                importedAfter: nil,
                importedBefore: nil,
                modifiedAfter: 1_700_000_000,
                modifiedBefore: nil,
                storageMode: .copied,
                includeDeleted: false
            ),
            sort: .relevance,
            limit: 50,
            offset: 0
        )
    }
}

private extension SavedSearchSnapshot {
    static func savedSearchFixture(id: Int64, request: CreateSavedSearchRequestSnapshot) -> SavedSearchSnapshot {
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

    static func smartListFixture(
        id: Int64,
        name: String,
        pinned: Bool,
        updatedAt: Int64
    ) -> SavedSearchSnapshot {
        let request = SearchQueryRequestSnapshot.savedSearchSavedSearchFixture(query: name)
        return SavedSearchSnapshot(
            id: id,
            name: name,
            query: SavedSearchQuerySnapshot(request: request),
            icon: "magnifyingglass",
            color: nil,
            pinned: pinned,
            createdAt: 1_700_000_000,
            updatedAt: updatedAt
        )
    }
}

private actor SmartListRecordingSavedSearchStore: CoreSavedSearchCRUD {
    enum Result {
        case listSuccess([SavedSearchSnapshot])
        case listFailure(Error)
    }

    private var results: [Result]
    private var listRepoPaths: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func createSavedSearch(
        repoPath _: String,
        request _: CreateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        throw CoreError.Internal(message: "create_saved_search is not used by smart-list-management list tests")
    }

    func listSavedSearches(repoPath: String) async throws -> [SavedSearchSnapshot] {
        listRepoPaths.append(repoPath)
        guard !results.isEmpty else { return [] }
        switch results.removeFirst() {
        case let .listSuccess(saved):
            return saved
        case let .listFailure(error):
            throw error
        }
    }

    func recordedListRepoPaths() -> [String] {
        listRepoPaths
    }
}

private extension SearchResultPageSnapshot {
    static func savedSearchSavedSearchFixture(
        request: SearchQueryRequestSnapshot,
        files: [FileEntrySnapshot]
    ) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: request.query,
            totalCount: Int64(files.count),
            results: files.map { file in
                SearchFileResultSnapshot(file: file, score: 1, matches: [], noteSnippet: nil)
            },
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

private func sortedSavedSearches(_ savedSearches: [SavedSearchSnapshot]) -> [SavedSearchSnapshot] {
    savedSearches.sorted { lhs, rhs in
        if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
        if lhs.pinned { return lhs.updatedAt > rhs.updatedAt }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

private extension RepositoryTreeNodeSnapshot {
    func appendingSortedSavedSearches(_ savedSearches: [SavedSearchSnapshot]) -> RepositoryTreeNodeSnapshot {
        sortedSavedSearches(savedSearches).reduce(self) { tree, saved in
            tree.insertingSavedSearch(saved)
        }
    }
}

private extension FileEntrySnapshot {
    static func savedSearchSavedSearchFixture() -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 203,
            path: "docs/finance/report.pdf",
            originalName: "report.pdf",
            currentName: "report.pdf",
            category: "docs",
            sizeBytes: 128,
            hashSha256: "saved-search-hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100,
            availability: .available
        )
    }
}

private extension RepositoryOpeningResult {
    static func savedSearchSavedSearchFixture(
        repoPath: String,
        tree: RepositoryTreeNodeSnapshot
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func savedSearchSavedSearchFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "inbox",
                    displayName: "inbox",
                    fileCount: 0,
                    children: []
                )
            ]
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func savedSearchSavedSearchDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Saved search is unavailable.",
            severity: .high,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "saved search db locked"
        )
    }
}
