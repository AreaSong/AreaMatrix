@testable import AreaMatrix

struct MainListFallbackRequestRecord: Equatable {
    var repoPath: String
    var request: AiFallbackStatusRequest
}

typealias MainListSearchRequestRecord = SearchQueryRequestRecord
typealias MainListSmartListRequestRecord = SmartListRunRequestRecord
typealias MainListRecordingSearchQuerying = RecordingSearchQuerying

actor MainListRecordingSemanticSearcher: CoreSemanticSearching {
    private let page: SearchResultPageSnapshot

    init(page: SearchResultPageSnapshot) {
        self.page = page
    }

    func semanticSearch(repoPath _: String,
                        request _: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        page
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        throw CoreError.Internal(message: "semantic-search ai-fallback-core test does not build the semantic index")
    }
}

actor MainListRecordingSemanticFallbackReader: CoreSemanticFallbackStatusReading {
    private let status: AiFallbackStatus
    private var requests: [MainListFallbackRequestRecord] = []

    init(status: AiFallbackStatus) {
        self.status = status
    }

    func semanticFallbackStatus(repoPath: String, request: AiFallbackStatusRequest) async throws -> AiFallbackStatus {
        requests.append(MainListFallbackRequestRecord(repoPath: repoPath, request: request))
        return status
    }

    func recordedRequests() -> [MainListFallbackRequestRecord] {
        requests
    }
}

typealias MainListRecordingFileLister = RecordingFileLister
