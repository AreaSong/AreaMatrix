@testable import AreaMatrix
import XCTest

final class ImportBatchNamingStrategyTests: XCTestCase {
    @MainActor
    func testS118BatchNamingStrategiesUpdateImportFilenames() async {
        let unsafeURL = URL(fileURLWithPath: "/tmp/Quarter:Plan?.pdf")
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )
        let rows = [
            ImportBatchPreviewRow.ready(
                url: unsafeURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "Suggested.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            )
        ]

        model.applyPreviewRows(
            rows,
            request: s118NamingRequest(urls: [unsafeURL]),
            selectedDestination: .autoClassify
        )
        XCTAssertEqual(model.rows.first?.suggestedName, "Suggested.pdf")
        model.updateNamingStrategy(.normalizedCharacters)
        XCTAssertEqual(model.rows.first?.suggestedName, "Quarter-Plan-.pdf")
        model.namingPrefix = "Batch"
        model.updateNamingStrategy(.uniformPrefix)
        XCTAssertEqual(model.rows.first?.suggestedName, "Batch-Quarter-Plan-.pdf")

        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "Batch-Quarter-Plan-.pdf",
                duplicateStrategy: .ask
            )
        ])
    }
}

final class SavedSearchPageFeatureTests: XCTestCase {
    @MainActor
    func testS203SavedSearchFailureShowsRetryAndUnavailableResultCount() {
        var model = SavedSearchSheetModel(
            request: .s203SavedSearchFixture(query: "Finance"),
            resultCountState: .failed
        )

        model.saveFailure = .s203SavedSearchDbFixture()

        XCTAssertEqual(model.resultCountSummary, "Result count unavailable")
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.showsRetry)
        XCTAssertNil(model.emptyResultWarning)
    }

    @MainActor
    func testS203SavedSearchSuccessInsertsSidebarRowAndRestoresQuery() async {
        let request = SearchQueryRequestSnapshot.s203SavedSearchFixture(query: "Finance")
        let saved = SavedSearchSnapshot.s203Fixture(
            id: 77,
            request: CreateSavedSearchRequestSnapshot(
                name: "Finance",
                query: SavedSearchQuerySnapshot(request: request),
                icon: "magnifyingglass",
                color: nil,
                pinned: true
            )
        )
        let resultFile = FileEntrySnapshot.s203SavedSearchFixture()
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.s203SavedSearchFixture(
                request: SearchQueryRequestSnapshot(savedSearchQuery: saved.query),
                files: [resultFile]
            ))
        ])
        let model = MainFileListModel(
            opening: .s203SavedSearchFixture(repoPath: "/tmp/repo", tree: .s203SavedSearchFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainListRecordingErrorMapper(mapping: .s203SavedSearchDbFixture())
        )
        let updatedTree = RepositoryTreeNodeSnapshot.s203SavedSearchFixtureTree().insertingSavedSearch(saved)

        await model.restoreSavedSearch(saved)

        XCTAssertEqual(
            updatedTree.sidebarRow(id: RepositoryTreeNodeSnapshot.savedSearchSidebarID(77))?.displayName,
            "Finance"
        )
        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 77, name: "Finance"))
        XCTAssertEqual(model.searchState.request, SearchQueryRequestSnapshot(savedSearchQuery: saved.query))
        XCTAssertEqual(model.files, [resultFile])
        let recordedRequests = await searcher.recordedRequests().map(\.request)
        XCTAssertEqual(recordedRequests, [
            SearchQueryRequestSnapshot(savedSearchQuery: saved.query)
        ])
    }

    @MainActor
    func testS203SidebarSelectionRestoresCachedSavedSearchQuery() async {
        let request = SearchQueryRequestSnapshot.s203SavedSearchFixture(query: "Finance")
        let saved = SavedSearchSnapshot.s203Fixture(
            id: 77,
            request: CreateSavedSearchRequestSnapshot(
                name: "Finance",
                query: SavedSearchQuerySnapshot(request: request),
                icon: "magnifyingglass",
                color: nil,
                pinned: true
            )
        )
        let resultFile = FileEntrySnapshot.s203SavedSearchFixture()
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.s203SavedSearchFixture(
                request: SearchQueryRequestSnapshot(savedSearchQuery: saved.query),
                files: [resultFile]
            ))
        ])
        var content = MainRepositoryContentView(
            opening: .s203SavedSearchFixture(
                repoPath: "/tmp/repo",
                tree: .s203SavedSearchFixtureTree().insertingSavedSearch(saved)
            ),
            state: .list,
            onImport: {},
            onDropImport: { _, _ in },
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainListRecordingErrorMapper(mapping: .s203SavedSearchDbFixture())
        )

        content.savedSearchesBySidebarID = [
            RepositoryTreeNodeSnapshot.savedSearchSidebarID(77): saved
        ]
        content.selectedSidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(77)
        let restored = await content.restoreSelectedSavedSearchIfNeeded()

        XCTAssertTrue(restored)
        XCTAssertEqual(content.filterText, "Finance")
        XCTAssertEqual(content.searchScope, saved.query.scope)
        XCTAssertEqual(content.searchSort, saved.query.sort)
        XCTAssertEqual(content.searchFilters, saved.query.filter)
        XCTAssertEqual(content.fileListModel.lastSearchExitContext, .smartList(id: 77, name: "Finance"))
        XCTAssertEqual(
            content.fileListModel.searchState.request,
            SearchQueryRequestSnapshot(savedSearchQuery: saved.query)
        )
        XCTAssertEqual(content.fileListModel.files, [resultFile])
        let recordedRequests = await searcher.recordedRequests().map(\.request)
        XCTAssertEqual(recordedRequests, [
            SearchQueryRequestSnapshot(savedSearchQuery: saved.query)
        ])
    }

    @MainActor
    func testS206RenameBuildsUpdateRequestAndBlocksDuplicateName() {
        let saved = SavedSearchSnapshot.s206Fixture(id: 77, name: "Finance", pinned: true, updatedAt: 10)
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
    func testS206DuplicateCreatesUnpinnedRequestWithoutMutatingOriginal() {
        let saved = SavedSearchSnapshot.s206Fixture(id: 77, name: "Finance", pinned: true, updatedAt: 10)
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
    func testS206LoadSmartListsUsesCoreListAndBuildsPinnedSortedSidebar() async {
        let pinnedOld = SavedSearchSnapshot.s206Fixture(id: 1, name: "Pinned Old", pinned: true, updatedAt: 10)
        let pinnedNew = SavedSearchSnapshot.s206Fixture(id: 2, name: "Pinned New", pinned: true, updatedAt: 20)
        let alpha = SavedSearchSnapshot.s206Fixture(id: 3, name: "Alpha", pinned: false, updatedAt: 30)
        let store = S206RecordingSavedSearchStore(results: [.listSuccess([alpha, pinnedOld, pinnedNew])])
        var content = MainRepositoryContentView(
            opening: .s203SavedSearchFixture(repoPath: "/tmp/repo", tree: .s203SavedSearchFixtureTree()),
            state: .list,
            onImport: {},
            onDropImport: { _, _ in },
            savedSearchStore: store,
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            errorMapper: MainListRecordingErrorMapper(mapping: .s203SavedSearchDbFixture())
        )

        await content.loadSmartLists()

        let recordedRepoPaths = await store.recordedListRepoPaths()
        XCTAssertNil(content.smartListLoadError)
        XCTAssertEqual(recordedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(content.regularSidebarRows.map(\.displayName), ["inbox"])
        XCTAssertEqual(content.smartListRows.map(\.displayName), ["Pinned New", "Pinned Old", "Alpha"])
        XCTAssertEqual(content.smartListRows.compactMap(\.savedSearchID), [2, 1, 3])
    }

    @MainActor
    func testS206LoadSmartListsFailureKeepsNormalSidebarRecoverable() async {
        let mapping = CoreErrorMappingSnapshot.s203SavedSearchDbFixture()
        let mapper = MainListRecordingErrorMapper(mapping: mapping)
        let store = S206RecordingSavedSearchStore(results: [.listFailure(CoreError.Db(message: "db locked"))])
        var content = MainRepositoryContentView(
            opening: .s203SavedSearchFixture(repoPath: "/tmp/repo", tree: .s203SavedSearchFixtureTree()),
            state: .list,
            onImport: {},
            onDropImport: { _, _ in },
            savedSearchStore: store,
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            errorMapper: mapper
        )

        await content.loadSmartLists()

        let recordedErrors = await mapper.recordedErrors()
        XCTAssertEqual(content.regularSidebarRows.map(\.displayName), ["inbox"])
        XCTAssertEqual(content.smartListRows, [])
        XCTAssertEqual(content.smartListLoadError, mapping)
        XCTAssertEqual(recordedErrors, [CoreError.Db(message: "db locked")])
    }

    func testS206DeleteCopyStatesFilesAreNotMovedOrDeleted() {
        let saved = SavedSearchSnapshot.s206Fixture(id: 77, name: "Finance", pinned: true, updatedAt: 10)
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

private func s118NamingRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs"]
    )
}

private extension SearchQueryRequestSnapshot {
    static func s203SavedSearchFixture(query: String) -> SearchQueryRequestSnapshot {
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

    static func s206Fixture(
        id: Int64,
        name: String,
        pinned: Bool,
        updatedAt: Int64
    ) -> SavedSearchSnapshot {
        let request = SearchQueryRequestSnapshot.s203SavedSearchFixture(query: name)
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

private actor S206RecordingSavedSearchStore: CoreSavedSearchCRUD {
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
        throw CoreError.Internal(message: "create_saved_search is not used by S2-06 list tests")
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
    static func s203SavedSearchFixture(
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

private extension FileEntrySnapshot {
    static func s203SavedSearchFixture() -> FileEntrySnapshot {
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
    static func s203SavedSearchFixture(
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
    static func s203SavedSearchFixtureTree() -> RepositoryTreeNodeSnapshot {
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
    static func s203SavedSearchDbFixture() -> CoreErrorMappingSnapshot {
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
