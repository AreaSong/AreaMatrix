@testable import AreaMatrix
import XCTest

struct CategoryPredictionRequest: Equatable {
    var repoPath: String
    var filename: String
}

actor RecordingCategoryPredictor: CoreCategoryPredicting {
    private var resultQueue: TestResultQueue<ClassifyResultSnapshot>
    private var requestsStorage: [CategoryPredictionRequest] = []

    init(result: ClassifyResultSnapshot) {
        resultQueue = TestResultQueue(result: .success(result), missingResult: Self.missingResult)
    }

    init(result: Swift.Result<ClassifyResultSnapshot, Error>) {
        resultQueue = TestResultQueue(result: result, missingResult: Self.missingResult)
    }

    init(results: [Swift.Result<ClassifyResultSnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results, missingResult: Self.missingResult)
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requestsStorage.append(CategoryPredictionRequest(repoPath: repoPath, filename: filename))
        return try resultQueue.next()
    }

    func assertCategoryPredictionRequests(
        _ expectedRequests: [CategoryPredictionRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }

    func assertNoCategoryPredictionRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertCategoryPredictionRequests([], file: file, line: line)
    }

    func assertCategoryPredictionFilenames(
        _ expectedFilenames: Set<String>,
        repoPath expectedRepoPath: String? = nil,
        requestCount expectedRequestCount: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestsStorage.assertCategoryPredictionFilenames(
            expectedFilenames,
            repoPath: expectedRepoPath,
            requestCount: expectedRequestCount,
            file: file,
            line: line
        )
    }

    private static func missingResult() -> Swift.Result<ClassifyResultSnapshot, Error> {
        .failure(CoreError.Classify(reason: "missing test result"))
    }
}

actor MappedCategoryPredictor: CoreCategoryPredicting {
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

    func assertCategoryPredictionRequests(
        _ expectedRequests: [CategoryPredictionRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }

    func assertNoCategoryPredictionRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertCategoryPredictionRequests([], file: file, line: line)
    }

    func assertCategoryPredictionFilenames(
        _ expectedFilenames: Set<String>,
        repoPath expectedRepoPath: String? = nil,
        requestCount expectedRequestCount: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestsStorage.assertCategoryPredictionFilenames(
            expectedFilenames,
            repoPath: expectedRepoPath,
            requestCount: expectedRequestCount,
            file: file,
            line: line
        )
    }
}

private extension [CategoryPredictionRequest] {
    func assertCategoryPredictionFilenames(
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
