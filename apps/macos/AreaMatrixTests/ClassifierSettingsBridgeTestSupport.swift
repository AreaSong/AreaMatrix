@testable import AreaMatrix
import XCTest

actor ClassifierSettingsSequencePredictor: CoreCategoryPredicting {
    struct Request: Equatable {
        var repoPath: String
        var filename: String
    }

    private var results: [Swift.Result<ClassifyResultSnapshot, Error>]
    private var requestsStorage: [Request] = []

    init(
        results: [Swift.Result<ClassifyResultSnapshot, Error>] = [
            .success(classifierSettingsValidationProbeResult())
        ]
    ) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requestsStorage.append(Request(repoPath: repoPath, filename: filename))
        let result = results.isEmpty ? .success(classifierSettingsValidationProbeResult()) : results.removeFirst()
        return try result.get()
    }

    func assertRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, expectedRequests, file: file, line: line)
    }

    func assertRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage.count, expectedCount, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestsStorage, [], file: file, line: line)
    }
}

actor ClassifierSettingsRecordingRuleEditor: CoreClassifierRuleEditing {
    typealias CreateRequest = (repoPath: String, request: ClassifierRuleCreateRequestSnapshot)
    typealias UpdateRequest = (repoPath: String, request: ClassifierRuleUpdateSnapshot)
    typealias DeleteRequest = (repoPath: String, request: ClassifierRuleDeleteRequestSnapshot)

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

    func listRequests() -> [String] {
        listRequestsStorage
    }

    func assertListRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(listRequestsStorage, expectedRequests, file: file, line: line)
    }

    func createRequests() -> [CreateRequest] {
        createRequestsStorage
    }

    func updateRequests() -> [UpdateRequest] {
        updateRequestsStorage
    }

    func deleteRequests() -> [DeleteRequest] {
        deleteRequestsStorage
    }

    private func resolve(_ result: Swift.Result<ClassifierRuleEditorSnapshotState, Error>)
        throws -> ClassifierRuleEditorSnapshotState {
        try result.get()
    }
}
