import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreTagCRUD = AreaMatrixCoreBridgeContract.CoreTagCRUD
typealias CoreAITagSuggestionManaging = AreaMatrixCoreBridgeContract.CoreAITagSuggestionManaging

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
        try await Task.detached(priority: .userInitiated) {
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
    ) async throws -> AITagSuggestionReportSnapshot {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: repoPath)
        let coreRequest = try AiTagSuggestionRequest(
            fileId: request.fileID,
            candidateTags: request.candidateTags,
            privacyPolicyRef: request.privacyPolicyRef,
            contentLocale: ContentLocale(snapshotValue: contentLocale)
        )
        return try await Task.detached(priority: .userInitiated) {
            try AITagSuggestionReportSnapshot(
                coreReport: AreaMatrix.suggestTagsWithAi(repoPath: repoPath, request: coreRequest)
            )
        }.value
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAITagSuggestionsRequestSnapshot
    ) async throws -> AITagSuggestionApplyReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AITagSuggestionApplyReportSnapshot(coreReport: AreaMatrix.applyAiTagSuggestions(
                repoPath: repoPath,
                request: ApplyAiTagSuggestionsRequest(snapshot: request)
            ))
        }.value
    }
}
