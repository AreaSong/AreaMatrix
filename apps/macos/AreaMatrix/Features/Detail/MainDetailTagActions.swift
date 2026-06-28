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

    func clearStaleDetailTagUndoToast() {
        guard detailTagUndoToast?.fileID != selection.singleFileID else { return }
        detailTagUndoToast = nil
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
            detailTagUndoToast = shouldOfferUndo ? DetailTagUndoToast.make(
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

    func loadSuggestionUndoState(undoToken: String?) async -> BatchTagUndoState? {
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
}
