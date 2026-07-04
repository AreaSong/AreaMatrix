@testable import AreaMatrix

typealias ImportResultChangeLogRequest = ChangeLogListRequest
typealias ImportResultRecordingChangeLogLister = RecordingChangeLogLister

@MainActor
final class ImportResultExporter: ImportResultDetailsExporting {
    private(set) var requests: [(details: String, suggestedFilename: String)] = []

    func exportDetails(_ details: String, suggestedFilename: String) throws -> String {
        requests.append((details: details, suggestedFilename: suggestedFilename))
        return importResultExportPath(suggestedFilename: suggestedFilename)
    }
}
