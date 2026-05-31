import Foundation

extension MainFileListModel {
    func noteWriteBlock(for file: FileEntrySnapshot) -> MainDetailNoteWriteBlock? {
        if isReadOnly { return .repoReadOnly }
        if file.availability == .missing { return .fileMissing }
        if writeLockedFileIDs.contains(file.id) { return .importLocked }
        if isLoading { return .listLoading }
        return nil
    }
}

enum TagSuggestionPresentationSource: String, Equatable {
    case detailMeta
    case commandPalette
    case importResult
}

struct TagSuggestionPresentationRequest: Equatable, Identifiable {
    var fileID: Int64
    var source: TagSuggestionPresentationSource
    var sequence: Int

    var id: String {
        "\(fileID):\(source.rawValue):\(sequence)"
    }
}

enum DetailTagSuggestionState: Equatable {
    case idle
    case loading(fileID: Int64, previous: TagSuggestionReportSnapshot?)
    case loaded(fileID: Int64, TagSuggestionReportSnapshot, Set<String>)
    case editing(fileID: Int64, TagSuggestionReportSnapshot, TagSuggestionEditSession)
    case applying(fileID: Int64, report: TagSuggestionReportSnapshot, selectedIDs: Set<String>)
    case applyingEdited(fileID: Int64, report: TagSuggestionReportSnapshot, session: TagSuggestionEditSession)
    case editApplied(
        fileID: Int64,
        TagSuggestionReportSnapshot,
        TagSuggestionApplyReportSnapshot,
        TagSuggestionEditSession
    )
    case applied(fileID: Int64, TagSuggestionReportSnapshot, TagSuggestionApplyReportSnapshot, Set<String>)
    case failed(fileID: Int64, CoreErrorMappingSnapshot, previous: TagSuggestionReportSnapshot?)
}

enum DetailTagSuggestionAction {
    static let defaultLimit: Int64 = 12

    static func initialSelection(in report: TagSuggestionReportSnapshot) -> Set<String> {
        Set(report.suggestions.filter { $0.selectedByDefault && $0.canApply }.map(\.suggestionID))
    }

    static func selectedApplyItems(in state: DetailTagSuggestionState) -> [ApplyTagSuggestionItemSnapshot] {
        guard let report = state.report else { return [] }
        return report.suggestions.compactMap { suggestion in
            guard state.selectedIDs.contains(suggestion.suggestionID), suggestion.canApply else { return nil }
            return ApplyTagSuggestionItemSnapshot(
                suggestionID: suggestion.suggestionID,
                slug: suggestion.slug,
                displayName: suggestion.displayName
            )
        }
    }

    static func togglingSelection(
        suggestionID: String,
        in state: DetailTagSuggestionState
    ) -> DetailTagSuggestionState {
        guard let report = state.report else { return state }
        guard report.suggestions.contains(where: { $0.suggestionID == suggestionID && $0.canApply }) else {
            return state
        }
        var selected = state.selectedIDs
        selected.formSymmetricDifference([suggestionID])
        return .loaded(fileID: report.fileID, report, selected)
    }

    static func selectingAll(in state: DetailTagSuggestionState) -> DetailTagSuggestionState {
        guard let report = state.report else { return state }
        let strongIDs = report.suggestions.compactMap { suggestion in
            suggestion.canApply && suggestion.matchStrength == .strong ? suggestion.suggestionID : nil
        }
        return .loaded(fileID: report.fileID, report, state.selectedIDs.union(strongIDs))
    }

    static func clearingSelection(in state: DetailTagSuggestionState) -> DetailTagSuggestionState {
        guard let report = state.report else { return state }
        return .loaded(fileID: report.fileID, report, [])
    }
}

extension DetailTagSuggestionState {
    var report: TagSuggestionReportSnapshot? {
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

    var appliedReport: TagSuggestionApplyReportSnapshot? {
        switch self {
        case let .applied(_, _, report, _), let .editApplied(_, _, report, _):
            report
        case .idle, .loading, .loaded, .editing, .applying, .applyingEdited, .failed:
            nil
        }
    }

    var editSession: TagSuggestionEditSession? {
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
}

extension DetailTagSuggestionAction {
    static func startingEdit(in state: DetailTagSuggestionState, disabledReason: String?) -> DetailTagSuggestionState {
        guard let report = state.report else { return state }
        let selectedIDs = state.selectedIDs
        let drafts = report.suggestions.compactMap { suggestion -> TagSuggestionEditDraft? in
            guard selectedIDs.contains(suggestion.suggestionID) else { return nil }
            return TagSuggestionEditDraft(
                suggestionID: suggestion.suggestionID,
                originalSlug: suggestion.slug,
                originalDisplayName: suggestion.displayName,
                reason: suggestion.reason,
                displayName: suggestion.displayName,
                slug: suggestion.slug,
                slugWasEdited: false,
                status: .ready
            )
        }
        let session = validatedSession(
            TagSuggestionEditSession(selectedIDs: selectedIDs, drafts: drafts),
            report: report,
            disabledReason: disabledReason
        )
        return .editing(fileID: report.fileID, report, session)
    }

    static func cancelingEdit(in state: DetailTagSuggestionState) -> DetailTagSuggestionState {
        guard let report = state.report else { return state }
        return .loaded(fileID: report.fileID, report, state.selectedIDs)
    }

    static func updatingDisplayName(
        suggestionID: String,
        displayName: String,
        in state: DetailTagSuggestionState,
        disabledReason: String?
    ) -> DetailTagSuggestionState {
        updateDraft(suggestionID: suggestionID, in: state, disabledReason: disabledReason) { draft in
            draft.displayName = displayName
            if !draft.slugWasEdited { draft.slug = normalizedSlug(from: displayName) }
        }
    }

    static func updatingSlug(
        suggestionID: String,
        slug: String,
        in state: DetailTagSuggestionState,
        disabledReason: String?
    ) -> DetailTagSuggestionState {
        updateDraft(suggestionID: suggestionID, in: state, disabledReason: disabledReason) { draft in
            draft.slug = slug
            draft.slugWasEdited = true
        }
    }

    static func regeneratingSlug(
        suggestionID: String,
        in state: DetailTagSuggestionState,
        disabledReason: String?
    ) -> DetailTagSuggestionState {
        updateDraft(suggestionID: suggestionID, in: state, disabledReason: disabledReason) { draft in
            draft.slug = normalizedSlug(from: draft.displayName)
            draft.slugWasEdited = false
        }
    }

    static func applyingEdited(in state: DetailTagSuggestionState) -> DetailTagSuggestionState {
        guard let report = state.report, let session = state.editSession else { return state }
        return .applyingEdited(fileID: report.fileID, report: report, session: session)
    }

    static func editedItems(in state: DetailTagSuggestionState) -> [ApplyTagSuggestionItemSnapshot] {
        state.editSession?.applyItems ?? []
    }

    static func retryFailedItems(in state: DetailTagSuggestionState) -> [ApplyTagSuggestionItemSnapshot] {
        state.editSession?.retryFailedItems ?? []
    }

    private static func updateDraft(
        suggestionID: String,
        in state: DetailTagSuggestionState,
        disabledReason: String?,
        update: (inout TagSuggestionEditDraft) -> Void
    ) -> DetailTagSuggestionState {
        guard let report = state.report, var session = state.editSession else { return state }
        guard let index = session.drafts.firstIndex(where: { $0.suggestionID == suggestionID }) else { return state }
        update(&session.drafts[index])
        return .editing(
            fileID: report.fileID,
            report,
            validatedSession(session, report: report, disabledReason: disabledReason)
        )
    }

    private static func validatedSession(
        _ session: TagSuggestionEditSession,
        report: TagSuggestionReportSnapshot,
        disabledReason: String?
    ) -> TagSuggestionEditSession {
        var seenSlugs: Set<String> = []
        var next = session
        next.drafts = session.drafts.map { draft in
            var updated = draft
            updated.status = status(for: draft, seenSlugs: &seenSlugs, report: report, disabledReason: disabledReason)
            return updated
        }
        return next
    }

    private static func status(
        for draft: TagSuggestionEditDraft,
        seenSlugs: inout Set<String>,
        report: TagSuggestionReportSnapshot,
        disabledReason: String?
    ) -> TagSuggestionEditRowStatus {
        if disabledReason != nil { return .blocked("Tag store is read-only.") }
        guard let suggestion = report.suggestions.first(where: { $0.suggestionID == draft.suggestionID }) else {
            return .blocked("Suggestion is no longer available.")
        }
        if suggestion.status == .alreadyAdded { return .alreadyAdded("Already added") }
        if suggestion.status == .blocked || suggestion.disabledReason != nil {
            return .blocked(suggestion.disabledReason ?? "Suggestion is blocked.")
        }
        guard let normalized = TagInputNormalization.normalizedValue(draft.slug) else {
            return .invalid(TagInputNormalization.invalidMessage)
        }
        if seenSlugs.contains(normalized) { return .duplicate("Duplicate slug in selected tags.") }
        seenSlugs.insert(normalized)
        if report.tagSet.containsFileTag(value: normalized) { return .alreadyAdded("Already added") }
        return .ready
    }

    private static func normalizedSlug(from displayName: String) -> String {
        displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

extension MainFileListModel {
    func loadSelectedFileAITagSuggestions() async {
        guard let fileID = selection.singleFileID else { return }
        await loadAITagSuggestions(fileID: fileID)
    }

    func retrySelectedFileAITagSuggestions() async {
        guard let fileID = selection.singleFileID else { return }
        await loadAITagSuggestions(fileID: fileID)
    }

    func toggleSelectedFileAITagSuggestion(_ suggestionID: String) {
        aiTagSuggestionState = AITagSuggestionAction.toggling(suggestionID, in: aiTagSuggestionState)
    }

    func applySelectedFileAITagSuggestion(_ suggestionID: String) async -> BatchTagUndoState? {
        guard let item = AITagSuggestionAction.applyItem(suggestionID: suggestionID, in: aiTagSuggestionState) else {
            return nil
        }
        return await applyAITagSuggestions([item])
    }

    func selectHighConfidenceAITagSuggestions() {
        aiTagSuggestionState = AITagSuggestionAction.selectingHighConfidence(in: aiTagSuggestionState)
    }

    func clearSelectedFileAITagSuggestions() {
        aiTagSuggestionState = AITagSuggestionAction.clearingSelection(in: aiTagSuggestionState)
    }

    func startEditingSelectedFileAITagSuggestions() {
        aiTagSuggestionState = AITagSuggestionAction.startingEdit(
            in: aiTagSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func cancelEditingSelectedFileAITagSuggestions() {
        aiTagSuggestionState = AITagSuggestionAction.cancelingEdit(in: aiTagSuggestionState)
    }

    func updateSelectedFileAITagSuggestionDisplayName(suggestionID: String, displayName: String) {
        aiTagSuggestionState = AITagSuggestionAction.updatingDisplayName(
            suggestionID: suggestionID,
            displayName: displayName,
            in: aiTagSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func updateSelectedFileAITagSuggestionSlug(suggestionID: String, slug: String) {
        aiTagSuggestionState = AITagSuggestionAction.updatingSlug(
            suggestionID: suggestionID,
            slug: slug,
            in: aiTagSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func regenerateSelectedFileAITagSuggestionSlug(suggestionID: String) {
        aiTagSuggestionState = AITagSuggestionAction.regeneratingSlug(
            suggestionID: suggestionID,
            in: aiTagSuggestionState,
            disabledReason: selectedAITagSuggestionDisabledReason()
        )
    }

    func applySelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        await applyAITagSuggestions(AITagSuggestionAction.selectedApplyItems(in: aiTagSuggestionState))
    }

    func applyEditedSelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        let items = AITagSuggestionAction.editedItems(in: aiTagSuggestionState)
        guard aiTagSuggestionState.editSession?.canApply == true else { return nil }
        return await applyAITagSuggestions(items, editedSession: aiTagSuggestionState.editSession)
    }

    func retryFailedSelectedFileAITagSuggestions() async -> BatchTagUndoState? {
        let items = AITagSuggestionAction.retryFailedItems(in: aiTagSuggestionState)
        return await applyAITagSuggestions(items, editedSession: aiTagSuggestionState.editSession)
    }

    private func loadAITagSuggestions(fileID: Int64) async {
        let previous = aiTagSuggestionState.report
        aiTagSuggestionState = .loading(fileID: fileID, previous: previous)
        do {
            let report = try await aiTagSuggestionStore.suggestTagsWithAI(
                repoPath: repoPath,
                request: AiTagSuggestionRequest(
                    fileId: fileID,
                    candidateTags: detailTagEditorState.tagSet?.allKnownTags.map(\.value) ?? [],
                    privacyPolicyRef: nil
                )
            )
            guard selection.singleFileID == fileID else { return }
            aiTagSuggestionState = .loaded(
                fileID: fileID,
                report,
                AITagSuggestionAction.initialSelection(in: report)
            )
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return }
            aiTagSuggestionState = .failed(fileID: fileID, mapping, previous: previous)
        }
    }

    private func applyAITagSuggestions(
        _ suggestions: [ApplyAiTagSuggestionItem],
        editedSession: AITagSuggestionEditSession? = nil
    ) async -> BatchTagUndoState? {
        guard let fileID = selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil,
              let report = aiTagSuggestionState.report,
              !suggestions.isEmpty else { return nil }

        let previousTagSet = detailTagEditorState.tagSet
        if let editedSession {
            aiTagSuggestionState = .applyingEdited(fileID: fileID, report: report, session: editedSession)
        } else {
            aiTagSuggestionState = .applying(fileID: fileID, report: report, selectedIDs: aiTagSuggestionState.selectedIDs)
        }
        detailTagEditorState = .loading(fileID: fileID, previous: previousTagSet)

        do {
            let applyReport = try await aiTagSuggestionStore.applyAITagSuggestions(
                repoPath: repoPath,
                request: ApplyAiTagSuggestionsRequest(
                    fileId: fileID,
                    suggestions: suggestions,
                    callLogId: report.callLogId,
                    privacyRuleId: report.privacyRuleId,
                    confirmed: true
                )
            )
            guard selection.singleFileID == fileID else { return nil }
            applyAITagSuggestionSuccess(report: report, applyReport: applyReport, editedSession: editedSession)
            await loadChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return nil }
            applyAITagSuggestionFailure(
                mapping: mapping,
                report: report,
                editedSession: editedSession,
                previousTagSet: previousTagSet,
                submittedSlugs: suggestions.map(\.slug)
            )
            return nil
        }
    }

    private func applyAITagSuggestionSuccess(
        report: AiTagSuggestionReport,
        applyReport: AiTagSuggestionApplyReport,
        editedSession: AITagSuggestionEditSession?
    ) {
        detailTagEditorState = .loaded(fileID: applyReport.fileId, TagSetSnapshot(coreTagSet: applyReport.tagSet))
        if let editedSession {
            aiTagSuggestionState = .editApplied(
                fileID: applyReport.fileId,
                report,
                applyReport,
                AITagSuggestionAction.sessionAfterApply(editedSession, report: applyReport)
            )
        } else {
            aiTagSuggestionState = .applied(fileID: applyReport.fileId, report, applyReport, aiTagSuggestionState.selectedIDs)
        }
    }

    private func applyAITagSuggestionFailure(
        mapping: CoreErrorMappingSnapshot,
        report: AiTagSuggestionReport,
        editedSession: AITagSuggestionEditSession?,
        previousTagSet: TagSetSnapshot?,
        submittedSlugs: [String]
    ) {
        if let editedSession {
            aiTagSuggestionState = .editing(fileID: report.fileId, report, editedSession)
        } else {
            aiTagSuggestionState = .failed(fileID: report.fileId, mapping, previous: report)
        }
        detailTagEditorState = .failed(
            fileID: report.fileId,
            operation: .applySuggestions(submittedSlugs),
            mapping,
            previous: previousTagSet
        )
    }

    private func selectedAITagSuggestionDisabledReason() -> String? {
        guard let fileID = selection.singleFileID else { return "Select a file before reviewing AI tag suggestions." }
        return writeActionDisabledReason(fileID: fileID)?.rawValue
    }
}
