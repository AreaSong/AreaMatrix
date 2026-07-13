import XCTest

struct TestRequestLog<Request: Equatable> {
    private var requestsStorage: [Request] = []

    var requests: [Request] {
        requestsStorage
    }

    mutating func append(_ request: Request) {
        requestsStorage.append(request)
    }

    func assertRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequests([], file: file, line: line)
    }
}

struct TestValueQueue<Value> {
    private var queuedValues: [Value]
    private let missingValue: () -> Value

    init(values: [Value], missingValue: @escaping () -> Value) {
        queuedValues = values
        self.missingValue = missingValue
    }

    mutating func next() -> Value {
        next(missingValue: missingValue)
    }

    mutating func next(missingValue: () -> Value) -> Value {
        queuedValues.isEmpty ? missingValue() : queuedValues.removeFirst()
    }
}

struct TestStepQueue<Step> {
    private var queuedSteps: [Step]
    private let missingStep: () throws -> Step

    init(
        steps: [Step],
        missingStep: @escaping () throws -> Step
    ) {
        queuedSteps = steps
        self.missingStep = missingStep
    }

    mutating func next() throws -> Step {
        try next(missingStep: missingStep)
    }

    mutating func next(missingStep: () throws -> Step) throws -> Step {
        guard !queuedSteps.isEmpty else {
            return try missingStep()
        }

        return queuedSteps.removeFirst()
    }
}

struct TestResultQueue<Value> {
    private let repeatingResult: Swift.Result<Value, Error>?
    private var queuedResults: [Swift.Result<Value, Error>]
    private let missingResult: () -> Swift.Result<Value, Error>

    init(
        result: Swift.Result<Value, Error>,
        missingResult: @escaping () -> Swift.Result<Value, Error>
    ) {
        repeatingResult = result
        queuedResults = []
        self.missingResult = missingResult
    }

    init(
        results: [Swift.Result<Value, Error>],
        missingResult: @escaping () -> Swift.Result<Value, Error>
    ) {
        repeatingResult = nil
        queuedResults = results
        self.missingResult = missingResult
    }

    mutating func nextResult() -> Swift.Result<Value, Error> {
        if let repeatingResult {
            return repeatingResult
        }

        return queuedResults.isEmpty ? missingResult() : queuedResults.removeFirst()
    }

    mutating func nextResult(
        missingResult: () -> Swift.Result<Value, Error>
    ) -> Swift.Result<Value, Error> {
        if let repeatingResult {
            return repeatingResult
        }

        return queuedResults.isEmpty ? missingResult() : queuedResults.removeFirst()
    }

    mutating func next() throws -> Value {
        try nextResult().get()
    }

    mutating func next(
        missingResult: () -> Swift.Result<Value, Error>
    ) throws -> Value {
        try nextResult(missingResult: missingResult).get()
    }
}

struct VoidResultQueue {
    private var resultQueue: TestResultQueue<Void>

    init(result: Swift.Result<Void, Error> = .success(())) {
        resultQueue = TestResultQueue(result: result) {
            .success(())
        }
    }

    init(results: [Swift.Result<Void, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .success(())
        }
    }

    init(failureThenSuccess error: Error) {
        resultQueue = TestResultQueue(results: [.failure(error), .success(())]) {
            .success(())
        }
    }

    mutating func next() -> Swift.Result<Void, Error> {
        resultQueue.nextResult()
    }
}
