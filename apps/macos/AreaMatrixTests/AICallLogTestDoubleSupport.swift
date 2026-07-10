@testable import AreaMatrix
import XCTest

typealias AICallLogListRequest = (filter: AiCallLogFilter, pagination: AiCallLogPagination)

private struct AICallLogListRequestExpectation {
    let feature: AiCallLogFeature?
    let route: AiCallLogRoute?
    let status: AiCallLogStatus?
    let occurredAfter: Int64?
    let occurredBefore: Int64?
    let searchQuery: String?
    let limit: Int64
    let offset: Int64
}

actor RecordingAICallLogLister: CoreAICallLogListing {
    private var pages: [AiCallLogPage]
    private let error: Error?
    private var recordedRequests: [AICallLogListRequest] = []

    init(page: AiCallLogPage) {
        pages = [page]
        error = nil
    }

    init(pages: [AiCallLogPage] = [], error: Error? = nil) {
        self.pages = pages
        self.error = error
    }

    func listAICalls(
        repoPath _: String,
        filter: AiCallLogFilter,
        pagination: AiCallLogPagination
    ) async throws -> AiCallLogPage {
        recordedRequests.append((filter, pagination))
        if let error { throw error }
        return pages.isEmpty ? .emptyTestPage() : pages.removeFirst()
    }

    func assertFirstRequest(
        feature: AiCallLogFeature? = nil,
        route: AiCallLogRoute? = nil,
        status: AiCallLogStatus? = nil,
        occurredAfter: Int64? = nil,
        occurredBefore: Int64? = nil,
        searchQuery: String? = nil,
        limit: Int64 = 100,
        offset: Int64 = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequest(
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

    func assertLastRequest(
        feature: AiCallLogFeature? = nil,
        route: AiCallLogRoute? = nil,
        status: AiCallLogStatus? = nil,
        occurredAfter: Int64? = nil,
        occurredBefore: Int64? = nil,
        searchQuery: String? = nil,
        limit: Int64 = 100,
        offset: Int64 = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequest(
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

    private func assertRequest(
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
    private var recordedRequests: [AiCallLogClearRequest] = []

    func clearAICallLog(repoPath _: String, request: AiCallLogClearRequest) async throws -> AiCallLogClearReport {
        recordedRequests.append(request)
        return AiCallLogClearReport(
            deletedCount: Int64(request.entryIds.count),
            remainingCount: 0,
            clearedAt: 1_700_000_100
        )
    }

    func assertFirstRequest(
        scope: AiCallLogClearScope,
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

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRequests, [], file: file, line: line)
    }
}

extension AiCallLogPage {
    static func emptyTestPage() -> AiCallLogPage {
        AiCallLogPage(
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
