@testable import AreaMatrix

actor DetailMetaImmediateDetailer: CoreFileDetailing {
    private let result: Swift.Result<FileEntrySnapshot, Error>

    init(result: Swift.Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    init(file: FileEntrySnapshot) {
        result = .success(file)
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        try result.get()
    }
}

struct FileDetailRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

actor RecordingFileDetailer: CoreFileDetailing {
    private var results: [Swift.Result<FileEntrySnapshot, Error>]
    private var requests: [FileDetailRequest] = []

    init() {
        results = []
    }

    init(results: [Swift.Result<FileEntrySnapshot, Error>]) {
        self.results = results
    }

    init(result: Swift.Result<FileEntrySnapshot, Error>) {
        results = [result]
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(FileDetailRequest(repoPath: repoPath, fileID: fileID))
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        return try results.removeFirst().get()
    }

    func recordedRequests() -> [FileDetailRequest] {
        requests
    }

    func recordedFileIDs() -> [Int64] {
        requests.map(\.fileID)
    }
}

typealias DetailLogRequest = ChangeLogListRequest
typealias DetailLogRecordingLister = RecordingChangeLogLister

extension [DetailMetaMetadataRow] {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}

@MainActor
func assertMainRepositoryDetailFileActionMenu(
    for detail: FileEntrySnapshot,
    disabledReason: MainFileWriteActionDisabledReason? = nil,
    contains expectedFragments: [String],
    file sourceFile: StaticString = #filePath,
    line: UInt = #line
) {
    let menu = MainRepositoryDetailFileActionMenu(
        detail: detail,
        disabledReason: disabledReason,
        onBeginRenameFile: { _ in },
        onBeginChangeCategoryFile: { _ in },
        onBeginClassifierCorrectionFile: { _ in },
        onBeginAIClassificationSuggestionFile: { _ in },
        onBeginDeleteFile: { _ in },
        onBeginICloudConflictResolution: { _ in },
        onBeginSyncConflictReview: { _ in }
    )
    assertTestMirrorDescription(
        of: menu.body,
        contains: expectedFragments,
        maxDepth: 8,
        file: sourceFile,
        line: line
    )
}
