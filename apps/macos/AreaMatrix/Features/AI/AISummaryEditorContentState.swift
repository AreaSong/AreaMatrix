import Foundation

struct AISummaryEditorContentState {
    private(set) var draftText = ""
    private(set) var savedText: String?
    private(set) var savedProvenance: AISummaryProvenance?
    private(set) var baselineText: String?
    private(set) var provenance: AISummaryProvenance?
    private(set) var status: AISummaryEditorStatus = .empty

    var characterCountText: String {
        "\(draftText.count) characters"
    }

    var hasSummaryContent: Bool {
        !draftText.isEmpty || savedText != nil || provenance != nil
    }

    var canDiscard: Bool {
        status == .dirty || status == .draft
    }

    var canSave: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (status == .dirty || status == .draft)
    }

    var needsExitConfirmation: Bool {
        canDiscard
    }

    var snapshot: AISummaryEditorSnapshot {
        AISummaryEditorSnapshot(
            draftText: draftText,
            savedText: savedText,
            savedProvenance: savedProvenance,
            baselineText: baselineText,
            provenance: provenance,
            status: status
        )
    }

    mutating func reset() {
        draftText = ""
        savedText = nil
        baselineText = nil
        provenance = nil
        savedProvenance = nil
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
        }
    }

    mutating func apply(_ draft: AiSummaryDraft) {
        provenance = AISummaryProvenance(draft: draft)
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

    mutating func apply(_ skip: AISummaryPrivacySkip, draft: AiSummaryDraft) {
        provenance = AISummaryProvenance(draft: draft)
        status = skip.editorStatus
    }

    mutating func apply(_ saved: AISummarySavedSnapshot?) {
        guard let saved else {
            reset()
            return
        }
        let savedProvenance = AISummaryProvenance(saved: saved)
        draftText = saved.summaryText
        savedText = saved.summaryText
        baselineText = saved.summaryText
        self.savedProvenance = savedProvenance
        provenance = savedProvenance
        status = .saved
    }

    mutating func acceptSaveReport(_ report: AiSummarySaveReport) {
        let saved = AISummaryProvenance(report: report)
        savedText = report.savedSummary
        draftText = report.savedSummary
        baselineText = report.savedSummary
        savedProvenance = saved
        provenance = saved
        status = .saved
    }

    mutating func discardChanges() {
        draftText = savedText ?? ""
        baselineText = savedText
        status = savedText == nil ? .empty : .saved
        provenance = savedProvenance
    }

    mutating func clear() {
        reset()
    }

    mutating func restore(_ snapshot: AISummaryEditorSnapshot) {
        draftText = snapshot.draftText
        savedText = snapshot.savedText
        baselineText = snapshot.baselineText
        savedProvenance = snapshot.savedProvenance
        provenance = snapshot.provenance
        status = snapshot.status
    }

    func saveRequest(fileID: Int64) -> AiSummarySaveRequest {
        AiSummarySaveRequest(
            fileId: fileID,
            summaryText: draftText,
            draftId: provenance?.draftID,
            route: provenance?.route,
            modelName: provenance?.modelName,
            generatedAt: provenance?.generatedAt,
            usedContext: provenance?.usedContext ?? [],
            privacyRuleId: provenance?.privacyRuleID,
            callLogId: provenance?.callLogID,
            editedByUser: status == .dirty
        )
    }
}
