@testable import AreaMatrix
import XCTest

typealias AICallLogListRequest = (filter: AICallLogFilterSnapshot, pagination: AICallLogPaginationSnapshot)

private struct AICallLogListRequestExpectation {
    let feature: AICallLogFeatureSnapshot?
    let route: AICallLogRouteSnapshot?
    let status: AICallLogStatusSnapshot?
    let occurredAfter: Int64?
    let occurredBefore: Int64?
    let searchQuery: String?
    let limit: Int64
    let offset: Int64
}

actor RecordingAICallLogLister: CoreAICallLogListing {
    private var pageQueue: TestValueQueue<AICallLogPageSnapshot>
    private let error: Error?
    private var recordedRequests: [AICallLogListRequest] = []

    init(page: AICallLogPageSnapshot) {
        pageQueue = TestValueQueue(values: [page], missingValue: AICallLogPageSnapshot.emptyTestPage)
        error = nil
    }

    init(pages: [AICallLogPageSnapshot] = [], error: Error? = nil) {
        pageQueue = TestValueQueue(values: pages, missingValue: AICallLogPageSnapshot.emptyTestPage)
        self.error = error
    }

    func listAICalls(
        repoPath _: String,
        filter: AICallLogFilterSnapshot,
        pagination: AICallLogPaginationSnapshot
    ) async throws -> AICallLogPageSnapshot {
        recordedRequests.append((filter, pagination))
        if let error { throw error }
        return pageQueue.next()
    }

    func assertFirstAICallLogListRequest(
        feature: AICallLogFeatureSnapshot? = nil,
        route: AICallLogRouteSnapshot? = nil,
        status: AICallLogStatusSnapshot? = nil,
        occurredAfter: Int64? = nil,
        occurredBefore: Int64? = nil,
        searchQuery: String? = nil,
        limit: Int64 = 100,
        offset: Int64 = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertAICallLogListRequest(
            recordedRequests.first,
            expected: AICallLogListRequestExpectation(
                feature: feature,
                route: route,
                status: status,
                occurredAfter: occurredAfter,
                occurredBefore: occurredBefore,
                searchQuery: searchQuery,
                limit: limit,
                offset: offset
            ),
            file: file,
            line: line
        )
    }

    func assertLastAICallLogListRequest(
        feature: AICallLogFeatureSnapshot? = nil,
        route: AICallLogRouteSnapshot? = nil,
        status: AICallLogStatusSnapshot? = nil,
        occurredAfter: Int64? = nil,
        occurredBefore: Int64? = nil,
        searchQuery: String? = nil,
        limit: Int64 = 100,
        offset: Int64 = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertAICallLogListRequest(
            recordedRequests.last,
            expected: AICallLogListRequestExpectation(
                feature: feature,
                route: route,
                status: status,
                occurredAfter: occurredAfter,
                occurredBefore: occurredBefore,
                searchQuery: searchQuery,
                limit: limit,
                offset: offset
            ),
            file: file,
            line: line
        )
    }

    private func assertAICallLogListRequest(
        _ request: AICallLogListRequest?,
        expected: AICallLogListRequestExpectation,
        file: StaticString,
        line: UInt
    ) {
        guard let request else {
            return XCTFail("Expected an AI call log list request.", file: file, line: line)
        }
        XCTAssertEqual(request.filter.feature, expected.feature, file: file, line: line)
        XCTAssertEqual(request.filter.route, expected.route, file: file, line: line)
        XCTAssertEqual(request.filter.status, expected.status, file: file, line: line)
        XCTAssertEqual(request.filter.occurredAfter, expected.occurredAfter, file: file, line: line)
        XCTAssertEqual(request.filter.occurredBefore, expected.occurredBefore, file: file, line: line)
        XCTAssertEqual(request.filter.searchQuery, expected.searchQuery, file: file, line: line)
        XCTAssertEqual(request.pagination.limit, expected.limit, file: file, line: line)
        XCTAssertEqual(request.pagination.offset, expected.offset, file: file, line: line)
    }
}

actor RecordingAICallLogClearer: CoreAICallLogClearing {
    private var recordedRequests: [AICallLogClearRequestSnapshot] = []

    func clearAICallLog(repoPath _: String,
                        request: AICallLogClearRequestSnapshot) async throws -> AICallLogClearReportSnapshot {
        recordedRequests.append(request)
        return AICallLogClearReportSnapshot(
            deletedCount: Int64(request.entryIds.count),
            remainingCount: 0,
            clearedAt: 1_700_000_100
        )
    }

    func assertFirstAICallLogClearRequest(
        scope: AICallLogClearScopeSnapshot,
        entryIDs: [Int64],
        olderThan: Int64? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request = recordedRequests.first else {
            return XCTFail("Expected an AI call log clear request.", file: file, line: line)
        }
        XCTAssertEqual(request.scope, scope, file: file, line: line)
        XCTAssertEqual(request.entryIds, entryIDs, file: file, line: line)
        XCTAssertEqual(request.olderThan, olderThan, file: file, line: line)
    }

    func assertNoAICallLogClearRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests, [], file: file, line: line)
    }
}

extension AICallLogPageSnapshot {
    static func emptyTestPage() -> AICallLogPageSnapshot {
        AICallLogPageSnapshot(
            totalCount: 0,
            records: [],
            limit: 100,
            offset: 0,
            hasMore: false,
            retentionDays: 90,
            redactionPolicy: "API keys, full prompts, outputs, notes, and file contents are redacted."
        )
    }
}
