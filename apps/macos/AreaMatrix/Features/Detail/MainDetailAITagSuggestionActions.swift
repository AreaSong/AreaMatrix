import Foundation

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
}
