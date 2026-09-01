@testable import AreaMatrix
import AreaMatrixFeatureAI
import XCTest

actor AICategorySuggestionSuggestionBridge: CoreAIClassificationSuggesting {
    private let result: Swift.Result<AIClassificationSuggestionState, Error>
    private var requests: [AIClassificationSuggestionRequestState] = []

    init(result: Swift.Result<AIClassificationSuggestionState, Error>) {
        self.result = result
    }

    func suggestCategoryWithAI(
        repoPath _: String,
        request: AIClassificationSuggestionRequestState
    ) async throws -> AIClassificationSuggestionState {
        requests.append(request)
        return try result.get()
    }

    func assertAIClassificationSuggestionRequests(
        _ expectedRequests: [AIClassificationSuggestionRequestState],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }
}

actor AICategorySuggestionFallbackBridge: CoreAIClassificationFallbackStatusReading {
    enum Response {
        case success(AIFallbackStatusSnapshot)
        case failure(CoreError)
        case unexpected
    }

    private let response: Response
    private var requests: [AIFallbackStatusRequestSnapshot] = []

    init(status: AIFallbackStatusSnapshot? = nil) {
        response = status.map(Response.success) ?? .unexpected
    }

    init(error: CoreError) {
        response = .failure(error)
    }

    func classificationFallbackStatus(
        repoPath _: String,
        request: AIFallbackStatusRequestSnapshot
    ) async throws -> AIFallbackStatusSnapshot {
        requests.append(request)
        switch response {
        case let .success(status):
            return status
        case let .failure(error):
            throw error
        case .unexpected:
            throw CoreError.Internal(message: "unexpected fallback status request")
        }
    }

    func assertSingleAIFallbackStatusRequest(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AIFallbackStatusRequestSnapshot? {
        XCTAssertEqual(requests.count, 1, file: file, line: line)
        return requests.first
    }
}
