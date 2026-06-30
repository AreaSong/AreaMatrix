import Foundation

extension MainFileListModel {
    func selectFiles(_ ids: Set<Int64>) async {
        if ids.isEmpty { clearDetail(); return }

        guard ids.count == 1, let id = ids.first else {
            selection = .multiple(ids)
            selectedFileDetail = nil; selectedFileNoteWriteBlock = nil; detailErrorMapping = nil
            detailTagEditorState = .notLoaded
            detailTagSuggestionState = .idle
            isDetailLoading = true
            resetDetailLog()
            await loadMultiSelectionDetails(ids: ids)
            return
        }

        await selectFile(id: id)
    }

    func selectFile(id: Int64?) async {
        guard let id else { clearDetail(); return }

        selection = .single(id); selectedFileDetail = cachedFile(id: id)
        selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = nil
        isDetailLoading = true
        resetDetailLog()
        await loadDetail(id: id)
    }

    func retrySelectedFileDetail() async {
        if selection.isMultiple {
            detailErrorMapping = nil
            isDetailLoading = true
            await loadMultiSelectionDetails(ids: selection.multipleFileIDs)
            return
        }

        guard let selectedFileID = selection.singleFileID else { return }

        selectedFileDetail = selectedFileDetail ?? cachedFile(id: selectedFileID)
        selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: selectedFileID)
    }

    func loadDetail(id: Int64) async {
        detailGeneration += 1
        let generation = detailGeneration

        do {
            let loadedFile = try await fileDetailer.getFile(repoPath: repoPath, fileID: id)
            guard generation == detailGeneration else { return }
            selection = .single(loadedFile.id)
            selectedFileDetail = loadedFile
            selectedFileNoteWriteBlock = noteWriteBlock(for: loadedFile)
            files = files.map { $0.id == loadedFile.id ? loadedFile : $0 }
            detailErrorMapping = nil
            isDetailLoading = false
            detailTagEditorState = .notLoaded
            detailTagSuggestionState = .idle
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == detailGeneration else { return }
            selectedFileDetail = missingDetailSnapshotIfNeeded(error, fileID: id) ??
                selectedFileDetail ??
                cachedFile(id: id)
            selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
            detailErrorMapping = mappedError
            isDetailLoading = false
        }
    }

    private func loadMultiSelectionDetails(ids: Set<Int64>) async {
        detailGeneration += 1
        let generation = detailGeneration
        guard let result = await MultiSelectionDetailLoader.refresh(
            request: MultiSelectionDetailRefreshRequest(
                ids: ids,
                repoPath: repoPath,
                currentFiles: files,
                detailer: fileDetailer,
                errorMapper: errorMapper
            ),
            shouldContinue: { [weak self] in
                self?.canApplyMultiSelectionDetailResult(generation: generation, ids: ids) == true
            }
        ) else { return }

        guard canApplyMultiSelectionDetailResult(generation: generation, ids: ids) else { return }
        files = result.files
        selectedFileDetail = nil
        selectedFileNoteWriteBlock = nil
        detailErrorMapping = result.errorMapping
        isDetailLoading = false
    }

    func clearDetail() {
        detailGeneration += 1
        selection = .none
        selectedFileDetail = nil; selectedFileNoteWriteBlock = nil; detailErrorMapping = nil
        detailTagEditorState = .notLoaded
        detailTagSuggestionState = .idle
        clearTagFilterRegistry()
        isDetailLoading = false
        resetDetailLog()
        pendingActionDestination = nil; renameState = .idle; deleteState = .idle; changeCategoryState = .idle
    }

    func resetDetailLog() {
        detailLogGeneration += 1
        detailLogState = .notLoaded
        detailLogDiagnosticsState = .idle
        detailExternalCreateSyncState = .idle
        detailTabRequest = nil
        iCloudConflictResolutionState = .idle
    }
}
