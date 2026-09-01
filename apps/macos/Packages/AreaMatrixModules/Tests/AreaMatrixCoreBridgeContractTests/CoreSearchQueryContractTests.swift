@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreSearchQueryContractTests: XCTestCase {
    func testSearchCapabilityCanBeImplementedWithoutGeneratedBindings() async throws {
        let page = SearchResultPageSnapshot(
            query: "report",
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
        let searcher: any CoreSearchQuerying = SearchQueryDouble(page: page)

        let result = try await searcher.searchFiles(
            repoPath: "/tmp/library",
            request: .pageFeature(
                query: "report",
                scope: .all,
                sort: .relevance,
                context: SearchQueryPageContext(
                    currentPath: "ignored/path",
                    category: "ignored-category",
                    filters: .empty
                ),
                mode: .normal
            )
        )

        XCTAssertEqual(result, page)
    }

    func testPageFeatureOnlyRetainsCurrentScopeContext() {
        let all = SearchQueryRequestSnapshot.pageFeature(
            query: "report",
            scope: .all,
            sort: .newestModified,
            context: SearchQueryPageContext(
                currentPath: "inbox",
                category: "documents",
                filters: .empty
            )
        )
        let current = SearchQueryRequestSnapshot.pageFeature(
            query: "report",
            scope: .current,
            sort: .newestModified,
            context: SearchQueryPageContext(
                currentPath: "inbox",
                category: "documents",
                filters: .empty
            )
        )

        XCTAssertNil(all.currentPath)
        XCTAssertNil(all.category)
        XCTAssertEqual(all.limit, 50)
        XCTAssertEqual(all.offset, 0)
        XCTAssertEqual(current.currentPath, "inbox")
        XCTAssertEqual(current.category, "documents")
    }

    func testSemanticPageExcludesDedupedNormalResults() {
        let semanticResult = searchResult(id: 1, path: "semantic.md")
        let dedupedNormalResult = searchResult(id: 2, path: "deduped.md")
        let visibleNormalResult = searchResult(id: 3, path: "normal.md")
        let page = SemanticSearchResultPageSnapshot(
            query: "report",
            semanticTotalCount: 1,
            normalTotalCount: 2,
            semanticMatches: [
                SemanticSearchMatchSnapshot(
                    result: semanticResult,
                    relevance: 0.9,
                    matchedReason: "title",
                    usedFields: [.fileName],
                    route: .local,
                    alsoMatchedNormalSearch: true,
                    callLogID: nil,
                    privacyRuleID: nil
                )
            ],
            normalMatches: [
                SemanticNormalSearchMatchSnapshot(result: dedupedNormalResult, dedupedBySemantic: true),
                SemanticNormalSearchMatchSnapshot(result: visibleNormalResult, dedupedBySemantic: false)
            ],
            dedupedNormalCount: 1,
            indexStatus: .ready,
            route: .local,
            fallbackReason: nil,
            fallbackMessage: nil,
            callLogID: nil,
            privacyRuleID: nil,
            lowConfidence: false
        )

        XCTAssertEqual(page.visibleResults.map(\.file.id), [1, 3])
        XCTAssertEqual(page.visibleTotalCount, 2)
    }

    func testDefaultSmartListCapabilityReportsTypedUnavailableError() async {
        let searcher = SearchQueryDouble(
            page: SearchResultPageSnapshot(
                query: "",
                totalCount: 0,
                results: [],
                diagnostics: [],
                indexStatus: .unavailable
            )
        )

        do {
            _ = try await searcher.runSmartList(repoPath: "/tmp/library", savedSearchID: 7, limit: 50, offset: 0)
            XCTFail("Expected the default smart-list capability to be unavailable")
        } catch {
            XCTAssertEqual(error as? CoreSearchCapabilityUnavailableError, .smartListRunning)
        }
    }

    private func searchResult(id: Int64, path: String) -> SearchFileResultSnapshot {
        SearchFileResultSnapshot(
            file: FileEntrySnapshot(
                id: id,
                path: path,
                originalName: path,
                currentName: path,
                category: "documents",
                sizeBytes: 10,
                hashSha256: "hash-\(id)",
                storageMode: "Indexed",
                origin: "Adopted",
                sourcePath: nil,
                importedAt: 1,
                updatedAt: 2
            ),
            score: 1,
            matches: [],
            noteSnippet: nil
        )
    }
}

private struct SearchQueryDouble: CoreSearchQuerying {
    let page: SearchResultPageSnapshot

    func searchFiles(repoPath _: String,
                     request _: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        page
    }
}
