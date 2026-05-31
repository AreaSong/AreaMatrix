import Foundation
import SwiftUI

enum AISummaryEditorGateReason: Equatable {
    case aiDisabled
    case featureDisabled
    case providerUnavailable
    case remoteScopeNotAllowed
    case privacyBlocked(AISummaryPrivacySkip)
    case noEligibleInput(AISummaryPrivacySkip)
    case callLogUnavailable
    case privacyUnavailable
}

struct AISummaryEditorNotice: Equatable {
    var title: String
    var detail: String
    var recovery: String
    var capability: String
    var opensAISettings: Bool
    var privacyRuleID: String?
    var reason: AISummaryEditorGateReason
}

enum AISummaryEditorGateState: Equatable {
    case unknown
    case checking
    case allowed
    case blocked(AISummaryEditorNotice)
    case failed(AISettingsError)

    var allowsGeneration: Bool {
        self == .allowed
    }
}

extension AISummaryEditorNotice {
    static func aiDisabled() -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: "AI summaries are off",
            detail: "AI is disabled for this repository.",
            recovery: "Open AI settings and turn on AI features.",
            capability: "C3-06",
            opensAISettings: true,
            privacyRuleID: nil,
            reason: .aiDisabled
        )
    }

    static func featureDisabled(_ detail: String?) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: "Auto summaries are off",
            detail: detail ?? "The Auto summaries feature is disabled.",
            recovery: "Open AI settings and enable Auto summaries.",
            capability: "C3-06",
            opensAISettings: true,
            privacyRuleID: nil,
            reason: .featureDisabled
        )
    }

    static func providerUnavailable(_ detail: String?) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: "AI provider is unavailable",
            detail: detail ?? "No local or remote AI route is enabled for summaries.",
            recovery: "Open AI settings and enable a summary provider.",
            capability: "C3-06",
            opensAISettings: true,
            privacyRuleID: nil,
            reason: .providerUnavailable
        )
    }

    static func remoteScopeBlocked(_ detail: String) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: "AI provider is unavailable",
            detail: detail,
            recovery: "Open AI settings and configure remote summaries.",
            capability: "C3-06",
            opensAISettings: true,
            privacyRuleID: nil,
            reason: .remoteScopeNotAllowed
        )
    }
}

enum AITagSuggestionState: Equatable {
    case idle
    case loading(fileID: Int64, previous: AiTagSuggestionReport?)
    case loaded(fileID: Int64, AiTagSuggestionReport, Set<String>)
    case editing(fileID: Int64, AiTagSuggestionReport, AITagSuggestionEditSession)
    case applying(fileID: Int64, report: AiTagSuggestionReport, selectedIDs: Set<String>)
    case applyingEdited(fileID: Int64, report: AiTagSuggestionReport, session: AITagSuggestionEditSession)
    case editApplied(fileID: Int64, AiTagSuggestionReport, AiTagSuggestionApplyReport, AITagSuggestionEditSession)
    case applied(fileID: Int64, AiTagSuggestionReport, AiTagSuggestionApplyReport, Set<String>)
    case failed(fileID: Int64, CoreErrorMappingSnapshot, previous: AiTagSuggestionReport?)
}

extension AITagSuggestionState {
    var report: AiTagSuggestionReport? {
        switch self {
        case let .loaded(_, report, _), let .loading(_, report?), let .editing(_, report, _),
             let .applying(_, report, _), let .applyingEdited(_, report, _),
             let .applied(_, report, _, _), let .editApplied(_, report, _, _),
             let .failed(_, _, report?):
            report
        case .idle, .loading, .failed:
            nil
        }
    }

    var selectedIDs: Set<String> {
        switch self {
        case let .loaded(_, _, selected), let .applying(_, _, selected), let .applied(_, _, _, selected):
            selected
        case let .editing(_, _, session), let .applyingEdited(_, _, session), let .editApplied(_, _, _, session):
            session.selectedIDs
        case .idle, .loading, .failed:
            []
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isApplying: Bool {
        switch self {
        case .applying, .applyingEdited:
            true
        case .idle, .loading, .loaded, .editing, .applied, .editApplied, .failed:
            false
        }
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(_, mapping, _) = self else { return nil }
        return mapping
    }

    var appliedReport: AiTagSuggestionApplyReport? {
        switch self {
        case let .applied(_, _, report, _), let .editApplied(_, _, report, _):
            report
        case .idle, .loading, .loaded, .editing, .applying, .applyingEdited, .failed:
            nil
        }
    }

    var editSession: AITagSuggestionEditSession? {
        switch self {
        case let .editing(_, _, session), let .applyingEdited(_, _, session), let .editApplied(_, _, _, session):
            session
        case .idle, .loading, .loaded, .applying, .applied, .failed:
            nil
        }
    }

    var fileID: Int64? {
        switch self {
        case let .loading(fileID, _), let .loaded(fileID, _, _), let .editing(fileID, _, _),
             let .applying(fileID, _, _), let .applyingEdited(fileID, _, _),
             let .applied(fileID, _, _, _), let .editApplied(fileID, _, _, _), let .failed(fileID, _, _):
            fileID
        case .idle:
            nil
        }
    }

    var hasHighConfidenceApplyCandidates: Bool {
        guard let report else { return false }
        return report.suggestions.contains {
            AITagSuggestionAction.canApply($0) && $0.confidence >= report.confidenceThreshold
        }
    }

    var canApplySelectedSuggestions: Bool {
        if let editSession { return editSession.canApply }
        return !AITagSuggestionAction.selectedApplyItems(in: self).isEmpty
    }

    var canEditSelectedSuggestions: Bool {
        !AITagSuggestionAction.selectedApplyItems(in: self).isEmpty
    }
}

struct AITagSuggestionEditDraft: Equatable, Identifiable {
    let suggestionID: String
    let originalSlug: String
    let originalDisplayName: String
    let reason: String
    let confidence: Float
    let mergeTargetSlug: String?
    var displayName: String
    var slug: String
    var slugEdited: Bool
    var status: TagSuggestionEditRowStatus
    var id: String { suggestionID }

    var applyItem: ApplyAiTagSuggestionItem {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ApplyAiTagSuggestionItem(
            suggestionId: suggestionID,
            slug: slug,
            displayName: cleanName.isEmpty ? slug : cleanName,
            confidence: confidence,
            editedByUser: slug != originalSlug || cleanName != originalDisplayName,
            mergeTargetSlug: mergeTargetSlug
        )
    }
}

struct AITagSuggestionEditSession: Equatable {
    var selectedIDs: Set<String>
    var drafts: [AITagSuggestionEditDraft]
    var attentionCount: Int { drafts.filter(\.status.preventsApply).count }
    var canApply: Bool { !drafts.isEmpty && drafts.allSatisfy { !$0.status.preventsApply } }
    var applyItems: [ApplyAiTagSuggestionItem] { canApply ? drafts.map(\.applyItem) : [] }
}

enum AITagSuggestionAction {
    static func canApply(_ suggestion: AiTagSuggestion) -> Bool {
        suggestion.status == .suggested && suggestion.disabledReason == nil
    }

    static func initialSelection(in report: AiTagSuggestionReport) -> Set<String> {
        Set(report.suggestions.filter { $0.selectedByDefault && canApply($0) }.map(\.suggestionId))
    }

    static func selectedApplyItems(in state: AITagSuggestionState) -> [ApplyAiTagSuggestionItem] {
        guard let report = state.report else { return [] }
        return report.suggestions.compactMap { suggestion in
            guard state.selectedIDs.contains(suggestion.suggestionId), canApply(suggestion) else { return nil }
            return ApplyAiTagSuggestionItem(suggestion: suggestion, editedByUser: false)
        }
    }

    static func applyItem(suggestionID: String, in state: AITagSuggestionState) -> ApplyAiTagSuggestionItem? {
        guard let suggestion = state.report?.suggestions.first(where: { $0.suggestionId == suggestionID }),
              canApply(suggestion) else {
            return nil
        }
        return ApplyAiTagSuggestionItem(suggestion: suggestion, editedByUser: false)
    }

    static func toggling(_ suggestionID: String, in state: AITagSuggestionState) -> AITagSuggestionState {
        guard let report = state.report,
              report.suggestions.contains(where: { $0.suggestionId == suggestionID && canApply($0) }) else {
            return state
        }
        var selected = state.selectedIDs
        selected.formSymmetricDifference([suggestionID])
        return .loaded(fileID: report.fileId, report, selected)
    }

    static func selectingHighConfidence(in state: AITagSuggestionState) -> AITagSuggestionState {
        guard let report = state.report else { return state }
        let ids = Set(report.suggestions.compactMap {
            canApply($0) && $0.confidence >= report.confidenceThreshold ? $0.suggestionId : nil
        })
        return .loaded(fileID: report.fileId, report, ids)
    }

    static func clearingSelection(in state: AITagSuggestionState) -> AITagSuggestionState {
        guard let report = state.report else { return state }
        return .loaded(fileID: report.fileId, report, [])
    }

    static func updatingDisplayName(
        suggestionID: String,
        displayName: String,
        in state: AITagSuggestionState,
        disabledReason: String?
    ) -> AITagSuggestionState {
        updatingDraft(suggestionID, in: state, disabledReason: disabledReason) { draft in
            draft.displayName = displayName
            if !draft.slugEdited { draft.slug = normalizedSlug(from: displayName) }
        }
    }

    static func updatingSlug(
        suggestionID: String,
        slug: String,
        in state: AITagSuggestionState,
        disabledReason: String?
    ) -> AITagSuggestionState {
        updatingDraft(suggestionID, in: state, disabledReason: disabledReason) { draft in
            draft.slug = slug
            draft.slugEdited = true
        }
    }

    static func regeneratingSlug(
        suggestionID: String,
        in state: AITagSuggestionState,
        disabledReason: String?
    ) -> AITagSuggestionState {
        updatingDraft(suggestionID, in: state, disabledReason: disabledReason) { draft in
            draft.slug = normalizedSlug(from: draft.displayName)
            draft.slugEdited = false
        }
    }

    static func startingEdit(in state: AITagSuggestionState, disabledReason: String?) -> AITagSuggestionState {
        guard let report = state.report else { return state }
        let drafts = report.suggestions.compactMap { suggestion -> AITagSuggestionEditDraft? in
            guard state.selectedIDs.contains(suggestion.suggestionId) else { return nil }
            return AITagSuggestionEditDraft(suggestion: suggestion)
        }
        let session = validated(
            AITagSuggestionEditSession(selectedIDs: state.selectedIDs, drafts: drafts),
            report: report,
            disabledReason: disabledReason
        )
        return .editing(fileID: report.fileId, report, session)
    }

    static func cancelingEdit(in state: AITagSuggestionState) -> AITagSuggestionState {
        guard let report = state.report else { return state }
        return .loaded(fileID: report.fileId, report, state.selectedIDs)
    }

    static func updatingDraft(
        _ suggestionID: String,
        in state: AITagSuggestionState,
        disabledReason: String?,
        update: (inout AITagSuggestionEditDraft) -> Void
    ) -> AITagSuggestionState {
        guard let report = state.report, var session = state.editSession,
              let index = session.drafts.firstIndex(where: { $0.suggestionID == suggestionID }) else { return state }
        update(&session.drafts[index])
        return .editing(fileID: report.fileId, report, validated(session, report: report, disabledReason: disabledReason))
    }

    static func applyingEdited(in state: AITagSuggestionState) -> AITagSuggestionState {
        guard let report = state.report, let session = state.editSession else { return state }
        return .applyingEdited(fileID: report.fileId, report: report, session: session)
    }

    static func editedItems(in state: AITagSuggestionState) -> [ApplyAiTagSuggestionItem] {
        state.editSession?.applyItems ?? []
    }

    static func retryFailedItems(in state: AITagSuggestionState) -> [ApplyAiTagSuggestionItem] {
        state.editSession?.drafts.compactMap { draft in
            if case .failed = draft.status { return draft.applyItem }
            return nil
        } ?? []
    }

    static func sessionAfterApply(
        _ session: AITagSuggestionEditSession,
        report: AiTagSuggestionApplyReport
    ) -> AITagSuggestionEditSession {
        var next = session
        next.drafts = session.drafts.map { draft in
            var updated = draft
            guard let result = report.itemResults.first(where: { $0.suggestionId == draft.suggestionID }) else {
                return updated
            }
            updated.status = rowStatus(for: result)
            return updated
        }
        return next
    }

    private static func validated(
        _ session: AITagSuggestionEditSession,
        report: AiTagSuggestionReport,
        disabledReason: String?
    ) -> AITagSuggestionEditSession {
        var seen: Set<String> = []
        var next = session
        next.drafts = session.drafts.map {
            var draft = $0
            draft.status = rowStatus(for: draft, report: report, disabledReason: disabledReason, seen: &seen)
            return draft
        }
        return next
    }

    private static func rowStatus(
        for draft: AITagSuggestionEditDraft,
        report: AiTagSuggestionReport,
        disabledReason: String?,
        seen: inout Set<String>
    ) -> TagSuggestionEditRowStatus {
        if disabledReason != nil { return .blocked("Tag store is read-only.") }
        guard let suggestion = report.suggestions.first(where: { $0.suggestionId == draft.suggestionID }) else {
            return .blocked("Suggestion is no longer available.")
        }
        if suggestion.status == .alreadyApplied { return .alreadyAdded("Already applied") }
        if suggestion.status == .blocked || suggestion.disabledReason != nil {
            return .blocked(suggestion.disabledReason ?? "Suggestion is blocked.")
        }
        guard let normalized = TagInputNormalization.normalizedValue(draft.slug) else {
            return .invalid(TagInputNormalization.invalidMessage)
        }
        if seen.contains(normalized) { return .duplicate("Duplicate slug in selected tags.") }
        seen.insert(normalized)
        return .ready
    }

    private static func rowStatus(for result: AiTagSuggestionApplyItemResult) -> TagSuggestionEditRowStatus {
        switch result.status {
        case .applied: return .applied
        case .alreadyAdded: return .alreadyAdded(result.error ?? "Already applied")
        case .failed: return .failed(result.error ?? "A suggestion could not be applied.")
        }
    }

    private static func normalizedSlug(from displayName: String) -> String {
        displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

extension AITagSuggestionEditDraft {
    init(suggestion: AiTagSuggestion) {
        suggestionID = suggestion.suggestionId
        originalSlug = suggestion.slug
        originalDisplayName = suggestion.displayName
        reason = suggestion.reason
        confidence = suggestion.confidence
        mergeTargetSlug = suggestion.matchedExistingSlug
        displayName = suggestion.displayName
        slug = suggestion.slug
        slugEdited = false
        status = .ready
    }
}

extension ApplyAiTagSuggestionItem {
    init(suggestion: AiTagSuggestion, editedByUser: Bool) {
        self.init(
            suggestionId: suggestion.suggestionId,
            slug: suggestion.slug,
            displayName: suggestion.displayName,
            confidence: suggestion.confidence,
            editedByUser: editedByUser,
            mergeTargetSlug: suggestion.matchedExistingSlug
        )
    }
}
