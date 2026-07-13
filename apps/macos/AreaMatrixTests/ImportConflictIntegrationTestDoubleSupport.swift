@testable import AreaMatrix
import XCTest

typealias ImportConflictBatchIntegrationUndoStore = LenientUndoActionRecordingTestStore
typealias ImportConflictChangeLogRequest = ChangeLogListRequest
typealias ImportConflictChangeLogLister = RecordingChangeLogLister

struct ImportConflictPreviewRequest: Equatable {
    var repoPath: String
    var request: ImportConflictBatchPreviewRequestSnapshot
}

struct ImportConflictApplyRequest: Equatable {
    var repoPath: String
    var request: ImportConflictBatchApplyRequestSnapshot
    var previewToken: String
}

actor ImportConflictBatcher: CoreImportConflictBatching {
    private var previews: TestStepQueue<ImportConflictBatchPreviewReportSnapshot>
    private var previewRequests = TestRequestLog<ImportConflictPreviewRequest>()
    private var applyRequests = TestRequestLog<ImportConflictApplyRequest>()

    init(previews: [ImportConflictBatchPreviewReportSnapshot]) {
        self.previews = TestStepQueue(steps: previews) {
            throw CoreError.Conflict(path: "missing import-conflict-batch preview")
        }
    }

    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        previewRequests.append(ImportConflictPreviewRequest(repoPath: repoPath, request: request))
        return try previews.next().withImportConflictBatchRequest(request)
    }

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        applyRequests.append(ImportConflictApplyRequest(
            repoPath: repoPath,
            request: request,
            previewToken: previewToken
        ))
        return .importConflictBatchIntegrationReport(for: request)
    }

    func assertImportConflictBatchPreviewRequests(
        _ expectedRequests: [ImportConflictPreviewRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        previewRequests.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertImportConflictBatchApplyRequests(
        _ expectedRequests: [ImportConflictApplyRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        applyRequests.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertImportConflictApplyRequests(
        _ expectedRequests: [ImportConflictApplyRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        applyRequests.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertNoImportConflictApplyRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        applyRequests.assertNoRequests(file: file, line: line)
    }

    func assertImportConflictPreviewRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(previewRequests.requests.count, expectedCount, file: file, line: line)
    }

    func assertFirstApplyRequestConflictIDs(
        _ expectedConflictIDs: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(applyRequests.requests.first?.request.conflictIDs, expectedConflictIDs, file: file, line: line)
    }

    func assertLastApplyRequestDuplicateStrategy(
        _ expectedStrategy: ImportConflictBatchStrategySnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            applyRequests.requests.last?.request.duplicateStrategy,
            expectedStrategy,
            file: file,
            line: line
        )
    }

    func assertLastImportConflictApplyRequest(
        duplicateStrategy: ImportConflictBatchStrategySnapshot? = nil,
        conflictIDs: [String]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request = applyRequests.requests.last else {
            XCTFail("Expected import conflict apply request", file: file, line: line)
            return
        }
        if let duplicateStrategy {
            XCTAssertEqual(request.request.duplicateStrategy, duplicateStrategy, file: file, line: line)
        }
        if let conflictIDs {
            XCTAssertEqual(request.request.conflictIDs, conflictIDs, file: file, line: line)
        }
    }

    func assertImportConflictPreviewStrategies(
        _ expectedStrategies: [ImportConflictBatchStrategySnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            previewRequests.requests.map(\.request.duplicateStrategy),
            expectedStrategies,
            file: file,
            line: line
        )
    }

    func assertImportConflictPreviewScopes(
        _ expectedScopes: [Bool],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            previewRequests.requests.map(\.request.applyToAllSimilarConflicts),
            expectedScopes,
            file: file,
            line: line
        )
    }
}
