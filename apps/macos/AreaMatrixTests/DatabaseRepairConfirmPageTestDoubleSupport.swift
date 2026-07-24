@testable import AreaMatrix
import XCTest

struct DatabaseRepairMetadataRepairRequest: Equatable {
    var repoPath: String
    var options: RepairOptionsSnapshot
}

actor DatabaseRepairRecordingMetadataRepairer: CoreMetadataRepairing {
    private var preflightResults: [Result<RepairMetadataPreflightSnapshot, Error>]
    private let repairResult: Result<RepairReportSnapshot, Error>
    private var preflightRequestLog = TestRequestLog<String>()
    private var requestLog = TestRequestLog<DatabaseRepairMetadataRepairRequest>()

    init(
        preflightResults: [Result<RepairMetadataPreflightSnapshot, Error>] = [
            .success(.databaseRepairHealthyPreflightFixture())
        ],
        result: Result<RepairReportSnapshot, Error>
    ) {
        self.preflightResults = preflightResults
        repairResult = result
    }

    func preflightRepairMetadata(repoPath: String) async throws -> RepairMetadataPreflightSnapshot {
        preflightRequestLog.append(repoPath)
        guard !preflightResults.isEmpty else {
            return .databaseRepairHealthyPreflightFixture()
        }
        return try preflightResults.removeFirst().get()
    }

    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        requestLog.append(DatabaseRepairMetadataRepairRequest(repoPath: repoPath, options: options))
        return try repairResult.get()
    }

    func assertPreflightRequests(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        preflightRequestLog.assertRequests(expectedRepoPaths, file: file, line: line)
    }

    func assertNoMetadataRepairRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertMetadataRepairRequests([], file: file, line: line)
    }

    func assertMetadataRepairRequests(
        _ expectedRequests: [DatabaseRepairMetadataRepairRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRequests, file: file, line: line)
    }
}

actor RepairRecordingReindexer: CoreRepositoryReindexing {
    private let result: Result<ReindexReportSnapshot, Error>
    private var requestLog = TestRequestLog<String>()

    init(result: Result<ReindexReportSnapshot, Error> = .success(.databaseRepairReindexReportFixture())) {
        self.result = result
    }

    func reindexRepository(repoPath: String) async throws -> ReindexReportSnapshot {
        requestLog.append(repoPath)
        return try result.get()
    }

    func assertReindexRequests(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRepoPaths, file: file, line: line)
    }
}
