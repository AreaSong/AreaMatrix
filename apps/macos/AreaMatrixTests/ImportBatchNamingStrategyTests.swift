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
        XCTAssertEqual(content.fileListModel.searchState.request, SearchQueryRequestSnapshot(savedSearchQuery: saved.query))
        XCTAssertEqual(content.fileListModel.files, [resultFile])
        let recordedRequests = await searcher.recordedRequests().map(\.request)
        XCTAssertEqual(recordedRequests, [
            SearchQueryRequestSnapshot(savedSearchQuery: saved.query)
        ])
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
