import Foundation

struct AISummaryEditorContentState {
    private(set) var draftText = ""
    private(set) var savedText: String?
    private(set) var savedProvenance: AISummaryProvenance?
    private(set) var baselineText: String?
    private(set) var provenance: AISummaryProvenance?
    private(set) var draftOwnership: AIContentOwnershipState = .generated
    private(set) var expectedContentRevision: Int64 = 0
    private(set) var status: AISummaryEditorStatus = .empty

    var characterCountText: String {
        L10n.plural("ai.summary.characterCount", count: draftText.count)
    }

    var hasSummaryContent: Bool {
        !draftText.isEmpty || savedText != nil || provenance != nil
    }

    var canDiscard: Bool {
        status == .dirty || status == .draft
    }

    var canSave: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (status == .dirty || status == .draft) &&
            provenance?.operationID != nil &&
            provenance?.contentLocale != nil &&
            provenance?.formatContractVersion != nil
    }

    var needsExitConfirmation: Bool {
        canDiscard
    }

    var replacesUserOwnedSummary: Bool {
        savedProvenance?.ownership == .userOwned && draftText != savedText
    }

    var snapshot: AISummaryEditorSnapshot {
        AISummaryEditorSnapshot(
            draftText: draftText,
            savedText: savedText,
            savedProvenance: savedProvenance,
            baselineText: baselineText,
            provenance: provenance,
            draftOwnership: draftOwnership,
            expectedContentRevision: expectedContentRevision,
            status: status
        )
    }

    mutating func reset() {
        draftText = ""
        savedText = nil
        baselineText = nil
        provenance = nil
        savedProvenance = nil
        draftOwnership = .generated
        expectedContentRevision = 0
        status = .empty
    }

    mutating func updateDraft(_ text: String) {
        guard draftText != text else { return }
        draftText = text
        if text.isEmpty, savedText == nil, provenance == nil {
            status = .empty
        } else if text == baselineText, savedText != nil {
            status = .saved
        } else if text == baselineText {
            status = .draft
        } else {
            status = .dirty
            draftOwnership = .userOwned
        }
    }

    mutating func apply(_ draft: AISummaryDraftSnapshot) {
        provenance = AISummaryProvenance(draft: draft)
        draftOwnership = .generated
        switch draft.status {
        case .draft:
            let text = draft.summaryText ?? ""
            draftText = text
            baselineText = text
            status = .draft
        case .skipped:
            status = .skipped(draft.skippedReason)
        case .unavailable:
            status = .unavailable(draft.skippedReason)
        }
    }

    mutating func apply(_ skip: AISummaryPrivacySkip, draft: AISummaryDraftSnapshot) {
        provenance = AISummaryProvenance(draft: draft)
        status = skip.editorStatus
    }

    mutating func apply(_ skip: AISummaryPrivacySkip) {
        provenance = nil
        status = skip.editorStatus
    }

    mutating func apply(_ saved: AISummarySavedSnapshot?) {
        apply(AISummaryPersistedStateSnapshot(
            summary: saved,
            contentRevision: saved?.contentRevision ?? 0
        ))
    }

    mutating func apply(_ state: AISummaryPersistedStateSnapshot) {
        guard let saved = state.summary else {
            reset()
            expectedContentRevision = state.contentRevision
            return
        }
        let savedProvenance = AISummaryProvenance(saved: saved)
        draftText = saved.summaryText
        savedText = saved.summaryText
        baselineText = saved.summaryText
        self.savedProvenance = savedProvenance
        provenance = savedProvenance
        draftOwnership = savedProvenance.ownership
        expectedContentRevision = state.contentRevision
        status = .saved
    }

    mutating func acceptSaveReport(_ report: AISummarySaveReportSnapshot) {
        let saved = AISummaryProvenance(report: report)
        savedText = report.savedSummary
        draftText = report.savedSummary
        baselineText = report.savedSummary
        savedProvenance = saved
        provenance = saved
        draftOwnership = saved.ownership
        expectedContentRevision = report.contentRevision
        status = .saved
    }

    mutating func discardChanges() {
        draftText = savedText ?? ""
        baselineText = savedText
        status = savedText == nil ? .empty : .saved
        provenance = savedProvenance
        draftOwnership = savedProvenance?.ownership ?? .generated
    }

    mutating func applyReplacementCandidate(_ review: AISummaryReplacementReview) {
        draftText = review.candidateText
        baselineText = review.candidateText
        provenance = review.candidateProvenance
        draftOwnership = .userOwned
        status = .dirty
    }

    mutating func rebaseSavedSummary(_ state: AISummaryPersistedStateSnapshot) {
        let localText = draftText
        let localProvenance = provenance
        apply(state)
        draftText = localText
        provenance = localProvenance
        draftOwnership = .userOwned
        status = .dirty
    }

    mutating func clear(_ report: AISummaryClearReportSnapshot) {
        reset()
        expectedContentRevision = report.contentRevision
    }

    mutating func restore(_ snapshot: AISummaryEditorSnapshot) {
        draftText = snapshot.draftText
        savedText = snapshot.savedText
        baselineText = snapshot.baselineText
        savedProvenance = snapshot.savedProvenance
        provenance = snapshot.provenance
        draftOwnership = snapshot.draftOwnership
        expectedContentRevision = snapshot.expectedContentRevision
        status = snapshot.status
    }

    func replacementReview(candidate: AISummaryDraftSnapshot) -> AISummaryReplacementReview? {
        guard candidate.status == .draft,
              let savedText,
              let savedProvenance,
              savedProvenance.ownership == .userOwned,
              let candidateText = candidate.summaryText
        else {
            return nil
        }
        return AISummaryReplacementReview(
            source: .generatedCandidate,
            savedText: savedText,
            savedProvenance: savedProvenance,
            candidateText: candidateText,
            candidateProvenance: AISummaryProvenance(draft: candidate)
        )
    }

    func currentDraftReplacementReview() -> AISummaryReplacementReview? {
        guard replacesUserOwnedSummary,
              let savedText,
              let savedProvenance,
              let provenance
        else {
            return nil
        }
        return AISummaryReplacementReview(
            source: .currentDraft,
            savedText: savedText,
            savedProvenance: savedProvenance,
            candidateText: draftText,
            candidateProvenance: provenance
        )
    }

    func saveRequest(fileID: Int64, confirmReplaceUserOwned: Bool) -> AISummarySaveRequestSnapshot? {
        guard let operationID = provenance?.operationID,
              let contentLocale = provenance?.contentLocale,
              let formatContractVersion = provenance?.formatContractVersion
        else {
            return nil
        }
        return AISummarySaveRequestSnapshot(
            fileID: fileID,
            expectedContentRevision: expectedContentRevision,
            confirmReplaceUserOwned: confirmReplaceUserOwned,
            summaryText: draftText,
            draftID: provenance?.draftID,
            route: provenance?.route,
            modelName: provenance?.modelName,
            generatedAt: provenance?.generatedAt,
            usedContext: provenance?.usedContext ?? [],
            privacyRuleID: provenance?.privacyRuleID,
            callLogID: provenance?.callLogID,
            ownership: draftOwnership,
            operationID: operationID,
            contentLocale: contentLocale,
            formatContractVersion: formatContractVersion
        )
    }
}
