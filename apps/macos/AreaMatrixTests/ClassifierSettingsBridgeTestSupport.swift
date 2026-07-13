@testable import AreaMatrix
import XCTest

actor ClassifierSettingsSequencePredictor: CoreCategoryPredicting {
    struct Request: Equatable {
        var repoPath: String
        var filename: String
    }

    private var resultQueue: TestResultQueue<ClassifyResultSnapshot>
    private var requestsStorage: [Request] = []

    init(
        results: [Swift.Result<ClassifyResultSnapshot, Error>] = [
            .success(classifierSettingsValidationProbeResult())
        ]
    ) {
        resultQueue = TestResultQueue(results: results) {
            .success(classifierSettingsValidationProbeResult())
        }
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requestsStorage.append(Request(repoPath: repoPath, filename: filename))
        return try resultQueue.next()
    }

    func assertCategoryPredictionRequests(
        _ expectedRequests: [Request],
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

    func assertCategoryPredictionRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage.count, expectedCount, file: file, line: line)
    }
}

actor ClassifierSettingsRecordingRuleEditor: CoreClassifierRuleEditing {
    typealias CreateRequest = (repoPath: String, request: ClassifierRuleCreateRequestSnapshot)
    typealias UpdateRequest = (repoPath: String, request: ClassifierRuleUpdateSnapshot)
    typealias DeleteRequest = (repoPath: String, request: ClassifierRuleDeleteRequestSnapshot)

    struct UpdateRequestExpectation {
        var repoPath: String
        var ruleID: String
        var displayName: String
        var extensions: [String]
        var keywords: [String]
        var previewConfirmed: Bool
    }

    private let listResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error>
    private let mutationResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error>
    private var listRequestsStorage: [String] = []
    private var createRequestsStorage: [CreateRequest] = []
    private var updateRequestsStorage: [UpdateRequest] = []
    private var deleteRequestsStorage: [DeleteRequest] = []

    init(
        listResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error> = .success(.classifierEditorFixture()),
        mutationResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error> = .success(.classifierEditorFixture())
    ) {
        self.listResult = listResult
        self.mutationResult = mutationResult
    }

    func listClassifierRules(repoPath: String) async throws -> ClassifierRuleEditorSnapshotState {
        listRequestsStorage.append(repoPath)
        return try resolve(listResult)
    }

    func createClassifierRule(
        repoPath: String,
        request: ClassifierRuleCreateRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        createRequestsStorage.append((repoPath, request))
        return try resolve(mutationResult)
    }

    func updateClassifierRule(
        repoPath: String,
        request: ClassifierRuleUpdateSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        updateRequestsStorage.append((repoPath, request))
        return try resolve(mutationResult)
    }

    func deleteClassifierRule(
        repoPath: String,
        request: ClassifierRuleDeleteRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        deleteRequestsStorage.append((repoPath, request))
        return try resolve(mutationResult)
    }

    func assertClassifierRuleListRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(listRequestsStorage, expectedRequests, file: file, line: line)
    }

    func assertSingleClassifierRuleCreateRequest(
        repoPath: String,
        slug: String,
        displayName: String,
        extensions: [String],
        namingTemplate: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(createRequestsStorage.count, 1, file: file, line: line)
        let request = createRequestsStorage.first
        XCTAssertEqual(request?.repoPath, repoPath, file: file, line: line)
        XCTAssertEqual(request?.request.slug, slug, file: file, line: line)
        XCTAssertEqual(request?.request.displayName, displayName, file: file, line: line)
        XCTAssertEqual(request?.request.extensions, extensions, file: file, line: line)
        XCTAssertEqual(request?.request.namingTemplate, namingTemplate, file: file, line: line)
    }

    func assertSingleClassifierRuleUpdateRequest(
        _ expected: UpdateRequestExpectation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(updateRequestsStorage.count, 1, file: file, line: line)
        let request = updateRequestsStorage.first
        XCTAssertEqual(request?.repoPath, expected.repoPath, file: file, line: line)
        XCTAssertEqual(request?.request.ruleID, expected.ruleID, file: file, line: line)
        XCTAssertEqual(request?.request.displayName, expected.displayName, file: file, line: line)
        XCTAssertEqual(request?.request.extensions, expected.extensions, file: file, line: line)
        XCTAssertEqual(request?.request.keywords, expected.keywords, file: file, line: line)
        XCTAssertEqual(request?.request.previewConfirmed, expected.previewConfirmed, file: file, line: line)
    }

    func assertNoClassifierRuleDeleteRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(deleteRequestsStorage.count, 0, file: file, line: line)
    }

    func assertSingleClassifierRuleDeleteRequest(
        repoPath: String,
        ruleID: String,
        replacementCategory: String,
        previewConfirmed: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(deleteRequestsStorage.count, 1, file: file, line: line)
        let request = deleteRequestsStorage.first
        XCTAssertEqual(request?.repoPath, repoPath, file: file, line: line)
        XCTAssertEqual(request?.request.ruleID, ruleID, file: file, line: line)
        XCTAssertEqual(request?.request.replacementCategory, replacementCategory, file: file, line: line)
        XCTAssertEqual(request?.request.previewConfirmed, previewConfirmed, file: file, line: line)
    }

    private func resolve(_ result: Swift.Result<ClassifierRuleEditorSnapshotState, Error>)
        throws -> ClassifierRuleEditorSnapshotState {
        try result.get()
    }
}
