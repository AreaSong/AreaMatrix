@testable import AreaMatrix
import Foundation
import XCTest

func makeInitDoneTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixInitDoneTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

extension RepoConfigSnapshot {
    static func initDoneFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
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
        )
    }
}

extension RepositoryOpeningResult {
    static func initDoneFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .initDoneFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}

extension FileEntrySnapshot {
    static func initDoneFileFixture(category: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 1,
            path: "\(category)/report.pdf",
            originalName: "report.pdf",
            currentName: "report.pdf",
            category: category,
            sizeBytes: 128,
            hashSha256: "fixture-hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func initDoneConfigFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "资料库配置不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }

    static func initDoneDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "资料库树不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

extension ScanSessionSnapshot {
    static func adoptCompletedFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: .completed,
            lastPath: "README.md",
            inserted: 1,
            updated: 0,
            skipped: 0,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_001,
            finishedAt: 1_700_000_001,
            errors: []
        )
    }
}

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
    static func s207TagDb() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "无法更新标签",
            severity: .medium,
            suggestedAction: "请保留输入并重试标签操作。",
            recoverability: .retryable,
            rawContext: "S2-07 C2-05 tag-crud"
        )
    }
}

extension TagSuggestionRequestSnapshot {
    static func s223(fileID: Int64) -> TagSuggestionRequestSnapshot {
        TagSuggestionRequestSnapshot(
            fileID: fileID,
            context: nil,
            limit: DetailTagSuggestionAction.defaultLimit
        )
    }
}

extension RepositorySidebarRowSnapshot {
    static let s208Root = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
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
    static func s223Fixture(
        detail: FileEntrySnapshot,
        tagStore: any CoreTagCRUD = DetailTagRecordingStore()
    ) -> MainFileListModel {
        MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            tagStore: tagStore,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )
    }
}

extension UndoActionRecordSnapshot {
    static func s223ApplySuggestion(token: String) -> UndoActionRecordSnapshot {
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

actor S307AITagBridge: CoreAITagSuggestionManaging {
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
        return s307ApplyReport(fileID: request.fileId)
    }

    func requests() -> (suggest: [AiTagSuggestionRequest], apply: [ApplyAiTagSuggestionsRequest]) {
        (suggestRequests, applyRequests)
    }
}

actor S307BatchAITagBridge: CoreAITagSuggestionManaging {
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
        return applyReports[request.fileId] ?? s307BatchApplyReport(
            fileID: request.fileId,
            suggestionID: request.suggestions.first?.suggestionId ?? "s3-07-finance",
            slug: request.suggestions.first?.slug ?? "finance"
        )
    }

    func requests() -> (suggest: [AiTagSuggestionRequest], apply: [ApplyAiTagSuggestionsRequest]) {
        (suggestRequests, applyRequests)
    }
}

actor S307AISettingsLoader: CoreAISettingsLoading {
    private let snapshot: AISettingsSnapshot
    private var recordedRepoPaths: [String] = []

    init(aiEnabled: Bool = true, autoTagsEnabled: Bool = true) {
        let config = AISettingsConfigSnapshot(
            repoPath: "/tmp/repo",
            aiEnabled: aiEnabled,
            providerPreference: .localFirst,
            localAIEnabled: true,
            remoteAIAllowed: false,
            privacyGateEnabled: true,
            privacyPolicyRef: nil,
            featureToggles: AISettingsFeatureKind.allCases.map { feature in
                AISettingsFeatureConfigSnapshot(
                    feature: feature,
                    enabled: feature == .autoTags ? autoTagsEnabled : false,
                    allowRemote: false
                )
            }
        )
        snapshot = AISettingsSnapshot(
            config: config,
            capabilities: AISettingsCapabilitySnapshot.derived(from: config.normalized()),
            updatedAt: 1_700_000_410
        )
    }

    func loadAISettings(repoPath: String) async throws -> AISettingsSnapshot {
        recordedRepoPaths.append(repoPath)
        return snapshot
    }

    func requests() -> [String] {
        recordedRepoPaths
    }
}

func s307AITagReport(
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

func s307AITagSuggestion(
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
        reason: "S3-07 C3-07 local tag suggestion.",
        status: status,
        mergeAction: mergeAction,
        matchedExistingSlug: matchedExistingSlug,
        selectedByDefault: selectedByDefault,
        disabledReason: disabledReason
    )
}

func s307ApplyReport(fileID: Int64) -> AiTagSuggestionApplyReport {
    let tag = s307Tag("finance")
    return AiTagSuggestionApplyReport(
        fileId: fileID,
        requestedCount: 1,
        appliedCount: 1,
        skippedCount: 0,
        failedCount: 0,
        itemResults: [
            AiTagSuggestionApplyItemResult(
                suggestionId: "s3-07-finance",
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

func s307BatchApplyReport(
    fileID: Int64,
    suggestionID: String,
    slug: String,
    status: AiTagSuggestionApplyStatus = .applied,
    error: String? = nil
) -> AiTagSuggestionApplyReport {
    let tag = s307Tag(slug)
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

func s307Tag(_ value: String) -> TagRecord {
    TagRecord(
        value: value,
        label: value.prefix(1).uppercased() + value.dropFirst(),
        fileCount: 1,
        selected: true,
        disabled: false,
        updatedAt: 1_700_000_350
    )
}

func s307ProviderGateReport(
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
