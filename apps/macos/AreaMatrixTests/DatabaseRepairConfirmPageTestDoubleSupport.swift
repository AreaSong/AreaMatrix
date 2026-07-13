@testable import AreaMatrix
import XCTest

struct DatabaseRepairMetadataRepairRequest: Equatable {
    var repoPath: String
    var options: RepairOptionsSnapshot
}

actor DatabaseRepairRecordingMetadataRepairer: CoreMetadataRepairing {
    private let result: Result<RepairReportSnapshot, Error>
    private var requestLog = TestRequestLog<DatabaseRepairMetadataRepairRequest>()

    init(result: Result<RepairReportSnapshot, Error>) {
        self.result = result
    }

    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        requestLog.append(DatabaseRepairMetadataRepairRequest(repoPath: repoPath, options: options))
        return try result.get()
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
