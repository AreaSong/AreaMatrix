@testable import AreaMatrix
import Foundation
import XCTest

final class CoreBridgeRepositoryTests: XCTestCase {
    @MainActor
    func testOnboardingLoadsConfiguredRepoThroughDefaultCoreBridge() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer { removeTestTemporaryItems(repoURL) }
        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)

        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: repoURL.path),
            helpOpener: NoopWelcomeHelpOpener()
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
        defer { removeTestTemporaryItems(repoURL) }

        let validation = try await CoreBridge().validateRepoPath(repoPath: repoURL.path)

        XCTAssertEqual(validation.repoPath, repoURL.path)
        XCTAssertTrue(validation.exists)
        XCTAssertTrue(validation.isDirectory)
        XCTAssertFalse(validation.isInsideAreaMatrix)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
    }

    func testCoreBridgeValidateInitializedRepoPathRequiresInitializedMetadata() async throws {
        let repoURL = try makeTemporaryRepoURL()
        defer { removeTestTemporaryItems(repoURL) }

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
    try makeTestTemporaryDirectory(named: "AreaMatrixCoreBridgeRepositoryTests")
}

final class MainSearchFiltersPageFeatureTests: XCTestCase {
    @MainActor
    func testSearchFiltersSearchFiltersDriveSearchFilesAndFacetCountsThroughSearchFiltersCore() async {
        let tree = RepositoryTreeNodeSnapshot.searchFiltersFixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let filters = SearchFilterStateSnapshot.testFixture(
            category: "docs",
            fileKind: "pdf",
            tags: ["finance"],
            tagMatchMode: .all,
            modifiedAfter: 1_700_000_000,
            storageMode: .copied
        )
        let searcher = MainListRecordingSearchQuerying(results: [.success(.searchFiltersSearchFixture(query: "合同"))])
        let facetLoader = MainListRecordingSearchFiltering(results: [.success(.searchFiltersFixture(active: 4))])
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            searchFiltering: facetLoader,
            errorMapper: StaticCoreErrorMapper(mapping: .searchFiltersDbFixture())
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
    func testSearchFiltersSearchFiltersUserControlsProduceNonEmptySearchFiltersCoreRequest() async {
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
                        in: SearchFilterStateSnapshot.testFixture(
                            category: SearchFilterEditing.optionalFacetValue("docs"),
                            fileKind: SearchFilterEditing.optionalFacetValue("pdf")
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
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: searcher,
            searchFiltering: MainListRecordingSearchFiltering(results: []),
            errorMapper: StaticCoreErrorMapper(mapping: .searchFiltersDbFixture())
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
    func testSearchFiltersSearchFiltersFailureMapsSearchFiltersCoreErrorAndCanRetryWithoutClearingSearch() async {
        let mapping = CoreErrorMappingSnapshot.searchFiltersDbFixture()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let facetLoader = MainListRecordingSearchFiltering(results: [
            .failure(CoreError.Db(message: "facet db locked")),
            .success(.searchFiltersFixture(active: 1))
        ])
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: .searchFiltersFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
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
    func testSearchFiltersClearSearchAlsoClearsSearchFiltersCoreFacetState() async {
        let model = MainFileListModel(
            opening: .searchFiltersFixture(repoPath: "/tmp/repo", tree: .searchFiltersFixtureTree()),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            searchFiltering: MainListRecordingSearchFiltering(results: [.success(.searchFiltersFixture(active: 2))]),
            errorMapper: StaticCoreErrorMapper(mapping: .searchFiltersDbFixture())
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
