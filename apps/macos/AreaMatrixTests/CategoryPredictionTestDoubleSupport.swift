@testable import AreaMatrix
import XCTest

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

    func assertRecordedRequests(
        _ expectedRequests: [CategoryPredictionRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }

    func assertRecordedRequestFilenames(
        _ expectedFilenames: Set<String>,
        repoPath expectedRepoPath: String? = nil,
        requestCount expectedRequestCount: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestsStorage.assertCategoryPredictionRequestFilenames(
            expectedFilenames,
            repoPath: expectedRepoPath,
            requestCount: expectedRequestCount,
            file: file,
            line: line
        )
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

    func assertRecordedRequests(
        _ expectedRequests: [CategoryPredictionRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }

    func assertRecordedRequestFilenames(
        _ expectedFilenames: Set<String>,
        repoPath expectedRepoPath: String? = nil,
        requestCount expectedRequestCount: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestsStorage.assertCategoryPredictionRequestFilenames(
            expectedFilenames,
            repoPath: expectedRepoPath,
            requestCount: expectedRequestCount,
            file: file,
            line: line
        )
    }
}

private extension [CategoryPredictionRequest] {
    func assertCategoryPredictionRequestFilenames(
        _ expectedFilenames: Set<String>,
        repoPath expectedRepoPath: String?,
        requestCount expectedRequestCount: Int?,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(Set(map(\.filename)), expectedFilenames, file: file, line: line)
        if let expectedRepoPath {
            XCTAssertTrue(
                allSatisfy { $0.repoPath == expectedRepoPath },
                "Expected all category prediction requests to use repoPath \(expectedRepoPath)",
                file: file,
                line: line
            )
        }
        if let expectedRequestCount {
            XCTAssertEqual(count, expectedRequestCount, file: file, line: line)
        }
    }
}
