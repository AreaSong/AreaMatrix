@testable import AreaMatrix
import XCTest

typealias ImportResultChangeLogRequest = ChangeLogListRequest
typealias ImportResultRecordingChangeLogLister = RecordingChangeLogLister

struct ImportResultExportRequest: Equatable {
    var details: String
    var suggestedFilename: String
}

@MainActor
final class ImportResultExporter: ImportResultDetailsExporting {
    private var requests: [ImportResultExportRequest] = []

    func exportDetails(_ details: String, suggestedFilename: String) throws -> String {
        requests.append(ImportResultExportRequest(details: details, suggestedFilename: suggestedFilename))
        return importResultExportPath(suggestedFilename: suggestedFilename)
    }

    func assertLastExportRequest(
        suggestedFilename: String,
        detailsContains expectedSnippets: [String] = [],
        detailsExcludes excludedSnippets: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let request = requests.last else {
            XCTFail("Expected import result export request", file: file, line: line)
            return
        }

        XCTAssertEqual(request.suggestedFilename, suggestedFilename, file: file, line: line)
        for snippet in expectedSnippets {
            XCTAssertTrue(request.details.contains(snippet), file: file, line: line)
        }
        for snippet in excludedSnippets {
            XCTAssertFalse(request.details.contains(snippet), file: file, line: line)
        }
    }
}
