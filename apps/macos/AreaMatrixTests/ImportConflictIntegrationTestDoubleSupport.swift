@testable import AreaMatrix

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
