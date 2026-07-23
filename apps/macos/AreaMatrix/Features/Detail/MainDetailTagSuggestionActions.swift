import Foundation

extension MainFileListModel {
    func loadSelectedFileTagSuggestions() async {
        guard let fileID = selection.singleFileID else { return }
        await loadTagSuggestions(fileID: fileID)
    }

    func retrySelectedFileTagSuggestions() async {
        guard let fileID = selection.singleFileID else { return }
        await loadTagSuggestions(fileID: fileID)
    }

    func presentSelectedFileTagSuggestions(source: TagSuggestionPresentationSource) {
        guard let fileID = selection.singleFileID else { return }
        tagSuggestionPresentationSequence += 1
        detailTabRequest = .automatic(.meta)
        tagSuggestionPresentationRequest = TagSuggestionPresentationRequest(
            fileID: fileID,
            source: source,
            sequence: tagSuggestionPresentationSequence
        )
    }

    func consumeTagSuggestionPresentationRequest(_ request: TagSuggestionPresentationRequest) {
        if tagSuggestionPresentationRequest == request {
            tagSuggestionPresentationRequest = nil
        }
    }

    func toggleSelectedFileTagSuggestion(_ suggestionID: String) {
        detailTagSuggestionState = DetailTagSuggestionAction.togglingSelection(
            suggestionID: suggestionID,
            in: detailTagSuggestionState
        )
    }

    func selectAllSelectedFileTagSuggestions() {
        detailTagSuggestionState = DetailTagSuggestionAction.selectingAll(in: detailTagSuggestionState)
    }

    func clearSelectedFileTagSuggestions() {
        detailTagSuggestionState = DetailTagSuggestionAction.clearingSelection(in: detailTagSuggestionState)
    }

    func startEditingSelectedFileTagSuggestions() {
        detailTagSuggestionState = DetailTagSuggestionAction.startingEdit(
            in: detailTagSuggestionState,
            disabledReason: selectedTagSuggestionDisabledReason()
        )
    }

    func cancelEditingSelectedFileTagSuggestions() {
        detailTagSuggestionState = DetailTagSuggestionAction.cancelingEdit(in: detailTagSuggestionState)
    }

    func updateSelectedFileTagSuggestionDisplayName(suggestionID: String, displayName: String) {
        detailTagSuggestionState = DetailTagSuggestionAction.updatingDisplayName(
            suggestionID: suggestionID,
            displayName: displayName,
            in: detailTagSuggestionState,
            disabledReason: selectedTagSuggestionDisabledReason()
        )
    }

    func updateSelectedFileTagSuggestionSlug(suggestionID: String, slug: String) {
        detailTagSuggestionState = DetailTagSuggestionAction.updatingSlug(
            suggestionID: suggestionID,
            slug: slug,
            in: detailTagSuggestionState,
            disabledReason: selectedTagSuggestionDisabledReason()
        )
    }

    func regenerateSelectedFileTagSuggestionSlug(suggestionID: String) {
        detailTagSuggestionState = DetailTagSuggestionAction.regeneratingSlug(
            suggestionID: suggestionID,
            in: detailTagSuggestionState,
            disabledReason: selectedTagSuggestionDisabledReason()
        )
    }

    func applySelectedFileTagSuggestions() async -> BatchTagUndoState? {
        guard let fileID = writableActionFileID(),
              let report = detailTagSuggestionState.report else { return nil }
        let suggestions = DetailTagSuggestionAction.selectedApplyItems(in: detailTagSuggestionState)
        guard !suggestions.isEmpty else { return nil }

        let previousTagSet = detailTagEditorState.tagSet
        let selectedIDs = detailTagSuggestionState.selectedIDs
        detailTagSuggestionState = .applying(fileID: fileID, report: report, selectedIDs: selectedIDs)
        detailTagEditorState = .loading(fileID: fileID, previous: previousTagSet)
        do {
            let applyReport = try await tagStore.applyTagSuggestions(
                repoPath: repoPath,
                request: ApplyTagSuggestionsRequestSnapshot(fileID: fileID, suggestions: suggestions)
            )
            guard selection.singleFileID == fileID else { return nil }
            detailTagSuggestionState = .applied(fileID: fileID, report, applyReport, selectedIDs)
            detailTagEditorState = .loaded(fileID: fileID, applyReport.tagSet)
            await loadChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return nil }
            detailTagSuggestionState = .failed(fileID: fileID, mapping, previous: report)
            detailTagEditorState = .failed(
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
              let report = detailTagSuggestionState.report,
              let session = detailTagSuggestionState.editSession,
              session.canApply else { return nil }
        let suggestions = DetailTagSuggestionAction.editedItems(in: detailTagSuggestionState)
        guard !suggestions.isEmpty else { return nil }

        let previousTagSet = detailTagEditorState.tagSet
        detailTagSuggestionState = DetailTagSuggestionAction.applyingEdited(in: detailTagSuggestionState)
        detailTagEditorState = .loading(fileID: fileID, previous: previousTagSet)
        do {
            let applyReport = try await tagStore.applyTagSuggestions(
                repoPath: repoPath,
                request: ApplyTagSuggestionsRequestSnapshot(fileID: fileID, suggestions: suggestions)
            )
            guard selection.singleFileID == fileID else { return nil }
            let recovered = editedSessionAfterApply(session, report: applyReport)
            detailTagSuggestionState = .editApplied(fileID: fileID, report, applyReport, recovered)
            detailTagEditorState = .loaded(fileID: fileID, applyReport.tagSet)
            await loadChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return nil }
            detailTagSuggestionState = .editing(fileID: fileID, report, session)
            detailTagEditorState = .failed(
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
              let report = detailTagSuggestionState.report,
              let session = detailTagSuggestionState.editSession else { return nil }
        let suggestions = DetailTagSuggestionAction.retryFailedItems(in: detailTagSuggestionState)
        guard !suggestions.isEmpty else { return nil }

        let previousTagSet = detailTagEditorState.tagSet
        detailTagSuggestionState = DetailTagSuggestionAction.applyingEdited(in: detailTagSuggestionState)
        detailTagEditorState = .loading(fileID: fileID, previous: previousTagSet)
        do {
            let applyReport = try await tagStore.applyTagSuggestions(
                repoPath: repoPath,
                request: ApplyTagSuggestionsRequestSnapshot(fileID: fileID, suggestions: suggestions)
            )
            guard selection.singleFileID == fileID else { return nil }
            let recovered = editedSessionAfterApply(session, report: applyReport)
            detailTagSuggestionState = .editApplied(fileID: fileID, report, applyReport, recovered)
            detailTagEditorState = .loaded(fileID: fileID, applyReport.tagSet)
            await loadChangeLog(fileID: fileID)
            return await loadSuggestionUndoState(undoToken: applyReport.undoToken)
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return nil }
            detailTagSuggestionState = .editing(fileID: fileID, report, session)
            detailTagEditorState = .failed(
                fileID: fileID,
                operation: .applySuggestions(suggestions.map(\.slug)),
                mapping,
                previous: previousTagSet
            )
            return nil
        }
    }

    func clearStaleDetailTagSuggestions() {
        let selectedFileID = selection.singleFileID
        if detailTagSuggestionState.fileID != selectedFileID {
            detailTagSuggestionState = .idle
            tagSuggestionPresentationRequest = nil
        }
        if aiTagSuggestionState.fileID != selectedFileID {
            aiTagSuggestionState = .idle
        }
        let selectedBatchFileIDs = selection.multipleFileIDs
        if selectedBatchFileIDs.isEmpty || aiTagBatchSuggestionState.fileIDs != selectedBatchFileIDs {
            aiTagBatchSuggestionState = .idle
        }
    }

    private func loadTagSuggestions(fileID: Int64) async {
        let previous = detailTagSuggestionState.report
        detailTagSuggestionState = .loading(fileID: fileID, previous: previous)
        do {
            let report = try await tagStore.suggestTagsForFile(
                repoPath: repoPath,
                request: TagSuggestionRequestSnapshot(
                    fileID: fileID,
                    context: nil,
                    limit: DetailTagSuggestionAction.defaultLimit
                )
            )
            guard selection.singleFileID == fileID else { return }
            detailTagEditorState = .loaded(fileID: fileID, report.tagSet)
            detailTagSuggestionState = .loaded(
                fileID: fileID,
                report,
                DetailTagSuggestionAction.initialSelection(in: report)
            )
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return }
            detailTagSuggestionState = .failed(fileID: fileID, mapping, previous: previous)
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
