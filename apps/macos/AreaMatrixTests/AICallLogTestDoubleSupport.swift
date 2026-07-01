@testable import AreaMatrix

typealias AICallLogListRequest = (filter: AiCallLogFilter, pagination: AiCallLogPagination)

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

    func requests() -> [AICallLogListRequest] {
        recordedRequests
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

    func requests() -> [AiCallLogClearRequest] {
        recordedRequests
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
