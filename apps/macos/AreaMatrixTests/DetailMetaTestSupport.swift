@testable import AreaMatrix

actor DetailMetaImmediateDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private let result: Result

    init(result: Result) {
        self.result = result
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        switch result {
        case let .success(file):
            return file
        case let .failure(error):
            throw error
        }
    }
}

actor DetailMetaErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

struct DetailLogRequest: Equatable {
    var repoPath: String
    var filter: ChangeFilterSnapshot
}

actor DetailLogRecordingLister: CoreChangeLogListing {
    enum Result {
        case success([ChangeLogEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [DetailLogRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        requests.append(DetailLogRequest(repoPath: repoPath, filter: filter))
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case let .success(entries):
            return entries
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [DetailLogRequest] {
        requests
    }
}

extension RepositoryOpeningResult {
    static func detailMetaFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "Repository",
                fileCount: Int64(files.count),
                children: []
            ),
            currentCategoryFiles: files
        )
    }
}

extension FileEntrySnapshot {
    static func detailMetaFixture(
        id: Int64,
        currentName: String,
        storageMode: String = "Copied",
        sourcePath: String? = "~/Downloads/source.pdf"
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/contracts/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 256,
            hashSha256: "detail-meta-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: sourcePath,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension [DetailMetaMetadataRow] {
    func value(for label: String) -> String? {
        first { $0.label == label }?.value
    }
}

extension ChangeLogEntrySnapshot {
    static func detailLogFixture(fileID: Int64, action: String) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: fileID + 100,
            fileID: fileID,
            filename: "logged.pdf",
            category: "docs",
            action: action,
            detailJSON: #"{"changed":"modified_at"}"#,
            occurredAt: 1_700_000_200
        )
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

extension CoreErrorMappingSnapshot {
    static func detailMetaFileNotFound() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "文件不存在",
            severity: .medium,
            suggestedAction: "刷新当前列表，确认文件是否已被移动或删除。",
            recoverability: .refreshRequired,
            rawContext: "file-detail file-detail-core get_file"
        )
    }

    static func detailLogDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "无法加载改动记录",
            severity: .medium,
            suggestedAction: "请重试改动时间线。",
            recoverability: .retryable,
            rawContext: "detail-change-log change-log-core list_changes"
        )
    }
}
