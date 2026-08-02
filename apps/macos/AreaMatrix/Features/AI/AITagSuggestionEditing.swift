import Foundation

struct AITagSuggestionRejectedFeedback: Equatable, Identifiable {
    var fileID: Int64
    var rejectedIDs: Set<String>
    var callLogID: Int64?

    var id: String {
        "\(fileID)-\(rejectedIDs.sorted().joined(separator: ","))-\(callLogID ?? -1)"
    }

    var message: String {
        L10n.plural("ai.tagSuggestions.rejectedFeedback", count: rejectedIDs.count)
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
    var id: String {
        suggestionID
    }

    var applyItem: ApplyAITagSuggestionItemSnapshot {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ApplyAITagSuggestionItemSnapshot(
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
    var attentionCount: Int {
        drafts.filter(\.status.preventsApply).count
    }

    var canApply: Bool {
        !drafts.isEmpty && drafts.allSatisfy { !$0.status.preventsApply }
    }

    var applyItems: [ApplyAITagSuggestionItemSnapshot] {
        canApply ? drafts.map(\.applyItem) : []
    }
}

enum AITagSuggestionAction {
    static func canApply(_ suggestion: AITagSuggestionSnapshot) -> Bool {
        suggestion.status == .suggested && suggestion.disabledReason == nil
    }

    static func initialSelection(in report: AITagSuggestionReportSnapshot) -> Set<String> {
        Set(report.suggestions.filter { $0.selectedByDefault && canApply($0) }.map(\.suggestionId))
    }

    static func selectedApplyItems(in state: AITagSuggestionState) -> [ApplyAITagSuggestionItemSnapshot] {
        guard let report = state.report else { return [] }
        return report.suggestions.compactMap { suggestion in
            guard state.selectedIDs.contains(suggestion.suggestionId), canApply(suggestion) else { return nil }
            return ApplyAITagSuggestionItemSnapshot(suggestion: suggestion, editedByUser: false)
        }
    }

    static func applyItem(suggestionID: String, in state: AITagSuggestionState) -> ApplyAITagSuggestionItemSnapshot? {
        guard let suggestion = state.report?.suggestions.first(where: { $0.suggestionId == suggestionID }),
              canApply(suggestion) else {
            return nil
        }
        return ApplyAITagSuggestionItemSnapshot(suggestion: suggestion, editedByUser: false)
    }

    static func toggling(_ suggestionID: String, in state: AITagSuggestionState) -> AITagSuggestionState {
        guard let report = state.report,
              report.suggestions.contains(where: { $0.suggestionId == suggestionID && canApply($0) }) else {
            return state
        }
        var selected = state.selectedIDs
        if selected.contains(suggestionID) {
            return rejectingSelection([suggestionID], in: state)
        }
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
        rejectingSelection(state.selectedIDs, in: state)
    }

    static func rejectingSelection(_ rejectedIDs: Set<String>, in state: AITagSuggestionState) -> AITagSuggestionState {
        guard let report = state.report else { return state }
        let visibleIDs = Set(report.suggestions.map(\.suggestionId))
        let idsToReject = rejectedIDs.intersection(visibleIDs)
        guard !idsToReject.isEmpty else { return state }
        let feedback = AITagSuggestionRejectedFeedback(
            fileID: report.fileId,
            rejectedIDs: idsToReject,
            callLogID: report.callLogId
        )
        return .rejected(fileID: report.fileId, report.hidingSuggestions(idsToReject), feedback)
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
        return .editing(
            fileID: report.fileId,
            report,
            validated(session, report: report, disabledReason: disabledReason)
        )
    }

    static func applyingEdited(in state: AITagSuggestionState) -> AITagSuggestionState {
        guard let report = state.report, let session = state.editSession else { return state }
        return .applyingEdited(fileID: report.fileId, report: report, session: session)
    }

    static func editedItems(in state: AITagSuggestionState) -> [ApplyAITagSuggestionItemSnapshot] {
        state.editSession?.applyItems ?? []
    }

    static func retryFailedItems(in state: AITagSuggestionState) -> [ApplyAITagSuggestionItemSnapshot] {
        state.editSession?.drafts.compactMap { draft in
            if case .failed = draft.status { return draft.applyItem }
            return nil
        } ?? []
    }

    static func sessionAfterApply(
        _ session: AITagSuggestionEditSession,
        report: AITagSuggestionApplyReportSnapshot
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
        report: AITagSuggestionReportSnapshot,
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
        report: AITagSuggestionReportSnapshot,
        disabledReason: String?,
        seen: inout Set<String>
    ) -> TagSuggestionEditRowStatus {
        if disabledReason != nil { return .blocked(L10n.display("Tag store is read-only.")) }
        guard let suggestion = report.suggestions.first(where: { $0.suggestionId == draft.suggestionID }) else {
            return .blocked(L10n.display("tag-suggestion.no-longer-available"))
        }
        if suggestion.status == .alreadyApplied { return .alreadyAdded(L10n.display("Already applied")) }
        if suggestion.status == .blocked || suggestion.disabledReason != nil {
            return .blocked(L10n.display(
                "Suggestion is blocked.",
                technicalDetail: suggestion.disabledReason
            ))
        }
        guard let normalized = TagInputNormalization.normalizedValue(draft.slug) else {
            return .invalid(L10n.display("Tag name is invalid."))
        }
        if seen.contains(normalized) {
            return .duplicate(L10n.display("tag-suggestion.duplicate-selected-slug"))
        }
        seen.insert(normalized)
        return .ready
    }

    private static func rowStatus(for result: AITagSuggestionApplyItemResultSnapshot) -> TagSuggestionEditRowStatus {
        switch result.status {
        case .applied: .applied
        case .alreadyAdded:
            .alreadyAdded(L10n.display("Already applied", technicalDetail: result.error))
        case .failed:
            .failed(L10n.display("A suggestion could not be applied.", technicalDetail: result.error))
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
    init(suggestion: AITagSuggestionSnapshot) {
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

extension ApplyAITagSuggestionItemSnapshot {
    init(suggestion: AITagSuggestionSnapshot, editedByUser: Bool) {
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

extension AITagSuggestionReportSnapshot {
    func hidingSuggestions(_ hiddenIDs: Set<String>) -> AITagSuggestionReportSnapshot {
        var next = self
        next.suggestions.removeAll { hiddenIDs.contains($0.suggestionId) }
        return next
    }
}
