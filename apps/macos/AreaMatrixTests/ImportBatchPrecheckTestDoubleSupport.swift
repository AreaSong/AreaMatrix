@testable import AreaMatrix
import Foundation
import XCTest

actor ImportBatchStaticBatchFileLoader: ImportBatchCoreFileLoading {
    private let pagesByCategory: [String: [[FileEntrySnapshot]]]
    private var requests: [FileFilterSnapshot] = []

    init(pagesByCategory: [String: [[FileEntrySnapshot]]]) {
        self.pagesByCategory = pagesByCategory
    }

    func loadImportPreviewFiles(repoPath: String, categories: Set<String?>) async throws -> [FileEntrySnapshot] {
        try await ImportBatchCoreFileLoader.load(repoPath: repoPath, categories: categories) { _, filter in
            requests.append(filter)
            let categoryKey = filter.category ?? "__all__"
            let pages = pagesByCategory[categoryKey] ?? []
            let pageIndex = Int(filter.offset / max(filter.limit, 1))
            guard pageIndex < pages.count else { return [] }
            return pages[pageIndex]
        }
    }

    func assertLoadedAllFilesForDuplicatePrecheck(
        limit: Int64 = 200,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, [.testFixture(limit: limit)], file: file, line: line)
    }

    func assertLoadedFilesForNameConflictPrecheck(
        categories expectedCategories: [String],
        limit: Int64 = 200,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            requests,
            expectedCategories.map { .testFixture(category: $0, limit: limit) },
            file: file,
            line: line
        )
    }

    func assertNoPreviewFileLoads(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, [], file: file, line: line)
    }
}

struct ImportPrecheckRowsRequest: Equatable {
    var repoPath: String
    var rowIDs: [String]
    var destination: ImportBatchDestinationOption
}

typealias ImportBatchNameConflictPrecheckRequest = ImportPrecheckRowsRequest

actor ImportBatchStaticNameConflictPrechecker: ImportBatchNameConflictPrechecking {
    private let results: [String: ImportBatchNameConflictPrecheckResult]
    private var requests: [ImportBatchNameConflictPrecheckRequest] = []

    init(results: [String: ImportBatchNameConflictPrecheckResult]) {
        self.results = results
    }

    func precheckNameConflicts(
        repoPath: String,
        rows: [ImportBatchPreviewRow],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportBatchNameConflictPrecheckResult] {
        requests.append(ImportBatchNameConflictPrecheckRequest(
            repoPath: repoPath,
            rowIDs: rows.map(\.id),
            destination: destination
        ))
        return results
    }

    func assertPrecheckedNameConflictRows(
        repoPath: String,
        rowIDs: [String],
        destination: ImportBatchDestinationOption,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            requests,
            [ImportBatchNameConflictPrecheckRequest(
                repoPath: repoPath,
                rowIDs: rowIDs,
                destination: destination
            )],
            file: file,
            line: line
        )
    }

    func assertNoNameConflictPrechecks(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, [], file: file, line: line)
    }
}
