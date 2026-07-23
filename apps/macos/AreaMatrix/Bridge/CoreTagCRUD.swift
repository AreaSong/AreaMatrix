import Foundation

protocol CoreTagCRUD: Sendable {
    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot
    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot
    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot
    func batchAddTags(repoPath: String, fileIDs: [Int64], tags: [String]) async throws -> BatchMutationReportSnapshot
    func suggestTagsForFile(
        repoPath: String,
        request: TagSuggestionRequestSnapshot
    ) async throws -> TagSuggestionReportSnapshot
    func applyTagSuggestions(
        repoPath: String,
        request: ApplyTagSuggestionsRequestSnapshot
    ) async throws -> TagSuggestionApplyReportSnapshot
}

protocol CoreAITagSuggestionManaging: Sendable {
    func suggestTagsWithAI(
        repoPath: String,
        request: AITagSuggestionRequestSnapshot
    ) async throws -> AiTagSuggestionReport
    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAiTagSuggestionsRequest
    ) async throws -> AiTagSuggestionApplyReport
}

struct AITagSuggestionRequestSnapshot: Equatable, Sendable {
    var fileID: Int64
    var candidateTags: [String]
    var privacyPolicyRef: String?
}

struct TagRecordSnapshot: Equatable, Identifiable {
    var value: String
    var label: String
    var fileCount: Int64
    var selected: Bool
    var disabled: Bool
    var updatedAt: Int64

    var id: String {
        value
    }

    var displayName: String {
        label.isEmpty ? value : label
    }
}

struct TagSetSnapshot: Equatable {
    var fileID: Int64
    var fileTags: [TagRecordSnapshot]
    var availableTags: [TagRecordSnapshot]
    var recentTags: [TagRecordSnapshot]
    var updatedAt: Int64
}

enum BatchMutationStatusSnapshot: Equatable {
    case added
    case alreadyHadTag
    case failed
}

struct BatchMutationItemResultSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var tag: String
    var status: BatchMutationStatusSnapshot
    var error: String?

    var id: String {
        "\(fileID):\(tag):\(status)"
    }
}

struct BatchMutationReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var requestedTagCount: Int64
    var addedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [BatchMutationItemResultSnapshot]
    var undoToken: String?
}

extension CoreTagCRUD {
    func batchAddTags(
        repoPath _: String,
        fileIDs _: [Int64],
        tags _: [String]
    ) async throws -> BatchMutationReportSnapshot {
        throw CoreError.Internal(message: "batch_add_tags is unavailable")
    }

    func suggestTagsForFile(
        repoPath _: String,
        request _: TagSuggestionRequestSnapshot
    ) async throws -> TagSuggestionReportSnapshot {
        throw CoreError.Internal(message: "suggest_tags_for_file is unavailable")
    }

    func applyTagSuggestions(
        repoPath _: String,
        request _: ApplyTagSuggestionsRequestSnapshot
    ) async throws -> TagSuggestionApplyReportSnapshot {
        throw CoreError.Internal(message: "apply_tag_suggestions is unavailable")
    }
}

extension CoreBridge: CoreTagCRUD {
    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot {
        return try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.listTags(repoPath: repoPath, fileId: fileID))
        }.value
    }

    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.addTag(repoPath: repoPath, fileId: fileID, tag: tag))
        }.value
    }

    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSetSnapshot(coreTagSet: AreaMatrix.removeTag(repoPath: repoPath, fileId: fileID, tag: tag))
        }.value
    }

    func batchAddTags(repoPath: String, fileIDs: [Int64], tags: [String]) async throws -> BatchMutationReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try BatchMutationReportSnapshot(coreReport: AreaMatrix.batchAddTags(
                repoPath: repoPath,
                fileIds: fileIDs,
                tags: tags
            ))
        }.value
    }

    func suggestTagsForFile(
        repoPath: String,
        request: TagSuggestionRequestSnapshot
    ) async throws -> TagSuggestionReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSuggestionReportSnapshot(coreReport: AreaMatrix.suggestTagsForFile(
                repoPath: repoPath,
                request: TagSuggestionRequest(snapshot: request)
            ))
        }.value
    }

    func applyTagSuggestions(
        repoPath: String,
        request: ApplyTagSuggestionsRequestSnapshot
    ) async throws -> TagSuggestionApplyReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TagSuggestionApplyReportSnapshot(coreReport: AreaMatrix.applyTagSuggestions(
                repoPath: repoPath,
                request: ApplyTagSuggestionsRequest(snapshot: request)
            ))
        }.value
    }
}

extension CoreBridge: CoreAITagSuggestionManaging {
    func suggestTagsWithAI(
        repoPath: String,
        request: AITagSuggestionRequestSnapshot
    ) async throws -> AiTagSuggestionReport {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: repoPath)
        let coreRequest = AiTagSuggestionRequest(
            fileId: request.fileID,
            candidateTags: request.candidateTags,
            privacyPolicyRef: request.privacyPolicyRef,
            contentLocale: contentLocale
        )
        return try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.suggestTagsWithAi(repoPath: repoPath, request: coreRequest)
        }.value
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAiTagSuggestionsRequest
    ) async throws -> AiTagSuggestionApplyReport {
        try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.applyAiTagSuggestions(repoPath: repoPath, request: request)
        }.value
    }
}

extension TagSetSnapshot {
    init(coreTagSet: TagSet) {
        fileID = coreTagSet.fileId
        fileTags = coreTagSet.fileTags.map(TagRecordSnapshot.init(coreRecord:))
        availableTags = coreTagSet.availableTags.map(TagRecordSnapshot.init(coreRecord:))
        recentTags = coreTagSet.recentTags.map(TagRecordSnapshot.init(coreRecord:))
        updatedAt = coreTagSet.updatedAt
    }
}

private extension TagRecordSnapshot {
    init(coreRecord: TagRecord) {
        value = coreRecord.value
        label = coreRecord.label
        fileCount = coreRecord.fileCount
        selected = coreRecord.selected
        disabled = coreRecord.disabled
        updatedAt = coreRecord.updatedAt
    }
}

private extension BatchMutationReportSnapshot {
    init(coreReport: BatchMutationReport) {
        requestedFileCount = coreReport.requestedFileCount
        requestedTagCount = coreReport.requestedTagCount
        addedCount = coreReport.addedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(BatchMutationItemResultSnapshot.init(coreResult:))
        undoToken = coreReport.undoToken
    }
}

private extension BatchMutationItemResultSnapshot {
    init(coreResult: BatchMutationItemResult) {
        fileID = coreResult.fileId
        tag = coreResult.tag
        status = BatchMutationStatusSnapshot(coreStatus: coreResult.status)
        error = coreResult.error
    }
}

private extension BatchMutationStatusSnapshot {
    init(coreStatus: BatchMutationStatus) {
        switch coreStatus {
        case .added:
            self = .added
        case .alreadyHadTag:
            self = .alreadyHadTag
        case .failed:
            self = .failed
        }
    }
}
