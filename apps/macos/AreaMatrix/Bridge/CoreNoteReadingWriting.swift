import Foundation

struct AISummarySavedSnapshot: Equatable {
    var fileID: Int64
    var summaryText: String
    var savedAt: Int64
    var draftID: String?
    var route: AISummaryRouteState?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AISummaryInputFieldState]
    var privacyRuleID: String?
    var callLogID: Int64?
    var editedByUser: Bool
    var contentRevision: Int64
    var ownership: AIContentOwnershipState
    var operationID: String?
    var contentLocale: ContentLocaleState?
    var formatContractVersion: Int64?
    var characterCount: Int64
}

struct AISummaryPersistedStateSnapshot: Equatable {
    var summary: AISummarySavedSnapshot?
    var contentRevision: Int64
}

protocol CoreAIPrivacyEvaluating: Sendable {
    func loadAIPrivacyRules(repoPath: String) async throws -> AIPrivacyRulesSnapshot
    func evaluateAIPrivacy(
        repoPath: String,
        request: AIPrivacyEvaluationRequestSnapshot
    ) async throws -> AIPrivacyEvaluationReportSnapshot
}

protocol RepositoryContentLocaleSnapshotting: Sendable {
    func repositoryContentLocaleSnapshot(repoPath: String) async throws -> String
}

protocol CoreNoteReadingWriting: Sendable {
    func readNote(repoPath: String, fileID: Int64) async throws -> String?
    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws
}

protocol CoreAISummaryManaging: Sendable {
    func loadAISummaryState(repoPath: String, fileID: Int64) async throws -> AISummaryPersistedStateSnapshot
    func loadSavedAISummary(repoPath: String, fileID: Int64) async throws -> AISummarySavedSnapshot?
    func generateAISummary(
        repoPath: String,
        request: AISummaryGenerationRequestSnapshot
    ) async throws -> AISummaryDraftSnapshot
    func saveAISummary(
        repoPath: String,
        request: AISummarySaveRequestSnapshot
    ) async throws -> AISummarySaveReportSnapshot
    func clearAISummary(
        repoPath: String,
        request: AISummaryClearRequestSnapshot
    ) async throws -> AISummaryClearReportSnapshot
}

extension CoreAISummaryManaging {
    func loadAISummaryState(repoPath: String, fileID: Int64) async throws -> AISummaryPersistedStateSnapshot {
        let summary = try await loadSavedAISummary(repoPath: repoPath, fileID: fileID)
        return AISummaryPersistedStateSnapshot(
            summary: summary,
            contentRevision: summary?.contentRevision ?? 0
        )
    }
}

extension CoreBridge: RepositoryContentLocaleSnapshotting {}

extension CoreBridge: CoreNoteReadingWriting {
    func readNote(repoPath: String, fileID: Int64) async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            try readCoreNote(repoPath: repoPath, fileID: fileID)
        }.value
    }

    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try writeCoreNote(repoPath: repoPath, fileID: fileID, contentMarkdown: contentMarkdown)
        }.value
    }
}

extension CoreBridge: CoreAISummaryManaging {
    func loadAISummaryState(repoPath: String, fileID: Int64) async throws -> AISummaryPersistedStateSnapshot {
        try await SQLiteAISummaryMetadataReader().persistedState(repoPath: repoPath, fileID: fileID)
    }

    func loadSavedAISummary(repoPath: String, fileID: Int64) async throws -> AISummarySavedSnapshot? {
        try await loadAISummaryState(repoPath: repoPath, fileID: fileID).summary
    }

    func generateAISummary(
        repoPath: String,
        request: AISummaryGenerationRequestSnapshot
    ) async throws -> AISummaryDraftSnapshot {
        let coreRequest = AiSummaryGenerationRequest(snapshot: request)
        return try await Task.detached(priority: .userInitiated) {
            try AISummaryDraftSnapshot(coreDraft: generateAiSummary(repoPath: repoPath, request: coreRequest))
        }.value
    }

    func saveAISummary(
        repoPath: String,
        request: AISummarySaveRequestSnapshot
    ) async throws -> AISummarySaveReportSnapshot {
        let coreRequest = AiSummarySaveRequest(snapshot: request)
        return try await Task.detached(priority: .userInitiated) {
            try AISummarySaveReportSnapshot(coreReport: saveAiSummary(repoPath: repoPath, request: coreRequest))
        }.value
    }

    func clearAISummary(
        repoPath: String,
        request: AISummaryClearRequestSnapshot
    ) async throws -> AISummaryClearReportSnapshot {
        let coreRequest = AiSummaryClearRequest(snapshot: request)
        return try await Task.detached(priority: .userInitiated) {
            try AISummaryClearReportSnapshot(coreReport: clearAiSummary(repoPath: repoPath, request: coreRequest))
        }.value
    }
}

private func readCoreNote(repoPath: String, fileID: Int64) throws -> String? {
    try readNote(repoPath: repoPath, fileId: fileID)
}

private func writeCoreNote(repoPath: String, fileID: Int64, contentMarkdown: String) throws {
    try writeNote(repoPath: repoPath, fileId: fileID, contentMd: contentMarkdown)
}
