@testable import AreaMatrix

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

    func recordedRequests() -> [AIClassificationSuggestionRequestState] {
        requests
    }
}

actor AICategorySuggestionFallbackBridge: CoreAIClassificationFallbackStatusReading {
    enum Response {
        case success(AiFallbackStatus)
        case failure(CoreError)
        case unexpected
    }

    private let response: Response
    private var requests: [AiFallbackStatusRequest] = []

    init(status: AiFallbackStatus? = nil) {
        response = status.map(Response.success) ?? .unexpected
    }

    init(error: CoreError) {
        response = .failure(error)
    }

    func classificationFallbackStatus(
        repoPath _: String,
        request: AiFallbackStatusRequest
    ) async throws -> AiFallbackStatus {
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

    func recordedRequests() -> [AiFallbackStatusRequest] {
        requests
    }
}
