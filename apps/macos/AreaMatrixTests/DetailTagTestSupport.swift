@testable import AreaMatrix

actor DetailTagFileDetailer: CoreFileDetailing {
    private let filesByID: [Int64: FileEntrySnapshot]

    init(files: [FileEntrySnapshot]) {
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = filesByID[fileID] else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }
        return file
    }
}

struct DetailTagMutationRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var tag: String
}

struct DetailTagListRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

struct TagSuggestionRequestRecord: Equatable {
    var repoPath: String
    var request: TagSuggestionRequestSnapshot
}

struct ApplyTagSuggestionsRequestRecord: Equatable {
    var repoPath: String
    var request: ApplyTagSuggestionsRequestSnapshot
}

extension CoreErrorMappingSnapshot {
    static func tagAddTagDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "无法更新标签",
            severity: .medium,
            suggestedAction: "请保留输入并重试标签操作。",
            recoverability: .retryable,
            rawContext: "tag-crud tag-crud-core tag-crud"
        )
    }
}

extension TagSuggestionRequestSnapshot {
    static func tagSuggestions(fileID: Int64) -> TagSuggestionRequestSnapshot {
        TagSuggestionRequestSnapshot(
            fileID: fileID,
            context: nil,
            limit: DetailTagSuggestionAction.defaultLimit
        )
    }
}

extension RepositorySidebarRowSnapshot {
    static let tagFilterRoot = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
        slug: "__root__",
        displayName: "Repository",
        kind: "RepositoryRoot",
        relativePath: "",
        fileCount: 0,
        depth: 0,
        children: []
    ), depth: 0)
}

extension MainFileListModel {
    @MainActor
    static func tagSuggestionsFixture(
        detail: FileEntrySnapshot,
        tagStore: any CoreTagCRUD = DetailTagRecordingStore()
    ) -> MainFileListModel {
        MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )
    }
}

extension UndoActionRecordSnapshot {
    static func tagSuggestionsApplySuggestion(token: String) -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: token,
            kind: "tag_suggestion_apply",
            summary: "Applied 1 suggested tag.",
            affectedCount: 1,
            affectedFileNames: ["invoice_2026.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_400,
            updatedAt: 1_700_000_400
        )
    }
}

actor DetailTagRecordingStore: CoreTagCRUD {
    enum Result {
        case success(TagSetSnapshot)
        case failure(Error)
    }

    enum SuggestionResult {
        case success(TagSuggestionReportSnapshot)
        case failure(Error)
    }

    enum ApplySuggestionResult {
        case success(TagSuggestionApplyReportSnapshot)
        case failure(Error)
    }

    private var listResults: [Result]
    private var addResults: [Result]
    private var removeResults: [Result]
    private var suggestionResults: [SuggestionResult]
    private var applySuggestionResults: [ApplySuggestionResult]
    private var recordedListRequests: [DetailTagListRequest] = []
    private var recordedAddRequests: [DetailTagMutationRequest] = []
    private var recordedRemoveRequests: [DetailTagMutationRequest] = []
    private var recordedSuggestionRequests: [TagSuggestionRequestRecord] = []
    private var recordedApplySuggestionRequests: [ApplyTagSuggestionsRequestRecord] = []

    init(
        listResults: [Result] = [],
        addResults: [Result] = [],
        removeResults: [Result] = [],
        suggestionResults: [SuggestionResult] = [],
        applySuggestionResults: [ApplySuggestionResult] = []
    ) {
        self.listResults = listResults
        self.addResults = addResults
        self.removeResults = removeResults
        self.suggestionResults = suggestionResults
        self.applySuggestionResults = applySuggestionResults
    }

    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot {
        recordedListRequests.append(DetailTagListRequest(repoPath: repoPath, fileID: fileID))
        return try consume(&listResults, fallbackFileID: fileID)
    }

    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        recordedAddRequests.append(DetailTagMutationRequest(repoPath: repoPath, fileID: fileID, tag: tag))
        return try consume(&addResults, fallbackFileID: fileID)
    }

    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        recordedRemoveRequests.append(DetailTagMutationRequest(repoPath: repoPath, fileID: fileID, tag: tag))
        return try consume(&removeResults, fallbackFileID: fileID)
    }

    func suggestTagsForFile(
        repoPath: String,
        request: TagSuggestionRequestSnapshot
    ) async throws -> TagSuggestionReportSnapshot {
        recordedSuggestionRequests.append(TagSuggestionRequestRecord(repoPath: repoPath, request: request))
        guard !suggestionResults.isEmpty else { return .tagSuggestionsFixture(fileID: request.fileID) }
        switch suggestionResults.removeFirst() {
        case let .success(report): return report
        case let .failure(error): throw error
        }
    }

    func applyTagSuggestions(
        repoPath: String,
        request: ApplyTagSuggestionsRequestSnapshot
    ) async throws -> TagSuggestionApplyReportSnapshot {
        recordedApplySuggestionRequests.append(ApplyTagSuggestionsRequestRecord(repoPath: repoPath, request: request))
        guard !applySuggestionResults.isEmpty else { return .tagSuggestionsApplied(fileID: request.fileID) }
        switch applySuggestionResults.removeFirst() {
        case let .success(report): return report
        case let .failure(error): throw error
        }
    }

    func addRequests() -> [DetailTagMutationRequest] {
        recordedAddRequests
    }

    func removeRequests() -> [DetailTagMutationRequest] {
        recordedRemoveRequests
    }

    func listRequests() -> [DetailTagListRequest] {
        recordedListRequests
    }

    func suggestionRequests() -> [TagSuggestionRequestRecord] {
        recordedSuggestionRequests
    }

    func applySuggestionRequests() -> [ApplyTagSuggestionsRequestRecord] {
        recordedApplySuggestionRequests
    }

    private func consume(_ results: inout [Result], fallbackFileID: Int64) throws -> TagSetSnapshot {
        guard !results.isEmpty else { return TagSetSnapshot.tagAddFixture(fileID: fallbackFileID, values: []) }
        switch results.removeFirst() {
        case let .success(tagSet): return tagSet
        case let .failure(error): throw error
        }
    }
}

actor TagFilterForbiddenTagStore: CoreTagCRUD {
    private var calls: [String] = []

    func listTags(repoPath _: String, fileID _: Int64) async throws -> TagSetSnapshot {
        calls.append("listTags")
        throw CoreError.Internal(message: "tag-filters search-filters must use list_filter_facets")
    }

    func addTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
        calls.append("addTag")
        throw CoreError.Internal(message: "tag-filters search-filters must not add tags")
    }

    func removeTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
        calls.append("removeTag")
        throw CoreError.Internal(message: "tag-filters search-filters must not remove tags")
    }

    func recordedCalls() -> [String] {
        calls
    }
}
