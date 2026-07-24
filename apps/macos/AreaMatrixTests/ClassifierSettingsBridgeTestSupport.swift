@testable import AreaMatrix
import XCTest

actor ClassifierSettingsSequencePredictor: CoreCategoryPredicting {
    struct Request: Equatable {
        var repoPath: String
        var filename: String
    }

    private var resultQueue: TestResultQueue<ClassifyResultSnapshot>
    private var requestLog = TestRequestLog<Request>()

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
        requestLog.append(Request(repoPath: repoPath, filename: filename))
        return try resultQueue.next()
    }

    func assertCategoryPredictionRequests(
        _ expectedRequests: [Request],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRequests, file: file, line: line)
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
        XCTAssertEqual(requestLog.requests.count, expectedCount, file: file, line: line)
    }
}

actor ClassifierSettingsRecordingRuleEditor: CoreClassifierRuleEditing {
    struct ListRequest: Equatable {
        var repoPath: String
        var editingLocale: ClassifierEditingLocale?
    }

    struct RecoveryRequest: Equatable {
        var repoPath: String
        var confirmed: Bool
        var editingLocale: ClassifierEditingLocale?
    }

    typealias CreateRequest = (repoPath: String, request: ClassifierRuleCreateRequestSnapshot)
    typealias UpdateRequest = (repoPath: String, request: ClassifierRuleUpdateSnapshot)
    typealias DeleteRequest = (repoPath: String, request: ClassifierRuleDeleteRequestSnapshot)

    struct UpdateRequestExpectation {
        var repoPath: String
        var ruleID: String
        var observedDisplayName: String
        var displayName: String
        var extensions: [String]
        var keywords: [String]
        var previewConfirmed: Bool
    }

    private var listResults: [Swift.Result<ClassifierRuleEditorSnapshotState, Error>]
    private var mutationResults: [Swift.Result<ClassifierRuleEditorSnapshotState, Error>]
    private var listRequestsStorage: [ListRequest] = []
    private var createRequestsStorage: [CreateRequest] = []
    private var updateRequestsStorage: [UpdateRequest] = []
    private var deleteRequestsStorage: [DeleteRequest] = []
    private var createDefaultRequestsStorage: [RecoveryRequest] = []
    private var restoreDefaultRequestsStorage: [RecoveryRequest] = []
    private var restoreLastValidRequestsStorage: [RecoveryRequest] = []

    init(
        listResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error> = .success(.classifierEditorFixture()),
        listResults: [Swift.Result<ClassifierRuleEditorSnapshotState, Error>]? = nil,
        mutationResult: Swift.Result<ClassifierRuleEditorSnapshotState, Error> = .success(.classifierEditorFixture()),
        mutationResults: [Swift.Result<ClassifierRuleEditorSnapshotState, Error>]? = nil
    ) {
        self.listResults = listResults ?? [listResult]
        self.mutationResults = mutationResults ?? [mutationResult]
    }

    func listClassifierRules(
        repoPath: String,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        listRequestsStorage.append(ListRequest(repoPath: repoPath, editingLocale: editingLocale))
        let result = listResults.count > 1 ? listResults.removeFirst() : listResults[0]
        return try resolve(result)
    }

    func createClassifierRule(
        repoPath: String,
        request: ClassifierRuleCreateRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        createRequestsStorage.append((repoPath, request))
        return try resolve(nextMutationResult())
    }

    func updateClassifierRule(
        repoPath: String,
        request: ClassifierRuleUpdateSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        updateRequestsStorage.append((repoPath, request))
        return try resolve(nextMutationResult())
    }

    func deleteClassifierRule(
        repoPath: String,
        request: ClassifierRuleDeleteRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        deleteRequestsStorage.append((repoPath, request))
        return try resolve(nextMutationResult())
    }

    func createDefaultClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        createDefaultRequestsStorage.append(RecoveryRequest(
            repoPath: repoPath,
            confirmed: confirmed,
            editingLocale: editingLocale
        ))
        return try resolve(nextMutationResult())
    }

    func restoreDefaultClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        restoreDefaultRequestsStorage.append(RecoveryRequest(
            repoPath: repoPath,
            confirmed: confirmed,
            editingLocale: editingLocale
        ))
        return try resolve(nextMutationResult())
    }

    func restoreLastValidClassifier(
        repoPath: String,
        confirmed: Bool,
        editingLocale: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        restoreLastValidRequestsStorage.append(RecoveryRequest(
            repoPath: repoPath,
            confirmed: confirmed,
            editingLocale: editingLocale
        ))
        return try resolve(nextMutationResult())
    }

    func assertClassifierRuleListRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(listRequestsStorage.map(\.repoPath), expectedRequests, file: file, line: line)
    }

    func assertClassifierRuleListRequestDetails(
        _ expectedRequests: [ListRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(listRequestsStorage, expectedRequests, file: file, line: line)
    }

    func assertCreateDefaultRequests(
        _ expectedRequests: [RecoveryRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(createDefaultRequestsStorage, expectedRequests, file: file, line: line)
    }

    func assertRestoreDefaultRequests(
        _ expectedRequests: [RecoveryRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(restoreDefaultRequestsStorage, expectedRequests, file: file, line: line)
    }

    func assertRestoreLastValidRequests(
        _ expectedRequests: [RecoveryRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(restoreLastValidRequestsStorage, expectedRequests, file: file, line: line)
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
        XCTAssertEqual(request?.request.observed.displayName, expected.observedDisplayName, file: file, line: line)
        XCTAssertEqual(request?.request.displayName, expected.displayName, file: file, line: line)
        XCTAssertEqual(request?.request.extensions, expected.extensions, file: file, line: line)
        XCTAssertEqual(request?.request.keywords, expected.keywords, file: file, line: line)
        XCTAssertEqual(request?.request.previewConfirmed, expected.previewConfirmed, file: file, line: line)
    }

    func assertClassifierRuleUpdateRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(updateRequestsStorage.count, expectedCount, file: file, line: line)
    }

    func classifierRuleUpdateRequest(at index: Int) -> ClassifierRuleUpdateSnapshot? {
        guard updateRequestsStorage.indices.contains(index) else { return nil }
        return updateRequestsStorage[index].request
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

    private func nextMutationResult() -> Swift.Result<ClassifierRuleEditorSnapshotState, Error> {
        if mutationResults.count > 1 {
            return mutationResults.removeFirst()
        }
        return mutationResults[0]
    }
}
