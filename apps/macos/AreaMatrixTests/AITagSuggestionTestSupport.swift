@testable import AreaMatrix
import XCTest

actor AITagSuggestionAITagBridge: CoreAITagSuggestionManaging {
    private let report: AiTagSuggestionReport
    private var suggestRequests: [AiTagSuggestionRequest] = []
    private var applyRequests: [ApplyAiTagSuggestionsRequest] = []

    init(_ report: AiTagSuggestionReport) {
        self.report = report
    }

    func suggestTagsWithAI(repoPath: String, request: AiTagSuggestionRequest) async throws -> AiTagSuggestionReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        suggestRequests.append(request)
        return report
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAiTagSuggestionsRequest
    ) async throws -> AiTagSuggestionApplyReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        applyRequests.append(request)
        return aiTagSuggestionApplyReport(fileID: request.fileId)
    }

    func requests() -> (suggest: [AiTagSuggestionRequest], apply: [ApplyAiTagSuggestionsRequest]) {
        (suggestRequests, applyRequests)
    }
}

actor AITagSuggestionBatchAITagBridge: CoreAITagSuggestionManaging {
    private let reports: [Int64: AiTagSuggestionReport]
    private let applyReports: [Int64: AiTagSuggestionApplyReport]
    private var suggestRequests: [AiTagSuggestionRequest] = []
    private var applyRequests: [ApplyAiTagSuggestionsRequest] = []

    init(
        reports: [Int64: AiTagSuggestionReport],
        applyReports: [Int64: AiTagSuggestionApplyReport] = [:]
    ) {
        self.reports = reports
        self.applyReports = applyReports
    }

    func suggestTagsWithAI(repoPath: String, request: AiTagSuggestionRequest) async throws -> AiTagSuggestionReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        suggestRequests.append(request)
        guard let report = reports[request.fileId] else {
            throw CoreError.FileNotFound(path: "\(request.fileId)")
        }
        return report
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAiTagSuggestionsRequest
    ) async throws -> AiTagSuggestionApplyReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        applyRequests.append(request)
        return applyReports[request.fileId] ?? aiTagSuggestionBatchApplyReport(
            fileID: request.fileId,
            suggestionID: request.suggestions.first?.suggestionId ?? "ai-tag-finance",
            slug: request.suggestions.first?.slug ?? "finance"
        )
    }

    func requests() -> (suggest: [AiTagSuggestionRequest], apply: [ApplyAiTagSuggestionsRequest]) {
        (suggestRequests, applyRequests)
    }
}

typealias AITagSuggestionAISettingsLoader = StaticAISettingsLoader

extension AITagBatchPageFeatureTests {
    static func aiTagMergeBridge(
        file: FileEntrySnapshot,
        unchangedFile: FileEntrySnapshot
    ) -> AITagSuggestionBatchAITagBridge {
        AITagSuggestionBatchAITagBridge(reports: [
            file.id: aiTagSuggestionAITagReport(fileID: file.id, suggestions: [
                aiTagSuggestionAITagSuggestion(
                    id: "ai-tag-merge",
                    slug: "finances",
                    confidence: 0.91,
                    selectedByDefault: false,
                    displayName: "Finances",
                    mergeAction: .mergeWithExistingTag,
                    matchedExistingSlug: "finance"
                )
            ]),
            unchangedFile.id: aiTagSuggestionAITagReport(fileID: unchangedFile.id, status: .noSuggestion)
        ])
    }

    @MainActor
    static func aiTagMergeModel(
        file: FileEntrySnapshot,
        unchangedFile: FileEntrySnapshot,
        bridge: AITagSuggestionBatchAITagBridge
    ) -> MainFileListModel {
        MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file, unchangedFile]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailTagFileDetailer(files: [file, unchangedFile]),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )
    }
}

func aiTagSuggestionAITagReport(
    fileID: Int64,
    status: AiTagSuggestionReportStatus = .suggested,
    skippedReason: AiTagSuggestionSkipReason? = nil,
    suggestions: [AiTagSuggestion] = []
) -> AiTagSuggestionReport {
    AiTagSuggestionReport(
        fileId: fileID,
        status: status,
        suggestions: suggestions,
        route: status == .suggested ? .local : nil,
        modelName: status == .suggested ? "Local tags model" : nil,
        generatedAt: status == .suggested ? 1_700_000_300 : nil,
        usedContext: status == .suggested ? [.fileName, .tagRegistry] : [],
        skippedReason: skippedReason,
        privacyRuleId: skippedReason == .privacyRule ? "rule-confidential" : nil,
        callLogId: 7707,
        requiresUserConfirmation: true,
        confidenceThreshold: 0.8,
        contentsRead: status == .suggested,
        aiUsed: status == .suggested,
        networkUsed: false
    )
}

func aiTagSuggestionAITagSuggestion(
    id: String,
    slug: String,
    confidence: Float,
    selectedByDefault: Bool = true,
    displayName: String? = nil,
    status: AiTagSuggestionCandidateStatus = .suggested,
    mergeAction: AiTagSuggestionMergeAction = .createTag,
    matchedExistingSlug: String? = nil,
    disabledReason: String? = nil
) -> AiTagSuggestion {
    AiTagSuggestion(
        suggestionId: id,
        slug: slug,
        displayName: displayName ?? slug.prefix(1).uppercased() + slug.dropFirst(),
        confidence: confidence,
        reason: "ai-tag-suggestions ai-tags-suggestion local tag suggestion.",
        status: status,
        mergeAction: mergeAction,
        matchedExistingSlug: matchedExistingSlug,
        selectedByDefault: selectedByDefault,
        disabledReason: disabledReason
    )
}

func aiTagSuggestionApplyReport(fileID: Int64) -> AiTagSuggestionApplyReport {
    let tag = aiTagSuggestionTag("finance")
    return AiTagSuggestionApplyReport(
        fileId: fileID,
        requestedCount: 1,
        appliedCount: 1,
        skippedCount: 0,
        failedCount: 0,
        itemResults: [
            AiTagSuggestionApplyItemResult(
                suggestionId: "ai-tag-finance",
                slug: "finance",
                status: .applied,
                error: nil
            )
        ],
        tagSet: TagSet(
            fileId: fileID,
            fileTags: [tag],
            availableTags: [tag],
            recentTags: [tag],
            updatedAt: 1_700_000_350
        ),
        undoToken: nil,
        callLogId: 7707,
        refreshTargets: ["tags", "change_log", "undo_actions", "ai_call_log"]
    )
}

func aiTagSuggestionBatchApplyReport(
    fileID: Int64,
    suggestionID: String,
    slug: String,
    status: AiTagSuggestionApplyStatus = .applied,
    error: String? = nil
) -> AiTagSuggestionApplyReport {
    let tag = aiTagSuggestionTag(slug)
    return AiTagSuggestionApplyReport(
        fileId: fileID,
        requestedCount: 1,
        appliedCount: status == AiTagSuggestionApplyStatus.applied ? 1 : 0,
        skippedCount: status == AiTagSuggestionApplyStatus.alreadyAdded ? 1 : 0,
        failedCount: status == AiTagSuggestionApplyStatus.failed ? 1 : 0,
        itemResults: [
            AiTagSuggestionApplyItemResult(
                suggestionId: suggestionID,
                slug: slug,
                status: status,
                error: error
            )
        ],
        tagSet: TagSet(
            fileId: fileID,
            fileTags: status == AiTagSuggestionApplyStatus.applied ? [tag] : [],
            availableTags: [tag],
            recentTags: [tag],
            updatedAt: 1_700_000_350
        ),
        undoToken: nil,
        callLogId: 7707,
        refreshTargets: ["tags", "change_log", "undo_actions", "ai_call_log"]
    )
}

func aiTagSuggestionTag(_ value: String) -> TagRecord {
    TagRecord(
        value: value,
        label: value.prefix(1).uppercased() + value.dropFirst(),
        fileCount: 1,
        selected: true,
        disabled: false,
        updatedAt: 1_700_000_350
    )
}

func aiTagSuggestionProviderGateReport(
    skippedReason: AiPrivacySkippedReason,
    providerGateReason: AiPrivacyProviderGateReason
) -> AiPrivacyEvaluationReport {
    AiPrivacyEvaluationReport(
        decision: .skipped,
        skippedReason: skippedReason,
        providerGateReason: providerGateReason,
        matchedRules: [],
        matchedFieldType: nil,
        allowedFields: [],
        blockedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
        sentFields: [],
        message: "Provider gate blocked AI tag suggestions before any fields were sent."
    )
}
