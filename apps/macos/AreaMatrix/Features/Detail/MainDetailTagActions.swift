import Foundation

extension DetailTagModel {
    func loadSelectedFileTags() async {
        guard let fileID = currentSelectedFileID else { return }
        await loadTags(fileID: fileID)
    }

    func retrySelectedFileTags() async {
        guard let fileID = currentSelectedFileID else { return }
        await loadTags(fileID: fileID)
    }

    func addSelectedFileTag(_ tag: String) async {
        guard let fileID = writableActionFileID() else { return }
        await mutateTags(fileID: fileID, operation: .add(tag)) {
            try await tagStore.addTag(repoPath: repoPath, fileID: fileID, tag: tag)
        }
    }

    func removeSelectedFileTag(_ tag: String) async {
        guard let fileID = writableActionFileID() else { return }
        await mutateTags(fileID: fileID, operation: .remove(tag)) {
            try await tagStore.removeTag(repoPath: repoPath, fileID: fileID, tag: tag)
        }
    }

    func undoLastDetailTagChange() async {
        guard let toast = undoToast else { return }
        guard currentSelectedFileID == toast.fileID else {
            undoToast = nil
            return
        }
        guard writableActionFileID(toast.fileID) != nil else { return }

        undoToast = nil
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
        undoToast = nil
    }

    func clearStaleDetailTagUndoToast() {
        guard undoToast?.fileID != currentSelectedFileID else { return }
        undoToast = nil
    }

    private func loadTags(fileID: Int64) async {
        let previous = editorState.tagSet
        editorState = .loading(fileID: fileID, previous: previous)
        do {
            let tagSet = try await tagStore.listTags(repoPath: repoPath, fileID: fileID)
            guard currentSelectedFileID == fileID else { return }
            editorState = .loaded(fileID: fileID, tagSet)
        } catch {
            let mapping = await mapCoreError(error)
            guard currentSelectedFileID == fileID else { return }
            editorState = .failed(fileID: fileID, operation: .load, mapping, previous: previous)
        }
    }

    private func mutateTags(
        fileID: Int64,
        operation: DetailTagEditorOperation,
        shouldOfferUndo: Bool = true,
        action: () async throws -> TagSetSnapshot
    ) async {
        let previous = editorState.tagSet
        editorState = .loading(fileID: fileID, previous: previous)
        do {
            let tagSet = try await action()
            guard currentSelectedFileID == fileID else { return }
            editorState = .loaded(fileID: fileID, tagSet)
            undoToast = shouldOfferUndo ? DetailTagUndoToast.make(
                operation: operation,
                fileID: fileID,
                previous: previous,
                current: tagSet
            ) : nil
            await refreshChangeLog(fileID: fileID)
        } catch {
            let mapping = await mapCoreError(error)
            guard currentSelectedFileID == fileID else { return }
            editorState = .failed(fileID: fileID, operation: operation, mapping, previous: previous)
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
