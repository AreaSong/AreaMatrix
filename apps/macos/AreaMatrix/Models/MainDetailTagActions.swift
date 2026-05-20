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
        }
    }
}
