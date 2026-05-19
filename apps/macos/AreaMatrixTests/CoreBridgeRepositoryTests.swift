@testable import AreaMatrix
import Foundation
import XCTest

final class CoreBridgeRepositoryTests: XCTestCase {
    @MainActor
    func testOnboardingLoadsConfiguredRepoThroughDefaultCoreBridge() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }
        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)

        let model = OnboardingModel(
            settingsReader: CoreBridgeTestSettingsReader(repoPath: repoURL.path),
            helpOpener: CoreBridgeTestHelpOpener()
        )

        await model.bootstrapIfNeeded()

        let expectedConfig = RepoConfigSnapshot(
            repoPath: repoURL.path,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )

        guard case let .mainEmpty(opening) = model.route else {
            return XCTFail("expected main empty route, got \(model.route)")
        }
        XCTAssertEqual(opening.config, expectedConfig)
        XCTAssertTrue(opening.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
    }

    func testCoreBridgePropagatesRealConfigError() async throws {
        do {
            _ = try await CoreBridge().loadConfig(repoPath: "")
            XCTFail("expected CoreError.Config")
        } catch let error as CoreError {
            guard case .Config = error else {
                return XCTFail("expected Config, got \(error)")
            }
        }
    }

    func testCoreBridgeValidatesTemporaryRepoPathWithoutCreatingMetadata() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }

        let validation = try await CoreBridge().validateRepoPath(repoPath: repoURL.path)

        XCTAssertEqual(validation.repoPath, repoURL.path)
        XCTAssertTrue(validation.exists)
        XCTAssertTrue(validation.isDirectory)
        XCTAssertFalse(validation.isInsideAreaMatrix)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
    }

    func testCoreBridgeValidateInitializedRepoPathRequiresInitializedMetadata() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }

        do {
            _ = try await CoreBridge().validateInitializedRepoPath(repoPath: repoURL.path)
            XCTFail("expected RepoNotInitialized")
        } catch let error as CoreError {
            guard case .RepoNotInitialized = error else {
                return XCTFail("expected RepoNotInitialized, got \(error)")
            }
        }
    }
}

private func makeTemporaryRepoURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixCoreBridgeRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct CoreBridgeTestSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

private struct CoreBridgeTestHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

final class MainSearchFiltersPageFeatureTests: XCTestCase {
    @MainActor
    func testS201SearchFiltersDriveSearchFilesAndFacetCountsThroughC202() async {
        let tree = RepositoryTreeNodeSnapshot.searchFiltersFixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let filters = SearchFilterStateSnapshot(
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
        )
        let searcher = MainListRecordingSearchQuerying(results: [.success(.searchFiltersSearchFixture(query: "合同"))])
        let facetLoader = MainListRecordingSearchFiltering(results: [.success(.searchFiltersFixture(active: 4))])
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            searchFiltering: facetLoader,
            errorMapper: MainListRecordingErrorMapper(mapping: .searchFiltersDbFixture())
        )

        await model.runSearch(
            query: " 合同 ",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: filters
        )
        await model.loadSearchFacets(query: " 合同 ", scope: .current, sidebarRow: row, filters: filters)

        let searchRequests = await searcher.recordedRequests().map(\.request)
        let facetRequests = await facetLoader.recordedRequests().map(\.request)
        XCTAssertEqual(searchRequests.first?.filters, filters)
        XCTAssertEqual(searchRequests.first?.currentPath, "docs/contracts")
        XCTAssertEqual(searchRequests.first?.category, "docs")
        XCTAssertEqual(facetRequests, [
            SearchFacetRequestSnapshot(
                query: "合同",
                scope: .current,
                currentPath: "docs/contracts",
                category: "docs",
                filters: filters
            )
        ])
        XCTAssertEqual(model.searchFacetsState.facets?.activeFilterCount, 4)
    }

    @MainActor
    func testS201SearchFiltersUserControlsProduceNonEmptyC202Request() async {
        let tree = RepositoryTreeNodeSnapshot.searchFiltersFixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let editedFilters = SearchFilterEditing.settingIncludeDeleted(
            true,
            in: SearchFilterEditing.settingStorage(
                SearchStorageModeSnapshot.indexed.rawValue,
                in: SearchFilterEditing.settingDatePreset(
                    .last30Days,
                    field: .modified,
                    in: SearchFilterEditing.settingSingleTag(
                        "finance",
                        in: SearchFilterStateSnapshot(
                            category: SearchFilterEditing.optionalFacetValue("docs"),
                            fileKind: SearchFilterEditing.optionalFacetValue("pdf"),
                            tags: [],
                            tagMatchMode: .any,
                            importedAfter: nil,
                            importedBefore: nil,
                            modifiedAfter: nil,
                            modifiedBefore: nil,
                            storageMode: nil,
                            includeDeleted: false
                        )
                    ),
                    now: now
                )
            )
        )
        let searcher = MainListRecordingSearchQuerying(results: [.success(.searchFiltersSearchFixture(query: "合同"))])
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            searchFiltering: MainListRecordingSearchFiltering(results: []),
            errorMapper: MainListRecordingErrorMapper(mapping: .searchFiltersDbFixture())
        )

        await model.runSearch(
            query: "合同",
            scope: .current,
            sort: .newestImported,
            sidebarRow: row,
            filters: editedFilters
        )

        let request = await searcher.recordedRequests().first?.request
        XCTAssertEqual(request?.filters.category, "docs")
        XCTAssertEqual(request?.filters.fileKind, "pdf")
        XCTAssertEqual(request?.filters.tags, ["finance"])
        XCTAssertEqual(request?.filters.modifiedAfter, 1_797_408_000)
        XCTAssertEqual(request?.filters.storageMode, .indexed)
        XCTAssertEqual(request?.filters.includeDeleted, true)
        XCTAssertGreaterThan(editedFilters.activeFilterCount, 0)
    }

    @MainActor
    func testS201SearchFiltersFailureMapsC202ErrorAndCanRetryWithoutClearingSearch() async {
        let mapping = CoreErrorMappingSnapshot.searchFiltersDbFixture()
        let mapper = MainListRecordingErrorMapper(mapping: mapping)
        let facetLoader = MainListRecordingSearchFiltering(results: [
            .failure(CoreError.Db(message: "facet db locked")),
            .success(.searchFiltersFixture(active: 1))
        ])
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: .searchFiltersFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            searchFiltering: facetLoader,
            errorMapper: mapper
        )

        await model.loadSearchFacets(
            query: "合同",
            scope: .all,
            sidebarRow: RepositoryTreeNodeSnapshot.searchFiltersFixtureTree().sidebarRows[0],
            filters: .empty
        )
        XCTAssertEqual(model.searchFacetsState.errorMapping, mapping)
        let mappedErrors = await mapper.recordedErrors()
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "facet db locked")])

        await model.retrySearchFacets()
        XCTAssertEqual(model.searchFacetsState.facets?.activeFilterCount, 1)
    }

    @MainActor
    func testS201ClearSearchAlsoClearsC202FacetState() async {
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: .searchFiltersFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            searchFiltering: MainListRecordingSearchFiltering(results: [.success(.searchFiltersFixture(active: 2))]),
            errorMapper: MainListRecordingErrorMapper(mapping: .searchFiltersDbFixture())
        )

        await model.loadSearchFacets(
            query: "合同",
            scope: .all,
            sidebarRow: RepositoryTreeNodeSnapshot.searchFiltersFixtureTree().sidebarRows[0],
            filters: .empty
        )
        model.clearSearch()

        XCTAssertEqual(model.searchFacetsState, .idle)
        XCTAssertEqual(model.searchState, .idle)
    }
}

struct MainListSearchFacetRequestRecord: Equatable {
    var repoPath: String
    var request: SearchFacetRequestSnapshot
}

actor MainListRecordingSearchFiltering: CoreSearchFiltering {
    enum Result {
        case success(SearchFacetsSnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [MainListSearchFacetRequestRecord] = []

    init(results: [Result]) {
        self.results = results
    }

    func listFilterFacets(repoPath: String, request: SearchFacetRequestSnapshot) async throws -> SearchFacetsSnapshot {
        requests.append(MainListSearchFacetRequestRecord(repoPath: repoPath, request: request))
        guard !results.isEmpty else {
            return .searchFiltersFixture(active: request.filters.activeFilterCount)
        }

        switch results.removeFirst() {
        case let .success(facets):
            return facets
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [MainListSearchFacetRequestRecord] {
        requests
    }
}

private extension RepositoryOpeningResult {
    static func searchFiltersFixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .searchFiltersFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

private extension RepoConfigSnapshot {
    static func searchFiltersFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
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
        )
    }
}

private extension SearchResultPageSnapshot {
    static func searchFiltersSearchFixture(query: String) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .ready
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
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 0,
                    children: [
                        RepositoryTreeNodeSnapshot(
                            slug: "contracts",
                            displayName: "contracts",
                            kind: "Subdir",
                            relativePath: "docs/contracts",
                            fileCount: 2,
                            depth: 2,
                            children: []
                        )
                    ]
                )
            ]
        )
    }
}

private extension SearchFacetsSnapshot {
    static func searchFiltersFixture(active: Int64) -> SearchFacetsSnapshot {
        SearchFacetsSnapshot(
            query: "合同",
            totalCount: 7,
            categories: [],
            fileKinds: [],
            tags: [],
            storageModes: [],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: nil,
                newestImportedAt: nil,
                oldestModifiedAt: nil,
                newestModifiedAt: nil
            ),
            activeFilterCount: active
        )
    }
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
