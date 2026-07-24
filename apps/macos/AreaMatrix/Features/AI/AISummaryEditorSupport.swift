import Combine
import Foundation

enum AISummaryEditorOperation: Equatable {
    case idle, loading, generating, saving, clearing, failed(AISettingsError)

    var isBusy: Bool {
        self == .loading || self == .generating || self == .saving || self == .clearing
    }

    var progressText: String? {
        switch self {
        case .loading:
            L10n.string("Loading summary...")
        case .generating:
            L10n.string("Generating...")
        case .saving:
            L10n.string("Saving summary...")
        case .clearing:
            L10n.string("Clearing summary...")
        case .idle, .failed:
            nil
        }
    }
}

enum AISummaryEditorFailedAction: Equatable {
    case load, generate, save, clear
}

extension AISummaryEditorModel {
    var characterCountText: String {
        contentState.characterCountText
    }

    var status: AISummaryEditorStatus {
        contentState.status
    }

    var provenance: AISummaryProvenance? {
        contentState.provenance
    }

    var draftText: String {
        contentState.draftText
    }

    var canGenerate: Bool {
        canEdit && gateState.allowsGeneration
    }

    var canCancelGeneration: Bool {
        operation == .generating
    }

    var canRegenerate: Bool {
        canGenerate && contentState.hasSummaryContent
    }

    var canDiscard: Bool {
        canEdit && contentState.canDiscard
    }

    var canClear: Bool {
        canEdit && privacySkip == nil && contentState.hasSummaryContent
    }

    var canSave: Bool {
        canEdit && contentState.canSave
    }

    var needsExitConfirmation: Bool {
        contentState.needsExitConfirmation
    }

    var canEdit: Bool {
        !operation.isBusy
    }

    func retryGeneration() async {
        let failed = failedGenerationAttempt
        await generate(
            regenerate: failed?.regenerate ?? false,
            retryOfOperationID: failed?.operationID
        )
    }

    func cancelFailedAction() {
        guard failedAction != nil else { return }
        failedAction = nil
        operation = .idle
    }

    func summaryError(for error: Error, message: LocalizedMessage) async -> AISettingsError {
        await AISummaryEditorPresentationSupport.error(
            for: error,
            message: message,
            errorMapper: errorMapper
        )
    }

    func applyClearConflictIfPresent(_ error: Error) async -> Bool {
        guard case let CoreError.RevisionConflict(resource, expected, current) = error,
              resource == "ai_summary_content_revision"
        else {
            return false
        }
        do {
            let latest = try await summaryStore.loadAISummaryState(repoPath: repoPath, fileID: fileID)
            apply(latest)
            clearConflictNotice = AISummaryClearConflictNotice(
                expectedRevision: expected,
                currentRevision: current
            )
            failedAction = nil
            operation = .idle
            return true
        } catch {
            return false
        }
    }

    func saveRequest() -> AiSummarySaveRequest? {
        contentState.saveRequest(fileID: fileID, confirmReplaceUserOwned: confirmedReplacement)
    }

    func snapshot() -> AISummaryEditorSnapshot {
        contentState.snapshot
    }
}

enum AISummaryEditorStatus: Equatable {
    case empty, draft, saved, dirty
    case skipped(AiSummarySkipReason?)
    case unavailable(AiSummarySkipReason?)

    var label: String {
        switch self {
        case .empty: L10n.string("No AI summary yet.")
        case .draft: L10n.string("Draft")
        case .saved: L10n.string("Saved")
        case .dirty: L10n.string("Unsaved changes")
        case let .skipped(reason): reason.map(aiSummarySkipReasonLabel) ?? L10n.string("Skipped")
        case .unavailable: L10n.string("Summary unavailable")
        }
    }
}

struct AISummaryProvenance: Equatable {
    var operationID: String?
    var contentLocale: ContentLocale?
    var formatContractVersion: Int64?
    var contentRevision: Int64
    var ownership: AiContentOwnership
    var draftID: String?
    var route: AiSummaryRoute?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AiSummaryInputField]
    var privacyRuleID: String?
    var callLogID: Int64?
    var characterCount: Int64

    init(draft: AiSummaryDraft) {
        operationID = draft.operationId
        contentLocale = draft.contentLocale
        formatContractVersion = draft.formatContractVersion
        contentRevision = 0
        ownership = .generated
        draftID = draft.draftId
        route = draft.route
        modelName = draft.modelName
        generatedAt = draft.generatedAt
        usedContext = draft.usedContext
        privacyRuleID = draft.privacyRuleId
        callLogID = draft.callLogId
        characterCount = draft.characterCount
    }

    init(report: AiSummarySaveReport) {
        operationID = report.operationId
        contentLocale = report.contentLocale
        formatContractVersion = report.formatContractVersion
        contentRevision = report.contentRevision
        ownership = report.ownership
        draftID = nil
        route = report.route
        modelName = report.modelName
        generatedAt = report.generatedAt
        usedContext = report.usedContext
        privacyRuleID = report.privacyRuleId
        callLogID = report.callLogId
        characterCount = report.characterCount
    }

    init(saved: AISummarySavedSnapshot) {
        operationID = saved.operationID
        contentLocale = saved.contentLocale
        formatContractVersion = saved.formatContractVersion
        contentRevision = saved.contentRevision
        ownership = saved.ownership
        draftID = saved.draftID
        route = saved.route
        modelName = saved.modelName
        generatedAt = saved.generatedAt
        usedContext = saved.usedContext
        privacyRuleID = saved.privacyRuleID
        callLogID = saved.callLogID
        characterCount = saved.characterCount
    }
}

struct AISummaryEditorSnapshot {
    var draftText: String
    var savedText: String?
    var savedProvenance: AISummaryProvenance?
    var baselineText: String?
    var provenance: AISummaryProvenance?
    var draftOwnership: AiContentOwnership
    var expectedContentRevision: Int64
    var status: AISummaryEditorStatus
}

struct AISummarySaveConflictReview: Equatable {
    var observedText: String?
    var latestState: AISummaryPersistedStateSnapshot
    var localText: String
    var expectedRevision: Int64
    var currentRevision: Int64
}

struct AISummaryClearConflictNotice: Equatable {
    var expectedRevision: Int64
    var currentRevision: Int64
}

struct AISummaryReplacementReview: Equatable {
    enum Source: Equatable {
        case generatedCandidate
        case currentDraft
    }

    var source: Source
    var savedText: String
    var savedProvenance: AISummaryProvenance
    var candidateText: String
    var candidateProvenance: AISummaryProvenance
}

struct AISummaryGenerationAttempt: Equatable {
    var operationID: String
    var retryOfOperationID: String?
    var regenerate: Bool
}

struct AISummaryEditorIdentity: Equatable {
    var fileID: Int64
    var privacyContext: AISummaryPrivacyContext
}

@MainActor
final class AISummaryEditorExitController: ObservableObject {
    @Published private(set) var needsConfirmation = false

    private var saveHandler: (@MainActor () async -> Bool)?
    private var discardHandler: (@MainActor () -> Void)?

    func update(
        needsConfirmation: Bool,
        saveHandler: @escaping @MainActor () async -> Bool,
        discardHandler: @escaping @MainActor () -> Void
    ) {
        self.needsConfirmation = needsConfirmation
        self.saveHandler = saveHandler
        self.discardHandler = discardHandler
    }

    func saveChanges() async -> Bool {
        guard let saveHandler else { return true }
        let saved = await saveHandler()
        needsConfirmation = !saved
        return saved
    }

    func discardChanges() {
        discardHandler?()
        needsConfirmation = false
    }
}

enum AISummaryConfirmation {
    case regenerate, clear

    var title: String {
        switch self {
        case .regenerate: L10n.string("Regenerate AI summary?")
        case .clear: L10n.string("Clear AI summary?")
        }
    }

    var message: String {
        switch self {
        case .regenerate:
            L10n.string("ai.summary.regenerateConfirmationMessage")
        case .clear:
            L10n.string("ai.summary.clearConfirmationMessage")
        }
    }

    var actionTitle: String {
        switch self {
        case .regenerate: L10n.string("Regenerate")
        case .clear: L10n.string("Clear summary")
        }
    }

    var isDestructive: Bool {
        self == .clear
    }
}

struct AISummaryCallLogRoute: Identifiable, Equatable {
    var callLogID: Int64
    var id: Int64 {
        callLogID
    }
}
