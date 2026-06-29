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
            "Loading summary..."
        case .generating:
            "Generating..."
        case .saving:
            "Saving summary..."
        case .clearing:
            "Clearing summary..."
        case .idle, .failed:
            nil
        }
    }
}

enum AISummaryEditorFailedAction: Equatable {
    case load, generate, save, clear
}

enum AISummaryEditorStatus: Equatable {
    case empty, draft, saved, dirty
    case skipped(AiSummarySkipReason?)
    case unavailable(AiSummarySkipReason?)

    var label: String {
        switch self {
        case .empty: "No AI summary yet."
        case .draft: "Draft"
        case .saved: "Saved"
        case .dirty: "Unsaved changes"
        case let .skipped(reason): reason.map(aiSummarySkipReasonLabel) ?? "Skipped"
        case .unavailable: "Summary unavailable"
        }
    }
}

struct AISummaryProvenance: Equatable {
    var draftID: String?
    var route: AiSummaryRoute?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AiSummaryInputField]
    var privacyRuleID: String?
    var callLogID: Int64?
    var characterCount: Int64

    init(draft: AiSummaryDraft) {
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
    var status: AISummaryEditorStatus
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
        case .regenerate: "Regenerate AI summary?"
        case .clear: "Clear AI summary?"
        }
    }

    var message: String {
        switch self {
        case .regenerate:
            """
            This replaces the current draft or unsaved edits with a new AI-generated draft. \
            Saved notes and the original file will not be changed.
            """
        case .clear:
            """
            This clears the AI-derived summary for this file. It will not delete your note, \
            original file, extracted text, tags, or AI call log.
            """
        }
    }

    var actionTitle: String {
        switch self {
        case .regenerate: "Regenerate"
        case .clear: "Clear summary"
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
