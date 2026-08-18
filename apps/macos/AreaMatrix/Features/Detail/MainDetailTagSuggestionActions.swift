import Foundation

extension DetailTagModel {
    func loadSelectedFileTagSuggestions() async {
        guard let fileID = currentSelectedFileID else { return }
        await loadTagSuggestions(fileID: fileID)
    }

    func retrySelectedFileTagSuggestions() async {
        guard let fileID = currentSelectedFileID else { return }
        await loadTagSuggestions(fileID: fileID)
    }

    func presentSelectedFileTagSuggestions(source: TagSuggestionPresentationSource) {
        guard let fileID = currentSelectedFileID else { return }
        presentationSequence += 1
        showDetailTab(.meta)
        presentationRequest = TagSuggestionPresentationRequest(
            fileID: fileID,
            source: source,
            sequence: presentationSequence
        )
    }

    func consumeTagSuggestionPresentationRequest(_ request: TagSuggestionPresentationRequest) {
        if presentationRequest == request {
            presentationRequest = nil
        }
    }

    func toggleSelectedFileTagSuggestion(_ suggestionID: String) {
        suggestionState = DetailTagSuggestionAction.togglingSelection(
            suggestionID: suggestionID,
            in: suggestionState
        )
    }

    func selectAllSelectedFileTagSuggestions() {
        suggestionState = DetailTagSuggestionAction.selectingAll(in: suggestionState)
    }

    func clearSelectedFileTagSuggestions() {
        suggestionState = DetailTagSuggestionAction.clearingSelection(in: suggestionState)
    }

    func startEditingSelectedFileTagSuggestions() {
        suggestionState = DetailTagSuggestionAction.startingEdit(
            in: suggestionState,
            disabledReason: selectedTagSuggestionDisabledReason()
        )
    }

    func cancelEditingSelectedFileTagSuggestions() {
        suggestionState = DetailTagSuggestionAction.cancelingEdit(in: suggestionState)
    }

    func updateSelectedFileTagSuggestionDisplayName(suggestionID: String, displayName: String) {
        suggestionState = DetailTagSuggestionAction.updatingDisplayName(
            suggestionID: suggestionID,
            displayName: displayName,
            in: suggestionState,
            disabledReason: selectedTagSuggestionDisabledReason()
        )
    }

    func updateSelectedFileTagSuggestionSlug(suggestionID: String, slug: String) {
        suggestionState = DetailTagSuggestionAction.updatingSlug(
            suggestionID: suggestionID,
            slug: slug,
            in: suggestionState,
            disabledReason: selectedTagSuggestionDisabledReason()
        )
    }

    func regenerateSelectedFileTagSuggestionSlug(suggestionID: String) {
        suggestionState = DetailTagSuggestionAction.regeneratingSlug(
            suggestionID: suggestionID,
            in: suggestionState,
            disabledReason: selectedTagSuggestionDisabledReason()
        )
    }

    func applySelectedFileTagSuggestions() async -> BatchTagUndoState? {
        guard let fileID = writableActionFileID(),
              let report = suggestionState.report else { return nil }
        let suggestions = DetailTagSuggestionAction.selectedApplyItems(in: suggestionState)
        guard !suggestions.isEmpty else { return nil }

        let previousTagSet = editorState.tagSet
        let selectedIDs = suggestionState.selectedIDs
        suggestionState = .applying(fileID: fileID, report: report, selectedIDs: selectedIDs)
        editorState = .loading(fileID: fileID, previous: previousTagSet)
        do {
            let applyReport = try await tagStore.applyTagSuggestions(
                repoPath: repoPath,
                request: ApplyTagSuggestionsRequestSnapshot(fileID: fileID, suggestions: suggestions)
            )
            guard currentSelectedFileID == fileID else { return nil }
            suggestionState = .applied(fileID: fileID, report, applyReport, selectedIDs)
            editorState = .loaded(fileID: fileID, applyReport.tagSet)
            await refreshChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard currentSelectedFileID == fileID else { return nil }
            suggestionState = .failed(fileID: fileID, mapping, previous: report)
            editorState = .failed(
                fileID: fileID,
                operation: .applySuggestions(suggestions.map(\.slug)),
                mapping,
                previous: previousTagSet
            )
            return nil
        }
    }

    func applyEditedSelectedFileTagSuggestions() async -> BatchTagUndoState? {
        guard let fileID = writableActionFileID(),
              let report = suggestionState.report,
              let session = suggestionState.editSession,
              session.canApply else { return nil }
        let suggestions = DetailTagSuggestionAction.editedItems(in: suggestionState)
        guard !suggestions.isEmpty else { return nil }

        let previousTagSet = editorState.tagSet
        suggestionState = DetailTagSuggestionAction.applyingEdited(in: suggestionState)
        editorState = .loading(fileID: fileID, previous: previousTagSet)
        do {
            let applyReport = try await tagStore.applyTagSuggestions(
                repoPath: repoPath,
                request: ApplyTagSuggestionsRequestSnapshot(fileID: fileID, suggestions: suggestions)
            )
            guard currentSelectedFileID == fileID else { return nil }
            let recovered = editedSessionAfterApply(session, report: applyReport)
            suggestionState = .editApplied(fileID: fileID, report, applyReport, recovered)
            editorState = .loaded(fileID: fileID, applyReport.tagSet)
            await refreshChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard currentSelectedFileID == fileID else { return nil }
            suggestionState = .editing(fileID: fileID, report, session)
            editorState = .failed(
                fileID: fileID,
                operation: .applySuggestions(suggestions.map(\.slug)),
                mapping,
                previous: previousTagSet
            )
            return nil
        }
    }

    func retryFailedSelectedFileTagSuggestions() async -> BatchTagUndoState? {
        guard let fileID = writableActionFileID(),
              let report = suggestionState.report,
              let session = suggestionState.editSession else { return nil }
        let suggestions = DetailTagSuggestionAction.retryFailedItems(in: suggestionState)
        guard !suggestions.isEmpty else { return nil }

        let previousTagSet = editorState.tagSet
        suggestionState = DetailTagSuggestionAction.applyingEdited(in: suggestionState)
        editorState = .loading(fileID: fileID, previous: previousTagSet)
        do {
            let applyReport = try await tagStore.applyTagSuggestions(
                repoPath: repoPath,
                request: ApplyTagSuggestionsRequestSnapshot(fileID: fileID, suggestions: suggestions)
            )
            guard currentSelectedFileID == fileID else { return nil }
            let recovered = editedSessionAfterApply(session, report: applyReport)
            suggestionState = .editApplied(fileID: fileID, report, applyReport, recovered)
            editorState = .loaded(fileID: fileID, applyReport.tagSet)
            await refreshChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard currentSelectedFileID == fileID else { return nil }
            suggestionState = .editing(fileID: fileID, report, session)
            editorState = .failed(
                fileID: fileID,
                operation: .applySuggestions(suggestions.map(\.slug)),
                mapping,
                previous: previousTagSet
            )
            return nil
        }
    }

    func clearStaleDetailTagSuggestions() {
        let selectedFileID = currentSelectedFileID
        if suggestionState.fileID != selectedFileID {
            suggestionState = .idle
            presentationRequest = nil
        }
        if aiSuggestionState.fileID != selectedFileID {
            aiSuggestionState = .idle
        }
    }

    private func loadTagSuggestions(fileID: Int64) async {
        let previous = suggestionState.report
        suggestionState = .loading(fileID: fileID, previous: previous)
        do {
            let report = try await tagStore.suggestTagsForFile(
                repoPath: repoPath,
                request: TagSuggestionRequestSnapshot(
                    fileID: fileID,
                    context: nil,
                    limit: DetailTagSuggestionAction.defaultLimit
                )
            )
            guard currentSelectedFileID == fileID else { return }
            editorState = .loaded(fileID: fileID, report.tagSet)
            suggestionState = .loaded(
                fileID: fileID,
                report,
                DetailTagSuggestionAction.initialSelection(in: report)
            )
        } catch {
            let mapping = await mapCoreError(error)
            guard currentSelectedFileID == fileID else { return }
            suggestionState = .failed(fileID: fileID, mapping, previous: previous)
        }
    }

    private func selectedTagSuggestionDisabledReason() -> String? {
        selectedWriteActionDisabledMessage(
            noSelectionMessage: L10n.string("Select a file before reviewing tag suggestions.")
        )
    }

    private func editedSessionAfterApply(
        _ session: TagSuggestionEditSession,
        report: TagSuggestionApplyReportSnapshot
    ) -> TagSuggestionEditSession {
        var next = session
        next.drafts = session.drafts.map { draft in
            var updated = draft
            guard let result = report.itemResults.first(where: { $0.suggestionID == draft.suggestionID }) else {
                return updated
            }
            switch result.status {
            case .applied:
                updated.status = .applied
            case .alreadyAdded:
                updated.status = .alreadyAdded(L10n.display(
                    "Already added",
                    technicalDetail: result.error
                ))
            case .failed:
                updated.status = .failed(L10n.display(
                    "A suggestion could not be applied.",
                    technicalDetail: result.error
                ))
            }
            return updated
        }
        return next
    }
}
