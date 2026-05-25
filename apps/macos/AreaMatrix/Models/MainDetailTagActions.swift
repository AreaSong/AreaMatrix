import Foundation

extension MainFileListModel {
    func loadSelectedFileTags() async {
        guard let fileID = selection.singleFileID else { return }
        await loadTags(fileID: fileID)
    }

    func retrySelectedFileTags() async {
        guard let fileID = selection.singleFileID else { return }
        await loadTags(fileID: fileID)
    }

    func addSelectedFileTag(_ tag: String) async {
        guard let fileID = selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        await mutateTags(fileID: fileID, operation: .add(tag)) {
            try await tagStore.addTag(repoPath: repoPath, fileID: fileID, tag: tag)
        }
    }

    func removeSelectedFileTag(_ tag: String) async {
        guard let fileID = selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        await mutateTags(fileID: fileID, operation: .remove(tag)) {
            try await tagStore.removeTag(repoPath: repoPath, fileID: fileID, tag: tag)
        }
    }

    func undoLastDetailTagChange() async {
        guard let toast = detailTagUndoToast else { return }
        guard selection.singleFileID == toast.fileID else {
            detailTagUndoToast = nil
            return
        }
        guard writeActionDisabledReason(fileID: toast.fileID) == nil else { return }

        detailTagUndoToast = nil
        await mutateTags(fileID: toast.fileID, operation: toast.undoOperation, shouldOfferUndo: false) {
            switch toast.action {
            case .removeAddedTag:
                try await tagStore.removeTag(repoPath: repoPath, fileID: toast.fileID, tag: toast.tagValue)
            case .restoreRemovedTag:
                try await tagStore.addTag(repoPath: repoPath, fileID: toast.fileID, tag: toast.tagValue)
            }
        }
    }

    func dismissDetailTagUndoToast() {
        detailTagUndoToast = nil
    }

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
        guard let fileID = selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil,
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
        guard let fileID = selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil,
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

    func clearStaleDetailTagUndoToast() {
        guard detailTagUndoToast?.fileID != selection.singleFileID else { return }
        detailTagUndoToast = nil
    }

    func clearStaleDetailTagSuggestions() {
        guard detailTagSuggestionState.fileID != selection.singleFileID else { return }
        detailTagSuggestionState = .idle
        tagSuggestionPresentationRequest = nil
    }

    func loadTagFilterRegistry(activeFileID: Int64?) async {
        guard let activeFileID else {
            clearTagFilterRegistry()
            return
        }
        await loadTagFilterRegistry(fileID: activeFileID)
    }

    func retryTagFilterRegistry() async {
        switch tagFilterRegistryState {
        case let .failed(fileID, _, _), let .loaded(fileID, _), let .loading(fileID, _):
            await loadTagFilterRegistry(fileID: fileID)
        case .idle:
            return
        }
    }

    func clearTagFilterRegistry() {
        tagFilterRegistryGeneration += 1
        tagFilterRegistryState = .idle
    }

    private func loadTags(fileID: Int64) async {
        let previous = detailTagEditorState.tagSet
        detailTagEditorState = .loading(fileID: fileID, previous: previous)
        do {
            let tagSet = try await tagStore.listTags(repoPath: repoPath, fileID: fileID)
            guard selection.singleFileID == fileID else { return }
            detailTagEditorState = .loaded(fileID: fileID, tagSet)
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return }
            detailTagEditorState = .failed(fileID: fileID, operation: .load, mapping, previous: previous)
        }
    }

    private func loadTagFilterRegistry(fileID: Int64) async {
        tagFilterRegistryGeneration += 1
        let generation = tagFilterRegistryGeneration
        let previous = tagFilterRegistryState.tagSet
        tagFilterRegistryState = .loading(fileID: fileID, previous: previous)

        do {
            let tagSet = try await tagStore.listTags(repoPath: repoPath, fileID: fileID)
            guard generation == tagFilterRegistryGeneration else { return }
            tagFilterRegistryState = .loaded(fileID: fileID, tagSet)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == tagFilterRegistryGeneration else { return }
            tagFilterRegistryState = .failed(fileID: fileID, mappedError, previous: previous)
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
        guard let fileID = selection.singleFileID else { return "Select a file before reviewing tag suggestions." }
        return writeActionDisabledReason(fileID: fileID)?.rawValue
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
                updated.status = .alreadyAdded(result.error ?? "Already added")
            case .failed:
                updated.status = .blocked(result.error ?? "A suggestion could not be applied.")
            }
            return updated
        }
        return next
    }

    private func mutateTags(
        fileID: Int64,
        operation: DetailTagEditorOperation,
        shouldOfferUndo: Bool = true,
        action: () async throws -> TagSetSnapshot
    ) async {
        let previous = detailTagEditorState.tagSet
        detailTagEditorState = .loading(fileID: fileID, previous: previous)
        do {
            let tagSet = try await action()
            guard selection.singleFileID == fileID else { return }
            detailTagEditorState = .loaded(fileID: fileID, tagSet)
            detailTagUndoToast = shouldOfferUndo ? makeTagUndoToast(
                operation: operation,
                fileID: fileID,
                previous: previous,
                current: tagSet
            ) : nil
            await loadChangeLog(fileID: fileID)
        } catch {
            let mapping = await mapCoreError(error)
            guard selection.singleFileID == fileID else { return }
            detailTagEditorState = .failed(fileID: fileID, operation: operation, mapping, previous: previous)
        }
    }

    private func loadSuggestionUndoState(undoToken: String?) async -> BatchTagUndoState? {
        guard let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        let result = await BatchTagUndoAction.loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoActionStore,
            errorMapper: errorMapper
        )
        return result.toastState
    }

    private func makeTagUndoToast(
        operation: DetailTagEditorOperation,
        fileID: Int64,
        previous: TagSetSnapshot?,
        current: TagSetSnapshot
    ) -> DetailTagUndoToast? {
        switch operation {
        case .load:
            nil
        case .add:
            DetailTagUndoToast.addedTag(fileID: fileID, previous: previous, current: current)
        case .remove:
            DetailTagUndoToast.removedTag(fileID: fileID, previous: previous, current: current)
        case .suggest, .applySuggestions:
            nil
        }
    }
}
