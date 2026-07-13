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

        let expectedConfig = RepoConfigSnapshot.testFixture(repoPath: repoURL.path)

        guard let opening = requireMainEmptyRoute(model) else { return }
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

private func makeSearchFiltersUserControlsEditedFilters(now: Date) -> SearchFilterStateSnapshot {
    SearchFilterEditing.settingIncludeDeleted(
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
}

final class MainSearchFiltersPageFeatureTests: XCTestCase {
    @MainActor
    func testSearchFiltersSearchFiltersDriveSearchFilesAndFacetCountsThroughSearchFiltersCore() async {
        let tree = RepositoryTreeNodeSnapshot.searchFiltersFixtureTree()
        guard let row = requireSidebarRow(tree, id: "docs/contracts") else { return }
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

        await searcher.assertSearchRequests([
            .testFixture(
                query: "合同",
                scope: .current,
                currentPath: "docs/contracts",
                category: "docs",
                filters: filters,
                sort: .relevance
            )
        ])
        await facetLoader.assertSearchFacetRequests([
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
        guard let row = requireSidebarRow(tree, id: "docs/contracts") else { return }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let editedFilters = makeSearchFiltersUserControlsEditedFilters(now: now)
        let expectedFilters = SearchFilterStateSnapshot.testFixture(
            category: "docs",
            fileKind: "pdf",
            tags: ["finance"],
            modifiedAfter: 1_797_408_000,
            storageMode: .indexed,
            includeDeleted: true
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

        await searcher.assertSearchRequests([
            .testFixture(
                query: "合同",
                scope: .current,
                currentPath: "docs/contracts",
                category: "docs",
                filters: expectedFilters,
                sort: .newestImported
            )
        ])
        XCTAssertEqual(editedFilters, expectedFilters)
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
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "facet db locked")])

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
