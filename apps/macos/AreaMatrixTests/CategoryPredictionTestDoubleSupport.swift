@testable import AreaMatrix

struct CategoryPredictionRequest: Equatable {
    var repoPath: String
    var filename: String
}

actor RecordingCategoryPredictor: CoreCategoryPredicting {
    typealias Request = CategoryPredictionRequest

    private let repeatingResult: Swift.Result<ClassifyResultSnapshot, Error>?
    private var queuedResults: [Swift.Result<ClassifyResultSnapshot, Error>]
    private var requestsStorage: [CategoryPredictionRequest] = []

    init(result: ClassifyResultSnapshot) {
        repeatingResult = .success(result)
        queuedResults = []
    }

    init(result: Swift.Result<ClassifyResultSnapshot, Error>) {
        repeatingResult = result
        queuedResults = []
    }

    init(results: [Swift.Result<ClassifyResultSnapshot, Error>]) {
        repeatingResult = nil
        queuedResults = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requestsStorage.append(CategoryPredictionRequest(repoPath: repoPath, filename: filename))
        if let repeatingResult {
            return try repeatingResult.get()
        }
        guard !queuedResults.isEmpty else {
            throw CoreError.Classify(reason: "missing test result")
        }

        return try queuedResults.removeFirst().get()
    }

    func recordedRequests() -> [CategoryPredictionRequest] {
        requestsStorage
    }

    func requests() -> [CategoryPredictionRequest] {
        requestsStorage
    }
}

actor MappedCategoryPredictor: CoreCategoryPredicting {
    typealias Request = CategoryPredictionRequest

    private let resultsByFilename: [String: Swift.Result<ClassifyResultSnapshot, Error>]
    private var requestsStorage: [CategoryPredictionRequest] = []

    init(resultsByFilename: [String: Swift.Result<ClassifyResultSnapshot, Error>]) {
        self.resultsByFilename = resultsByFilename
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requestsStorage.append(CategoryPredictionRequest(repoPath: repoPath, filename: filename))
        guard let result = resultsByFilename[filename] else {
            throw CoreError.Classify(reason: "missing test result")
        }

        return try result.get()
    }

    func recordedRequests() -> [CategoryPredictionRequest] {
        requestsStorage
    }

    func requests() -> [CategoryPredictionRequest] {
        requestsStorage
    }
}
